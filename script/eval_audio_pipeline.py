#!/usr/bin/env python3

from __future__ import annotations

import argparse
import gc
import json
import mimetypes
import os
import shutil
import subprocess
import sys
import tempfile
import time
import wave
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Callable, Iterable
from urllib import error as urllib_error
from urllib import request as urllib_request


ACCEPTED_SOURCE_EXTENSIONS = {
    "wav",
    "mp3",
    "m4a",
    "aac",
    "flac",
    "wma",
}

TRANSCRIPTION_INPUTS_FOLDER = "_transcription_inputs"
COMPARISON_FOLDER = "_model_comparisons"
DEFAULT_STACKS = [
    "whispercpp_nllb",
    "whispercpp_indictrans2",
    "fasterwhisper_indictrans2",
    "indicconformer_indictrans2",
    "gemini_flash_lite",
]
DEFAULT_VARIANTS = ["short", "dfn"]

SHORT_SUFFIX = "_short"
DFN_SUFFIX = "_DFN"
HYBRID_SUFFIX = "_HYBRID"

DFN_PREPROCESS_FILTER = ",".join(
    [
        "adeclick=window=20:overlap=75:arorder=2:threshold=3:burst=4:method=save",
        "adeclip=window=55:overlap=75:arorder=8:threshold=8:hsize=1200:method=save",
    ]
)

DFN_POSTPROCESS_FILTER = ",".join(
    [
        "highpass=f=80",
        "lowpass=f=7800",
        "speechnorm=e=4.0:r=0.0001:l=1",
    ]
)

HYBRID_PREPROCESS_FILTER = ",".join(
    [
        "adeclick=window=20:overlap=75:arorder=2:threshold=3:burst=4:method=save",
        "adeclip=window=55:overlap=75:arorder=8:threshold=8:hsize=1200:method=save",
        "highpass=f=70",
    ]
)

HYBRID_POSTPROCESS_FILTER = ",".join(
    [
        "highpass=f=80",
        "lowpass=f=7800",
        "afftdn=nr=6:nf=-72:tn=1",
        "speechnorm=e=4.0:r=0.0001:l=1",
    ]
)

GEMINI_SERVICE = "com.clearvoice.ClearVoice"
GEMINI_ACCOUNT = "gemini_api_key"


class HarnessError(Exception):
    pass


@dataclass
class Toolchain:
    repo_root: Path
    ffmpeg: Path
    deep_filter: Path
    whisper_cli: Path
    whisper_model_dir: Path
    runtime_python: Path
    nllb_model_dir: Path
    hf_cache_dir: Path
    whisper_threads: int
    faster_whisper_model: str
    indic_conformer_model: str
    indic_trans2_model: str
    gemini_transcription_model: str
    gemini_translation_model: str


@dataclass
class TranscriptSegment:
    text: str
    start_ms: int
    end_ms: int


@dataclass
class TranslationChunk:
    text: str
    start_ms: int
    end_ms: int


@dataclass
class AudioVariantArtifact:
    key: str
    label: str
    audio_path: Path
    transcript_source_path: Path


@dataclass
class PreparedSource:
    source_path: Path
    folder_path: Path
    comparison_folder: Path
    variants: dict[str, AudioVariantArtifact]


@dataclass
class EvaluationResult:
    stack_name: str
    stack_description: str
    variant_key: str
    variant_label: str
    audio_path: Path
    transcript_source_path: Path
    transcript_segments: list[TranscriptSegment] | None = None
    translation_chunks: list[TranslationChunk] | None = None
    transcript_language: str | None = None
    error: str | None = None

    @property
    def succeeded(self) -> bool:
        return self.error is None and self.transcript_segments is not None


@dataclass
class StackSpec:
    name: str
    description: str
    asr_factory: Callable[[Toolchain, "ProgressPrinter", argparse.Namespace], "ASRBackend"]
    translation_factory: Callable[[Toolchain, "ProgressPrinter", argparse.Namespace], "TranslationBackend"]


class ProgressPrinter:
    def __init__(self, total_steps: int) -> None:
        self.total_steps = max(1, total_steps)
        self.completed_steps = 0
        self.started_at = time.time()

    def info(self, message: str) -> None:
        print(message, flush=True)

    def step(self, message: str) -> None:
        self.completed_steps += 1
        elapsed = int(time.time() - self.started_at)
        print(
            f"[{self.completed_steps}/{self.total_steps}] +{elapsed:04d}s {message}",
            flush=True,
        )


class ASRBackend:
    def transcribe(self, audio_path: Path) -> dict[str, object]:
        raise NotImplementedError

    def close(self) -> None:
        return


class TranslationBackend:
    def translate(self, segments: list[TranscriptSegment]) -> list[TranslationChunk]:
        raise NotImplementedError

    def close(self) -> None:
        return


class WhisperCppASRBackend(ASRBackend):
    def __init__(self, toolchain: Toolchain) -> None:
        self.toolchain = toolchain

    def transcribe(self, audio_path: Path) -> dict[str, object]:
        with tempfile.TemporaryDirectory(prefix="cv_eval_whisper_") as temp_dir:
            temp_root = Path(temp_dir)
            output_prefix = temp_root / "transcript"
            json_output = output_prefix.with_suffix(".json")

            payload = None
            errors: list[str] = []

            for model_name in ("ggml-large-v3-turbo.bin", "ggml-large-v3.bin"):
                model_path = self.toolchain.whisper_model_dir / model_name
                if not model_path.exists():
                    continue

                for no_gpu in (False, True):
                    try:
                        run_command(
                            whisper_arguments(
                                executable=self.toolchain.whisper_cli,
                                model_path=model_path,
                                audio_path=audio_path,
                                output_prefix=output_prefix,
                                threads=self.toolchain.whisper_threads,
                                no_gpu=no_gpu,
                            ),
                            error_prefix=whisper_error_prefix(audio_path, model_name, no_gpu),
                            env=whisper_environment(self.toolchain.whisper_cli),
                        )
                        payload = json.loads(json_output.read_text(encoding="utf-8"))
                        break
                    except Exception as error:  # noqa: BLE001
                        errors.append(str(error))

                if payload is not None:
                    break

            if payload is None:
                raise HarnessError("\n".join(errors) or f"whisper.cpp failed for {audio_path.name}")

            segments_payload = payload.get("transcription")
            if not isinstance(segments_payload, list):
                raise HarnessError(
                    f"whisper.cpp returned JSON in an unexpected format for {audio_path.name}"
                )

            segments: list[dict[str, object]] = []
            for segment in segments_payload:
                if not isinstance(segment, dict):
                    continue
                text = str(segment.get("text", "")).strip()
                if not text:
                    continue
                offsets = segment.get("offsets") or {}
                segments.append(
                    {
                        "text": text,
                        "start_ms": int(offsets.get("from", 0)),
                        "end_ms": int(offsets.get("to", 0)),
                    }
                )

            if not segments:
                raise HarnessError(f"whisper.cpp returned an empty transcript for {audio_path.name}")

            return {
                "detected_language": "mr",
                "segments": segments,
            }


class FasterWhisperASRBackend(ASRBackend):
    def __init__(self, toolchain: Toolchain) -> None:
        try:
            from faster_whisper import WhisperModel
        except ImportError as error:
            raise HarnessError(
                "faster-whisper is not installed in the shared runtime. Install it before using the faster-whisper stack."
            ) from error

        self.model = WhisperModel(
            toolchain.faster_whisper_model,
            device="cpu",
            compute_type="int8",
            cpu_threads=toolchain.whisper_threads,
        )

    def transcribe(self, audio_path: Path) -> dict[str, object]:
        segments_iter, info = self.model.transcribe(
            str(audio_path),
            language="mr",
            beam_size=5,
            vad_filter=True,
            condition_on_previous_text=False,
        )
        segments: list[dict[str, object]] = []
        for segment in segments_iter:
            text = segment.text.strip()
            if not text:
                continue
            segments.append(
                {
                    "text": text,
                    "start_ms": int(segment.start * 1000),
                    "end_ms": int(segment.end * 1000),
                }
            )

        if not segments:
            raise HarnessError(f"faster-whisper returned an empty transcript for {audio_path.name}")

        return {
            "detected_language": info.language or "mr",
            "segments": segments,
        }


class IndicConformerASRBackend(ASRBackend):
    def __init__(self, toolchain: Toolchain) -> None:
        try:
            import numpy as np  # noqa: F401
            import torch
            from transformers import AutoModel
        except ImportError as error:
            raise HarnessError(
                "IndicConformer dependencies are missing. The shared runtime needs torch and transformers."
            ) from error

        self.torch = torch
        self.numpy = __import__("numpy")
        self.device = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
        try:
            self.model = AutoModel.from_pretrained(
                toolchain.indic_conformer_model,
                trust_remote_code=True,
                cache_dir=str(toolchain.hf_cache_dir),
            )
        except Exception as error:  # noqa: BLE001
            raise HarnessError(
                "Failed to load IndicConformer. If this is the first run, make sure the Hugging Face gated model access has been accepted."
            ) from error

        self.model.to(self.device)
        self.model.eval()
        self.language_code = "mr"
        self.decode_mode = "ctc"

    def transcribe(self, audio_path: Path) -> dict[str, object]:
        waveform = load_pcm_wave_tensor(audio_path, torch_module=self.torch, numpy_module=self.numpy)
        waveform = waveform.to(self.device)

        with self.torch.no_grad():
            transcript = self.model(waveform, self.language_code, self.decode_mode)

        text = transcript[0] if isinstance(transcript, (list, tuple)) else str(transcript)
        text = text.strip()
        if not text:
            raise HarnessError(f"IndicConformer returned an empty transcript for {audio_path.name}")

        duration_ms = audio_duration_ms(audio_path)
        return {
            "detected_language": "mr",
            "segments": [
                {
                    "text": text,
                    "start_ms": 0,
                    "end_ms": duration_ms,
                }
            ],
        }

    def close(self) -> None:
        del self.model
        if self.device.type == "mps":
            self.torch.mps.empty_cache()


class CTranslate2TranslationBackend(TranslationBackend):
    def __init__(
        self,
        model_dir: Path,
        source_lang: str,
        target_lang: str,
        intra_threads: int,
    ) -> None:
        try:
            import ctranslate2
            from transformers import AutoTokenizer
        except ImportError as error:
            raise HarnessError(
                "CTranslate2 translation dependencies are missing from the shared runtime."
            ) from error

        if not model_dir.exists():
            raise HarnessError(f"Translation model directory not found: {model_dir}")

        self.source_lang = source_lang
        self.target_lang = target_lang
        self.translator = ctranslate2.Translator(
            str(model_dir),
            device="cpu",
            inter_threads=1,
            intra_threads=intra_threads,
        )
        self.tokenizer = AutoTokenizer.from_pretrained(
            str(model_dir),
            src_lang=source_lang,
            fix_mistral_regex=True,
        )

    def translate(self, segments: list[TranscriptSegment]) -> list[TranslationChunk]:
        groups = build_translation_groups(segments)
        if not groups:
            return []

        texts_to_translate = [group["text"] for group in groups if should_translate_group(group["text"])]
        translated_by_text: dict[str, str] = {}
        if texts_to_translate:
            token_batches = [
                self.tokenizer.convert_ids_to_tokens(self.tokenizer.encode(text))
                for text in texts_to_translate
            ]
            target_prefix = [[self.target_lang] for _ in texts_to_translate]
            results = self.translator.translate_batch(
                token_batches,
                target_prefix=target_prefix,
                beam_size=4,
                max_batch_size=16,
            )
            for original, result in zip(texts_to_translate, results):
                hypothesis = result.hypotheses[0][1:]
                token_ids = self.tokenizer.convert_tokens_to_ids(hypothesis)
                translated_by_text[original] = self.tokenizer.decode(
                    token_ids,
                    skip_special_tokens=True,
                ).strip()

        return [
            TranslationChunk(
                text=translated_by_text.get(group["text"], group["text"]),
                start_ms=int(group["start_ms"]),
                end_ms=int(group["end_ms"]),
            )
            for group in groups
        ]


class IndicTrans2TranslationBackend(TranslationBackend):
    def __init__(self, toolchain: Toolchain) -> None:
        try:
            import torch
            from transformers import AutoModelForSeq2SeqLM, AutoTokenizer
            from transformers import tokenization_utils, tokenization_utils_base

            if not hasattr(tokenization_utils, "PreTrainedTokenizerBase"):
                tokenization_utils.PreTrainedTokenizerBase = tokenization_utils_base.PreTrainedTokenizerBase

            from IndicTransToolkit.processor import IndicProcessor
        except ImportError as error:
            raise HarnessError(
                "IndicTrans2 dependencies are missing. Install IndicTransToolkit in the shared runtime before using this stack."
            ) from error

        self.torch = torch
        self.device = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
        dtype = torch.float16 if self.device.type == "mps" else torch.float32
        model_name = toolchain.indic_trans2_model

        try:
            self.tokenizer = AutoTokenizer.from_pretrained(
                model_name,
                trust_remote_code=True,
                cache_dir=str(toolchain.hf_cache_dir),
            )
            self.model = AutoModelForSeq2SeqLM.from_pretrained(
                model_name,
                trust_remote_code=True,
                cache_dir=str(toolchain.hf_cache_dir),
                torch_dtype=dtype,
            ).to(self.device)
        except Exception as error:  # noqa: BLE001
            raise HarnessError(
                "Failed to load IndicTrans2. If this is the first run, make sure the Hugging Face gated model access has been accepted."
            ) from error

        self.processor = IndicProcessor(inference=True)
        self.src_lang = "mar_Deva"
        self.tgt_lang = "eng_Latn"

    def translate(self, segments: list[TranscriptSegment]) -> list[TranslationChunk]:
        groups = build_translation_groups(segments)
        if not groups:
            return []

        translation_chunks: list[TranslationChunk] = []

        for batch in group_batches(groups, max_batch_size=8, max_batch_characters=2000):
            texts = [group["text"] for group in batch]
            translated_texts = texts[:]

            indexes_to_translate = [
                index
                for index, text in enumerate(texts)
                if should_translate_group(text)
            ]

            if indexes_to_translate:
                prepared = self.processor.preprocess_batch(
                    [texts[index] for index in indexes_to_translate],
                    src_lang=self.src_lang,
                    tgt_lang=self.tgt_lang,
                )
                inputs = self.tokenizer(
                    prepared,
                    truncation=True,
                    padding="longest",
                    return_tensors="pt",
                    return_attention_mask=True,
                ).to(self.device)
                with self.torch.no_grad():
                    generated_tokens = self.model.generate(
                        **inputs,
                        use_cache=True,
                        min_length=0,
                        max_length=256,
                        num_beams=5,
                        num_return_sequences=1,
                    )
                decoded = self.tokenizer.batch_decode(
                    generated_tokens,
                    skip_special_tokens=True,
                    clean_up_tokenization_spaces=True,
                )
                postprocessed = self.processor.postprocess_batch(
                    decoded,
                    lang=self.tgt_lang,
                )
                for relative_index, translation in zip(indexes_to_translate, postprocessed):
                    translated_texts[relative_index] = translation.strip()

            for group, translated in zip(batch, translated_texts):
                translation_chunks.append(
                    TranslationChunk(
                        text=translated,
                        start_ms=int(group["start_ms"]),
                        end_ms=int(group["end_ms"]),
                    )
                )

        return translation_chunks

    def close(self) -> None:
        del self.model
        if self.device.type == "mps":
            self.torch.mps.empty_cache()


class GeminiClient:
    def __init__(
        self,
        api_key: str,
        transcription_model: str,
        translation_model: str,
        progress: ProgressPrinter,
    ) -> None:
        self.api_key = api_key.strip()
        self.transcription_model = transcription_model
        self.translation_model = translation_model
        self.progress = progress
        self.minimum_spacing_seconds = 1.0
        self.last_request_at = 0.0

    def transcribe(self, audio_path: Path) -> dict[str, object]:
        uploaded_file = self.upload_file(audio_path)
        try:
            response_text = self.generate_text(
                model=self.transcription_model,
                prompt=transcription_prompt(),
                uploaded_file=uploaded_file,
                response_mime_type="application/json",
                response_schema=transcription_schema(),
            )
        finally:
            try:
                self.delete_file(uploaded_file["name"])
            except Exception:
                pass

        payload = json.loads(response_text)
        transcript = str(payload.get("transcript", "")).strip()
        if not transcript:
            raise HarnessError(f"Gemini returned an empty transcript for {audio_path.name}")
        duration_ms = audio_duration_ms(audio_path)
        return {
            "detected_language": str(payload.get("language_code", "mr")).strip() or "mr",
            "segments": [
                {
                    "text": transcript,
                    "start_ms": 0,
                    "end_ms": duration_ms,
                }
            ],
        }

    def translate(self, segments: list[TranscriptSegment]) -> list[TranslationChunk]:
        groups = build_translation_groups(segments)
        if not groups:
            return []

        chunks: list[TranslationChunk] = []
        for group in groups:
            text = group["text"]
            translated = text
            if should_translate_group(text):
                translated = self.generate_text(
                    model=self.translation_model,
                    prompt=translation_prompt(text),
                    uploaded_file=None,
                ).strip()
            chunks.append(
                TranslationChunk(
                    text=translated or text,
                    start_ms=int(group["start_ms"]),
                    end_ms=int(group["end_ms"]),
                )
            )
        return chunks

    def upload_file(self, audio_path: Path) -> dict[str, str]:
        file_data = audio_path.read_bytes()
        mime_type = mime_type_for(audio_path)
        start_headers = {
            "x-goog-api-key": self.api_key,
            "X-Goog-Upload-Protocol": "resumable",
            "X-Goog-Upload-Command": "start",
            "X-Goog-Upload-Header-Content-Length": str(len(file_data)),
            "X-Goog-Upload-Header-Content-Type": mime_type,
            "Content-Type": "application/json",
        }
        metadata = {
            "file": {
                "display_name": audio_path.name,
            }
        }
        _, start_response_headers, _ = self.send_request(
            method="POST",
            url="https://generativelanguage.googleapis.com/upload/v1beta/files",
            headers=start_headers,
            body=json.dumps(metadata).encode("utf-8"),
        )
        upload_url = start_response_headers.get("x-goog-upload-url")
        if not upload_url:
            raise HarnessError("Gemini did not return an upload URL.")

        upload_headers = {
            "Content-Length": str(len(file_data)),
            "X-Goog-Upload-Offset": "0",
            "X-Goog-Upload-Command": "upload, finalize",
        }
        _, _, response_data = self.send_request(
            method="POST",
            url=upload_url,
            headers=upload_headers,
            body=file_data,
        )
        payload = json.loads(response_data.decode("utf-8"))
        file_payload = payload.get("file")
        if not isinstance(file_payload, dict):
            raise HarnessError("Gemini upload response was missing the uploaded file metadata.")
        return {
            "name": str(file_payload["name"]),
            "mime_type": str(file_payload["mimeType"]),
            "uri": str(file_payload["uri"]),
        }

    def delete_file(self, file_name: str) -> None:
        self.send_request(
            method="DELETE",
            url=f"https://generativelanguage.googleapis.com/v1beta/{file_name}",
            headers={"x-goog-api-key": self.api_key},
            body=None,
        )

    def generate_text(
        self,
        model: str,
        prompt: str,
        uploaded_file: dict[str, str] | None,
        response_mime_type: str | None = None,
        response_schema: dict[str, object] | None = None,
    ) -> str:
        parts: list[dict[str, object]] = []
        if uploaded_file:
            parts.append(
                {
                    "file_data": {
                        "mime_type": uploaded_file["mime_type"],
                        "file_uri": uploaded_file["uri"],
                    }
                }
            )
        parts.append({"text": prompt})

        payload: dict[str, object] = {
            "contents": [
                {
                    "parts": parts,
                }
            ]
        }
        if response_mime_type or response_schema:
            generation_config: dict[str, object] = {}
            if response_mime_type:
                generation_config["response_mime_type"] = response_mime_type
            if response_schema:
                generation_config["response_schema"] = response_schema
            payload["generation_config"] = generation_config

        _, _, response_data = self.send_request(
            method="POST",
            url=f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent",
            headers={
                "x-goog-api-key": self.api_key,
                "Content-Type": "application/json",
            },
            body=json.dumps(payload).encode("utf-8"),
        )
        parsed = json.loads(response_data.decode("utf-8"))
        candidates = parsed.get("candidates") or []
        if not candidates:
            raise HarnessError("Gemini returned no candidates.")
        parts = candidates[0].get("content", {}).get("parts", [])
        for part in parts:
            text = part.get("text")
            if isinstance(text, str) and text.strip():
                return text.strip()
        raise HarnessError("Gemini returned an empty text response.")

    def send_request(
        self,
        method: str,
        url: str,
        headers: dict[str, str],
        body: bytes | None,
        retries: int = 3,
    ) -> tuple[int, dict[str, str], bytes]:
        for attempt in range(1, retries + 1):
            self.wait_for_turn()
            request = urllib_request.Request(url=url, data=body, headers=headers, method=method)
            try:
                with urllib_request.urlopen(request, timeout=180) as response:
                    response_body = response.read()
                    response_headers = {key.lower(): value for key, value in response.headers.items()}
                    return response.status, response_headers, response_body
            except urllib_error.HTTPError as error:
                body_text = error.read().decode("utf-8", errors="replace").strip()
                retryable = error.code in {429, 500, 502, 503, 504}
                if attempt < retries and retryable:
                    time.sleep(min(20, 2 ** attempt))
                    continue
                raise HarnessError(
                    f"Gemini request failed with HTTP {error.code}: {body_text or error.reason}"
                ) from error
            except urllib_error.URLError as error:
                if attempt < retries:
                    time.sleep(min(20, 2 ** attempt))
                    continue
                raise HarnessError(f"Gemini request failed: {error.reason}") from error

        raise HarnessError("Gemini request failed after retries.")

    def wait_for_turn(self) -> None:
        elapsed = time.time() - self.last_request_at
        if elapsed < self.minimum_spacing_seconds:
            time.sleep(self.minimum_spacing_seconds - elapsed)
        self.last_request_at = time.time()


class GeminiASRBackend(ASRBackend):
    def __init__(self, client: GeminiClient) -> None:
        self.client = client

    def transcribe(self, audio_path: Path) -> dict[str, object]:
        return self.client.transcribe(audio_path)


class GeminiTranslationBackend(TranslationBackend):
    def __init__(self, client: GeminiClient) -> None:
        self.client = client

    def translate(self, segments: list[TranscriptSegment]) -> list[TranslationChunk]:
        return self.client.translate(segments)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Build a local-first audio evaluation bundle that compares multiple transcription and translation stacks on the same prepared audio variants."
        )
    )
    parser.add_argument("input_folder", help="Folder containing source audio files.")
    parser.add_argument(
        "--output-root",
        help="Optional output folder. Defaults to a sibling folder named output_eval_<timestamp>.",
    )
    parser.add_argument(
        "--seconds",
        type=int,
        default=60,
        help="How many seconds to keep from the start of each source file. Default: 60.",
    )
    parser.add_argument(
        "--non-recursive",
        action="store_true",
        help="Only scan the top level of the input folder.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Optional cap on the number of supported audio files to process.",
    )
    parser.add_argument(
        "--variants",
        default=",".join(DEFAULT_VARIANTS),
        help="Comma-separated variant keys to evaluate. Supported values: short,dfn,hybrid. Default: short,dfn",
    )
    parser.add_argument(
        "--stacks",
        default=",".join(DEFAULT_STACKS),
        help=(
            "Comma-separated model stacks to evaluate. Supported values: "
            "whispercpp_nllb,whispercpp_indictrans2,fasterwhisper_indictrans2,indicconformer_indictrans2,gemini_flash_lite"
        ),
    )
    parser.add_argument("--ffmpeg", help="Override FFmpeg path.")
    parser.add_argument("--deep-filter", dest="deep_filter", help="Override deep-filter path.")
    parser.add_argument("--whisper-cli", dest="whisper_cli", help="Override whisper-cli path.")
    parser.add_argument("--whisper-model-dir", dest="whisper_model_dir", help="Override whisper model directory.")
    parser.add_argument(
        "--runtime-python",
        dest="runtime_python",
        help="Override the shared Python runtime used for local model backends.",
    )
    parser.add_argument(
        "--nllb-model-dir",
        dest="nllb_model_dir",
        help="Override CTranslate2 NLLB model directory.",
    )
    parser.add_argument(
        "--hf-cache-dir",
        dest="hf_cache_dir",
        help="Override Hugging Face cache directory used for gated/local model downloads.",
    )
    parser.add_argument(
        "--whisper-threads",
        type=int,
        default=None,
        help="Override whisper.cpp thread count.",
    )
    parser.add_argument(
        "--faster-whisper-model",
        default="large-v3",
        help="Model name to use for faster-whisper. Default: large-v3",
    )
    parser.add_argument(
        "--indic-conformer-model",
        default="ai4bharat/indic-conformer-600m-multilingual",
        help="Hugging Face model id or local path for IndicConformer.",
    )
    parser.add_argument(
        "--indic-trans2-model",
        default="ai4bharat/indictrans2-indic-en-dist-200M",
        help="Hugging Face model id or local path for IndicTrans2.",
    )
    parser.add_argument(
        "--gemini-transcription-model",
        default="gemini-2.5-flash-lite",
        help="Gemini model name used for transcription. Default: gemini-2.5-flash-lite",
    )
    parser.add_argument(
        "--gemini-translation-model",
        default="gemini-2.5-flash-lite",
        help="Gemini model name used for translation. Default: gemini-2.5-flash-lite",
    )
    parser.add_argument(
        "--gemini-api-key",
        default=None,
        help="Optional Gemini API key. If omitted, the script reads the saved key once from Keychain.",
    )
    parser.add_argument(
        "--save-gemini-api-key",
        action="store_true",
        help="Save the provided Gemini API key to Keychain before evaluation.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parent.parent
    maybe_reexec_with_runtime_python(args, repo_root)

    input_folder = Path(args.input_folder).expanduser().resolve()
    if not input_folder.is_dir():
        print(f"Input folder does not exist: {input_folder}", file=sys.stderr)
        return 2

    output_root = resolve_output_root(input_folder, args.output_root)
    output_root.mkdir(parents=True, exist_ok=True)

    selected_variants = parse_variants(args.variants)
    selected_stacks = parse_stacks(args.stacks)

    toolchain = resolve_toolchain(args, repo_root)
    supported, skipped = scan_audio_files(
        input_folder=input_folder,
        recursive=not args.non_recursive,
        limit=args.limit,
    )
    write_skipped_log(output_root, skipped)

    if not supported:
        raise HarnessError(f"No supported audio files were found in {input_folder}.")

    total_steps = len(supported) * (
        1 + max(0, len(selected_variants) - (1 if "short" in selected_variants else 0))
        + (len(selected_variants) * len(selected_stacks))
    )
    progress = ProgressPrinter(total_steps=total_steps)
    progress.info(f"Preparing {len(supported)} source file(s) into {output_root}")

    prepared_sources = prepare_sources(
        supported=supported,
        output_root=output_root,
        toolchain=toolchain,
        seconds=args.seconds,
        selected_variants=selected_variants,
        progress=progress,
    )

    all_results: dict[str, dict[str, list[EvaluationResult]]] = {
        source.folder_path.name: {variant.key: [] for variant in source.variants.values()}
        for source in prepared_sources
    }

    for stack_name in selected_stacks:
        spec = stack_specification(stack_name)
        progress.info(f"Initializing stack: {spec.name}")
        stack_error: str | None = None
        asr_backend: ASRBackend | None = None
        translation_backend: TranslationBackend | None = None
        try:
            asr_backend = spec.asr_factory(toolchain, progress, args)
            translation_backend = spec.translation_factory(toolchain, progress, args)
            for prepared in prepared_sources:
                for variant in prepared.variants.values():
                    progress.step(
                        f"{prepared.source_path.name} :: {spec.name} :: {variant.label} :: transcribe + translate"
                    )
                    result = evaluate_variant(
                        prepared=prepared,
                        variant=variant,
                        spec=spec,
                        asr_backend=asr_backend,
                        translation_backend=translation_backend,
                    )
                    all_results[prepared.folder_path.name][variant.key].append(result)
                    write_stack_result_json(prepared.comparison_folder, result)
        except Exception as error:  # noqa: BLE001
            stack_error = str(error)
            progress.info(f"Stack failed to initialize: {spec.name} :: {stack_error}")
            for prepared in prepared_sources:
                for variant in prepared.variants.values():
                    result = EvaluationResult(
                        stack_name=spec.name,
                        stack_description=spec.description,
                        variant_key=variant.key,
                        variant_label=variant.label,
                        audio_path=variant.audio_path,
                        transcript_source_path=variant.transcript_source_path,
                        error=stack_error,
                    )
                    all_results[prepared.folder_path.name][variant.key].append(result)
                    write_stack_result_json(prepared.comparison_folder, result)
        finally:
            if asr_backend is not None:
                asr_backend.close()
            if translation_backend is not None:
                translation_backend.close()
            gc.collect()

    for prepared in prepared_sources:
        write_comparison_report(
            source_path=prepared.source_path,
            folder_path=prepared.folder_path,
            variants=prepared.variants,
            results_by_variant=all_results[prepared.folder_path.name],
        )

    progress.info(f"Evaluation output written to: {output_root}")
    return 0


def maybe_reexec_with_runtime_python(args: argparse.Namespace, repo_root: Path) -> None:
    if os.environ.get("CLEARVOICE_EVAL_REEXEC") == "1":
        return

    runtime_python = Path(
        args.runtime_python
        or (repo_root / ".build/local_translation/venv/bin/python")
    ).expanduser()
    if not runtime_python.exists():
        return

    current_python = Path(sys.executable).resolve()
    if current_python == runtime_python.resolve():
        return

    env = dict(os.environ)
    env["CLEARVOICE_EVAL_REEXEC"] = "1"
    os.execve(
        str(runtime_python),
        [str(runtime_python), str(Path(__file__).resolve()), *sys.argv[1:]],
        env,
    )


def parse_variants(raw_variants: str) -> list[str]:
    allowed = {"short", "dfn", "hybrid"}
    variants = [variant.strip().lower() for variant in raw_variants.split(",") if variant.strip()]
    if not variants:
        raise HarnessError("At least one audio variant must be selected.")
    invalid = [variant for variant in variants if variant not in allowed]
    if invalid:
        raise HarnessError(f"Unsupported variant(s): {', '.join(invalid)}")
    return variants


def parse_stacks(raw_stacks: str) -> list[str]:
    allowed = {
        "whispercpp_nllb",
        "whispercpp_indictrans2",
        "fasterwhisper_indictrans2",
        "indicconformer_indictrans2",
        "gemini_flash_lite",
    }
    stacks = [stack.strip() for stack in raw_stacks.split(",") if stack.strip()]
    if not stacks:
        raise HarnessError("At least one model stack must be selected.")
    invalid = [stack for stack in stacks if stack not in allowed]
    if invalid:
        raise HarnessError(f"Unsupported stack(s): {', '.join(invalid)}")
    return stacks


def resolve_output_root(input_folder: Path, explicit_output: str | None) -> Path:
    if explicit_output:
        return Path(explicit_output).expanduser().resolve()
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    return input_folder.parent / f"output_eval_{timestamp}"


def resolve_toolchain(args: argparse.Namespace, repo_root: Path) -> Toolchain:
    ffmpeg = resolve_executable(
        explicit=args.ffmpeg,
        env_name="FFMPEG_PATH",
        binary_name="ffmpeg",
        candidates=[
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg",
        ],
    )
    deep_filter = resolve_executable(
        explicit=args.deep_filter,
        env_name="DEEP_FILTER_PATH",
        binary_name="deep-filter",
        candidates=[
            "/opt/homebrew/bin/deep-filter",
            "/usr/local/bin/deep-filter",
            "/tmp/deep-filter",
        ],
    )
    whisper_cli = resolve_executable(
        explicit=args.whisper_cli,
        env_name="WHISPER_CPP_CLI_PATH",
        binary_name="whisper-cli",
        candidates=[
            "/tmp/clearvoice_whispercpp_build_v184/bin/whisper-cli",
            str(Path.home() / "Library/Application Support/ClearVoice/Tools/whisper.cpp/bin/whisper-cli"),
            "/opt/homebrew/bin/whisper-cli",
            "/usr/local/bin/whisper-cli",
        ],
    )
    whisper_model_dir = Path(
        args.whisper_model_dir
        or (Path.home() / "Library/Application Support/ClearVoice/Models/whisper.cpp")
    ).expanduser().resolve()
    runtime_python = Path(
        args.runtime_python
        or (repo_root / ".build/local_translation/venv/bin/python")
    ).expanduser().resolve()
    nllb_model_dir = Path(
        args.nllb_model_dir
        or (repo_root / ".build/local_translation/models/nllb-200-distilled-600M-int8")
    ).expanduser().resolve()
    hf_cache_dir = Path(
        args.hf_cache_dir
        or (repo_root / ".build/model_eval/hf_home")
    ).expanduser().resolve()
    hf_cache_dir.mkdir(parents=True, exist_ok=True)

    if not runtime_python.exists():
        raise HarnessError(f"Shared runtime Python not found: {runtime_python}")
    if not nllb_model_dir.exists():
        raise HarnessError(f"NLLB model directory not found: {nllb_model_dir}")

    return Toolchain(
        repo_root=repo_root,
        ffmpeg=ffmpeg,
        deep_filter=deep_filter,
        whisper_cli=whisper_cli,
        whisper_model_dir=whisper_model_dir,
        runtime_python=runtime_python,
        nllb_model_dir=nllb_model_dir,
        hf_cache_dir=hf_cache_dir,
        whisper_threads=args.whisper_threads or default_whisper_threads(),
        faster_whisper_model=args.faster_whisper_model,
        indic_conformer_model=args.indic_conformer_model,
        indic_trans2_model=args.indic_trans2_model,
        gemini_transcription_model=args.gemini_transcription_model,
        gemini_translation_model=args.gemini_translation_model,
    )


def resolve_executable(
    explicit: str | None,
    env_name: str,
    binary_name: str,
    candidates: list[str],
) -> Path:
    candidate_paths: list[str] = []
    if explicit:
        candidate_paths.append(explicit)
    env_value = os.environ.get(env_name)
    if env_value:
        candidate_paths.append(env_value)
    which_path = shutil.which(binary_name)
    if which_path:
        candidate_paths.append(which_path)
    candidate_paths.extend(candidates)
    for candidate in candidate_paths:
        expanded = Path(candidate).expanduser()
        if expanded.exists() and os.access(expanded, os.X_OK):
            return expanded.resolve()
    raise HarnessError(f"Required executable not found: {binary_name}")


def default_whisper_threads() -> int:
    cpu_count = os.cpu_count() or 4
    return max(4, cpu_count - 2)


def scan_audio_files(
    input_folder: Path,
    recursive: bool,
    limit: int | None,
) -> tuple[list[Path], list[Path]]:
    iterator: Iterable[Path]
    if recursive:
        iterator = (path for path in input_folder.rglob("*") if path.is_file())
    else:
        iterator = (path for path in input_folder.iterdir() if path.is_file())

    supported: list[Path] = []
    skipped: list[Path] = []

    for path in sorted(iterator, key=audio_sort_key):
        if path.name.startswith("._"):
            skipped.append(path)
            continue
        extension = path.suffix.lower().lstrip(".")
        if extension not in ACCEPTED_SOURCE_EXTENSIONS:
            skipped.append(path)
            continue
        supported.append(path)
        if limit is not None and len(supported) >= limit:
            break
    return supported, skipped


def audio_sort_key(path: Path) -> tuple[str, str, str]:
    return (path.stem.lower(), path.suffix.lower(), path.name.lower())


def write_skipped_log(output_root: Path, skipped: list[Path]) -> None:
    if not skipped:
        return
    lines = ["SKIPPED FILES", ""]
    for path in skipped:
        lines.append(f"{path} | unsupported extension")
    (output_root / "_skipped.log").write_text("\n".join(lines) + "\n", encoding="utf-8")


def prepare_sources(
    supported: list[Path],
    output_root: Path,
    toolchain: Toolchain,
    seconds: int,
    selected_variants: list[str],
    progress: ProgressPrinter,
) -> list[PreparedSource]:
    used_folder_names: set[str] = set()
    prepared_sources: list[PreparedSource] = []

    for source_path in supported:
        folder_name = unique_folder_name(source_path.stem, used_folder_names)
        folder_path = output_root / folder_name
        folder_path.mkdir(parents=True, exist_ok=True)
        comparison_folder = folder_path / COMPARISON_FOLDER
        comparison_folder.mkdir(parents=True, exist_ok=True)
        transcription_folder = folder_path / TRANSCRIPTION_INPUTS_FOLDER
        transcription_folder.mkdir(parents=True, exist_ok=True)

        progress.step(f"{source_path.name} :: extract SHORT")
        short_output = folder_path / f"{source_path.stem}{SHORT_SUFFIX}.wav"
        extract_short_clip(toolchain.ffmpeg, source_path, short_output, seconds)
        short_transcription = transcription_folder / f"{source_path.stem}{SHORT_SUFFIX}_transcribe.wav"
        create_transcription_master(toolchain.ffmpeg, short_output, short_transcription)

        variants: dict[str, AudioVariantArtifact] = {}
        if "short" in selected_variants:
            variants["short"] = AudioVariantArtifact(
                key="short",
                label="SHORT",
                audio_path=short_output,
                transcript_source_path=short_transcription,
            )

        if "dfn" in selected_variants:
            progress.step(f"{source_path.name} :: build DFN")
            dfn_output = folder_path / f"{source_path.stem}{DFN_SUFFIX}.m4a"
            dfn_transcription = transcription_folder / f"{source_path.stem}{DFN_SUFFIX}_transcribe.wav"
            enhance_with_deepfilternet(
                input_path=short_output,
                output_path=dfn_output,
                transcription_output_path=dfn_transcription,
                toolchain=toolchain,
                preprocess_filter=DFN_PREPROCESS_FILTER,
                postprocess_filter=DFN_POSTPROCESS_FILTER,
            )
            variants["dfn"] = AudioVariantArtifact(
                key="dfn",
                label="DFN",
                audio_path=dfn_output,
                transcript_source_path=dfn_transcription,
            )

        if "hybrid" in selected_variants:
            progress.step(f"{source_path.name} :: build HYBRID")
            hybrid_output = folder_path / f"{source_path.stem}{HYBRID_SUFFIX}.m4a"
            hybrid_transcription = transcription_folder / f"{source_path.stem}{HYBRID_SUFFIX}_transcribe.wav"
            enhance_with_deepfilternet(
                input_path=short_output,
                output_path=hybrid_output,
                transcription_output_path=hybrid_transcription,
                toolchain=toolchain,
                preprocess_filter=HYBRID_PREPROCESS_FILTER,
                postprocess_filter=HYBRID_POSTPROCESS_FILTER,
            )
            variants["hybrid"] = AudioVariantArtifact(
                key="hybrid",
                label="HYBRID",
                audio_path=hybrid_output,
                transcript_source_path=hybrid_transcription,
            )

        prepared_sources.append(
            PreparedSource(
                source_path=source_path,
                folder_path=folder_path,
                comparison_folder=comparison_folder,
                variants=variants,
            )
        )

    return prepared_sources


def unique_folder_name(base_name: str, used_folder_names: set[str]) -> str:
    candidate = base_name
    suffix = 2
    while candidate in used_folder_names:
        candidate = f"{base_name}_{suffix}"
        suffix += 1
    used_folder_names.add(candidate)
    return candidate


def extract_short_clip(ffmpeg: Path, source_path: Path, output_path: Path, seconds: int) -> None:
    run_command(
        [
            str(ffmpeg),
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-i",
            str(source_path),
            "-t",
            str(seconds),
            "-vn",
            "-ac",
            "1",
            "-ar",
            "48000",
            "-c:a",
            "pcm_s16le",
            str(output_path),
        ],
        error_prefix=f"Failed to extract short clip from {source_path.name}",
    )


def create_transcription_master(ffmpeg: Path, source_path: Path, output_path: Path) -> None:
    run_command(
        [
            str(ffmpeg),
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-i",
            str(source_path),
            "-vn",
            "-ac",
            "1",
            "-ar",
            "16000",
            "-c:a",
            "pcm_s16le",
            str(output_path),
        ],
        error_prefix=f"Failed to create transcription master for {source_path.name}",
    )


def enhance_with_deepfilternet(
    input_path: Path,
    output_path: Path,
    transcription_output_path: Path,
    toolchain: Toolchain,
    preprocess_filter: str,
    postprocess_filter: str,
) -> None:
    with tempfile.TemporaryDirectory(prefix="cv_eval_dfn_") as temp_dir:
        temp_root = Path(temp_dir)
        repaired_input = temp_root / "deepfilter_input.wav"
        deepfilter_output_dir = temp_root / "deepfilter_out"
        deepfilter_output_dir.mkdir(parents=True, exist_ok=True)

        run_command(
            [
                str(toolchain.ffmpeg),
                "-hide_banner",
                "-loglevel",
                "error",
                "-y",
                "-i",
                str(input_path),
                "-vn",
                "-af",
                preprocess_filter,
                "-ac",
                "1",
                "-ar",
                "48000",
                "-c:a",
                "pcm_s16le",
                str(repaired_input),
            ],
            error_prefix=f"Failed to preprocess {input_path.name} for {output_path.stem}",
        )

        run_command(
            [
                str(toolchain.deep_filter),
                "--compensate-delay",
                "-o",
                str(deepfilter_output_dir),
                str(repaired_input),
            ],
            error_prefix=f"DeepFilterNet failed for {input_path.name}",
        )

        enhanced_wav = locate_deepfilter_output(
            expected_filename=repaired_input.name,
            output_directory=deepfilter_output_dir,
        )

        run_command(
            [
                str(toolchain.ffmpeg),
                "-hide_banner",
                "-loglevel",
                "error",
                "-y",
                "-i",
                str(enhanced_wav),
                "-vn",
                "-af",
                postprocess_filter,
                "-map",
                "0:a",
                "-ac",
                "1",
                "-ar",
                "16000",
                "-c:a",
                "aac",
                "-b:a",
                "96k",
                str(output_path),
                "-map",
                "0:a",
                "-ac",
                "1",
                "-ar",
                "16000",
                "-c:a",
                "pcm_s16le",
                str(transcription_output_path),
            ],
            error_prefix=f"Failed to export {output_path.name}",
        )


def locate_deepfilter_output(expected_filename: str, output_directory: Path) -> Path:
    expected = output_directory / expected_filename
    if expected.exists():
        return expected
    expected_stem = Path(expected_filename).stem
    matching = sorted(path for path in output_directory.glob("*.wav") if path.stem == expected_stem)
    if matching:
        return matching[0]
    wavs = sorted(output_directory.glob("*.wav"))
    if wavs:
        return wavs[0]
    raise HarnessError(f"DeepFilterNet finished but no WAV output was found in {output_directory}.")


def stack_specification(stack_name: str) -> StackSpec:
    if stack_name == "whispercpp_nllb":
        return StackSpec(
            name="whispercpp_nllb",
            description="whisper.cpp (large-v3-turbo with large-v3 fallback) + NLLB-200 distilled 600M",
            asr_factory=lambda toolchain, progress, args: WhisperCppASRBackend(toolchain),
            translation_factory=lambda toolchain, progress, args: CTranslate2TranslationBackend(
                model_dir=toolchain.nllb_model_dir,
                source_lang="mar_Deva",
                target_lang="eng_Latn",
                intra_threads=max(1, (os.cpu_count() or 4) // 2),
            ),
        )
    if stack_name == "whispercpp_indictrans2":
        return StackSpec(
            name="whispercpp_indictrans2",
            description="whisper.cpp (large-v3-turbo with large-v3 fallback) + IndicTrans2 distilled 200M",
            asr_factory=lambda toolchain, progress, args: WhisperCppASRBackend(toolchain),
            translation_factory=lambda toolchain, progress, args: IndicTrans2TranslationBackend(toolchain),
        )
    if stack_name == "fasterwhisper_indictrans2":
        return StackSpec(
            name="fasterwhisper_indictrans2",
            description="faster-whisper large-v3 + IndicTrans2 distilled 200M",
            asr_factory=lambda toolchain, progress, args: FasterWhisperASRBackend(toolchain),
            translation_factory=lambda toolchain, progress, args: IndicTrans2TranslationBackend(toolchain),
        )
    if stack_name == "indicconformer_indictrans2":
        return StackSpec(
            name="indicconformer_indictrans2",
            description="AI4Bharat IndicConformer 600M multilingual + IndicTrans2 distilled 200M",
            asr_factory=lambda toolchain, progress, args: IndicConformerASRBackend(toolchain),
            translation_factory=lambda toolchain, progress, args: IndicTrans2TranslationBackend(toolchain),
        )
    if stack_name == "gemini_flash_lite":
        return StackSpec(
            name="gemini_flash_lite",
            description="Gemini 2.5 Flash-Lite for both transcription and translation (benchmark control)",
            asr_factory=lambda toolchain, progress, args: GeminiASRBackend(
                gemini_client(toolchain, progress, args)
            ),
            translation_factory=lambda toolchain, progress, args: GeminiTranslationBackend(
                gemini_client(toolchain, progress, args)
            ),
        )
    raise HarnessError(f"Unsupported stack: {stack_name}")


_GEMINI_CLIENT_CACHE: GeminiClient | None = None


def gemini_client(toolchain: Toolchain, progress: ProgressPrinter, args: argparse.Namespace) -> GeminiClient:
    global _GEMINI_CLIENT_CACHE
    if _GEMINI_CLIENT_CACHE is not None:
        return _GEMINI_CLIENT_CACHE

    api_key = resolve_gemini_api_key(
        explicit=args.gemini_api_key,
        save_to_keychain=args.save_gemini_api_key,
    )
    _GEMINI_CLIENT_CACHE = GeminiClient(
        api_key=api_key,
        transcription_model=toolchain.gemini_transcription_model,
        translation_model=toolchain.gemini_translation_model,
        progress=progress,
    )
    progress.info("Gemini API key loaded once for this run and cached in memory.")
    return _GEMINI_CLIENT_CACHE


def resolve_gemini_api_key(explicit: str | None, save_to_keychain: bool) -> str:
    if explicit:
        api_key = explicit.strip()
        if not api_key:
            raise HarnessError("The provided Gemini API key was empty.")
        if save_to_keychain:
            save_gemini_api_key(api_key)
        return api_key

    for env_name in ("CLEARVOICE_GEMINI_API_KEY", "GEMINI_API_KEY"):
        env_value = os.environ.get(env_name)
        if env_value and env_value.strip():
            if save_to_keychain:
                save_gemini_api_key(env_value.strip())
            return env_value.strip()

    api_key = read_gemini_api_key_from_keychain()
    if api_key:
        return api_key

    raise HarnessError(
        "Gemini API key not found. Set CLEARVOICE_GEMINI_API_KEY or pass --gemini-api-key."
    )


def read_gemini_api_key_from_keychain() -> str | None:
    command = [
        "security",
        "find-generic-password",
        "-w",
        "-s",
        GEMINI_SERVICE,
        "-a",
        GEMINI_ACCOUNT,
    ]
    completed = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        return None
    key = completed.stdout.decode("utf-8", errors="replace").strip()
    return key or None


def save_gemini_api_key(api_key: str) -> None:
    command = [
        "security",
        "add-generic-password",
        "-U",
        "-s",
        GEMINI_SERVICE,
        "-a",
        GEMINI_ACCOUNT,
        "-w",
        api_key,
    ]
    completed = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        detail = completed.stderr.decode("utf-8", errors="replace").strip()
        raise HarnessError(f"Failed to save Gemini API key to Keychain: {detail}")


def evaluate_variant(
    prepared: PreparedSource,
    variant: AudioVariantArtifact,
    spec: StackSpec,
    asr_backend: ASRBackend,
    translation_backend: TranslationBackend,
) -> EvaluationResult:
    try:
        transcript_payload = asr_backend.transcribe(variant.transcript_source_path)
        transcript_segments = [
            TranscriptSegment(
                text=str(segment["text"]).strip(),
                start_ms=int(segment["start_ms"]),
                end_ms=int(segment["end_ms"]),
            )
            for segment in transcript_payload["segments"]
            if str(segment["text"]).strip()
        ]
        if not transcript_segments:
            raise HarnessError(
                f"{spec.name} returned an empty transcript for {variant.transcript_source_path.name}"
            )
        translation_chunks = translation_backend.translate(transcript_segments)
        return EvaluationResult(
            stack_name=spec.name,
            stack_description=spec.description,
            variant_key=variant.key,
            variant_label=variant.label,
            audio_path=variant.audio_path,
            transcript_source_path=variant.transcript_source_path,
            transcript_segments=transcript_segments,
            translation_chunks=translation_chunks,
            transcript_language=str(transcript_payload.get("detected_language", "mr")),
        )
    except Exception as error:  # noqa: BLE001
        return EvaluationResult(
            stack_name=spec.name,
            stack_description=spec.description,
            variant_key=variant.key,
            variant_label=variant.label,
            audio_path=variant.audio_path,
            transcript_source_path=variant.transcript_source_path,
            error=str(error),
        )


def write_stack_result_json(comparison_folder: Path, result: EvaluationResult) -> None:
    stack_folder = comparison_folder / result.stack_name
    stack_folder.mkdir(parents=True, exist_ok=True)
    path = stack_folder / f"{result.variant_key}.json"
    payload = {
        "stack_name": result.stack_name,
        "stack_description": result.stack_description,
        "variant_key": result.variant_key,
        "variant_label": result.variant_label,
        "audio_path": str(result.audio_path),
        "transcription_source_path": str(result.transcript_source_path),
        "language": result.transcript_language,
        "error": result.error,
        "transcript_segments": [
            {
                "text": segment.text,
                "start_ms": segment.start_ms,
                "end_ms": segment.end_ms,
            }
            for segment in (result.transcript_segments or [])
        ],
        "translation_chunks": [
            {
                "text": chunk.text,
                "start_ms": chunk.start_ms,
                "end_ms": chunk.end_ms,
            }
            for chunk in (result.translation_chunks or [])
        ],
    }
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def write_comparison_report(
    source_path: Path,
    folder_path: Path,
    variants: dict[str, AudioVariantArtifact],
    results_by_variant: dict[str, list[EvaluationResult]],
) -> None:
    report_path = folder_path / f"{source_path.stem}_comparison.txt"
    json_path = folder_path / f"{source_path.stem}_comparison.json"

    text_lines = [
        "CLEARVOICE MODEL COMPARISON REPORT",
        f"SOURCE FILE: {source_path}",
        f"SOURCE NAME: {source_path.name}",
        f"GENERATED AT: {datetime.now().isoformat(timespec='seconds')}",
        "",
    ]

    json_payload: dict[str, object] = {
        "source_file": str(source_path),
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "variants": {},
    }

    for variant_key, variant in variants.items():
        variant_results = results_by_variant.get(variant_key, [])
        text_lines.extend(
            [
                "=" * 80,
                f"VARIANT: {variant.label}",
                f"AUDIO FILE: {variant.audio_path.name}",
                f"AUDIO PATH: {variant.audio_path}",
                f"TRANSCRIPTION SOURCE: {variant.transcript_source_path}",
                "",
            ]
        )

        variant_json: dict[str, object] = {
            "variant_label": variant.label,
            "audio_path": str(variant.audio_path),
            "transcription_source_path": str(variant.transcript_source_path),
            "stacks": [],
        }

        for result in variant_results:
            text_lines.extend(
                [
                    "-" * 80,
                    f"STACK: {result.stack_name}",
                    f"DESCRIPTION: {result.stack_description}",
                ]
            )
            stack_json = {
                "stack_name": result.stack_name,
                "stack_description": result.stack_description,
                "language": result.transcript_language,
                "error": result.error,
                "transcript_segments": [
                    {
                        "text": segment.text,
                        "start_ms": segment.start_ms,
                        "end_ms": segment.end_ms,
                    }
                    for segment in (result.transcript_segments or [])
                ],
                "translation_chunks": [
                    {
                        "text": chunk.text,
                        "start_ms": chunk.start_ms,
                        "end_ms": chunk.end_ms,
                    }
                    for chunk in (result.translation_chunks or [])
                ],
            }

            if result.error:
                text_lines.extend(
                    [
                        "STATUS: ERROR",
                        f"ERROR: {result.error}",
                        "",
                    ]
                )
                variant_json["stacks"].append(stack_json)
                continue

            text_lines.extend(
                [
                    "STATUS: SUCCESS",
                    f"LANGUAGE: {result.transcript_language or 'mr'}",
                    "",
                    "TRANSCRIPT",
                    format_transcript_segments(result.transcript_segments or []),
                    "",
                    "ENGLISH TRANSLATION",
                    format_translation_chunks(result.translation_chunks or []),
                    "",
                ]
            )
            variant_json["stacks"].append(stack_json)

        json_payload["variants"][variant_key] = variant_json

    report_path.write_text("\n".join(text_lines).rstrip() + "\n", encoding="utf-8")
    json_path.write_text(json.dumps(json_payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def format_transcript_segments(segments: list[TranscriptSegment]) -> str:
    if not segments:
        return "[no transcript available]"
    return "\n".join(
        f"[{timestamp_string(segment.start_ms)} --> {timestamp_string(segment.end_ms)}]   {segment.text}"
        for segment in segments
    )


def format_translation_chunks(chunks: list[TranslationChunk]) -> str:
    if not chunks:
        return "[no translation available]"
    return "\n".join(
        f"[{timestamp_string(chunk.start_ms)} --> {timestamp_string(chunk.end_ms)}]   {chunk.text}"
        for chunk in chunks
    )


def timestamp_string(milliseconds: int) -> str:
    total_ms = max(0, milliseconds)
    hours = total_ms // 3_600_000
    minutes = (total_ms % 3_600_000) // 60_000
    seconds = (total_ms % 60_000) // 1_000
    ms = total_ms % 1_000
    return f"{hours:02d}:{minutes:02d}:{seconds:02d}.{ms:03d}"


def audio_duration_ms(audio_path: Path) -> int:
    with wave.open(str(audio_path), "rb") as handle:
        frames = handle.getnframes()
        framerate = handle.getframerate()
    return int((frames / max(1, framerate)) * 1000)


def build_translation_groups(segments: list[TranscriptSegment]) -> list[dict[str, object]]:
    groups: list[dict[str, object]] = []
    current_segments: list[TranscriptSegment] = []

    for segment in segments:
        text = segment.text.strip()
        if not text:
            continue
        current_segments.append(segment)
        current_text = " ".join(item.text.strip() for item in current_segments).strip()
        should_flush = text.endswith(("।", ".", "?", "!")) or len(current_text) >= 240
        if should_flush:
            groups.append(
                {
                    "text": current_text,
                    "start_ms": current_segments[0].start_ms,
                    "end_ms": current_segments[-1].end_ms,
                }
            )
            current_segments = []

    if current_segments:
        groups.append(
            {
                "text": " ".join(item.text.strip() for item in current_segments).strip(),
                "start_ms": current_segments[0].start_ms,
                "end_ms": current_segments[-1].end_ms,
            }
        )

    return groups


def group_batches(
    groups: list[dict[str, object]],
    max_batch_size: int,
    max_batch_characters: int,
) -> list[list[dict[str, object]]]:
    batches: list[list[dict[str, object]]] = []
    current_batch: list[dict[str, object]] = []
    current_characters = 0

    for group in groups:
        text = str(group["text"])
        proposed_characters = current_characters + len(text)
        if current_batch and (
            len(current_batch) >= max_batch_size or proposed_characters > max_batch_characters
        ):
            batches.append(current_batch)
            current_batch = []
            current_characters = 0

        current_batch.append(group)
        current_characters += len(text)

    if current_batch:
        batches.append(current_batch)
    return batches


def should_translate_group(text: str) -> bool:
    total_letters = sum(1 for character in text if character.isalpha())
    if total_letters == 0:
        return False
    devanagari_letters = sum(1 for character in text if "\u0900" <= character <= "\u097F")
    return (devanagari_letters / total_letters) > 0.3


def load_pcm_wave_tensor(audio_path: Path, torch_module, numpy_module):
    with wave.open(str(audio_path), "rb") as handle:
        channels = handle.getnchannels()
        sample_width = handle.getsampwidth()
        frame_rate = handle.getframerate()
        frames = handle.readframes(handle.getnframes())

    if channels != 1 or sample_width != 2 or frame_rate != 16000:
        raise HarnessError(
            f"IndicConformer expected a mono 16 kHz PCM WAV input, but got channels={channels}, sample_width={sample_width}, sample_rate={frame_rate} for {audio_path.name}"
        )

    waveform = numpy_module.frombuffer(frames, dtype=numpy_module.int16).astype(numpy_module.float32) / 32768.0
    return torch_module.from_numpy(waveform).unsqueeze(0)


def mime_type_for(path: Path) -> str:
    mime_type, _ = mimetypes.guess_type(path.name)
    return mime_type or "application/octet-stream"


def transcription_prompt() -> str:
    return (
        "Transcribe this audio exactly as spoken. "
        "Return valid JSON only with keys transcript, language_code, confidence_estimate. "
        "Do not include timestamps, markdown, commentary, or any extra keys."
    )


def transcription_schema() -> dict[str, object]:
    return {
        "type": "OBJECT",
        "properties": {
            "transcript": {"type": "STRING"},
            "language_code": {"type": "STRING"},
            "confidence_estimate": {"type": "NUMBER"},
        },
        "required": ["transcript", "language_code", "confidence_estimate"],
    }


def translation_prompt(text: str) -> str:
    return (
        "Translate the following transcript into clear natural English. "
        "Preserve meaning, including spiritual or philosophical wording when present. "
        "Return only the translation.\n\n"
        f"{text}"
    )


def whisper_arguments(
    executable: Path,
    model_path: Path,
    audio_path: Path,
    output_prefix: Path,
    threads: int,
    no_gpu: bool,
) -> list[str]:
    arguments = [
        str(executable),
        "-m",
        str(model_path),
        "-f",
        str(audio_path),
        "-l",
        "mr",
        "-t",
        str(threads),
        "-oj",
        "-of",
        str(output_prefix),
        "--max-context",
        "0",
        "--temperature",
        "0.0",
        "--temperature-inc",
        "0.2",
        "--entropy-thold",
        "2.4",
        "--logprob-thold",
        "-1.0",
        "--no-speech-thold",
        "0.6",
    ]
    if no_gpu:
        arguments.append("-ng")
    return arguments


def whisper_error_prefix(source_audio: Path, model_name: str, no_gpu: bool) -> str:
    mode = "cpu" if no_gpu else "gpu"
    return f"whisper.cpp failed for {source_audio.name} with model {model_name} ({mode})"


def whisper_environment(whisper_cli: Path) -> dict[str, str]:
    environment = dict(os.environ)
    build_root = whisper_cli.parent.parent
    search_paths = [
        build_root / "src",
        build_root / "ggml/src",
        build_root / "ggml/src/ggml-blas",
        build_root / "ggml/src/ggml-metal",
    ]
    existing = environment.get("DYLD_LIBRARY_PATH")
    resolved = [str(path) for path in search_paths if path.exists()]
    if existing:
        resolved.append(existing)
    if resolved:
        environment["DYLD_LIBRARY_PATH"] = ":".join(resolved)
    environment.setdefault("HF_HOME", str(build_root))
    return environment


def run_command(
    command: list[str],
    error_prefix: str,
    stdin: bytes | None = None,
    env: dict[str, str] | None = None,
    timeout: int | float | None = None,
) -> bytes:
    try:
        completed = subprocess.run(
            command,
            input=stdin,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as error:
        raise HarnessError(f"{error_prefix}: timed out after {timeout} seconds") from error
    except OSError as error:
        raise HarnessError(f"{error_prefix}: {error}") from error

    if completed.returncode != 0:
        detail = completed.stderr.decode("utf-8", errors="replace").strip()
        if not detail:
            detail = completed.stdout.decode("utf-8", errors="replace").strip()
        raise HarnessError(f"{error_prefix}: {detail or 'unknown failure'}")

    return completed.stdout


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except HarnessError as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)

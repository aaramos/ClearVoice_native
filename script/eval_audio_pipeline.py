#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterable


ACCEPTED_SOURCE_EXTENSIONS = {
    "wav",
    "mp3",
    "m4a",
    "aac",
    "flac",
    "wma",
}

SHORT_SUFFIX = "_short"
DFN_SUFFIX = "_DFN"
HYBRID_SUFFIX = "_HYBRID"
TRANSCRIPTION_INPUTS_FOLDER = "_transcription_inputs"

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


class HarnessError(Exception):
    pass


@dataclass
class Toolchain:
    ffmpeg: Path
    deep_filter: Path
    whisper_cli: Path
    whisper_model_dir: Path
    translation_python: Path
    translation_helper: Path
    translation_model_dir: Path
    whisper_threads: int


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
class VariantResult:
    label: str
    audio_path: Path
    transcript_source_path: Path
    transcript_segments: list[TranscriptSegment] | None = None
    translation_chunks: list[TranslationChunk] | None = None
    transcript_language: str | None = None
    error: str | None = None

    @property
    def succeeded(self) -> bool:
        return self.error is None and self.transcript_segments is not None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Build a short-form audio evaluation bundle for ClearVoice transcription and translation review."
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
    parser.add_argument("--ffmpeg", help="Override FFmpeg path.")
    parser.add_argument("--deep-filter", dest="deep_filter", help="Override deep-filter path.")
    parser.add_argument("--whisper-cli", dest="whisper_cli", help="Override whisper-cli path.")
    parser.add_argument("--whisper-model-dir", dest="whisper_model_dir", help="Override whisper model directory.")
    parser.add_argument(
        "--translation-python",
        dest="translation_python",
        help="Override Python executable used for NLLB translation helper.",
    )
    parser.add_argument(
        "--translation-helper",
        dest="translation_helper",
        help="Override path to nllb_translate.py helper.",
    )
    parser.add_argument(
        "--translation-model-dir",
        dest="translation_model_dir",
        help="Override CTranslate2 NLLB model directory.",
    )
    parser.add_argument(
        "--whisper-threads",
        type=int,
        default=None,
        help="Override whisper.cpp thread count.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parent.parent
    input_folder = Path(args.input_folder).expanduser().resolve()

    if not input_folder.is_dir():
        print(f"Input folder does not exist: {input_folder}", file=sys.stderr)
        return 2

    output_root = resolve_output_root(input_folder, args.output_root)
    output_root.mkdir(parents=True, exist_ok=True)

    toolchain = resolve_toolchain(args, repo_root)

    supported, skipped = scan_audio_files(
        input_folder=input_folder,
        recursive=not args.non_recursive,
        limit=args.limit,
    )

    write_skipped_log(output_root, skipped)

    if not supported:
        raise HarnessError(
            f"No supported audio files were found in {input_folder}."
        )

    used_folder_names: set[str] = set()

    for source_path in supported:
        process_source_file(
            source_path=source_path,
            output_root=output_root,
            toolchain=toolchain,
            used_folder_names=used_folder_names,
            seconds=args.seconds,
        )

    print(f"Evaluation output written to: {output_root}")
    return 0


def resolve_output_root(input_folder: Path, explicit_output: str | None) -> Path:
    if explicit_output:
        return Path(explicit_output).expanduser().resolve()

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    return input_folder.parent / f"output_eval_{timestamp}"


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
    return (
        path.stem.lower(),
        path.suffix.lower(),
        path.name.lower(),
    )


def write_skipped_log(output_root: Path, skipped: list[Path]) -> None:
    if not skipped:
        return

    lines = ["SKIPPED FILES", ""]
    for path in skipped:
        lines.append(f"{path} | unsupported extension")

    (output_root / "_skipped.log").write_text("\n".join(lines) + "\n", encoding="utf-8")


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
            str(
                Path.home()
                / "Library/Application Support/ClearVoice/Tools/whisper.cpp/bin/whisper-cli"
            ),
            "/opt/homebrew/bin/whisper-cli",
            "/usr/local/bin/whisper-cli",
        ],
    )

    whisper_model_dir = Path(
        args.whisper_model_dir
        or (
            Path.home()
            / "Library/Application Support/ClearVoice/Models/whisper.cpp"
        )
    ).expanduser().resolve()

    translation_python = Path(
        args.translation_python
        or (
            repo_root
            / ".build/local_translation/venv/bin/python"
        )
    ).expanduser()
    translation_helper = Path(
        args.translation_helper
        or (repo_root / "ClearVoice/Support/nllb_translate.py")
    ).expanduser().resolve()
    translation_model_dir = Path(
        args.translation_model_dir
        or (
            repo_root
            / ".build/local_translation/models/nllb-200-distilled-600M-int8"
        )
    ).expanduser().resolve()

    if not translation_python.exists():
        raise HarnessError(f"Translation Python runtime not found: {translation_python}")
    if not translation_helper.exists():
        raise HarnessError(f"NLLB translation helper not found: {translation_helper}")
    if not translation_model_dir.exists():
        raise HarnessError(f"NLLB model directory not found: {translation_model_dir}")

    primary_model = whisper_model_dir / "ggml-large-v3-turbo.bin"
    fallback_model = whisper_model_dir / "ggml-large-v3.bin"
    if not primary_model.exists() and not fallback_model.exists():
        raise HarnessError(
            f"No whisper.cpp model found in {whisper_model_dir}."
        )

    whisper_threads = args.whisper_threads or default_whisper_threads()

    return Toolchain(
        ffmpeg=ffmpeg,
        deep_filter=deep_filter,
        whisper_cli=whisper_cli,
        whisper_model_dir=whisper_model_dir,
        translation_python=translation_python,
        translation_helper=translation_helper,
        translation_model_dir=translation_model_dir,
        whisper_threads=whisper_threads,
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


def process_source_file(
    source_path: Path,
    output_root: Path,
    toolchain: Toolchain,
    used_folder_names: set[str],
    seconds: int,
) -> None:
    folder_name = unique_folder_name(source_path.stem, used_folder_names)
    folder_path = output_root / folder_name
    folder_path.mkdir(parents=True, exist_ok=True)

    errors: list[str] = []

    try:
        transcription_folder = folder_path / TRANSCRIPTION_INPUTS_FOLDER
        transcription_folder.mkdir(parents=True, exist_ok=True)

        short_output = folder_path / f"{source_path.stem}{SHORT_SUFFIX}.wav"
        extract_short_clip(
            ffmpeg=toolchain.ffmpeg,
            source_path=source_path,
            output_path=short_output,
            seconds=seconds,
        )

        short_transcription_input = transcription_folder / f"{source_path.stem}{SHORT_SUFFIX}_transcribe.wav"
        create_transcription_master(
            ffmpeg=toolchain.ffmpeg,
            source_path=short_output,
            output_path=short_transcription_input,
        )

        variant_results: list[VariantResult] = [
            build_variant_result(
                label="SHORT",
                audio_path=short_output,
                transcript_source_path=short_transcription_input,
                toolchain=toolchain,
            ),
            build_enhanced_variant_result(
                label="DFN",
                source_short_path=short_output,
                output_path=folder_path / f"{source_path.stem}{DFN_SUFFIX}.m4a",
                transcription_output_path=transcription_folder / f"{source_path.stem}{DFN_SUFFIX}_transcribe.wav",
                toolchain=toolchain,
                preprocess_filter=DFN_PREPROCESS_FILTER,
                postprocess_filter=DFN_POSTPROCESS_FILTER,
            ),
            build_enhanced_variant_result(
                label="HYBRID",
                source_short_path=short_output,
                output_path=folder_path / f"{source_path.stem}{HYBRID_SUFFIX}.m4a",
                transcription_output_path=transcription_folder / f"{source_path.stem}{HYBRID_SUFFIX}_transcribe.wav",
                toolchain=toolchain,
                preprocess_filter=HYBRID_PREPROCESS_FILTER,
                postprocess_filter=HYBRID_POSTPROCESS_FILTER,
            ),
        ]

        for result in variant_results:
            if result.error:
                errors.append(f"{result.label}: {result.error}")

        write_combined_report(
            source_path=source_path,
            folder_path=folder_path,
            variant_results=variant_results,
        )

    except Exception as error:  # noqa: BLE001
        errors.append(str(error))

    if errors:
        write_error_log(folder_path, source_path, errors)


def unique_folder_name(base_name: str, used_folder_names: set[str]) -> str:
    candidate = base_name
    suffix = 2
    while candidate in used_folder_names:
        candidate = f"{base_name}_{suffix}"
        suffix += 1
    used_folder_names.add(candidate)
    return candidate


def extract_short_clip(
    ffmpeg: Path,
    source_path: Path,
    output_path: Path,
    seconds: int,
) -> None:
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


def create_transcription_master(
    ffmpeg: Path,
    source_path: Path,
    output_path: Path,
) -> None:
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


def build_enhanced_variant_result(
    label: str,
    source_short_path: Path,
    output_path: Path,
    transcription_output_path: Path,
    toolchain: Toolchain,
    preprocess_filter: str,
    postprocess_filter: str,
) -> VariantResult:
    try:
        enhance_with_deepfilternet(
            input_path=source_short_path,
            output_path=output_path,
            transcription_output_path=transcription_output_path,
            toolchain=toolchain,
            preprocess_filter=preprocess_filter,
            postprocess_filter=postprocess_filter,
        )
        return build_variant_result(
            label=label,
            audio_path=output_path,
            transcript_source_path=transcription_output_path,
            toolchain=toolchain,
        )
    except Exception as error:  # noqa: BLE001
        return VariantResult(
            label=label,
            audio_path=output_path,
            transcript_source_path=transcription_output_path,
            error=str(error),
        )


def build_variant_result(
    label: str,
    audio_path: Path,
    transcript_source_path: Path,
    toolchain: Toolchain,
) -> VariantResult:
    try:
        transcript = transcribe_audio(
            source_audio=transcript_source_path,
            toolchain=toolchain,
        )
        translation_chunks = translate_segments(
            transcript["segments"],
            toolchain=toolchain,
        )

        segments = [
            TranscriptSegment(
                text=segment["text"],
                start_ms=segment["start_ms"],
                end_ms=segment["end_ms"],
            )
            for segment in transcript["segments"]
        ]

        return VariantResult(
            label=label,
            audio_path=audio_path,
            transcript_source_path=transcript_source_path,
            transcript_segments=segments,
            translation_chunks=translation_chunks,
            transcript_language=transcript["detected_language"],
        )
    except Exception as error:  # noqa: BLE001
        return VariantResult(
            label=label,
            audio_path=audio_path,
            transcript_source_path=transcript_source_path,
            error=str(error),
        )


def enhance_with_deepfilternet(
    input_path: Path,
    output_path: Path,
    transcription_output_path: Path,
    toolchain: Toolchain,
    preprocess_filter: str,
    postprocess_filter: str,
) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    transcription_output_path.parent.mkdir(parents=True, exist_ok=True)

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
                "-ac",
                "1",
                "-ar",
                "16000",
                "-c:a",
                "aac",
                "-b:a",
                "96k",
                str(output_path),
            ],
            error_prefix=f"Failed to export {output_path.name}",
        )

        create_transcription_master(
            ffmpeg=toolchain.ffmpeg,
            source_path=enhanced_wav,
            output_path=transcription_output_path,
        )


def locate_deepfilter_output(expected_filename: str, output_directory: Path) -> Path:
    expected = output_directory / expected_filename
    if expected.exists():
        return expected

    expected_stem = Path(expected_filename).stem
    wavs = sorted(
        path
        for path in output_directory.glob("*.wav")
        if path.stem == expected_stem
    )
    if wavs:
        return wavs[0]

    wavs = sorted(path for path in output_directory.glob("*.wav"))
    if wavs:
        return wavs[0]

    raise HarnessError(
        f"DeepFilterNet finished but no WAV output was found in {output_directory}."
    )


def transcribe_audio(source_audio: Path, toolchain: Toolchain) -> dict[str, object]:
    with tempfile.TemporaryDirectory(prefix="cv_eval_whisper_") as temp_dir:
        temp_root = Path(temp_dir)
        output_prefix = temp_root / "transcript"
        json_output = output_prefix.with_suffix(".json")

        transcript_payload = None
        errors: list[str] = []

        for model_name in ("ggml-large-v3-turbo.bin", "ggml-large-v3.bin"):
            model_path = toolchain.whisper_model_dir / model_name
            if not model_path.exists():
                continue

            for no_gpu in (False, True):
                try:
                    run_command(
                        whisper_arguments(
                            executable=toolchain.whisper_cli,
                            model_path=model_path,
                            audio_path=source_audio,
                            output_prefix=output_prefix,
                            threads=toolchain.whisper_threads,
                            no_gpu=no_gpu,
                        ),
                        error_prefix=whisper_error_prefix(
                            source_audio=source_audio,
                            model_name=model_name,
                            no_gpu=no_gpu,
                        ),
                        env=whisper_environment(toolchain.whisper_cli),
                    )
                    transcript_payload = json.loads(json_output.read_text(encoding="utf-8"))
                    break
                except Exception as error:  # noqa: BLE001
                    errors.append(str(error))

                if transcript_payload is not None:
                    break

            if transcript_payload is not None:
                break

        if transcript_payload is None:
            raise HarnessError("\n".join(errors) or f"whisper.cpp failed for {source_audio.name}")

        segments_payload = transcript_payload.get("transcription")
        if not isinstance(segments_payload, list):
            raise HarnessError(
                f"whisper.cpp returned JSON in an unexpected format for {source_audio.name}"
            )

        segments: list[dict[str, object]] = []
        for segment in segments_payload:
            if not isinstance(segment, dict):
                continue
            text = str(segment.get("text", "")).strip()
            if not text:
                continue
            offsets = segment.get("offsets") or {}
            start_ms = int(offsets.get("from", 0))
            end_ms = int(offsets.get("to", 0))
            segments.append(
                {
                    "text": text,
                    "start_ms": start_ms,
                    "end_ms": end_ms,
                }
            )

        if not segments:
            raise HarnessError(f"whisper.cpp returned an empty transcript for {source_audio.name}")

        return {
            "detected_language": "mr",
            "segments": segments,
        }


def whisper_arguments(
    executable: Path,
    model_path: Path,
    audio_path: Path,
    output_prefix: Path,
    threads: int,
    no_gpu: bool,
) -> list[str]:
    _ = executable
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
    return environment


def translate_segments(
    segments: list[dict[str, object]],
    toolchain: Toolchain,
) -> list[TranslationChunk]:
    grouped_segments = build_translation_groups(segments)
    if not grouped_segments:
        return []

    translated_texts: list[str] = [""] * len(grouped_segments)
    pending_translation_indexes = [
        index for index, group in enumerate(grouped_segments) if should_translate_group(group["text"])
    ]

    for batch in segment_batches(pending_translation_indexes, grouped_segments, max_batch_segments=16, max_batch_characters=4000):
        payload = json.dumps(
            {"segments": [grouped_segments[index]["text"] for index in batch]},
            ensure_ascii=False,
        ).encode("utf-8")
        stdout = run_command(
            [
                str(toolchain.translation_python),
                str(toolchain.translation_helper),
                "--model-dir",
                str(toolchain.translation_model_dir),
                "--source-lang",
                "mar_Deva",
                "--target-lang",
                "eng_Latn",
            ],
            error_prefix="NLLB translation failed",
            stdin=payload,
            timeout=600,
        )
        payload = json.loads(stdout.decode("utf-8"))
        translations = payload.get("translations")
        if not isinstance(translations, list) or len(translations) != len(batch):
            raise HarnessError("NLLB returned an unexpected number of translated segments.")
        for index, translation in zip(batch, translations):
            translated_texts[index] = str(translation).strip()

    translation_chunks: list[TranslationChunk] = []
    for index, group in enumerate(grouped_segments):
        translated_text = translated_texts[index]
        if not translated_text:
            translated_text = group["text"]
        translation_chunks.append(
            TranslationChunk(
                text=translated_text,
                start_ms=int(group["start_ms"]),
                end_ms=int(group["end_ms"]),
            )
        )

    return translation_chunks


def segment_batches(
    indexes: list[int],
    groups: list[dict[str, object]],
    max_batch_segments: int,
    max_batch_characters: int,
) -> list[list[int]]:
    batches: list[list[int]] = []
    current_batch: list[int] = []
    current_characters = 0

    for index in indexes:
        text = str(groups[index]["text"])
        proposed_characters = current_characters + len(text)
        would_overflow_count = len(current_batch) >= max_batch_segments
        would_overflow_characters = bool(current_batch) and proposed_characters > max_batch_characters

        if would_overflow_count or would_overflow_characters:
            batches.append(current_batch)
            current_batch = []
            current_characters = 0

        current_batch.append(index)
        current_characters += len(text)

    if current_batch:
        batches.append(current_batch)

    return batches


def build_translation_groups(segments: list[dict[str, object]]) -> list[dict[str, object]]:
    groups: list[dict[str, object]] = []
    current_segments: list[dict[str, object]] = []

    for segment in segments:
        text = str(segment["text"]).strip()
        if not text:
            continue

        current_segments.append(segment)
        current_text = " ".join(str(item["text"]).strip() for item in current_segments).strip()
        should_flush = (
            text.endswith(("।", ".", "?", "!"))
            or len(current_text) >= 240
        )

        if should_flush:
            groups.append(
                {
                    "text": current_text,
                    "start_ms": int(current_segments[0]["start_ms"]),
                    "end_ms": int(current_segments[-1]["end_ms"]),
                }
            )
            current_segments = []

    if current_segments:
        groups.append(
            {
                "text": " ".join(str(item["text"]).strip() for item in current_segments).strip(),
                "start_ms": int(current_segments[0]["start_ms"]),
                "end_ms": int(current_segments[-1]["end_ms"]),
            }
        )

    return groups


def should_translate_group(text: str) -> bool:
    total_letters = sum(1 for character in text if character.isalpha())
    if total_letters == 0:
        return False

    devanagari_letters = sum(
        1 for character in text if "\u0900" <= character <= "\u097F"
    )
    return (devanagari_letters / total_letters) > 0.3


def write_combined_report(
    source_path: Path,
    folder_path: Path,
    variant_results: list[VariantResult],
) -> None:
    report_path = folder_path / f"{source_path.stem}_evaluation.txt"
    lines = [
        "CLEARVOICE EVALUATION REPORT",
        f"SOURCE FILE: {source_path}",
        f"SOURCE NAME: {source_path.name}",
        f"GENERATED AT: {datetime.now().isoformat(timespec='seconds')}",
        "",
    ]

    for result in variant_results:
        lines.extend(
            [
                "=" * 72,
                f"VARIANT: {result.label}",
                f"AUDIO FILE: {result.audio_path.name}",
                f"AUDIO PATH: {result.audio_path}",
                f"TRANSCRIPTION SOURCE FILE: {result.transcript_source_path.name}",
                f"TRANSCRIPTION SOURCE PATH: {result.transcript_source_path}",
            ]
        )

        if result.error:
            lines.extend(
                [
                    "STATUS: ERROR",
                    f"ERROR: {result.error}",
                    "",
                ]
            )
            continue

        lines.extend(
            [
                "STATUS: SUCCESS",
                f"LANGUAGE: {result.transcript_language or 'mr'}",
                "",
                "ORIGINAL TRANSCRIPT",
                format_transcript_segments(result.transcript_segments or []),
                "",
                "ENGLISH TRANSLATION",
                format_translation_chunks(result.translation_chunks or []),
                "",
            ]
        )

    report_path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")


def format_transcript_segments(segments: list[TranscriptSegment]) -> str:
    if not segments:
        return "[no transcript available]"

    lines: list[str] = []
    for segment in segments:
        lines.append(
            f"[{timestamp_string(segment.start_ms)} --> {timestamp_string(segment.end_ms)}]   {segment.text}"
        )
    return "\n".join(lines)


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


def write_error_log(folder_path: Path, source_path: Path, errors: list[str]) -> None:
    log_path = folder_path / "_error.log"
    lines = [
        "CLEARVOICE EVALUATION ERROR",
        f"source: {source_path}",
    ]
    for error in errors:
        lines.append(f"error: {error}")
    log_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


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
        if detail:
            raise HarnessError(f"{error_prefix}: {detail}")
        raise HarnessError(error_prefix)

    return completed.stdout


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except HarnessError as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)

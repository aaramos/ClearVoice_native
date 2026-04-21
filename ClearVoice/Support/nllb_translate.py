#!/usr/bin/env python3
import argparse
import json
import os
import sys

import ctranslate2
from transformers import AutoTokenizer


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-dir", required=True)
    parser.add_argument("--source-lang", required=True)
    parser.add_argument("--target-lang", required=True)
    parser.add_argument("--beam-size", type=int, default=4)
    parser.add_argument("--max-batch-size", type=int, default=16)
    parser.add_argument("--inter-threads", type=int, default=1)
    parser.add_argument("--intra-threads", type=int, default=max(1, (os.cpu_count() or 4) // 2))
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    payload = json.load(sys.stdin)
    segments = payload.get("segments", [])

    if not isinstance(segments, list):
        raise ValueError("segments must be a list")

    if not segments:
        json.dump({"translations": []}, sys.stdout, ensure_ascii=False)
        return 0

    translator = ctranslate2.Translator(
        args.model_dir,
        device="cpu",
        inter_threads=args.inter_threads,
        intra_threads=args.intra_threads,
    )
    tokenizer = AutoTokenizer.from_pretrained(
        args.model_dir,
        src_lang=args.source_lang,
        fix_mistral_regex=True,
    )

    token_batches = [
        tokenizer.convert_ids_to_tokens(tokenizer.encode(text))
        for text in segments
    ]
    target_prefix = [[args.target_lang] for _ in segments]

    results = translator.translate_batch(
        token_batches,
        target_prefix=target_prefix,
        beam_size=args.beam_size,
        max_batch_size=args.max_batch_size,
    )

    translations = []
    for result in results:
        hypothesis = result.hypotheses[0][1:]
        token_ids = tokenizer.convert_tokens_to_ids(hypothesis)
        translated = tokenizer.decode(token_ids, skip_special_tokens=True).strip()
        translations.append(translated)

    json.dump({"translations": translations}, sys.stdout, ensure_ascii=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

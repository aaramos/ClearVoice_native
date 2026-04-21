# ClearVoice Backlog

This backlog tracks future work from the current shipped enhancement-only release. Items below are not part of the live product flow today unless they are explicitly described as already shipped elsewhere in the repo docs.

## Local-First Product Work

- Phase 2 transcription: integrate `whisper.cpp` as the primary local Marathi transcription engine, consuming the `HYBRID` enhancement output via a temporary `16 kHz` mono PCM WAV input and keeping the active model resident in memory instead of reloading per file.
- Phase 3 translation: add a local Marathi-to-English translation step after transcription using `facebook/nllb-200-distilled-600M` through `CTranslate2` with `int8` conversion, translating bounded segments in order and writing `translation_en` onto each segment.
- Phase 3 translation runtime: replace the current placeholder batch-phase translator hook with the real `NLLB-200/CTranslate2` runtime and keep translation serialized after the full batch finishes transcription.
- Revisit the enhancement product surface after more listening tests and decide whether the app should stay dual-mode (`DFN` / `HYBRID`) or simplify to a single default enhancement path.
- After translation is stable, extend that same UX with English translation controls and Results-screen transcript sections as captured in `UX_TARGET_POST_TRANSLATION.md`.
- Add first-run onboarding for local model setup so non-technical users can download and verify required transcription and translation models without leaving the app.
- Replace the placeholder summary block with a real local summarization path once the release-critical transcription and translation flow is stable.
- Tune FFmpeg enhancement presets against real speech fixtures, especially Marathi recordings with background noise, pops, and inconsistent volume.
- Add a user-facing retry path after auto-detect failure so the app can return the user directly to language selection with the failed batch context preserved.

## Performance And Reliability

- Measure local-memory and CPU pressure across concurrency levels `1...10` on Apple Silicon machines and adjust the default recommendation if `5` proves too aggressive or too conservative.
- Validate `whisper.cpp` throughput, peak memory, and thread defaults on the actual target machine class before locking the production transcription configuration.
- Sequence transcription and translation so `whisper.cpp` and `NLLB-200` do not co-reside in memory during normal operation.
- Decide whether legacy cloud services should stay in the repo for fallback/rollback safety or be removed once the local-first branch is proven stable.
- For the standalone evaluation harness, probe `whisper.cpp` GPU availability once per run and reuse that decision instead of retrying GPU and CPU mode on every file.
- Tune the harness transcription decode profile for short Marathi clips, including beam search, deterministic fallback behavior, and Indic-specific threshold A/B tests.
- Parallelize harness enhancement and transcription work where it does not increase model contention, especially CPU-side DFN work while whisper.cpp is on Metal.
- Add resume/caching support to the harness so partially completed evaluation bundles do not rerun every stage from scratch.
- Benchmark larger or Marathi-stronger local translation models for the harness, including `NLLB` variants beyond `distilled-600M` and `IndicTrans2`.

## Documentation

- Update the engineering handoff package and any external specs that still describe Gemini as the primary processing path.
- Update the engineering docs that still describe WhisperKit as the next transcription step; the current roadmap is `whisper.cpp` first, then local `NLLB/CTranslate2` translation.
- Document end-user setup expectations for FFmpeg, `whisper.cpp` models, and local translation model provisioning before this branch is handed to broader internal users.

# ClearVoice Backlog

## Local-First Product Work

- Phase 2 transcription: integrate `whisper.cpp` as the primary local Marathi transcription engine, consuming the `HYBRID` enhancement output via a temporary `16 kHz` mono PCM WAV input and keeping the active model resident in memory instead of reloading per file.
- Phase 3 translation: add a local Marathi-to-English translation step after transcription using `facebook/nllb-200-distilled-600M` through `CTranslate2` with `int8` conversion, translating bounded segments in order and writing `translation_en` onto each segment.
- Phase 3 translation runtime: replace the current placeholder batch-phase translator hook with the real `NLLB-200/CTranslate2` runtime and keep translation serialized after the full batch finishes transcription.
- Continue the 4-step Marathi-only UX pass now: Desktop `output_<timestamp>` batch folders, single enhancement selection (`DFN` or `HYBRID`), optional transcription, live batch status, results review, and `Export All ZIP`.
- After translation is stable, extend that same UX with English translation controls and Results-screen transcript sections as captured in `UX_TARGET_POST_TRANSLATION.md`.
- Add first-run onboarding for local model setup so non-technical users can download and verify required transcription and translation models without leaving the app.
- Replace the placeholder summary block with a real local summarization path once the release-critical transcription and translation flow is stable.
- Tune FFmpeg enhancement presets against real speech fixtures, especially Marathi recordings with background noise, pops, and inconsistent volume.
- Add a user-facing retry path after auto-detect failure so the app can return the user directly to language selection with the failed batch context preserved.

## Performance And Reliability

- Measure local-memory and CPU pressure across concurrency levels `1...5` on Apple Silicon machines and adjust the default if `2` proves too aggressive or too conservative.
- Validate `whisper.cpp` throughput, peak memory, and thread defaults on the actual target machine class before locking the production transcription configuration.
- Sequence transcription and translation so `whisper.cpp` and `NLLB-200` do not co-reside in memory during normal operation.
- Decide whether legacy cloud services should stay in the repo for fallback/rollback safety or be removed once the local-first branch is proven stable.

## Documentation

- Update the engineering handoff package and any external specs that still describe Gemini as the primary processing path.
- Update the engineering docs that still describe WhisperKit as the next transcription step; the current roadmap is `whisper.cpp` first, then local `NLLB/CTranslate2` translation.
- Document end-user setup expectations for FFmpeg, `whisper.cpp` models, and local translation model provisioning before this branch is handed to broader internal users.

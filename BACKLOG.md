# ClearVoice Backlog

## Local-First Product Work

- Add first-run onboarding for WhisperKit model setup so non-technical users can download and verify required local models without leaving the app.
- Replace the placeholder summary block with a real local summarization path once the release-critical transcription and translation flow is stable.
- Tune FFmpeg enhancement presets against real speech fixtures, especially Marathi recordings with background noise, pops, and inconsistent volume.
- Add a user-facing retry path after auto-detect failure so the app can return the user directly to language selection with the failed batch context preserved.

## Performance And Reliability

- Measure local-memory and CPU pressure across concurrency levels `1...5` on Apple Silicon machines and adjust the default if `2` proves too aggressive or too conservative.
- Explore prewarming and reuse strategies for WhisperKit that improve throughput without keeping too much model state resident at once.
- Decide whether legacy cloud services should stay in the repo for fallback/rollback safety or be removed once the local-first branch is proven stable.

## Documentation

- Update the engineering handoff package and any external specs that still describe Gemini as the primary processing path.
- Document end-user setup expectations for FFmpeg and first-run WhisperKit downloads before this branch is handed to broader internal users.

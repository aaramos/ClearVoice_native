# ClearVoice

ClearVoice is a native macOS batch audio utility for cleaning speech recordings, writing a transcript in the spoken language, and producing an English translation for each source file.

This branch, `local-offline-v2`, is the local-first refactor. The primary workflow runs on this Mac without Gemini in the processing path.

## What This Branch Does

- Accepts local audio files, including `.wma`
- Converts source audio into a speech-processing format with FFmpeg
- Enhances speech locally with FFmpeg click repair, declipping, broadband noise suppression, gating, and speech normalization, then exports a final clean audio file as `.m4a`
- Runs local transcription plus English translation with WhisperKit
- Exports one folder per source file containing:
  - `<name>_clean.m4a`
  - `<name>_transcript.txt`

Temporary evaluation mode on this branch:

- Transcription and translation are currently disabled so audio enhancement can be evaluated in isolation
- Each per-file output folder now contains two enhanced variants:
  - `<name>_DFN.m4a`
  - `<name>_HYBRID.m4a`

## Current Product Shape

- Translation output is fixed to English for now
- Summarization is deferred for this release
- The transcript export currently includes a placeholder summary block so the file shape stays stable while summarization is stubbed
- Auto language detection is supported, but if the local model cannot detect the spoken language confidently, ClearVoice tells the user to rerun after choosing the input language manually
- Parallelism is configurable from the UI between `1` and `5` files, with a default of `2`

## Local Requirements

Install FFmpeg:

```sh
brew install ffmpeg
```

DeepFilterNet binary required for the current enhancement-only evaluation mode:

```sh
curl -fsSL https://github.com/Rikorose/DeepFilterNet/releases/download/v0.5.6/deep-filter-0.5.6-aarch64-apple-darwin -o /opt/homebrew/bin/deep-filter
chmod +x /opt/homebrew/bin/deep-filter
```

The next transcription phase on this branch will use `whisper.cpp` with local models stored in the current user's Application Support directory:

- `~/Library/Application Support/ClearVoice/Models`

Because first-run setup UX is deferred on this branch, model provisioning is currently an engineering/setup task rather than an in-app user flow.

## Development

Build and run:

```sh
./script/build_and_run.sh
```

Run tests:

```sh
xcodebuild test -project ClearVoice.xcodeproj -scheme ClearVoice -destination 'platform=macOS'
```

## Known Limitations

- This branch is intentionally English-only for translation
- Summarization is a placeholder, not a real model-backed feature yet
- The next transcription phase is planned around `whisper.cpp`, not `WhisperKit`
- The translation phase after transcription is planned around local `NLLB-200` inference through `CTranslate2`, not a native Swift/CoreML path in v1
- First-run onboarding for local model setup is still deferred
- The legacy Gemini, Apple Speech, and Apple Translation codepaths still exist in the repo for reference and rollback safety, but they are not part of the primary workflow on this branch
- `.dmg` packaging is still planned for a later phase

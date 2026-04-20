# ClearVoice

ClearVoice is a native macOS batch audio utility for cleaning recordings, transcribing them, translating them, and exporting a transcript package per source file.

## Current Setup

The live cloud path now uses a single Google Gemini key:

```sh
export GEMINI_API_KEY="your-key-here"
```

For local development, launch the app from a shell that already has that variable set:

```sh
./script/build_and_run.sh
```

If you want Finder-launched or drag-installed builds to see the key too, set it at the macOS launch-services level before launching the app:

```sh
launchctl setenv GEMINI_API_KEY "your-key-here"
```

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

- Phase 8 audio DSP work is still in progress, so the current export path uses the existing clean-audio stub behavior.
- The live Gemini path is implemented and covered by unit tests, but this repo has not yet been smoke-tested against a real `GEMINI_API_KEY` in the current shell session.
- `.dmg` packaging is planned for a later phase; use the local run script for now.

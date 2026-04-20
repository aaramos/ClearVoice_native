# ClearVoice

ClearVoice is a native macOS batch audio utility for cleaning recordings, transcribing them, translating them, and exporting a transcript package per source file.

## Current Setup

The live cloud path now uses a single Google Gemini key.

On first launch, ClearVoice now prompts for that key and stores it in the macOS Keychain for the current user on that Mac. You do not need to paste the key on every launch.

For developer overrides, ClearVoice still honors `GEMINI_API_KEY` from the launch environment before falling back to Keychain storage:

```sh
export GEMINI_API_KEY="your-key-here"
./script/build_and_run.sh
```

If you want Finder-launched or drag-installed builds to use an environment override, set it at the macOS launch-services level before launching the app:

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
- The live Gemini path is implemented, covered by unit tests, and verified to launch locally, but it has not yet been exercised against a real Gemini API key in this shell session.
- `.dmg` packaging is planned for a later phase; use the local run script for now.

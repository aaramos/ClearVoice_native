# ClearVoice

ClearVoice is a native macOS batch audio utility for cleaning speech recordings and exporting a shareable results package with the original source audio, the enhanced output, and a browser-friendly review page.

## Download

- Direct download: [ClearVoice 0.1.0 DMG](https://github.com/aaramos/ClearVoice_native/releases/download/v0.1.0/ClearVoice-0.1.0.dmg)
- Releases page: [github.com/aaramos/ClearVoice_native/releases](https://github.com/aaramos/ClearVoice_native/releases)

## Current Product

- Batch-processes local audio folders on macOS
- Repairs and enhances speech with local FFmpeg and DeepFilterNet tooling
- Supports `.wav`, `.mp3`, `.m4a`, `.aac`, `.flac`, and `.wma`
- Lets the user choose the enhancement method in-app
- Writes one output folder per source file
- Generates a local `index.html` results page that opens in the browser
- Lets reviewers switch between the source audio and enhanced audio at the same playback position
- Includes a first-run setup flow that checks, downloads, and verifies required dependencies without Terminal

## Tech Stack

- App layer: native macOS app built in `Swift` with `SwiftUI`
- Project tooling: `XcodeGen` generates the Xcode project from `project.yml`
- Audio processing: local `FFmpeg` for normalization and repair plus `DeepFilterNet` for enhancement
- Apple frameworks: `AVFoundation` for media inspection and playback, plus standard macOS file and window APIs for import, export, and setup flows
- Results surface: generated local `HTML`, `CSS`, and `JavaScript` review page opened directly from disk in the user's browser
- Packaging: `xcodebuild` for app builds and `hdiutil` via `./script/build_dmg.sh` for DMG creation
- Runtime model: fully local enhancement workflow with no required cloud backend for the shipped product

## First-Run Setup

ClearVoice currently installs and manages these local tools:

- `FFmpeg`
- `DeepFilterNet`

They are stored under:

- `~/Library/Application Support/ClearVoice/Tools`

At launch, ClearVoice:

1. explains which tools are required and why
2. checks whether they already exist on the Mac
3. downloads only the missing tools
4. shows progress, status, and verification before entering the app

## Output Structure

For each processed file, ClearVoice creates a folder inside the batch output directory containing:

- the original source file
- the enhanced output file
- a browser-readable results index for the batch

The browser results page is generated locally and opened directly from disk rather than through a local web server.

## Build From Source

Build and run:

```sh
./script/build_and_run.sh
```

Run tests:

```sh
xcodebuild test -project ClearVoice.xcodeproj -scheme ClearVoice -destination 'platform=macOS'
```

Build a distributable DMG:

```sh
./script/build_dmg.sh
```

## Distribution Notes

- The current `.dmg` is packaged from the local app bundle and is intended for direct sharing.
- Code signing and notarization are still separate follow-up work; this repo currently builds unsigned distribution artifacts.

## Known Scope

- The live app is currently focused on audio enhancement and review.
- Transcription and translation experimentation has been moved off `main` onto the dedicated branch `transcription-translation-rnd`.

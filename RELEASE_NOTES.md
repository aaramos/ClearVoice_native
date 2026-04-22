# Release Notes

## 0.3.2 — 2026-04-21

### Workflow and Defaults

- ClearVoice now remembers the last processing speed and enhancement mode you used, so the next batch starts with your most recent settings instead of resetting each time.
- The default processing speed now starts at `5` files at a time on first use.
- The `Open Results` button now stays disabled until processing is actually complete, and it now looks visibly greyed out while unavailable.

### Results Review Page

- Percent-encoded file names such as `010.%2011%20may%201980%20ch23%20v53.mp3` now display in a readable form on the review page.
- The results cards now show only `Browse folder` as the file action, aligned to the right for a cleaner layout.

### Project Docs and Release Tooling

- Added `DEPENDENCIES.md` so the repo has a plain-English inventory of app, tool, and release dependencies.
- GitHub release publishing now pulls notes directly from `RELEASE_NOTES.md` and always includes the standard unsigned-DMG distribution note.

### Distribution Note

- The docs and release notes now explain the simplest current sharing path for an unsigned `.dmg`.
- Trusted testers should expect the first launch to require `System Settings > Privacy & Security > Open Anyway` until signing and notarization are added.

## 0.3.1 — 2026-04-21

### Security and Setup

- First-run setup now pins exact FFmpeg and DeepFilterNet downloads and verifies the downloaded file fingerprint before anything is unpacked or run.
- If a download fails verification, ClearVoice now stops setup without wiping a previously installed managed tool.
- Dependency downloads now fail earlier with a clearer message when the server response is invalid.

### Distribution Note

- The docs and release notes now explain the simplest current sharing path for an unsigned `.dmg`.
- Trusted testers should expect the first launch to require `System Settings > Privacy & Security > Open Anyway` until signing and notarization are added.

## 0.3.0 — 2026-04-21

### Added

- Recursive audio discovery now includes supported files found in nested subfolders at any depth.
- The processing screen now supports both per-file cancel and full-batch cancel.
- The results page now keeps the source/enhanced playback toggle without copying source files into the output folder.

### Changed

- Batch output now writes to a sibling folder named `<source>_enhanced`.
- Output now mirrors the source directory structure instead of flattening results into one folder per file.
- Enhanced exports keep a method suffix such as `_DFN` or `_HYBRID`.
- If the target `_enhanced` folder already exists, the app now asks the user to rename the new output folder or delete the old one before starting.

### Cleanup and Reliability

- Temporary normalized audio, DeepFilterNet work folders, and partial cancelled outputs are cleaned up more aggressively.
- If the app quits during a batch, ClearVoice now attempts to stop running work before termination so cleanup can complete more cleanly.

### Review Page Note

- The browser review page links back to the original source files on disk. If the source folder is moved or deleted later, the source-side toggle will no longer work.

### Distribution Note

- The docs and release notes now explain the simplest current sharing path for an unsigned `.dmg`.
- Trusted testers should expect the first launch to require `System Settings > Privacy & Security > Open Anyway` until signing and notarization are added.

## 0.2.0 — 2026-04-21

### App and Workflow

- ClearVoice shipped the cleaned enhancement-only app with the new app icon, expanded throughput controls, browser-based review output, and first-run dependency setup for FFmpeg and DeepFilterNet.
- Supports 1 to 20 files concurrently, defaulting to 5.
- Generates a local `index.html` review page with source and enhanced switching.
- Installs required local dependencies without Terminal.

### Distribution Note

- The docs and release notes now explain the simplest current sharing path for an unsigned `.dmg`.
- Trusted testers should expect the first launch to require `System Settings > Privacy & Security > Open Anyway` until signing and notarization are added.

## 0.1.0 — 2026-04-21

### Initial Release

- ClearVoice shipped the enhancement-only macOS workflow with first-run dependency setup, direct browser-based results review, and packaged DMG distribution.
- Includes local FFmpeg and DeepFilterNet setup with guided installation.
- Includes batch enhancement with browser review for source and enhanced audio.
- Ships as a shareable DMG built from the current macOS app bundle.

### Distribution Note

- The docs and release notes now explain the simplest current sharing path for an unsigned `.dmg`.
- Trusted testers should expect the first launch to require `System Settings > Privacy & Security > Open Anyway` until signing and notarization are added.

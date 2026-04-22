# Release Notes

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

### Sharing Note

- The simplest current sharing path is to upload the generated `.dmg` to a GitHub Release and share it with trusted testers.
- Because the build is still unsigned and not notarized, testers should expect the first launch to require `System Settings > Privacy & Security > Open Anyway`.
- This release packaging is suitable for direct testing, not a polished public Mac distribution flow yet.

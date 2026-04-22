# Release Notes

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

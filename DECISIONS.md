# ClearVoice Implementation Decisions

This file records implementation choices that were left to engineering discretion in the handoff package.

## 2026-04-19

- Project root: created the app under `/Users/adrian/Apps/Projects/Benchmarking/ClearVoice` so the full repo stays inside the writable workspace while still keeping the handoff docs untouched in `/Users/adrian/Apps/Projects/clear_vision/docs`.
- Project generation: using `xcodegen` to generate and version a native `.xcodeproj` from `project.yml` instead of hand-editing Xcode project files.
- Bundle identifier: `com.clearvoice.ClearVoice`.
- Target layout: app target `ClearVoice`, test target `ClearVoiceTests`.
- Build tooling: added `script/build_and_run.sh` plus `.codex/environments/environment.toml` as the single local run entrypoint for Codex and terminal use.
- Signing posture for v1 local builds: code signing disabled in project settings to match the unsigned, non-notarized distribution target.

# ClearVoice Implementation Decisions

This file records implementation choices that were left to engineering discretion in the handoff package.

## 2026-04-19

- Project root: created the app under `/Users/adrian/Apps/Projects/Benchmarking/ClearVoice` so the full repo stays inside the writable workspace while still keeping the handoff docs untouched in `/Users/adrian/Apps/Projects/clear_vision/docs`.
- Project generation: using `xcodegen` to generate and version a native `.xcodeproj` from `project.yml` instead of hand-editing Xcode project files.
- Bundle identifier: `com.clearvoice.ClearVoice`.
- Target layout: app target `ClearVoice`, test target `ClearVoiceTests`.
- Build tooling: added `script/build_and_run.sh` plus `.codex/environments/environment.toml` as the single local run entrypoint for Codex and terminal use.
- Signing posture for v1 local builds: code signing disabled in project settings to match the unsigned, non-notarized distribution target.
- Output-path precedence: the handoff's `OutputPathResolver` pseudocode conflicts with its own rule-precedence text and test matrix, so the implementation follows the rule text/tests. Same-batch queue order assigns the candidate suffix first, then prior-run folder existence is checked against that assigned candidate.
- Phase 6 concurrency model: using a custom actor-backed `AsyncSemaphore` plus `TaskGroup` instead of `DispatchSemaphore` or detached queueing so the batch runner stays Swift-concurrency-native, respects the configured parallelism cap, and defines "Stop after current" as "stop scheduling new files while letting the active set finish cleanly."
- Phase 7 networking stack: using lightweight `URLSession`-backed HTTP clients plus a shared retry helper instead of adding a third-party networking dependency, with exponential backoff + jitter capped at 3 attempts for transient transport, 429, and 5xx failures.
- Translation prompt: strict transcript-preservation prompt that outputs only the translated transcript, with no headings, notes, or summarization.
- Summarization prompt: concise factual-summary prompt that returns only summary text in the selected output language, optimized for requests, decisions, and follow-ups.
- Gemini vendor switch: the live cloud path now uses the Gemini Developer API end-to-end behind a single `GEMINI_API_KEY`, superseding the earlier OpenAI+Ollama live wiring.
- Gemini transcription model: `gemini-3-flash-preview` for audio transcription because Google's audio-understanding examples target the Flash preview line directly.
- Gemini language-task model: `gemini-3.1-flash-lite-preview` for translation and summarization to bias toward lower cost and free-tier-friendly usage while keeping acceptable quality for post-transcription text work.
- Gemini transcription prompt: structured-output prompt that requests verbatim transcript text, BCP-47 language code, and a model-estimated confidence score between 0 and 1.
- Gemini confidence heuristic: trusting Gemini's structured `confidence_estimate` output directly for now, then clamping it into `0...1` before downstream fallback logic consumes it.
- Gemini file handling: always using the Files API upload flow for transcription inputs, then deleting the uploaded remote file after processing even though Gemini also expires files automatically after 48 hours.
- Launch-time key storage: normal app launches now check `GEMINI_API_KEY` first for developer overrides, then fall back to a Keychain item. If neither is present, ClearVoice shows a first-launch key entry screen instead of an unrecoverable startup failure.
- Keychain backend strategy: prefer the macOS data-protection keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` when entitlements allow it, but automatically fall back to the regular login Keychain for the current unsigned local distribution so first-launch key saving still works without provisioning-managed entitlements.

# ClearVoice Implementation Decisions

This file records implementation choices that were left to engineering discretion in the handoff package.

## 2026-04-19

- Project root: the active native repo now lives at `/Users/adrian/Apps/Projects/ClearVoice_native`.
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
- Gemini model selection: using `gemini-2.5-flash` for transcription, translation, and summarization to stay aligned with Google's current official audio and text-generation examples and to avoid relying on preview model names during end-user batch processing.
- Gemini transcription prompt: structured-output prompt that requests verbatim transcript text, BCP-47 language code, and a model-estimated confidence score between 0 and 1.
- Gemini confidence heuristic: trusting Gemini's structured `confidence_estimate` output directly for now, then clamping it into `0...1` before downstream fallback logic consumes it.
- Gemini file handling: always using the Files API upload flow for transcription inputs, then deleting the uploaded remote file after processing even though Gemini also expires files automatically after 48 hours.
- Launch-time key storage: normal app launches now check `GEMINI_API_KEY` first for developer overrides, then fall back to a Keychain item. If neither is present, ClearVoice shows a first-launch key entry screen instead of an unrecoverable startup failure.
- Keychain backend strategy: prefer the macOS data-protection keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` when entitlements allow it, but automatically fall back to the regular login Keychain for the current unsigned local distribution so first-launch key saving still works without provisioning-managed entitlements.
- Cloud resilience: treat Gemini summarization as best-effort so a transient cloud failure still exports the translated and original transcript instead of failing the whole file; transcription remains required and retries now use a longer default backoff window.
- Translation resilience: when the user selects on-device translation, ClearVoice still attempts Apple Translation first, but any runtime local translation failure now falls back to Gemini when a Gemini key is available rather than silently leaving the transcript untranslated.
- Transcription resilience: when the user selects on-device transcription, ClearVoice still attempts Apple Speech first, but if Apple reports the speech asset is `downloading` or merely `supported`/not installed, ClearVoice now falls back to Gemini when a Gemini key is available instead of failing the file.
- WMA support posture: ClearVoice now uses a local FFmpeg executable for source-format normalization, and `.wma` is admitted at scan time and normalized to temporary `.m4a` before enhancement/transcription. Common absolute macOS install paths are probed because Finder-launched app processes may not inherit a useful shell `PATH`.

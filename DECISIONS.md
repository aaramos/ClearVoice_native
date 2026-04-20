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
- Ollama cloud integration: calling `https://ollama.com/api/chat` directly with model `gpt-oss:120b` and one shared chat client for both translation and summarization instead of routing through an OpenAI-compatibility shim.
- Translation prompt: strict transcript-preservation prompt that outputs only the translated transcript, with no headings, notes, or summarization.
- Summarization prompt: concise factual-summary prompt that returns only summary text in the selected output language, optimized for requests, decisions, and follow-ups.
- Whisper confidence heuristic: deriving confidence from the average `exp(avg_logprob)` across Whisper `verbose_json` segments, with a fallback confidence of `0.75` if segment log-probability data is unavailable.
- Launch-time key gating: normal app launches now block on missing `OPENAI_API_KEY` / `OLLAMA_API_KEY` with a dedicated startup failure screen, while the rest of the app continues to use injected stubs in tests.

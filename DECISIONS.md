# ClearVoice Implementation Decisions

This file records implementation choices that were left to engineering discretion in the handoff package.

The notes below are cumulative. Older sections capture earlier experiments and branch-specific decisions, while the newest section reflects the shipped product on `main`.

## 2026-04-19

- Project root: the active native repo lives in the current local checkout of `ClearVoice_native`.
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
- Gemini free-tier protection: ClearVoice now applies a shared, client-side Gemini request throttle across upload, transcription, translation, summarization, and delete calls. The default policy is intentionally conservative at 8 requests per minute with adaptive cooldown after 429 responses.
- Gemini model routing: transcription stays on `gemini-2.5-flash`, while translation and summarization now default to `gemini-2.5-flash-lite` to reduce quota pressure on the text-only steps.

## 2026-04-20

- Branching strategy: the local-first redesign lives on `local-offline-v2` so the earlier Gemini-heavy workflow remains intact on `main` for comparison, rollback, or selective reuse.
- Primary workflow posture: the active batch path on this branch is local-first and does not use Gemini in the normal processing flow. Existing cloud services stay in the repo for rollback safety, but they are no longer the branch's main architecture.
- Apple speech terminology correction: the earlier product discussion referenced `SFSpeechRecognizer`, but the code being replaced in ClearVoice used `SpeechTranscriber` and `SpeechAnalyzer`.
- Speech model stack: using WhisperKit as the main local speech engine, with one pass for source-language transcription and one pass for English translation.
- Whisper model choice: defaulting to WhisperKit's multilingual `large-v3-v20240930_626MB` model to prioritize Marathi and other non-English speech accuracy over faster but weaker small-model performance.
- Model provisioning for this branch: deferring first-run onboarding and allowing WhisperKit to download its local model on demand into `~/Library/Application Support/ClearVoice/Models`.
- Conversion pipeline: every accepted source format is normalized into a temporary `16 kHz` mono WAV for local speech processing.
- Final clean-audio export: always writing the user-visible enhanced audio artifact as `<basename>_clean.m4a`.
- Enhancement implementation: replacing the copy stub in the primary workflow with an FFmpeg-based speech cleanup chain using filtering, denoising, and speech normalization tuned for intelligibility over music fidelity.
- Translation scope: fixing translation output to English for this branch instead of keeping the broader arbitrary-target-language product surface.
- Summarization release scope: deferring real summarization for this release while keeping the code shape and exporting a placeholder summary block for transcript compatibility.
- Auto-detect fallback UX: when local language detection confidence is too low, the file fails with a direct instruction to rerun after choosing the input language manually.
- Concurrency posture: local processing remains configurable from `1` to `5` files in parallel, with a default of `2` to balance throughput against RAM and CPU pressure on Apple Silicon laptops and desktops.
- Local transcription engine direction: the next transcription implementation on this branch will use in-process `whisper.cpp` with Metal support, Marathi pinned as the input language for v1, and `ggml-large-v3-turbo` as the primary model with `ggml-large-v3` as a fallback.
- Transcription input contract: local transcription should consume the `HYBRID` enhancement output, then create a temporary `16 kHz` mono PCM WAV specifically for inference rather than transcribing directly from the exported `.m4a`.
- Local translation sequencing: translation work should begin only after `whisper.cpp` transcription support is landed and validated on real Marathi-enhanced files.
- Local translation engine direction: the first serious Marathi-to-English translation implementation on this branch will use `facebook/nllb-200-distilled-600M` via `CTranslate2` with `int8` conversion, operating on bounded Marathi transcript segments and writing `translation_en` onto each segment in order.
- Translation runtime constraints: do not promise a native Swift/CoreML translation path or M4 GPU acceleration in v1; translation should be treated as a local post-transcription phase that does not co-reside with Whisper in memory during normal execution.
- Translation orchestration: even once local translation is enabled, it should not start while other files are still transcribing. The batch runner now reserves translation for a separate post-transcription phase so the translation model can run after the transcription phase drains.
- Post-translation output destination: the future updated UX should create a fresh Desktop batch folder named `output_<timestamp>` instead of asking the user to choose an output location manually.
- Post-translation enhancement selection: the future updated UX should make enhancement a single batch-level choice between `DFN` and `HYBRID`, not a side-by-side dual-output comparison flow.
- Post-translation source-language scope: the future updated UX should fix source language to Marathi for this release instead of exposing a language picker.
- Post-translation export scope: `Export All ZIP` should package the entire generated batch output folder and all per-file contents.
- Current UI pass scope: start the 4-step UX refactor before translation returns, with Marathi fixed as the source language, no translation toggle in Configure, and the Results screen focused on processed audio plus Marathi transcript preview.
- Current UI controls: keep `Transcribe audio` as a visible toggle so the team can disable transcription quickly while audio cleanup and local ASR quality are still being validated.

## 2026-04-21

- Mainline promotion: the `local-offline-v2` work is now the product direction that should live on `main`.
- Repository split: dormant transcription, translation, and evaluation-harness code has been moved off `main` and preserved on the dedicated branch `transcription-translation-rnd`.
- Shipped feature scope: the live app is enhancement-only for now; `main` contains only the code required for that shipped workflow.
- Runtime dependency setup: first-run onboarding now checks, downloads, verifies, and manages `FFmpeg` and `DeepFilterNet` inside `~/Library/Application Support/ClearVoice/Tools`.
- Results review surface: step 4 now opens a generated local `index.html` page directly from disk instead of rendering an embedded review surface or running a local web server.
- Distribution artifact: the repo now includes a reproducible `script/build_dmg.sh` flow for packaging a shareable `.dmg` from the current macOS app bundle.
- Source scan depth: the enhancement workflow should always scan nested subfolders recursively rather than only the first folder level.
- Enhancement output location: the shipped enhancement-only app now writes to a sibling folder named `<source>_enhanced` instead of a Desktop `output_<timestamp>` folder.
- Enhancement output layout: the shipped enhancement-only app mirrors the source directory structure inside `<source>_enhanced` and keeps enhancement suffixes on the generated files.
- Existing output-folder collision handling: if `<source>_enhanced` already exists, the app should block starting the batch until the user either chooses a new folder name or deletes the old output folder.
- Source/enhanced review toggle: the browser results page should switch between enhanced audio and the original source file in place, without copying source audio into the output directory.
- Cancellation posture: the processing screen should support both per-file cancel and full-batch cancel, and both should stop active subprocess work as soon as possible rather than waiting for the current file to finish naturally.
- Temp-file cleanup posture: temporary normalized audio, DeepFilterNet working folders, and partial enhancement outputs should be cleaned up immediately after use and also during cancel/quit paths where possible.

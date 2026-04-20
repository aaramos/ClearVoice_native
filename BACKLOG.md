# ClearVoice Backlog

## Media Pipeline

- Evaluate FFmpeg for Gemini cloud-upload preparation so ClearVoice can transcode speech inputs into a smaller supported upload format before transcription.
- Goal: prefer the smallest reliable Gemini-supported format for speech uploads, likely low-bitrate AAC or MP3, instead of the current temporary WAV path.
- Constraints:
  - Keep the converted file temporary-only and clean it up after upload.
  - Verify actual Gemini API acceptance for the chosen MIME/container combination before switching the default path.
  - Document packaging and license/compliance implications for bundling or requiring FFmpeg on macOS.
  - Preserve the current WAV fallback if compressed upload prep is unavailable or fails at runtime.

## Documentation

- Update the engineering handoff, README, and any behavior docs to reflect the runtime translation fallback: when `Translation` is set to on-device and the local Apple Translation step fails, ClearVoice now retries translation with Gemini if a Gemini key is available.
- Update the engineering handoff, README, and any behavior docs to reflect the runtime transcription fallback: when `Transcription` is set to on-device and the local Apple speech asset is not installed or still downloading, ClearVoice now retries transcription with Gemini if a Gemini key is available, and the user-facing status text now distinguishes `downloading` from `available but not installed`.

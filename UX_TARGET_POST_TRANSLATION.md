# ClearVoice UX Roadmap

This document captures the intended future UX direction for ClearVoice after transcription and translation return.

The live app currently ships as an enhancement-and-review product with browser-based results, bundled dependency setup, user-selectable `DFN` / `HYBRID` enhancement, and no active transcription or translation flow. The roadmap below is retained as a future-facing reference for a later local text-processing release, and the experimental implementation work for that future path now lives on `transcription-translation-rnd`.

## Product Decisions Locked For This Future UX

- Source language is fixed to Marathi for that future text-processing release.
- The app does not ask the user to choose an output folder.
- Each batch creates a new Desktop folder named `output_<timestamp>`.
- Each processed source file gets its own subfolder inside that batch output folder.
- Enhancement is a single choice per batch:
  - `DFN`
  - `HYBRID`
- `Export All ZIP` packages the entire batch output folder and all contents.

## Step 1: Import

### Goal

The user drops a folder into the app and immediately sees what is eligible for processing.

### UI

- Header shows `ClearVoice` and `Step 1 of 4`
- Primary drop zone supports drag-and-drop of a folder
- Secondary affordance allows choosing a folder with a standard picker
- After scan completes, a file table appears

### File Table

Columns:

- `File Name`
- `Status`
- `Duration`

Status values:

- `Ready`
- `Skipped`

If skipped, a reason should be available inline or on expansion.

### Batch Output Preview

The screen should show the planned output location before the user proceeds:

- `Desktop/output_<timestamp>`

### CTA

- `Next`
- Disabled until at least one file is `Ready`

## Step 2: Configure

### Goal

Let the user make only the essential processing choices.

### UI

- Header shows `Step 2 of 4`
- Title: `How should we process the audio?`

### Controls

#### A. Enhancement Method

Single-select cards or segmented control:

- `DFN`
  - DeepFilterNet enhancement
  - Voice cleanup with lighter overall shaping
- `HYBRID`
  - FFmpeg cleanup plus DeepFilterNet
  - Stronger noise reduction

Only one may be selected.

#### B. Processing Options

- `Transcribe audio`
  - Output is Marathi transcript

For that future UI pass, no English translation control is shown until local translation is ready again.

#### C. Processing Speed

- Label: `Processing Speed`
- Values: `1` to `10`
- Default: `5`
- Guidance text should explain that higher values are better for machines with more compute

### CTA

- `Back`
- `Next`

## Step 3: Process

### Goal

Show clear live progress for the overall batch and each file.

### Global Batch Status

- Elapsed time
- Global progress bar
- Count summary:
  - complete
  - processing
  - pending
  - failed
  - skipped

### Per-File Status Rows

Each file row should stay in place and update in place.

Recommended stage labels:

- `Analyzing`
- `Normalizing`
- `Enhancing`
- `Preparing transcript`
- `Transcribing`
- `Exporting`
- `Finished`
- `Skipped`
- `Error`

Failures and skips must remain visible and include the reason.

### CTA

- `Show Results`
- Enabled only when every file is terminal:
  - finished
  - skipped
  - error

## Step 4: Results

### Goal

Let the user review what was created and export everything with minimal friction.

### Layout

Each processed file appears as its own result item.

Per file, show:

- source filename
- enhancement method used (`DFN` or `HYBRID`)
- audio player for the processed output
- transcript preview

### Transcript Structure In The Current UI Pass

The current UI pass should show the Marathi transcript only.

- `SOURCE TRANSCRIPT (MARATHI)`

### Transcript Structure After Translation Returns

The transcript text file should contain:

1. source-language transcript first
2. English translation second

Recommended section order:

- `SOURCE TRANSCRIPT (MARATHI)`
- `ENGLISH TRANSLATION`

If English translation is not selected, omit the English section.

### Per-File Actions

- `Copy Transcript`
- `Reveal in Finder`
- `Open Folder`

### Global Actions

- `Export All ZIP`
- `Done`

## Output Structure

Each run creates:

```text
~/Desktop/output_<timestamp>/
```

Inside that folder:

```text
output_<timestamp>/
  <file-basename>/
    <file-basename>_<DFN or HYBRID>.m4a
    <file-basename>_transcript.txt
```

If a file fails:

- keep the per-file folder if it was created
- write `_error.log`

## Export All ZIP

`Export All ZIP` should create a zip archive of the entire batch output folder, including:

- every per-file subfolder
- processed audio files
- transcript text files
- any error logs

## Build Order

The Marathi-only shell can land before translation.

Suggested order:

1. ship the Marathi-only 4-step shell
2. validate transcription and results review in the new shell
3. finish local translation
4. add English translation controls and results sections
5. keep ZIP export in the same Results screen

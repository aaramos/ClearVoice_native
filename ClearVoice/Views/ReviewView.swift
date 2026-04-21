import AppKit
import SwiftUI

struct ReviewView: View {
    @ObservedObject var viewModel: BatchViewModel
    let onStartNewBatch: () -> Void

    @State private var isExportingArchive = false
    @State private var archiveMessage: String?

    private let archiveExporter = BatchArchiveExporter()

    var body: some View {
        StepCard(
            title: "Results",
            detail: "Review the generated files for this batch, preview the Marathi transcript when available, and export the full output folder as a ZIP."
        ) {
            VStack(alignment: .leading, spacing: 18) {
                summaryCard

                if let archiveMessage {
                    Text(archiveMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(viewModel.files) { file in
                            resultCard(for: file)
                        }
                    }
                }

                HStack {
                    if let outputFolderURL = viewModel.outputFolderURL {
                        Button("Reveal Batch Folder") {
                            revealInFinder(outputFolderURL)
                        }
                    }

                    Spacer()

                    Button(isExportingArchive ? "Exporting ZIP…" : "Export All ZIP") {
                        exportAll()
                    }
                    .disabled(isExportingArchive || viewModel.outputFolderURL == nil)

                    Button("New Batch", action: onStartNewBatch)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Batch Summary")
                .font(.headline)

            HStack(spacing: 12) {
                summaryMetric(label: "Complete", value: "\(viewModel.completedCount)")
                Divider()
                summaryMetric(label: "Failed", value: "\(viewModel.failedCount)")
                Divider()
                summaryMetric(label: "Skipped", value: "\(viewModel.skippedCount)")
                Divider()
                summaryMetric(label: "Enhancement", value: viewModel.selectedEnhancementMethod?.title ?? "—")
            }

            if let outputFolderURL = viewModel.outputFolderURL {
                Text(outputFolderURL.path(percentEncoded: false))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .cardStyle()
    }

    private func resultCard(for file: AudioFileItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.sourceURL.lastPathComponent)
                        .font(.headline)

                    if let durationSeconds = file.durationSeconds {
                        Text(DurationFormatter.formattedDuration(seconds: durationSeconds))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(resultBadgeTitle(for: file.stage))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(resultBadgeColor(for: file.stage).opacity(0.12))
                    )
                    .foregroundStyle(resultBadgeColor(for: file.stage))
            }

            if let detail = resultDetail(for: file) {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if let processedAudioURL = processedAudioURL(for: file) {
                    Button("Open Audio") {
                        NSWorkspace.shared.open(processedAudioURL)
                    }
                }

                if let transcriptURL = transcriptURL(for: file), viewModel.transcriptionEnabled {
                    Button("Open Transcript") {
                        NSWorkspace.shared.open(transcriptURL)
                    }
                }

                if let folderURL = file.outputFolderURL {
                    Button("Reveal Folder") {
                        revealInFinder(folderURL)
                    }
                }

                Spacer()
            }

            if viewModel.transcriptionEnabled {
                transcriptPreview(for: file)
            } else {
                Text("Transcription was turned off for this batch.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private func transcriptPreview(for file: AudioFileItem) -> some View {
        if let preview = transcriptPreviewText(for: file) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Marathi Transcript")
                    .font(.subheadline.weight(.semibold))
                Text(preview)
                    .font(.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if case .complete = file.stage {
            Text("No transcript preview is available for this file yet.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func summaryMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func resultBadgeTitle(for stage: ProcessingStage) -> String {
        switch stage {
        case .complete:
            return "Ready"
        case .failed:
            return "Failed"
        case .skipped:
            return "Skipped"
        default:
            return "In Progress"
        }
    }

    private func resultBadgeColor(for stage: ProcessingStage) -> Color {
        switch stage {
        case .complete:
            return .green
        case .failed:
            return .red
        case .skipped:
            return .orange
        default:
            return .secondary
        }
    }

    private func resultDetail(for file: AudioFileItem) -> String? {
        switch file.stage {
        case .failed(let error):
            switch error {
            case .audioUnreadable:
                return "ClearVoice couldn’t read this source file."
            case .enhancementFailed(let message),
                    .transcriptionFailed(let message),
                    .translationFailed(let message),
                    .summarizationFailed(let message),
                    .exportFailed(let message):
                return message
            case .cancelled:
                return "Processing stopped before the file finished."
            }
        case .skipped(let reason):
            switch reason {
            case .outputFolderExists(let folderURL):
                return "Skipped because \(folderURL.lastPathComponent) already existed in the Desktop output folder."
            }
        case .complete:
            if viewModel.transcriptionEnabled {
                return "Processed audio and Marathi transcript are ready in this file folder."
            }
            return "Processed audio is ready in this file folder."
        default:
            return nil
        }
    }

    private func processedAudioURL(for file: AudioFileItem) -> URL? {
        guard
            let folderURL = file.outputFolderURL,
            let enhancementMethod = viewModel.selectedEnhancementMethod
        else {
            return nil
        }

        let url = folderURL.appendingPathComponent("\(file.basename)_\(enhancementMethod.outputSuffix).m4a")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func transcriptURL(for file: AudioFileItem) -> URL? {
        guard let folderURL = file.outputFolderURL else {
            return nil
        }

        let url = folderURL.appendingPathComponent("\(file.basename)_transcript.txt")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func transcriptPreviewText(for file: AudioFileItem) -> String? {
        guard let transcript = file.originalTranscript?.trimmingCharacters(in: .whitespacesAndNewlines), !transcript.isEmpty else {
            return nil
        }

        let limit = 1_200
        guard transcript.count > limit else {
            return transcript
        }

        return String(transcript.prefix(limit)) + "\n…"
    }

    private func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func exportAll() {
        guard let outputFolderURL = viewModel.outputFolderURL else {
            archiveMessage = BatchArchiveExportError.missingOutputFolder.localizedDescription
            return
        }

        isExportingArchive = true
        archiveMessage = nil

        Task {
            do {
                let archiveURL = try await Task.detached(priority: .userInitiated) {
                    try archiveExporter.exportArchive(for: outputFolderURL)
                }.value

                await MainActor.run {
                    isExportingArchive = false
                    archiveMessage = "Exported \(archiveURL.lastPathComponent) next to the batch folder on the Desktop."
                    revealInFinder(archiveURL)
                }
            } catch {
                await MainActor.run {
                    isExportingArchive = false
                    archiveMessage = error.localizedDescription
                }
            }
        }
    }
}

private extension View {
    func cardStyle() -> some View {
        self
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
    }
}

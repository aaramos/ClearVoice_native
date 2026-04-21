import AppKit
import SwiftUI

struct ReviewView: View {
    @ObservedObject var viewModel: BatchViewModel
    let onStartNewBatch: () -> Void

    @State private var isExportingArchive = false
    @State private var archiveMessage: String?

    private let archiveExporter = BatchArchiveExporter()

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Text("Results")
                    .font(.system(size: 22, weight: .semibold))

                Text(resultsSubtitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 16)

            if let archiveMessage {
                Text(archiveMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ScrollView {
                VStack(spacing: 18) {
                    ForEach(viewModel.files) { file in
                        resultRow(for: file)
                    }
                }
            }

            HStack {
                Button(isExportingArchive ? "Exporting…" : "Export All") {
                    exportAll()
                }
                .buttonStyle(SecondaryActionButtonStyle())
                .disabled(isExportingArchive || viewModel.outputFolderURL == nil)

                Spacer()

                Button("Done", action: onStartNewBatch)
                    .buttonStyle(PrimaryActionButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var resultsSubtitle: String {
        if viewModel.transcriptionEnabled {
            return "All processing is complete. Review your enhanced audio and Marathi transcripts below."
        }

        return "All processing is complete. Review your enhanced audio files below."
    }

    private func resultRow(for file: AudioFileItem) -> some View {
        HStack(alignment: .top, spacing: 22) {
            mediaCard(for: file)
                .frame(maxWidth: .infinity)

            transcriptCard(for: file)
                .frame(maxWidth: .infinity)
        }
    }

    private func mediaCard(for file: AudioFileItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: iconName(for: file.sourceURL))
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Text(file.sourceURL.lastPathComponent)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)

                Text("Enhanced: \(viewModel.selectedEnhancementMethod?.title ?? "—")")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.blue.opacity(0.08))
                    )

                Spacer()
            }

            if let processedAudioURL = processedAudioURL(for: file) {
                AudioPreviewPlayerView(fileURL: processedAudioURL)
            }

            HStack(spacing: 10) {
                Button("Copy") {
                    copyTranscript(for: file)
                }
                .buttonStyle(SecondaryActionButtonStyle())
                .disabled(transcriptPreviewText(for: file) == nil)

                if let processedAudioURL = processedAudioURL(for: file) {
                    Button("Download") {
                        revealInFinder(processedAudioURL)
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                }

                if let folderURL = file.outputFolderURL {
                    Button("Open Folder") {
                        revealInFinder(folderURL)
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                }
            }

            if let detail = resultDetail(for: file) {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func transcriptCard(for file: AudioFileItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(viewModel.transcriptionEnabled ? "Marathi Transcript" : "Transcript")
                    .font(.title3.weight(.medium))

                Spacer()

                if let transcriptURL = transcriptURL(for: file), viewModel.transcriptionEnabled {
                    Button("Download .txt") {
                        revealInFinder(transcriptURL)
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                }
            }

            if let preview = transcriptPreviewText(for: file), viewModel.transcriptionEnabled {
                ScrollView {
                    Text(preview)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(minHeight: 210)
            } else if viewModel.transcriptionEnabled {
                Text("No transcript is available for this file.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .frame(minHeight: 210)
            } else {
                Text("Transcription was turned off for this batch.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .frame(minHeight: 210)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        )
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
                return "Skipped because \(folderURL.lastPathComponent) already existed in the batch output folder."
            }
        case .complete:
            return nil
        default:
            return "This file is still processing."
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

        return transcript
    }

    private func copyTranscript(for file: AudioFileItem) {
        guard let transcript = transcriptPreviewText(for: file) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
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
                    archiveMessage = "Exported \(archiveURL.lastPathComponent) next to the batch folder."
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

    private func iconName(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "wav", "flac":
            return "waveform"
        case "mp3", "aac", "m4a", "wma":
            return "music.note"
        default:
            return "waveform.circle"
        }
    }
}

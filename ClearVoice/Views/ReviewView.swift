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
                Text("Results Opened In Browser")
                    .font(.system(size: 22, weight: .semibold))

                Text(resultsSubtitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 16)

            browserStatusCard

            if let archiveMessage {
                Text(archiveMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
        .task {
            await viewModel.prepareResultsBrowserIfNeeded()
        }
    }

    private var resultsSubtitle: String {
        "ClearVoice writes an index page directly into the batch output folder and opens that local file in your browser so you can review and share the results outside the app."
    }

    private var browserStatusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if viewModel.isPreparingResultsBrowser {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Preparing the results page and opening your browser…")
                        .foregroundStyle(.secondary)
                }
            } else if let resultsBrowserURL = viewModel.resultsBrowserURL {
                Label("Results page is ready", systemImage: "globe")
                    .font(.headline)
                    .foregroundStyle(Color.blue)

                Link(destination: resultsBrowserURL) {
                    Text(resultsBrowserURL.absoluteString)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }

                if let resultsPageFileURL = viewModel.resultsPageFileURL {
                    Text("Saved page: \(resultsPageFileURL.path)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } else if let resultsBrowserError = viewModel.resultsBrowserError {
                Label(resultsBrowserError, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Open the batch in your browser to review the processed audio outside the app.")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button("Open Browser Again") {
                    viewModel.openResultsInBrowser()
                }
                .buttonStyle(SecondaryActionButtonStyle())
                .disabled(viewModel.resultsBrowserURL == nil)

                if let outputFolderURL = viewModel.outputFolderURL {
                    Button("Reveal Batch Folder") {
                        revealInFinder(outputFolderURL)
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
}

import SwiftUI

struct ImportView: View {
    @ObservedObject var viewModel: ImportViewModel
    let onNext: () -> Void

    var body: some View {
        StepCard(
            title: "Import",
            detail: "Choose a source folder and an output folder. ClearVoice scans supported audio before you move on."
        ) {
            VStack(alignment: .leading, spacing: 18) {
                FolderPicker(
                    title: "Source Folder",
                    subtitle: "Select the folder that contains your audio recordings.",
                    selection: viewModel.sourceFolderURL,
                    buttonTitle: "Choose Source"
                ) { url in
                    viewModel.selectSourceFolder(url)
                }

                FolderPicker(
                    title: "Output Folder",
                    subtitle: "Select an existing folder where ClearVoice should create per-file subfolders later.",
                    selection: viewModel.outputFolderURL,
                    buttonTitle: "Choose Output"
                ) { url in
                    viewModel.selectOutputFolder(url)
                }

                summaryCard

                if !viewModel.validationMessages.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Before You Continue")
                            .font(.headline)

                        ForEach(viewModel.validationMessages, id: \.self) { message in
                            Label(message, systemImage: "exclamationmark.circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                }

                if !viewModel.scanResult.supported.isEmpty || !viewModel.scanResult.skipped.isEmpty {
                    DisclosureGroup("View Files") {
                        VStack(alignment: .leading, spacing: 12) {
                            if !viewModel.scanResult.supported.isEmpty {
                                fileList(title: "Supported", urls: viewModel.scanResult.supported)
                            }

                            if !viewModel.scanResult.skipped.isEmpty {
                                fileList(title: "Skipped", urls: viewModel.scanResult.skipped)
                            }
                        }
                        .padding(.top, 12)
                    }
                }

                Spacer()

                HStack {
                    Spacer()
                    Button("Next", action: onNext)
                        .disabled(!viewModel.canProceed)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Scan Summary")
                .font(.headline)

            if viewModel.isScanning {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Scanning the selected source folder…")
                        .foregroundStyle(.secondary)
                }
            } else if let scanErrorMessage = viewModel.scanErrorMessage {
                Text(scanErrorMessage)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    summaryMetric(label: "Files", value: "\(viewModel.supportedFileCount)")
                    Divider()
                    summaryMetric(label: "Skipped", value: "\(viewModel.skippedFileCount)")
                    Divider()
                    summaryMetric(label: "Duration", value: viewModel.formattedDuration)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
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

    private func fileList(title: String, urls: [URL]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            ForEach(urls, id: \.path) { url in
                HStack(alignment: .top) {
                    Image(systemName: "waveform")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.lastPathComponent)
                        Text(url.deletingLastPathComponent().path(percentEncoded: false))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

import SwiftUI

struct ImportView: View {
    @ObservedObject var viewModel: ImportViewModel
    let onNext: () -> Void

    var body: some View {
        StepCard(
            title: "Import",
            detail: "Choose the source folder once. ClearVoice scans supported audio, shows what is ready, and creates a new Desktop output folder for this batch automatically."
        ) {
            VStack(alignment: .leading, spacing: 18) {
                FolderPicker(
                    title: "Source Folder",
                    subtitle: "Select the folder that contains the Marathi recordings you want to process.",
                    selection: viewModel.sourceFolderURL,
                    buttonTitle: "Choose Source Folder"
                ) { url in
                    viewModel.selectSourceFolder(url)
                }

                summaryCard
                outputPreviewCard

                if !viewModel.validationMessages.isEmpty {
                    validationCard
                }

                if !viewModel.scanResult.supported.isEmpty || !viewModel.scanResult.skipped.isEmpty {
                    fileTableCard
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
                    summaryMetric(label: "Ready", value: "\(viewModel.supportedFileCount)")
                    Divider()
                    summaryMetric(label: "Skipped", value: "\(viewModel.skippedFileCount)")
                    Divider()
                    summaryMetric(label: "Duration", value: viewModel.formattedDuration)
                }
            }
        }
        .cardStyle()
    }

    private var outputPreviewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output Location")
                .font(.headline)

            if viewModel.plannedOutputFolderDisplayPath.isEmpty {
                Text("Choose a source folder to preview the Desktop output folder.")
                    .foregroundStyle(.secondary)
            } else {
                Text(viewModel.plannedOutputFolderDisplayPath)
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }

    private var validationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Before You Continue")
                .font(.headline)

            ForEach(viewModel.validationMessages, id: \.self) { message in
                Label(message, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }

    private var fileTableCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Files")
                .font(.headline)

            fileHeader

            ForEach(viewModel.readyFiles, id: \.url.path) { file in
                fileRow(
                    name: file.url.lastPathComponent,
                    status: "Ready",
                    duration: DurationFormatter.formattedDuration(seconds: file.durationSeconds)
                )
            }

            ForEach(viewModel.scanResult.skipped, id: \.path) { url in
                fileRow(
                    name: url.lastPathComponent,
                    status: "Skipped",
                    duration: "—"
                )
            }
        }
        .cardStyle()
    }

    private var fileHeader: some View {
        HStack {
            Text("File Name")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Status")
                .frame(width: 80, alignment: .leading)
            Text("Duration")
                .frame(width: 80, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private func fileRow(name: String, status: String, duration: String) -> some View {
        HStack {
            Text(name)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(status)
                .foregroundStyle(status == "Ready" ? .primary : .secondary)
                .frame(width: 80, alignment: .leading)

            Text(duration)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, 4)
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

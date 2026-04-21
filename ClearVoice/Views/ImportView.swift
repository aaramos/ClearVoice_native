import SwiftUI

struct ImportView: View {
    @ObservedObject var viewModel: ImportViewModel
    let onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            FolderPicker(
                title: "Drop a folder of audio files",
                subtitle: "to begin",
                selection: viewModel.sourceFolderURL,
                buttonTitle: "Click to choose a folder"
            ) { url in
                viewModel.selectSourceFolder(url)
            }

            if viewModel.isScanning {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("ClearVoice is scanning the selected folder and listing eligible files.")
                        .foregroundStyle(.secondary)
                }
            } else if let scanErrorMessage = viewModel.scanErrorMessage {
                inlineNotice(scanErrorMessage, tone: .error)
            } else if !viewModel.plannedOutputFolderDisplayPath.isEmpty {
                Text("Batch output: \(viewModel.plannedOutputFolderDisplayPath)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if !viewModel.validationMessages.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(viewModel.validationMessages, id: \.self) { message in
                        inlineNotice(message, tone: .neutral)
                    }
                }
            }

            if !viewModel.scanResult.supported.isEmpty || !viewModel.scanResult.skipped.isEmpty {
                fileTable
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()

                Button("Next", action: onNext)
                    .buttonStyle(PrimaryActionButtonStyle())
                    .disabled(!viewModel.canProceed)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.top, 8)
    }

    private var fileTable: some View {
        VStack(spacing: 0) {
            tableHeader

            ForEach(Array(viewModel.readyFiles.enumerated()), id: \.element.url.path) { index, file in
                if index > 0 {
                    Divider()
                }

                fileRow(
                    url: file.url,
                    status: "Ready",
                    duration: DurationFormatter.formattedDuration(seconds: file.durationSeconds)
                )
            }

            if !viewModel.readyFiles.isEmpty && !viewModel.scanResult.skipped.isEmpty {
                Divider()
            }

            ForEach(Array(viewModel.scanResult.skipped.enumerated()), id: \.element.path) { index, url in
                if index > 0 {
                    Divider()
                }

                fileRow(
                    url: url,
                    status: "Skipped",
                    duration: "—"
                )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        )
    }

    private var tableHeader: some View {
        HStack(spacing: 12) {
            Text("File Name")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Status")
                .frame(width: 120, alignment: .leading)
            Text("Duration")
                .frame(width: 120, alignment: .trailing)
        }
        .font(.headline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private func fileRow(url: URL, status: String, duration: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: audioIconName(for: url))
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            Text(url.lastPathComponent)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            statusPill(status)
                .frame(width: 120, alignment: .leading)

            Text(duration)
                .font(.title3.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .trailing)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private func statusPill(_ status: String) -> some View {
        Text(status)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(status == "Ready" ? Color.blue : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(status == "Ready" ? Color.blue.opacity(0.10) : Color(nsColor: .controlColor))
            )
    }

    private func inlineNotice(_ message: String, tone: InlineTone) -> some View {
        Label(message, systemImage: tone.symbolName)
            .font(.footnote)
            .foregroundStyle(tone.color)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tone.backgroundColor)
            )
    }

    private func audioIconName(for url: URL) -> String {
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

private enum InlineTone {
    case neutral
    case error

    var symbolName: String {
        switch self {
        case .neutral:
            return "info.circle"
        case .error:
            return "exclamationmark.triangle"
        }
    }

    var color: Color {
        switch self {
        case .neutral:
            return .secondary
        case .error:
            return .orange
        }
    }

    var backgroundColor: Color {
        switch self {
        case .neutral:
            return Color(nsColor: .controlBackgroundColor)
        case .error:
            return Color.orange.opacity(0.10)
        }
    }
}

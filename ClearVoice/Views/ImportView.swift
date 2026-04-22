import SwiftUI

struct ImportView: View {
    @ObservedObject var viewModel: ImportViewModel
    let onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            intro

            FolderPicker(
                title: "Drop a folder of audio files",
                subtitle: "ClearVoice will scan the folder, list supported files, and mirror the folder structure into a sibling enhanced folder.",
                selection: viewModel.sourceFolderURL,
                buttonTitle: "Click to choose a folder"
            ) { url in
                viewModel.selectSourceFolder(url)
            }

            if viewModel.sourceFolderURL != nil {
                outputFolderSettings
            }

            if viewModel.isScanning {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("ClearVoice is scanning the selected folder and listing eligible files.")
                        .foregroundStyle(Color.black.opacity(0.62))
                }
            } else if let scanErrorMessage = viewModel.scanErrorMessage {
                inlineNotice(scanErrorMessage, tone: .error)
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

            HStack {
                Spacer()

                Button("Next", action: onNext)
                    .buttonStyle(PrimaryActionButtonStyle())
                    .disabled(!viewModel.canProceed)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.top, 4)
    }

    private var outputFolderSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enhanced Output Folder")
                .font(.headline)
                .foregroundStyle(Color.black.opacity(0.78))

            Text("ClearVoice will create a sibling folder next to the source folder and mirror the same nested structure inside it.")
                .font(.footnote)
                .foregroundStyle(Color.black.opacity(0.58))

            TextField("Enhanced folder name", text: $viewModel.outputFolderName)
                .textFieldStyle(.roundedBorder)

            if !viewModel.plannedOutputFolderDisplayPath.isEmpty {
                Text(viewModel.plannedOutputFolderDisplayPath)
                    .font(.footnote)
                    .foregroundStyle(Color.black.opacity(0.55))
                    .textSelection(.enabled)
            }

            if viewModel.outputFolderExists {
                HStack(spacing: 12) {
                    Button("Use New Name") {
                        viewModel.chooseSuggestedOutputFolderName()
                    }
                    .buttonStyle(SecondaryActionButtonStyle())

                    Button("Delete Existing") {
                        viewModel.deleteExistingOutputFolder()
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        )
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose Your Files")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.92))

            Text("Drop a folder into ClearVoice to scan audio files, estimate duration, and prepare a mirrored enhanced folder for processing.")
                .font(.title3)
                .foregroundStyle(Color.black.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
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
        .foregroundStyle(Color.black.opacity(0.58))
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
                .foregroundStyle(Color.black.opacity(0.88))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            statusPill(status)
                .frame(width: 120, alignment: .leading)

            Text(duration)
                .font(.title3.monospacedDigit())
                .foregroundStyle(Color.black.opacity(0.54))
                .frame(width: 120, alignment: .trailing)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private func statusPill(_ status: String) -> some View {
        Text(status)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(status == "Ready" ? Color.blue : Color.black.opacity(0.55))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(status == "Ready" ? Color.blue.opacity(0.10) : Color.black.opacity(0.05))
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
            return Color.black.opacity(0.65)
        case .error:
            return .orange
        }
    }

    var backgroundColor: Color {
        switch self {
        case .neutral:
            return Color.black.opacity(0.05)
        case .error:
            return Color.orange.opacity(0.10)
        }
    }
}

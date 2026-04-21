import SwiftUI

struct ProcessView: View {
    @ObservedObject var viewModel: BatchViewModel
    let onBack: () -> Void
    let onShowResults: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Text("Processing Status")
                    .font(.system(size: 22, weight: .semibold))

                Text("Enhancing files and exporting cleaned audio. This may take a while. Please keep this window open.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 16)

            statusBoard

            HStack {
                Button("Back", action: onBack)
                    .buttonStyle(SecondaryActionButtonStyle())
                    .disabled(viewModel.isRunning)

                Spacer()

                Button("Open Results", action: onShowResults)
                    .buttonStyle(PrimaryActionButtonStyle())
                    .disabled(!viewModel.didFinish)
            }
            .padding(.top, 4)
        }
        .task {
            viewModel.startIfNeeded()
        }
    }

    private var statusBoard: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.files.enumerated()), id: \.element.id) { index, file in
                if index > 0 {
                    Divider()
                }

                fileRow(for: file)
            }

            Divider()

            elapsedFooter
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

    private func fileRow(for file: AudioFileItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: iconName(for: file.sourceURL))
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 8) {
                Text(file.sourceURL.lastPathComponent)
                    .font(.title3.weight(.semibold))

                HStack(spacing: 10) {
                    Text(stageLabel(for: file.stage))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(stageAccentColor(for: file.stage))

                    if isProgressStage(file.stage) {
                        ProgressView(value: progressFraction(for: file.stage))
                            .tint(Color.orange)
                    }
                }

                if let detail = stageDetail(for: file.stage) {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Text(file.durationSeconds.map { DurationFormatter.formattedDuration(seconds: $0) } ?? "—")
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private var elapsedFooter: some View {
        if let runFinishedAt = viewModel.runFinishedAt {
            footerRow(at: runFinishedAt)
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                footerRow(at: context.date)
            }
        }
    }

    private func footerRow(at date: Date) -> some View {
        HStack(spacing: 12) {
            Text("Elapsed: \(elapsedLabel(at: date))")
                .font(.title3.monospacedDigit())
                .foregroundStyle(.secondary)

            ProgressView(value: viewModel.overallProgressFraction)
                .tint(Color.blue)

            Text("\(Int(viewModel.overallProgressFraction * 100))%")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    private func elapsedLabel(at date: Date) -> String {
        guard let runStartedAt = viewModel.runStartedAt else {
            return "00:00"
        }

        let elapsed = max(Int(date.timeIntervalSince(runStartedAt)), 0)
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        return String(format: "%02d:%02d", minutes, seconds)
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

    private func isProgressStage(_ stage: ProcessingStage) -> Bool {
        switch stage {
        case .analyzing, .analyzingFormat, .normalizingFormat, .cleaning, .exporting:
            return true
        default:
            return false
        }
    }

    private func progressFraction(for stage: ProcessingStage) -> Double {
        switch stage {
        case .pending:
            return 0
        case .analyzing:
            return 0.08
        case .analyzingFormat:
            return 0.14
        case .normalizingFormat:
            return 0.24
        case .cleaning(let progress):
            return 0.24 + (0.70 * progress)
        case .exporting:
            return 0.98
        case .complete, .failed, .skipped:
            return 1
        }
    }

    private func stageLabel(for stage: ProcessingStage) -> String {
        switch stage {
        case .pending:
            return "Pending"
        case .analyzing, .analyzingFormat:
            return "Analyzing"
        case .normalizingFormat:
            return "Normalizing"
        case .cleaning:
            return "Enhancing"
        case .exporting:
            return "Exporting"
        case .complete:
            return "Finished"
        case .failed:
            return "Error"
        case .skipped:
            return "Skipped"
        }
    }

    private func stageAccentColor(for stage: ProcessingStage) -> Color {
        switch stage {
        case .complete:
            return .green
        case .failed:
            return .red
        case .skipped:
            return .secondary
        default:
            return .orange
        }
    }

    private func stageDetail(for stage: ProcessingStage) -> String? {
        switch stage {
        case .failed(let error):
            return error.displayMessage
        case .skipped(let reason):
            switch reason {
            case .outputFolderExists(let url):
                return "Skipped because \(url.lastPathComponent) already exists in the output folder."
            }
        default:
            return nil
        }
    }
}

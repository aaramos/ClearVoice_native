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

                Text("Processing files. This may take a while. Please keep this window open.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 16)

            if let languageSelectionPrompt = viewModel.languageSelectionPrompt {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(languageSelectionPrompt)
                            .fixedSize(horizontal: false, vertical: true)

                        Button("Choose Source Language", action: onBack)
                            .buttonStyle(SecondaryActionButtonStyle())
                            .disabled(viewModel.isRunning)
                    }

                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.orange.opacity(0.10))
                )
            }

            statusBoard

            HStack {
                Button("Back", action: onBack)
                    .buttonStyle(SecondaryActionButtonStyle())
                    .disabled(viewModel.isRunning)

                Spacer()

                Button("Show Results", action: onShowResults)
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

            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 12) {
                    Text("Elapsed: \(elapsedLabel(at: context.date))")
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
        case .analyzing, .analyzingFormat, .normalizingFormat, .cleaning, .optimizingForUpload, .transcribing, .exporting:
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
            return 0.24 + (0.36 * progress)
        case .optimizingForUpload:
            return 0.62
        case .transcribing(let progress):
            return 0.62 + (0.24 * progress)
        case .translating:
            return 0.86
        case .summarizing:
            return 0.92
        case .exporting:
            return 0.97
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
        case .optimizingForUpload:
            return "Preparing transcript"
        case .transcribing:
            return "Transcribing"
        case .translating:
            return "Translating"
        case .summarizing:
            return "Summarizing"
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
            switch error {
            case .audioUnreadable:
                return "ClearVoice couldn’t read this audio file."
            case .enhancementFailed(let message),
                    .transcriptionFailed(let message),
                    .translationFailed(let message),
                    .summarizationFailed(let message),
                    .exportFailed(let message):
                return message
            case .cancelled:
                return "Processing stopped before this file finished."
            }
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

import SwiftUI

struct ProcessView: View {
    @ObservedObject var viewModel: BatchViewModel
    let onBack: () -> Void
    let onCompletePlaceholder: () -> Void

    var body: some View {
        StepCard(
            title: "Process",
            detail: "ClearVoice is temporarily running in enhancement-only mode: each file gets a DeepFilterNet output and a Hybrid output."
        ) {
            VStack(alignment: .leading, spacing: 18) {
                Text(viewModel.statusText)
                    .foregroundStyle(.secondary)

                if let languageSelectionPrompt = viewModel.languageSelectionPrompt {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 10) {
                            Text(languageSelectionPrompt)
                                .fixedSize(horizontal: false, vertical: true)

                            Button("Choose Source Language", action: onBack)
                                .disabled(viewModel.isRunning)
                        }

                        Spacer()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.orange.opacity(0.12))
                    )
                }

                if !viewModel.files.isEmpty {
                    HStack {
                        metric(label: "Complete", value: "\(viewModel.completedCount)")
                        Divider()
                        metric(label: "Processing", value: "\(viewModel.processingCount)")
                        Divider()
                        metric(label: "Pending", value: "\(viewModel.pendingCount)")
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                }

                ForEach(viewModel.files) { file in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(file.sourceURL.lastPathComponent)
                            Spacer()
                            Text(stageLabel(for: file.stage))
                                .foregroundStyle(.secondary)
                        }

                        if let detail = stageDetail(for: file.stage) {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                }

                Spacer()

                HStack {
                    Button("Back", action: onBack)
                        .disabled(viewModel.isRunning)
                    Spacer()
                    if viewModel.didFinish {
                        Button("Show Review Shell", action: onCompletePlaceholder)
                    }
                }
            }
        }
        .task {
            viewModel.startIfNeeded()
        }
    }

    private func metric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stageLabel(for stage: ProcessingStage) -> String {
        switch stage {
        case .pending:
            "Pending"
        case .analyzing:
            "Analyzing"
        case .analyzingFormat:
            "Analyzing format"
        case .normalizingFormat:
            "Normalizing format"
        case .cleaning(let progress):
            "Cleaning \(Int(progress * 100))%"
        case .optimizingForUpload:
            "Optimizing for upload"
        case .transcribing(let progress):
            "Transcribing \(Int(progress * 100))%"
        case .translating:
            "Translating"
        case .summarizing:
            "Summarizing"
        case .exporting:
            "Exporting"
        case .complete:
            "Complete"
        case .failed:
            "Failed"
        case .skipped:
            "Skipped"
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

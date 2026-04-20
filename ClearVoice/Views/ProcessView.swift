import SwiftUI

struct ProcessView: View {
    @ObservedObject var viewModel: BatchViewModel
    let onBack: () -> Void
    let onCompletePlaceholder: () -> Void

    var body: some View {
        StepCard(
            title: "Process",
            detail: "This phase runs a sequential stub pipeline so the UI can show real stage changes before concurrency lands."
        ) {
            VStack(alignment: .leading, spacing: 18) {
                Text(viewModel.statusText)
                    .foregroundStyle(.secondary)

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
                    HStack {
                        Text(file.sourceURL.lastPathComponent)
                        Spacer()
                        Text(stageLabel(for: file.stage))
                            .foregroundStyle(.secondary)
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
        case .cleaning(let progress):
            "Cleaning \(Int(progress * 100))%"
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
}

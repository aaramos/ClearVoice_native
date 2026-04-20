import SwiftUI

struct ProcessView: View {
    @ObservedObject var viewModel: BatchViewModel
    let onBack: () -> Void
    let onCompletePlaceholder: () -> Void

    var body: some View {
        StepCard(
            title: "Process",
            detail: "Later phases will replace these placeholders with the real pipeline, concurrency control, and file detail drawer."
        ) {
            VStack(alignment: .leading, spacing: 18) {
                Text(viewModel.overviewText)
                    .foregroundStyle(.secondary)

                ForEach(viewModel.jobs) { job in
                    HStack {
                        Text(job.fileName)
                        Spacer()
                        Text(job.stage)
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
                    Spacer()
                    Button("Show Review Shell", action: onCompletePlaceholder)
                }
            }
        }
    }
}

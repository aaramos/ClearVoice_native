import SwiftUI

struct RootView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)
                .background(.regularMaterial)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ClearVoice")
                .font(.system(size: 28, weight: .semibold))
            HStack(alignment: .center) {
                Text("Phase 1 shell")
                    .font(.headline)
                Spacer()
                stepBadge
            }
            Text(viewModel.state.description)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .importing:
            ImportView(viewModel: viewModel.importViewModel) {
                viewModel.goForward()
            }
        case .configuring:
            ConfigureView(
                viewModel: viewModel.configureViewModel,
                onBack: viewModel.goBack,
                onStart: viewModel.goForward
            )
        case .processing:
            ProcessView(
                viewModel: viewModel.batchViewModel,
                onBack: viewModel.goBack,
                onCompletePlaceholder: viewModel.revealReviewPlaceholder
            )
        case .review:
            ReviewView(onStartNewBatch: viewModel.startNewBatch)
        }
    }

    private var stepBadge: some View {
        Text("Step \(viewModel.state.stepIndex) of 4")
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.accentColor.opacity(0.12))
            )
    }
}

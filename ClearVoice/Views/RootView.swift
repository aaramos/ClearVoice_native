import SwiftUI

struct RootView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 40)
                .padding(.bottom, 36)
        }
        .background(Color.white)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ClearVoice")
                    .font(.system(size: 28, weight: .semibold))

                Text("Batch Audio Utility")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Spacer()

            stepBadge
        }
        .padding(.horizontal, 56)
        .padding(.top, 44)
        .padding(.bottom, 28)
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            Group {
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
                        onShowResults: viewModel.showResults
                    )
                case .review:
                    ReviewView(
                        viewModel: viewModel.batchViewModel,
                        onStartNewBatch: viewModel.startNewBatch
                    )
                }
            }
            .frame(maxWidth: 1040)
            .frame(maxWidth: .infinity)
        }
    }

    private var stepBadge: some View {
        Text("Step \(viewModel.state.stepIndex) of 4")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.blue.opacity(0.8))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.blue.opacity(0.08))
            )
    }
}

import SwiftUI

struct RootView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                content
            }
            .frame(maxWidth: 1040)
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.horizontal, 40)
            .padding(.top, 32)
            .padding(.bottom, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(red: 0.978, green: 0.982, blue: 0.992))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ClearVoice")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.9))

                Text("Batch Audio Utility")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.black.opacity(0.72))
            }

            Spacer()

            stepBadge
        }
    }

    @ViewBuilder
    private var content: some View {
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

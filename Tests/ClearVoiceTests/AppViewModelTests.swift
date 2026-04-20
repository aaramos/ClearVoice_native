import Testing
@testable import ClearVoice

@MainActor
struct AppViewModelTests {
    @Test
    func forwardNavigationMovesThroughShellSteps() {
        let viewModel = AppViewModel()

        #expect(viewModel.state == .importing)

        viewModel.goForward()
        #expect(viewModel.state == .configuring)

        viewModel.goForward()
        #expect(viewModel.state == .processing)
    }

    @Test
    func backNavigationReturnsToPreviousScreen() {
        let viewModel = AppViewModel()

        viewModel.goForward()
        viewModel.goForward()
        viewModel.goBack()

        #expect(viewModel.state == .configuring)
    }

    @Test
    func reviewPlaceholderCanReturnToNewBatch() {
        let viewModel = AppViewModel()

        viewModel.revealReviewPlaceholder()
        #expect(viewModel.state == .review)

        viewModel.startNewBatch()
        #expect(viewModel.state == .importing)
    }
}

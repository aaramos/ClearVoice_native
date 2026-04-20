import Testing
@testable import ClearVoice

@MainActor
struct AppLaunchViewModelTests {
    @Test
    func bootstrapTransitionsDirectlyToReady() {
        let appViewModel = AppViewModel()
        let viewModel = AppLaunchViewModel {
            appViewModel
        }

        #expect(viewModel.phase == .ready)
        #expect(viewModel.appViewModel === appViewModel)
    }
}

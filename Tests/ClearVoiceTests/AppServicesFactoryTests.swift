import Testing
@testable import ClearVoice

struct AppServicesFactoryTests {
    @Test
    @MainActor
    func makeAppViewModelBuildsLocalFirstWorkflow() {
        let viewModel = AppServicesFactory.makeAppViewModel()

        #expect(viewModel.configureViewModel.maxConcurrency == 2)
        #expect(viewModel.configureViewModel.enhancementMethod == .hybrid)
    }

    @Test
    func makeServiceBundleProvidesPlaceholderSummary() {
        let services = AppServicesFactory.makeServiceBundle()

        #expect(!services.summaryPlaceholder.isEmpty)
    }

    @Test
    func launchErrorUsesPlainStartupMessage() {
        let error = LaunchRequirementsError.unexpectedStartupFailure("Test failure")

        #expect(error.title == "Couldn’t Start ClearVoice")
        #expect(error.message.contains("Test failure"))
    }
}

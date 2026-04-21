import Foundation
import Testing
@testable import ClearVoice

struct AppServicesFactoryTests {
    @Test
    @MainActor
    func makeAppViewModelBuildsLocalFirstWorkflow() {
        let viewModel = AppServicesFactory.makeAppViewModel()

        #expect(viewModel.configureViewModel.maxConcurrency == ConfigureViewModel.recommendedConcurrency(for: ProcessInfo.processInfo.activeProcessorCount))
        #expect(viewModel.configureViewModel.enhancementMethod == .hybrid)
    }

    @Test
    func makeServiceBundleProvidesEnhancementServices() {
        let services = AppServicesFactory.makeServiceBundle()

        #expect(!services.comparisonEnhancements.isEmpty)
    }

    @Test
    func launchErrorUsesPlainStartupMessage() {
        let error = LaunchRequirementsError.unexpectedStartupFailure("Test failure")

        #expect(error.title == "Couldn’t Start ClearVoice")
        #expect(error.message.contains("Test failure"))
    }
}

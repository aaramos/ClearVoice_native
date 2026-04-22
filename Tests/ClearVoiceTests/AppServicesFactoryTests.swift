import Foundation
import Testing
@testable import ClearVoice

struct AppServicesFactoryTests {
    @Test
    @MainActor
    func makeAppViewModelBuildsLocalFirstWorkflow() {
        let defaults = UserDefaults(suiteName: "clearvoice.factory.\(UUID().uuidString)")!
        let configureViewModel = ConfigureViewModel(
            preferences: ConfigurePreferencesStore(defaults: defaults)
        )
        configureViewModel.enhancementMethod = .dfn
        configureViewModel.maxConcurrency = 6

        let viewModel = AppServicesFactory.makeAppViewModel(configureViewModel: configureViewModel)

        #expect(viewModel.configureViewModel.maxConcurrency == 6)
        #expect(viewModel.configureViewModel.enhancementMethod == .dfn)
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

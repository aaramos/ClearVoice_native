import Foundation
import Testing
@testable import ClearVoice

@MainActor
struct ConfigureViewModelTests {
    @Test
    func defaultsMatchLocalFirstWorkflow() {
        let defaults = makeDefaults()
        let viewModel = ConfigureViewModel(preferences: ConfigurePreferencesStore(defaults: defaults))

        #expect(viewModel.enhancementMethod == .hybrid)
        #expect(viewModel.maxConcurrency == ConfigureViewModel.defaultConcurrency)
        #expect(viewModel.canStart)
    }

    @Test
    func helperTextDescribesEnhancementOnlyWorkflow() {
        let defaults = makeDefaults()
        let viewModel = ConfigureViewModel(preferences: ConfigurePreferencesStore(defaults: defaults))

        #expect(viewModel.helperText.contains("cleaned audio"))
        #expect(!viewModel.helperText.contains("transcript"))
    }

    @Test
    func advancedSummaryMentionsExpandedConcurrencyRange() {
        let defaults = makeDefaults()
        let viewModel = ConfigureViewModel(preferences: ConfigurePreferencesStore(defaults: defaults))

        #expect(viewModel.advancedSummary.contains("1 to 20"))
        #expect(viewModel.advancedSummary.contains("\(ConfigureViewModel.defaultConcurrency)"))
    }

    @Test
    func persistedSelectionsLoadOnNextLaunch() {
        let defaults = makeDefaults()
        let preferences = ConfigurePreferencesStore(defaults: defaults)
        let firstViewModel = ConfigureViewModel(preferences: preferences)

        firstViewModel.enhancementMethod = .dfn
        firstViewModel.maxConcurrency = 9

        let secondViewModel = ConfigureViewModel(preferences: preferences)
        #expect(secondViewModel.enhancementMethod == .dfn)
        #expect(secondViewModel.maxConcurrency == 9)
    }

    @Test
    func invalidSavedConcurrencyIsClampedIntoRange() {
        let defaults = makeDefaults()
        defaults.set(99, forKey: "clearvoice.configure.maxConcurrency")

        let viewModel = ConfigureViewModel(preferences: ConfigurePreferencesStore(defaults: defaults))
        #expect(viewModel.maxConcurrency == ConfigureViewModel.maximumConcurrency)
    }
}

private func makeDefaults() -> UserDefaults {
    UserDefaults(suiteName: "clearvoice.configure.\(UUID().uuidString)")!
}

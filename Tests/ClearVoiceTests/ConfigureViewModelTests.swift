import Testing
@testable import ClearVoice

@MainActor
struct ConfigureViewModelTests {
    @Test
    func outputLanguageOptionsExcludeAutoDetect() {
        let viewModel = ConfigureViewModel()

        #expect(viewModel.outputLanguageOptions.contains(.english))
        #expect(!viewModel.outputLanguageOptions.contains(.autoDetect))
    }

    @Test
    func selectingIntensityBandUpdatesIntensityValue() {
        let viewModel = ConfigureViewModel()

        viewModel.intensityBand = .maximum

        #expect(viewModel.intensity.band == .maximum)
        #expect(viewModel.intensity == .maximum)
    }

    @Test
    func helperTextReflectsSelectedLanguagesAndConcurrency() {
        let viewModel = ConfigureViewModel()
        viewModel.selectInputLanguage(id: Language.hindi.id)
        viewModel.selectOutputLanguage(id: Language.english.id)
        viewModel.maxConcurrency = 5

        #expect(viewModel.helperText.contains("Hindi"))
        #expect(viewModel.helperText.contains("English"))
        #expect(viewModel.helperText.contains("5"))
    }
}

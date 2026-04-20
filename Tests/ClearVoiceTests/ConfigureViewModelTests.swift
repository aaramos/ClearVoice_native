import Testing
@testable import ClearVoice

@MainActor
struct ConfigureViewModelTests {
    @Test
    func defaultsMatchLocalFirstWorkflow() {
        let viewModel = ConfigureViewModel()

        #expect(viewModel.inputLanguage == .autoDetect)
        #expect(viewModel.outputLanguage == .english)
        #expect(viewModel.maxConcurrency == 2)
        #expect(viewModel.canStart)
    }

    @Test
    func selectingInputLanguageUpdatesSelection() {
        let viewModel = ConfigureViewModel()

        viewModel.selectInputLanguage(id: Language.marathi.id)

        #expect(viewModel.inputLanguage == .marathi)
        #expect(viewModel.selectedInputLanguage == .specific("mr"))
    }

    @Test
    func helperTextExplainsManualRetryForAutoDetect() {
        let viewModel = ConfigureViewModel()

        #expect(viewModel.helperText.contains("detect the spoken language"))
        #expect(viewModel.helperText.contains("choosing the source language manually"))
    }
}

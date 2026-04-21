import Testing
@testable import ClearVoice

@MainActor
struct ConfigureViewModelTests {
    @Test
    func defaultsMatchLocalFirstWorkflow() {
        let viewModel = ConfigureViewModel()

        #expect(viewModel.enhancementMethod == .hybrid)
        #expect(viewModel.maxConcurrency == ConfigureViewModel.defaultConcurrency)
        #expect(viewModel.canStart)
    }

    @Test
    func helperTextDescribesEnhancementOnlyWorkflow() {
        let viewModel = ConfigureViewModel()

        #expect(viewModel.helperText.contains("cleaned audio"))
        #expect(!viewModel.helperText.contains("transcript"))
    }

    @Test
    func advancedSummaryMentionsExpandedConcurrencyRange() {
        let viewModel = ConfigureViewModel()

        #expect(viewModel.advancedSummary.contains("1 to 20"))
        #expect(viewModel.advancedSummary.contains("5"))
    }
}

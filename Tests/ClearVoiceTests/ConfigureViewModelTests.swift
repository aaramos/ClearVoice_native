import Testing
@testable import ClearVoice

@MainActor
struct ConfigureViewModelTests {
    @Test
    func defaultsMatchLocalFirstWorkflow() {
        let viewModel = ConfigureViewModel()

        #expect(viewModel.enhancementMethod == .hybrid)
        #expect(viewModel.maxConcurrency == 2)
        #expect(viewModel.canStart)
    }

    @Test
    func marathiIsAlwaysSelectedForThisPass() {
        let viewModel = ConfigureViewModel()

        #expect(viewModel.selectedInputLanguage == .specific("mr"))
    }

    @Test
    func helperTextDescribesEnhancementOnlyWorkflow() {
        let viewModel = ConfigureViewModel()

        #expect(viewModel.helperText.contains("cleaned audio"))
        #expect(!viewModel.helperText.contains("transcript"))
    }
}

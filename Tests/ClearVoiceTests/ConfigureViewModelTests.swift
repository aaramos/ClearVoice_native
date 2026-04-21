import Testing
@testable import ClearVoice

@MainActor
struct ConfigureViewModelTests {
    @Test
    func defaultsMatchLocalFirstWorkflow() {
        let viewModel = ConfigureViewModel()

        #expect(viewModel.enhancementMethod == .hybrid)
        #expect(viewModel.transcriptionEnabled)
        #expect(viewModel.maxConcurrency == 2)
        #expect(viewModel.canStart)
    }

    @Test
    func marathiIsAlwaysSelectedForThisPass() {
        let viewModel = ConfigureViewModel()

        #expect(viewModel.selectedInputLanguage == .specific("mr"))
    }

    @Test
    func helperTextReflectsTranscriptionToggle() {
        let viewModel = ConfigureViewModel()

        #expect(viewModel.helperText.contains("Marathi"))

        viewModel.transcriptionEnabled = false
        #expect(viewModel.helperText.contains("only export the processed audio"))
    }
}

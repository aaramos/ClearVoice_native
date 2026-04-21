import Testing
@testable import ClearVoice

@MainActor
struct ConfigureViewModelTests {
    @Test
    func defaultsMatchLocalFirstWorkflow() {
        let viewModel = ConfigureViewModel(processorCount: 12)

        #expect(viewModel.enhancementMethod == .hybrid)
        #expect(viewModel.maxConcurrency == 5)
        #expect(viewModel.canStart)
    }

    @Test
    func helperTextDescribesEnhancementOnlyWorkflow() {
        let viewModel = ConfigureViewModel()

        #expect(viewModel.helperText.contains("cleaned audio"))
        #expect(!viewModel.helperText.contains("transcript"))
    }

    @Test
    func slowerMachinesStartWithLowerRecommendation() {
        let viewModel = ConfigureViewModel(processorCount: 4)

        #expect(viewModel.maxConcurrency == 2)
    }
}

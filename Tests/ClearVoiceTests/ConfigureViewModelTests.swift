import Foundation
import Testing
@testable import ClearVoice

@MainActor
struct ConfigureViewModelTests {
    @Test
    func unsupportedLanguageWithoutKeyDisablesStartAndLocksCloudTranscription() async {
        let store = makeStore()
        let viewModel = ConfigureViewModel(
            apiKeyPresent: false,
            processingModeStore: store,
            localSpeechSupportProvider: { [Locale(identifier: "hi")] }
        )

        viewModel.selectInputLanguage(id: Language.gujarati.id)
        await viewModel.updateRoutingForLanguage(viewModel.inputLanguage)

        #expect(viewModel.transcriptionMode == .cloud)
        #expect(viewModel.canToggleTranscription == false)
        #expect(viewModel.canStart == false)
    }

    @Test
    func unsupportedLanguageWithKeyKeepsStartEnabledAndLocksCloudTranscription() async {
        let store = makeStore()
        let viewModel = ConfigureViewModel(
            apiKeyPresent: true,
            processingModeStore: store,
            localSpeechSupportProvider: { [Locale(identifier: "hi")] }
        )

        viewModel.selectInputLanguage(id: Language.gujarati.id)
        await viewModel.updateRoutingForLanguage(viewModel.inputLanguage)

        #expect(viewModel.transcriptionMode == .cloud)
        #expect(viewModel.canToggleTranscription == false)
        #expect(viewModel.canStart)
    }

    @Test
    func supportedLanguageLeavesTranscriptionToggleAvailable() async {
        let store = makeStore()
        let viewModel = ConfigureViewModel(
            apiKeyPresent: true,
            processingModeStore: store,
            localSpeechSupportProvider: { [Locale(identifier: "hi"), Locale(identifier: "gu")] }
        )

        viewModel.selectInputLanguage(id: Language.hindi.id)
        await viewModel.updateRoutingForLanguage(viewModel.inputLanguage)

        #expect(viewModel.canToggleTranscription)
        #expect(viewModel.canStart)
    }

    @Test
    func toggleStatePersistsAcrossViewModelReinitialization() async {
        let store = makeStore()
        let first = ConfigureViewModel(
            apiKeyPresent: true,
            processingModeStore: store,
            localSpeechSupportProvider: { [Locale(identifier: "hi")] }
        )

        first.transcriptionMode = .cloud
        first.translationMode = .cloud

        let second = ConfigureViewModel(
            apiKeyPresent: true,
            processingModeStore: store,
            localSpeechSupportProvider: { [Locale(identifier: "hi")] }
        )
        await second.updateRoutingForLanguage(second.inputLanguage)

        #expect(second.transcriptionMode == .cloud)
        #expect(second.translationMode == .cloud)
    }

    private func makeStore() -> ProcessingModeStore {
        let suiteName = "ClearVoice.ConfigureViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return ProcessingModeStore(userDefaults: defaults)
    }
}

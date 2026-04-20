import Testing
@testable import ClearVoice

@MainActor
struct AppLaunchViewModelTests {
    @Test
    func bootstrapPromptsForAPIKeyWhenNothingIsConfigured() {
        let store = MockAPIKeyStore()

        let viewModel = AppLaunchViewModel(
            environment: [:],
            apiKeyStore: store,
            makeAppViewModel: { _, _ in AppViewModel() }
        )

        #expect(viewModel.phase == .needsAPIKey)
        #expect(viewModel.appViewModel == nil)
    }

    @Test
    func bootstrapUsesSavedKeyWhenAvailable() {
        let store = MockAPIKeyStore(storedKey: "saved-key")

        let viewModel = AppLaunchViewModel(
            environment: [:],
            apiKeyStore: store,
            makeAppViewModel: { _, _ in AppViewModel() }
        )

        #expect(viewModel.phase == .ready)
        #expect(viewModel.appViewModel != nil)
    }

    @Test
    func environmentVariableOverridesKeychainPrompt() {
        let store = MockAPIKeyStore()

        let viewModel = AppLaunchViewModel(
            environment: ["GEMINI_API_KEY": "env-key"],
            apiKeyStore: store,
            makeAppViewModel: { _, _ in AppViewModel() }
        )

        #expect(viewModel.phase == .ready)
        #expect(viewModel.appViewModel != nil)
        #expect(store.readCount == 0)
    }

    @Test
    func saveAPIKeyPersistsTrimmedValueAndTransitionsToReady() {
        let store = MockAPIKeyStore()

        let viewModel = AppLaunchViewModel(
            environment: [:],
            apiKeyStore: store,
            makeAppViewModel: { _, _ in AppViewModel() }
        )
        viewModel.apiKeyInput = "  new-key  "

        viewModel.saveAPIKey()

        #expect(store.savedKeys == ["new-key"])
        #expect(viewModel.phase == .ready)
        #expect(viewModel.appViewModel != nil)
        #expect(viewModel.submissionErrorMessage == nil)
    }

    @Test
    func skipToLocalModeClearsSavedKeyAndTransitionsToReady() {
        let store = MockAPIKeyStore(storedKey: "saved-key")

        let viewModel = AppLaunchViewModel(
            environment: [:],
            apiKeyStore: store,
            makeAppViewModel: { _, _ in AppViewModel() }
        )

        viewModel.skipToLocalMode()

        #expect(store.clearCount == 1)
        #expect(store.storedKey == nil)
        #expect(viewModel.phase == .ready)
        #expect(viewModel.appViewModel != nil)
    }
}

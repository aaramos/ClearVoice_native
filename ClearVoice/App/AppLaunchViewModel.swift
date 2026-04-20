import Foundation

@MainActor
final class AppLaunchViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case needsAPIKey
        case ready
        case failed
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var appViewModel: AppViewModel?
    @Published private(set) var launchError: LaunchRequirementsError?
    @Published private(set) var submissionErrorMessage: String?
    @Published var apiKeyInput = ""

    private let environment: [String: String]
    private let apiKeyStore: any APIKeyStore
    private let makeAppViewModel: @MainActor (String?, @escaping @MainActor () -> Void) -> AppViewModel

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        apiKeyStore: any APIKeyStore = KeychainGeminiAPIKeyStore(),
        makeAppViewModel: @escaping @MainActor (String?, @escaping @MainActor () -> Void) -> AppViewModel = {
            AppServicesFactory.makeAppViewModel(geminiAPIKey: $0, onRequestAPIKeySetup: $1)
        }
    ) {
        self.environment = environment
        self.apiKeyStore = apiKeyStore
        self.makeAppViewModel = makeAppViewModel
        bootstrap()
    }

    var canSubmitAPIKey: Bool {
        apiKeyInput.trimmedNonEmpty != nil
    }

    func saveAPIKey() {
        guard let apiKey = apiKeyInput.trimmedNonEmpty else {
            submissionErrorMessage = APIKeyStoreError.invalidInput.localizedDescription
            return
        }

        do {
            try apiKeyStore.saveGeminiAPIKey(apiKey)
            submissionErrorMessage = nil
            apiKeyInput = ""
            launch(with: apiKey)
        } catch let error as APIKeyStoreError {
            submissionErrorMessage = error.localizedDescription
        } catch {
            submissionErrorMessage = "ClearVoice couldn’t save your Gemini API key: \(error.localizedDescription)"
        }
    }

    func skipToLocalMode() {
        do {
            try apiKeyStore.clearGeminiAPIKey()
            submissionErrorMessage = nil
            apiKeyInput = ""
            launch(with: nil)
        } catch let error as APIKeyStoreError {
            submissionErrorMessage = error.localizedDescription
        } catch {
            submissionErrorMessage = "ClearVoice couldn’t clear the saved Gemini API key: \(error.localizedDescription)"
        }
    }

    func retryBootstrap() {
        bootstrap()
    }

    private func bootstrap() {
        appViewModel = nil
        launchError = nil
        submissionErrorMessage = nil
        phase = .loading

        do {
            if let apiKey = try AppServicesFactory.resolvedGeminiAPIKey(
                environment: environment,
                apiKeyStore: apiKeyStore
            ) {
                launch(with: apiKey)
            } else {
                phase = .needsAPIKey
            }
        } catch let error as APIKeyStoreError {
            launchError = LaunchRequirementsError.keychainAccessFailed(error.localizedDescription)
            phase = .failed
        } catch {
            launchError = LaunchRequirementsError.unexpectedStartupFailure(error.localizedDescription)
            phase = .failed
        }
    }

    private func launch(with apiKey: String?) {
        appViewModel = makeAppViewModel(apiKey) { [weak self] in
            self?.presentAPIKeyEntry()
        }
        launchError = nil
        phase = .ready
    }

    private func presentAPIKeyEntry() {
        submissionErrorMessage = nil
        apiKeyInput = ""
        phase = .needsAPIKey
    }
}

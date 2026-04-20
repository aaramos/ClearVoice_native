import Foundation

enum AppServicesFactory {
    @MainActor
    static func makeLiveAppViewModel(
        geminiAPIKey: String
    ) -> AppViewModel {
        let serviceBundle = makeLiveServiceBundle(geminiAPIKey: geminiAPIKey)
        return AppViewModel(batchViewModel: BatchViewModel(services: serviceBundle))
    }

    static func makeLiveServiceBundle(
        geminiAPIKey: String
    ) -> ServiceBundle {
        return .live(
            geminiAPIKey: geminiAPIKey
        )
    }

    static func resolvedGeminiAPIKey(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        apiKeyStore: any APIKeyStore = KeychainGeminiAPIKeyStore()
    ) throws -> String? {
        if let environmentKey = environment["GEMINI_API_KEY"]?.trimmedNonEmpty {
            return environmentKey
        }

        return try apiKeyStore.readGeminiAPIKey()
    }
}

struct LaunchRequirementsError: Error, Equatable {
    let title: String
    let message: String

    static func keychainAccessFailed(_ detail: String) -> LaunchRequirementsError {
        return LaunchRequirementsError(
            title: "Couldn’t Access Your Saved API Key",
            message: "\(detail) ClearVoice stores your Gemini API key in the macOS Keychain for this Mac user account."
        )
    }

    static func unexpectedStartupFailure(_ detail: String) -> LaunchRequirementsError {
        LaunchRequirementsError(
            title: "Couldn’t Start ClearVoice",
            message: "ClearVoice hit an unexpected startup error: \(detail)"
        )
    }
}

extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

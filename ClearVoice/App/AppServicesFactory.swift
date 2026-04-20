import Foundation

enum AppServicesFactory {
    @MainActor
    static func makeLiveAppViewModel(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> AppViewModel {
        let serviceBundle = try makeLiveServiceBundle(environment: environment)
        return AppViewModel(batchViewModel: BatchViewModel(services: serviceBundle))
    }

    static func makeLiveServiceBundle(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> ServiceBundle {
        let geminiAPIKey = environment["GEMINI_API_KEY"]?.trimmedNonEmpty

        var missingVariables: [String] = []

        if geminiAPIKey == nil {
            missingVariables.append("GEMINI_API_KEY")
        }

        guard let geminiAPIKey, missingVariables.isEmpty else {
            throw LaunchRequirementsError.missingEnvironmentVariables(missingVariables)
        }

        return .live(
            geminiAPIKey: geminiAPIKey
        )
    }
}

struct LaunchRequirementsError: Error, Equatable {
    let title: String
    let message: String

    static func missingEnvironmentVariables(_ names: [String]) -> LaunchRequirementsError {
        let joinedNames = names.joined(separator: " and ")
        return LaunchRequirementsError(
            title: "Missing API Keys",
            message: "ClearVoice couldn’t start because \(joinedNames) \(names.count == 1 ? "is" : "are") missing. Set \(joinedNames) in the shell you use to launch ClearVoice, then relaunch the app."
        )
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

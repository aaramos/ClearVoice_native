import Foundation

final class ProcessingModeStore: @unchecked Sendable {
    static let shared = ProcessingModeStore()

    private enum Keys {
        static let transcriptionMode = "cv.transcriptionMode"
        static let translationMode = "cv.translationMode"
        static let summarizationEnabled = "cv.summarizationEnabled"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> ProcessingModeConfiguration {
        var configuration = ProcessingModeConfiguration()

        if let transcriptionMode = mode(forKey: Keys.transcriptionMode) {
            configuration.transcription = transcriptionMode
        }

        if let translationMode = mode(forKey: Keys.translationMode) {
            configuration.translation = translationMode
        }

        if userDefaults.object(forKey: Keys.summarizationEnabled) != nil {
            configuration.summarizationEnabled = userDefaults.bool(forKey: Keys.summarizationEnabled)
        }

        return configuration
    }

    func save(_ config: ProcessingModeConfiguration) {
        userDefaults.set(config.transcription.rawValue, forKey: Keys.transcriptionMode)
        userDefaults.set(config.translation.rawValue, forKey: Keys.translationMode)
        userDefaults.set(config.summarizationEnabled, forKey: Keys.summarizationEnabled)
    }

    private func mode(forKey key: String) -> ProcessingMode? {
        guard let rawValue = userDefaults.string(forKey: key) else {
            return nil
        }

        return ProcessingMode(rawValue: rawValue)
    }
}

import Foundation

final class ProcessingModeStore: @unchecked Sendable {
    static let shared = ProcessingModeStore()

    private enum Keys {
        static let transcriptionMode = "cv.transcriptionMode"
        static let translationMode = "cv.translationMode"
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

        configuration.summarization = .cloud
        return configuration
    }

    func save(_ config: ProcessingModeConfiguration) {
        userDefaults.set(config.transcription.rawValue, forKey: Keys.transcriptionMode)
        userDefaults.set(config.translation.rawValue, forKey: Keys.translationMode)
    }

    private func mode(forKey key: String) -> ProcessingMode? {
        guard let rawValue = userDefaults.string(forKey: key) else {
            return nil
        }

        return ProcessingMode(rawValue: rawValue)
    }
}

import Foundation

@MainActor
final class ConfigureViewModel: ObservableObject {
    static let minimumConcurrency = 1
    static let maximumConcurrency = 20
    static let defaultConcurrency = 5

    @Published var enhancementMethod: EnhancementMethod {
        didSet {
            preferences.saveEnhancementMethod(enhancementMethod)
        }
    }

    @Published var maxConcurrency: Int {
        didSet {
            let clamped = Self.clampedConcurrency(maxConcurrency)
            guard maxConcurrency == clamped else {
                maxConcurrency = clamped
                return
            }

            preferences.saveMaxConcurrency(maxConcurrency)
        }
    }

    private let preferences: ConfigurePreferencesStore

    init(preferences: ConfigurePreferencesStore = ConfigurePreferencesStore()) {
        self.preferences = preferences
        self.enhancementMethod = preferences.savedEnhancementMethod(fallback: .hybrid)
        self.maxConcurrency = preferences.savedMaxConcurrency(
            fallback: Self.defaultConcurrency,
            validRange: Self.minimumConcurrency...Self.maximumConcurrency
        )
    }

    static func recommendedConcurrency(for processorCount: Int) -> Int {
        defaultConcurrency
    }

    var canStart: Bool {
        true
    }

    var helperText: String {
        "ClearVoice will process each file with the selected enhancement method and export one cleaned audio file per source folder."
    }

    var advancedSummary: String {
        "All processing runs on this Mac. ClearVoice is currently set to \(maxConcurrency) files at a time, and you can tune the batch anywhere from \(Self.minimumConcurrency) to \(Self.maximumConcurrency) files."
    }

    func reset() {
        enhancementMethod = preferences.savedEnhancementMethod(fallback: .hybrid)
        maxConcurrency = preferences.savedMaxConcurrency(
            fallback: Self.defaultConcurrency,
            validRange: Self.minimumConcurrency...Self.maximumConcurrency
        )
    }

    private static func clampedConcurrency(_ value: Int) -> Int {
        min(max(value, minimumConcurrency), maximumConcurrency)
    }
}

struct ConfigurePreferencesStore {
    private let defaults: UserDefaults
    private let enhancementMethodKey = "clearvoice.configure.enhancementMethod"
    private let maxConcurrencyKey = "clearvoice.configure.maxConcurrency"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func savedEnhancementMethod(fallback: EnhancementMethod) -> EnhancementMethod {
        guard
            let rawValue = defaults.string(forKey: enhancementMethodKey),
            let method = EnhancementMethod(rawValue: rawValue)
        else {
            return fallback
        }

        return method
    }

    func savedMaxConcurrency(
        fallback: Int,
        validRange: ClosedRange<Int>
    ) -> Int {
        guard defaults.object(forKey: maxConcurrencyKey) != nil else {
            return fallback
        }

        return min(max(defaults.integer(forKey: maxConcurrencyKey), validRange.lowerBound), validRange.upperBound)
    }

    func saveEnhancementMethod(_ method: EnhancementMethod) {
        defaults.set(method.rawValue, forKey: enhancementMethodKey)
    }

    func saveMaxConcurrency(_ value: Int) {
        defaults.set(value, forKey: maxConcurrencyKey)
    }
}

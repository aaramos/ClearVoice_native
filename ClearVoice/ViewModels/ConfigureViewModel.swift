import Foundation

@MainActor
final class ConfigureViewModel: ObservableObject {
    @Published var intensity = Intensity.balanced
    @Published var inputLanguage = Language.autoDetect
    @Published var outputLanguage = Language.english
    @Published var maxConcurrency = 3
    @Published var preserveChannels = false

    var intensityBand: Intensity.Band {
        get { intensity.band }
        set { intensity = Intensity(band: newValue) }
    }

    var inputLanguageOptions: [Language] {
        Language.prioritized
    }

    var outputLanguageOptions: [Language] {
        Language.prioritized.filter { $0 != .autoDetect }
    }

    var helperText: String {
        let sourceLanguage = inputLanguage == .autoDetect ? "auto-detect the source language" : "transcribe in \(inputLanguage.displayName)"
        return "ClearVoice will \(sourceLanguage), translate into \(outputLanguage.displayName), and process up to \(maxConcurrency) files in parallel."
    }

    var intensityDescription: String {
        switch intensity.band {
        case .minimal:
            return "Light cleanup for already-usable recordings."
        case .balanced:
            return "Recommended for most voice notes and interviews."
        case .strong:
            return "More aggressive noise reduction for rougher captures."
        case .maximum:
            return "Highest cleanup intensity for difficult recordings."
        }
    }

    var advancedSummary: String {
        let channelSummary = preserveChannels ? "Preserve original channels when possible." : "Downmix when the pipeline benefits from it."
        return "\(channelSummary) Parallelism is capped at \(maxConcurrency) file\(maxConcurrency == 1 ? "" : "s")."
    }

    var selectedInputLanguage: LanguageSelection {
        inputLanguage.id == Language.autoDetect.id ? .auto : .specific(inputLanguage.id)
    }

    func selectInputLanguage(id: String) {
        if let match = inputLanguageOptions.first(where: { $0.id == id }) {
            inputLanguage = match
        }
    }

    func selectOutputLanguage(id: String) {
        if let match = outputLanguageOptions.first(where: { $0.id == id }) {
            outputLanguage = match
        }
    }
}

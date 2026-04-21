import Foundation

@MainActor
final class ConfigureViewModel: ObservableObject {
    @Published var intensity = Intensity.balanced
    @Published var inputLanguage = Language.autoDetect
    @Published var maxConcurrency = 2

    var canStart: Bool {
        true
    }

    var intensityBand: Intensity.Band {
        get { intensity.band }
        set { intensity = Intensity(band: newValue) }
    }

    var inputLanguageOptions: [Language] {
        Language.prioritized
    }

    var outputLanguage: Language {
        .english
    }

    var helperText: String {
        if inputLanguage == .autoDetect {
            return "ClearVoice will clean the audio locally, use the Hybrid output for Marathi transcription, and write a timestamped Marathi transcript. If it can’t detect the spoken language, retry by choosing the source language manually. Translation remains off while we validate transcription quality."
        }

        return "ClearVoice will clean the audio locally and write a timestamped transcript in \(inputLanguage.displayName). Translation remains off while we validate transcription quality."
    }

    var intensityDescription: String {
        switch intensity.band {
        case .minimal:
            return "Light cleanup for already-usable speech."
        case .balanced:
            return "Recommended for most voice recordings."
        case .strong:
            return "More aggressive cleanup for noisy speech."
        case .maximum:
            return "Highest cleanup for difficult recordings, with the most processing."
        }
    }

    var advancedSummary: String {
        "All processing runs on this Mac. Parallelism can be set between 1 and 5 files. Start with 2 unless the machine is clearly keeping up."
    }

    var selectedInputLanguage: LanguageSelection {
        inputLanguage.id == Language.autoDetect.id ? .auto : .specific(inputLanguage.id)
    }

    func selectInputLanguage(id: String) {
        if let match = inputLanguageOptions.first(where: { $0.id == id }) {
            inputLanguage = match
        }
    }
}

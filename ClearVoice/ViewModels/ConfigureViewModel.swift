import Foundation

@MainActor
final class ConfigureViewModel: ObservableObject {
    @Published var enhancementMethod: EnhancementMethod = .hybrid
    @Published var transcriptionEnabled = true
    @Published var maxConcurrency = 2

    var canStart: Bool {
        true
    }

    var outputLanguage: Language {
        .english
    }

    var helperText: String {
        if transcriptionEnabled {
            return "ClearVoice will process each file with the selected enhancement method, transcribe the result in Marathi, and write one transcript file per source folder."
        }

        return "ClearVoice will only export the processed audio file for each source. Leave transcription off if you only want audio cleanup."
    }

    var advancedSummary: String {
        "All processing runs on this Mac. Parallelism can be set between 1 and 5 files. Start with 2 unless the machine is clearly keeping up."
    }

    var selectedInputLanguage: LanguageSelection {
        .specific(Language.marathi.id)
    }

    func reset() {
        enhancementMethod = .hybrid
        transcriptionEnabled = true
        maxConcurrency = 2
    }
}

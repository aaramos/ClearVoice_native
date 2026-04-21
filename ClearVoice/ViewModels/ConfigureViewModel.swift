import Foundation

@MainActor
final class ConfigureViewModel: ObservableObject {
    @Published var enhancementMethod: EnhancementMethod = .hybrid
    @Published var maxConcurrency = 2

    var canStart: Bool {
        true
    }

    var outputLanguage: Language {
        .english
    }

    var helperText: String {
        "ClearVoice will process each file with the selected enhancement method and export one cleaned audio file per source folder."
    }

    var advancedSummary: String {
        "All processing runs on this Mac. Parallelism can be set between 1 and 5 files. Start with 2 unless the machine is clearly keeping up."
    }

    var selectedInputLanguage: LanguageSelection {
        .specific(Language.marathi.id)
    }

    func reset() {
        enhancementMethod = .hybrid
        maxConcurrency = 2
    }
}

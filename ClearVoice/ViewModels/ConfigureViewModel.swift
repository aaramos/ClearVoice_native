import Foundation

@MainActor
final class ConfigureViewModel: ObservableObject {
    @Published var intensity = Intensity.balanced
    @Published var inputLanguage = Language.autoDetect
    @Published var outputLanguage = Language.english
    @Published var helperText = "Advanced controls and final validation land in later phases."
    @Published var maxConcurrency = 3
    @Published var preserveChannels = false

    var selectedInputLanguage: LanguageSelection {
        inputLanguage.id == Language.autoDetect.id ? .auto : .specific(inputLanguage.id)
    }
}

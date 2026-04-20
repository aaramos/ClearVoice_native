import Foundation

@MainActor
final class ConfigureViewModel: ObservableObject {
    @Published var intensity = Intensity.balanced
    @Published var inputLanguage = Language.autoDetect
    @Published var outputLanguage = Language.english
    @Published var helperText = "Advanced controls and final validation land in later phases."
}

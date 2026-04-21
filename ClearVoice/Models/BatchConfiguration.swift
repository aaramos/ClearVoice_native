import Foundation

struct BatchConfiguration: Equatable, Sendable {
    let sourceFolder: URL
    let outputFolder: URL
    let enhancementMethod: EnhancementMethod
    let transcriptionEnabled: Bool
    let inputLanguage: LanguageSelection
    let outputLanguage: String
    let maxConcurrency: Int
    let recursiveScan: Bool
    let preserveChannels: Bool
    var processingMode: ProcessingModeConfiguration = ProcessingModeConfiguration()
}

enum LanguageSelection: Equatable, Sendable {
    case auto
    case specific(String)
}

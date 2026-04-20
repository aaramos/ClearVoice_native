import Foundation

struct BatchConfiguration: Equatable, Sendable {
    let sourceFolder: URL
    let outputFolder: URL
    let intensity: Intensity
    let inputLanguage: LanguageSelection
    let outputLanguage: String
    let maxConcurrency: Int
    let recursiveScan: Bool
    let preserveChannels: Bool
}

enum LanguageSelection: Equatable, Sendable {
    case auto
    case specific(String)
}

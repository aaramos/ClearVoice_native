import Foundation

enum ProcessingMode: String, Codable, Equatable, Sendable {
    case local
    case cloud
}

struct ProcessingModeConfiguration: Codable, Equatable, Sendable {
    var transcription: ProcessingMode = .local
    var translation: ProcessingMode = .local
    var summarizationEnabled = true
}

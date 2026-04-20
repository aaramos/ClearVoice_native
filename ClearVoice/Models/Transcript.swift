import Foundation

struct Transcript: Equatable, Sendable {
    let text: String
    let detectedLanguage: String
    let confidence: Double
}

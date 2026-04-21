import Foundation

struct Transcript: Equatable, Sendable {
    let text: String
    let detectedLanguage: String
    let confidence: Double
    var segments: [TranscriptSegment] = []
}

struct TranscriptSegment: Equatable, Sendable {
    let text: String
    let startMilliseconds: Int
    let endMilliseconds: Int
    var translationEN: String? = nil
    var tokens: [TranscriptToken] = []
}

struct TranscriptToken: Equatable, Sendable {
    let text: String
    let probability: Double
    let startMilliseconds: Int?
    let endMilliseconds: Int?
}

extension Transcript {
    var exportText: String {
        guard !segments.isEmpty else {
            return text
        }

        return segments
            .map { segment in
                "[\(Self.timestampString(for: segment.startMilliseconds)) --> \(Self.timestampString(for: segment.endMilliseconds))]   \(segment.text)"
            }
            .joined(separator: "\n")
    }

    private static func timestampString(for milliseconds: Int) -> String {
        let totalMilliseconds = max(0, milliseconds)
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds % 3_600_000) / 60_000
        let seconds = (totalMilliseconds % 60_000) / 1_000
        let ms = totalMilliseconds % 1_000

        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, seconds, ms)
    }
}

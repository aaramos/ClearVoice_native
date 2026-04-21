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
                Self.formattedLine(
                    text: segment.text,
                    startMilliseconds: segment.startMilliseconds,
                    endMilliseconds: segment.endMilliseconds
                )
            }
            .joined(separator: "\n")
    }

    var translatedExportText: String? {
        guard !segments.isEmpty else {
            return nil
        }

        let translatedSegments = segments.compactMap { segment -> String? in
            guard let translationEN = segment.translationEN?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !translationEN.isEmpty else {
                return nil
            }

            return Self.formattedLine(
                text: translationEN,
                startMilliseconds: segment.startMilliseconds,
                endMilliseconds: segment.endMilliseconds
            )
        }

        guard translatedSegments.count == segments.count else {
            return nil
        }

        return translatedSegments.joined(separator: "\n")
    }

    private static func formattedLine(
        text: String,
        startMilliseconds: Int,
        endMilliseconds: Int
    ) -> String {
        "[\(timestampString(for: startMilliseconds)) --> \(timestampString(for: endMilliseconds))]   \(text)"
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

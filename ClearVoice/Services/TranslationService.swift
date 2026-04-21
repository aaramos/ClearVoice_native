import Foundation

enum TranslationServiceError: Error, Equatable, Sendable {
    case pairUnavailable
}

protocol TranslationService: Sendable {
    /// Translates the original transcript into the user-selected output language without summarizing or reformatting it.
    func translate(
        text: String,
        from sourceLanguage: String,
        to targetLanguage: String
    ) async throws -> String

    /// Translates transcript segments in order. The default implementation preserves order
    /// and calls the single-text translator for each segment.
    func translateSegments(
        _ segments: [String],
        from sourceLanguage: String,
        to targetLanguage: String
    ) async throws -> [String]
}

extension TranslationService {
    func translateSegments(
        _ segments: [String],
        from sourceLanguage: String,
        to targetLanguage: String
    ) async throws -> [String] {
        var outputs: [String] = []
        outputs.reserveCapacity(segments.count)

        for segment in segments {
            outputs.append(
                try await translate(
                    text: segment,
                    from: sourceLanguage,
                    to: targetLanguage
                )
            )
        }

        return outputs
    }
}

actor StubTranslationService: TranslationService {
    func translate(
        text: String,
        from sourceLanguage: String,
        to targetLanguage: String
    ) async throws -> String {
        "[\(sourceLanguage) -> \(targetLanguage)] \(text)"
    }
}

actor UnavailableTranslationService: TranslationService {
    func translate(
        text: String,
        from sourceLanguage: String,
        to targetLanguage: String
    ) async throws -> String {
        throw ServiceError.cloudUnavailable
    }
}

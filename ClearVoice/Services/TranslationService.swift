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

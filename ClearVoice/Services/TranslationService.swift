import Foundation

protocol TranslationService: Sendable {
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

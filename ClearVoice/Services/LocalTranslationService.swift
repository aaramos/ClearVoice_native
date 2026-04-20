import Foundation
import Translation

actor LocalTranslationService: TranslationService {
    func translate(
        text: String,
        from sourceLanguage: String,
        to targetLanguage: String
    ) async throws -> String {
        guard sourceLanguage != targetLanguage else {
            return text
        }

        let source = Locale.Language(identifier: sourceLanguage)
        let target = Locale.Language(identifier: targetLanguage)
        let availability = LanguageAvailability()

        guard await availability.status(from: source, to: target) == .installed else {
            throw TranslationServiceError.pairUnavailable
        }

        let session = TranslationSession(installedSource: source, target: target)

        do {
            try await session.prepareTranslation()
            let response = try await session.translate(text)
            return response.targetText
        } catch let error where Translation.TranslationError.unsupportedLanguagePairing ~= error
            || Translation.TranslationError.unsupportedSourceLanguage ~= error
            || Translation.TranslationError.unsupportedTargetLanguage ~= error {
            throw TranslationServiceError.pairUnavailable
        }
    }
}

import Foundation

actor GeminiTranslationService: TranslationService {
    private let client: GeminiDeveloperClient
    private let model: String

    init(
        client: GeminiDeveloperClient,
        model: String = "gemini-3.1-flash-lite-preview"
    ) {
        self.client = client
        self.model = model
    }

    func translate(
        text: String,
        from sourceLanguage: String,
        to targetLanguage: String
    ) async throws -> String {
        guard sourceLanguage != targetLanguage else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let sourceLanguageName = Language.displayName(for: sourceLanguage)
        let targetLanguageName = Language.displayName(for: targetLanguage)
        let prompt = """
        Translate this spoken-audio transcript from \(sourceLanguageName) (\(sourceLanguage)) to \(targetLanguageName) (\(targetLanguage)).
        Preserve the meaning, sentence order, tone, and named entities.
        Output only the translated transcript with no heading, notes, or commentary.

        Transcript:
        \(text)
        """

        do {
            return try await client.generateText(model: model, prompt: prompt)
        } catch let error as CloudHTTPClient.RequestError {
            throw ProcessingError.translationFailed(Self.message(for: error))
        } catch let error as URLError {
            throw ProcessingError.translationFailed("Gemini translation request failed: \(error.localizedDescription)")
        } catch {
            throw ProcessingError.translationFailed(error.localizedDescription)
        }
    }

    private static func message(for error: CloudHTTPClient.RequestError) -> String {
        switch error {
        case .invalidResponse:
            return "Gemini returned an unreadable translation response."
        case .unsuccessfulStatus(let code, let bodySnippet):
            let trimmedBody = bodySnippet.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedBody.isEmpty {
                return "Gemini translation failed with status \(code)."
            }
            return "Gemini translation failed with status \(code): \(trimmedBody)"
        }
    }
}

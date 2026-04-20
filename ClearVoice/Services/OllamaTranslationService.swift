import Foundation

actor OllamaTranslationService: TranslationService {
    private let chatClient: OllamaCloudChatClient

    init(chatClient: OllamaCloudChatClient) {
        self.chatClient = chatClient
    }

    func translate(
        text: String,
        from sourceLanguage: String,
        to targetLanguage: String
    ) async throws -> String {
        guard sourceLanguage != targetLanguage else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let targetLanguageName = Language.displayName(for: targetLanguage)
        let sourceLanguageName = Language.displayName(for: sourceLanguage)

        let systemPrompt = """
        You translate spoken-audio transcripts for ClearVoice.
        Preserve meaning, sentence order, speaker intent, and named entities.
        Output only the translated transcript in \(targetLanguageName).
        Do not summarize, add headings, explain choices, or include notes.
        """

        let userPrompt = """
        Source language: \(sourceLanguageName) (\(sourceLanguage))
        Target language: \(targetLanguageName) (\(targetLanguage))

        Transcript:
        \(text)
        """

        do {
            return try await chatClient.chat(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt
            )
        } catch let error as CloudHTTPClient.RequestError {
            throw ProcessingError.translationFailed(Self.message(for: error))
        } catch let error as URLError {
            throw ProcessingError.translationFailed("Ollama translation request failed: \(error.localizedDescription)")
        } catch OllamaCloudChatClient.ClientError.emptyResponse {
            throw ProcessingError.translationFailed("Ollama returned an empty translation.")
        } catch {
            throw ProcessingError.translationFailed(error.localizedDescription)
        }
    }

    private static func message(for error: CloudHTTPClient.RequestError) -> String {
        switch error {
        case .invalidResponse:
            return "Ollama returned an unreadable translation response."
        case .unsuccessfulStatus(let code, let bodySnippet):
            let trimmedBody = bodySnippet.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedBody.isEmpty {
                return "Ollama translation failed with status \(code)."
            }
            return "Ollama translation failed with status \(code): \(trimmedBody)"
        }
    }
}

import Foundation

actor OllamaSummarizationService: SummarizationService {
    private let chatClient: OllamaCloudChatClient

    init(chatClient: OllamaCloudChatClient) {
        self.chatClient = chatClient
    }

    func summarize(
        text: String,
        inLanguage targetLanguage: String
    ) async throws -> String {
        let targetLanguageName = Language.displayName(for: targetLanguage)

        let systemPrompt = """
        You summarize translated spoken-audio transcripts for ClearVoice.
        Write a concise, factual summary in \(targetLanguageName).
        Capture the main points, requests, decisions, and follow-ups when they are present.
        Output only the summary text with no heading or preamble.
        """

        let userPrompt = """
        Output language: \(targetLanguageName) (\(targetLanguage))

        Transcript:
        \(text)
        """

        do {
            return try await chatClient.chat(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt
            )
        } catch let error as CloudHTTPClient.RequestError {
            throw ProcessingError.summarizationFailed(Self.message(for: error))
        } catch let error as URLError {
            throw ProcessingError.summarizationFailed("Ollama summarization request failed: \(error.localizedDescription)")
        } catch OllamaCloudChatClient.ClientError.emptyResponse {
            throw ProcessingError.summarizationFailed("Ollama returned an empty summary.")
        } catch {
            throw ProcessingError.summarizationFailed(error.localizedDescription)
        }
    }

    private static func message(for error: CloudHTTPClient.RequestError) -> String {
        switch error {
        case .invalidResponse:
            return "Ollama returned an unreadable summarization response."
        case .unsuccessfulStatus(let code, let bodySnippet, _):
            let trimmedBody = bodySnippet.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedBody.isEmpty {
                return "Ollama summarization failed with status \(code)."
            }
            return "Ollama summarization failed with status \(code): \(trimmedBody)"
        }
    }
}

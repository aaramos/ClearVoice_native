import Foundation

actor GeminiSummarizationService: SummarizationService {
    private let client: GeminiDeveloperClient
    private let model: String

    init(
        client: GeminiDeveloperClient,
        model: String = "gemini-2.5-flash"
    ) {
        self.client = client
        self.model = model
    }

    func summarize(
        text: String,
        inLanguage targetLanguage: String
    ) async throws -> String {
        let targetLanguageName = Language.displayName(for: targetLanguage)
        let prompt = """
        Summarize this translated spoken-audio transcript in \(targetLanguageName) (\(targetLanguage)).
        Keep the summary concise and factual.
        Capture the main points, requests, decisions, and follow-ups when present.
        Output only the summary text with no heading or commentary.

        Transcript:
        \(text)
        """

        do {
            return try await client.generateText(model: model, prompt: prompt)
        } catch let error as CloudHTTPClient.RequestError {
            throw ProcessingError.summarizationFailed(Self.message(for: error))
        } catch let error as URLError {
            throw ProcessingError.summarizationFailed("Gemini summarization request failed: \(error.localizedDescription)")
        } catch {
            throw ProcessingError.summarizationFailed(error.localizedDescription)
        }
    }

    private static func message(for error: CloudHTTPClient.RequestError) -> String {
        switch error {
        case .invalidResponse:
            return "Gemini returned an unreadable summarization response."
        case .unsuccessfulStatus(let code, let bodySnippet):
            let trimmedBody = bodySnippet.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedBody.isEmpty {
                return "Gemini summarization failed with status \(code)."
            }
            return "Gemini summarization failed with status \(code): \(trimmedBody)"
        }
    }
}

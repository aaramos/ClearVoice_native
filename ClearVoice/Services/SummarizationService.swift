import Foundation

protocol SummarizationService: Sendable {
    /// Produces a concise summary in the selected output language from the already translated transcript.
    func summarize(
        text: String,
        inLanguage targetLanguage: String
    ) async throws -> String
}

actor StubSummarizationService: SummarizationService {
    func summarize(
        text: String,
        inLanguage targetLanguage: String
    ) async throws -> String {
        let prefix = text.prefix(72)
        return "Stub summary (\(targetLanguage)): \(prefix)"
    }
}

actor UnavailableSummarizationService: SummarizationService {
    func summarize(
        text: String,
        inLanguage targetLanguage: String
    ) async throws -> String {
        throw ServiceError.cloudUnavailable
    }
}

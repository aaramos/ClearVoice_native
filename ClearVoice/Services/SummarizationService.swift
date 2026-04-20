import Foundation

protocol SummarizationService: Sendable {
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

import Foundation
import OSLog

actor OllamaCloudChatClient {
    enum ClientError: Error, Sendable {
        case emptyResponse
    }

    private let endpoint = URL(string: "https://ollama.com/api/chat")!
    private let apiKey: String
    private let model: String
    private let httpClient: CloudHTTPClient

    init(
        apiKey: String,
        model: String = "gpt-oss:120b",
        transport: any HTTPTransport = URLSessionHTTPTransport(),
        retryPolicy: RetryPolicy = .default
    ) {
        self.apiKey = apiKey
        self.model = model
        self.httpClient = CloudHTTPClient(
            transport: transport,
            retryPolicy: retryPolicy,
            logger: Logger(subsystem: "com.clearvoice.app", category: "ollama")
        )
    }

    func chat(
        systemPrompt: String,
        userPrompt: String
    ) async throws -> String {
        let payload = OllamaChatRequest(
            model: model,
            stream: false,
            messages: [
                OllamaChatMessage(role: "system", content: systemPrompt),
                OllamaChatMessage(role: "user", content: userPrompt)
            ]
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data = try await httpClient.send(
            request: request,
            body: try JSONEncoder().encode(payload)
        )

        let response = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        let content = response.message.content.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !content.isEmpty else {
            throw ClientError.emptyResponse
        }

        return content
    }
}

private struct OllamaChatRequest: Encodable {
    let model: String
    let stream: Bool
    let messages: [OllamaChatMessage]
}

private struct OllamaChatMessage: Codable {
    let role: String
    let content: String
}

private struct OllamaChatResponse: Decodable {
    let message: OllamaChatMessage
}

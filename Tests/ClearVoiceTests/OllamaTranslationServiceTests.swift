import Foundation
import Testing
@testable import ClearVoice

struct OllamaTranslationServiceTests {
    @Test
    func translateUsesOllamaChatAPIAndReturnsAssistantContent() async throws {
        let transport = MockHTTPTransport(
            responses: [.success(statusCode: 200, body: Data("{\"message\":{\"role\":\"assistant\",\"content\":\"Hello from ClearVoice\"}}".utf8))]
        )
        let service = OllamaTranslationService(
            chatClient: OllamaCloudChatClient(
                apiKey: "ollama-test-key",
                transport: transport,
                retryPolicy: RetryPolicy(maxAttempts: 1, baseDelayMilliseconds: 0, maxJitterMilliseconds: 0)
            )
        )

        let translated = try await service.translate(
            text: "नमस्ते दुनिया",
            from: "hi",
            to: "en"
        )

        let requests = await transport.capturedRequests()
        let requestBody = try #require(requests.first?.body)
        let payload = try JSONDecoder().decode(TestChatRequest.self, from: requestBody)

        #expect(translated == "Hello from ClearVoice")
        #expect(requests.count == 1)
        #expect(requests[0].request.url?.absoluteString == "https://ollama.com/api/chat")
        #expect(requests[0].request.value(forHTTPHeaderField: "Authorization") == "Bearer ollama-test-key")
        #expect(payload.model == "gpt-oss:120b")
        #expect(payload.stream == false)
        #expect(payload.messages.count == 2)
        #expect(payload.messages[0].role == "system")
        #expect(payload.messages[0].content.contains("Output only the translated transcript"))
        #expect(payload.messages[1].content.contains("Source language: Hindi (hi)"))
        #expect(payload.messages[1].content.contains("Target language: English (en)"))
        #expect(payload.messages[1].content.contains("नमस्ते दुनिया"))
    }

    @Test
    func translateShortCircuitsWhenSourceAndTargetLanguagesMatch() async throws {
        let transport = MockHTTPTransport(responses: [])
        let service = OllamaTranslationService(
            chatClient: OllamaCloudChatClient(
                apiKey: "ollama-test-key",
                transport: transport,
                retryPolicy: RetryPolicy(maxAttempts: 1, baseDelayMilliseconds: 0, maxJitterMilliseconds: 0)
            )
        )

        let translated = try await service.translate(
            text: "  Already English.  ",
            from: "en",
            to: "en"
        )

        let requests = await transport.capturedRequests()

        #expect(translated == "Already English.")
        #expect(requests.isEmpty)
    }
}

struct TestChatRequest: Decodable {
    let model: String
    let stream: Bool
    let messages: [TestChatMessage]
}

struct TestChatMessage: Decodable {
    let role: String
    let content: String
}

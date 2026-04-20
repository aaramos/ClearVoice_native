import Foundation
import Testing
@testable import ClearVoice

struct OllamaSummarizationServiceTests {
    @Test
    func summarizeUsesOllamaChatAPIAndReturnsAssistantContent() async throws {
        let transport = MockHTTPTransport(
            responses: [.success(statusCode: 200, body: Data("{\"message\":{\"role\":\"assistant\",\"content\":\"Short English summary.\"}}".utf8))]
        )
        let service = OllamaSummarizationService(
            chatClient: OllamaCloudChatClient(
                apiKey: "ollama-test-key",
                transport: transport,
                retryPolicy: RetryPolicy(maxAttempts: 1, baseDelayMilliseconds: 0, maxJitterMilliseconds: 0)
            )
        )

        let summary = try await service.summarize(
            text: "This is the translated transcript that should be summarized.",
            inLanguage: "en"
        )

        let requests = await transport.capturedRequests()
        let requestBody = try #require(requests.first?.body)
        let payload = try JSONDecoder().decode(TestChatRequest.self, from: requestBody)

        #expect(summary == "Short English summary.")
        #expect(requests.count == 1)
        #expect(payload.messages.count == 2)
        #expect(payload.messages[0].content.contains("Write a concise, factual summary"))
        #expect(payload.messages[1].content.contains("Output language: English (en)"))
        #expect(payload.messages[1].content.contains("This is the translated transcript"))
    }
}

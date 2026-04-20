import Foundation
import Testing
@testable import ClearVoice

struct GeminiSummarizationServiceTests {
    @Test
    func summarizeUsesGeminiGenerateContentAndReturnsModelText() async throws {
        let transport = MockHTTPTransport(
            responses: [
                .success(
                    statusCode: 200,
                    body: Data("""
                    {
                      "candidates": [
                        {
                          "content": {
                            "parts": [
                              { "text": "Short English summary." }
                            ]
                          }
                        }
                      ]
                    }
                    """.utf8)
                )
            ]
        )

        let service = GeminiSummarizationService(
            client: GeminiDeveloperClient(
                apiKey: "gemini-test-key",
                transport: transport,
                retryPolicy: RetryPolicy(maxAttempts: 1, baseDelayMilliseconds: 0, maxJitterMilliseconds: 0)
            )
        )

        let summary = try await service.summarize(
            text: "This is the translated transcript that should be summarized.",
            inLanguage: "en"
        )

        let requests = await transport.capturedRequests()
        let requestBody = String(decoding: requests[0].body ?? Data(), as: UTF8.self)

        #expect(summary == "Short English summary.")
        #expect(requests.count == 1)
        #expect(requests[0].request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent")
        #expect(requestBody.contains("Summarize this translated spoken-audio transcript in English (en)."))
        #expect(requestBody.contains("Keep the summary concise and factual."))
        #expect(requestBody.contains("This is the translated transcript that should be summarized."))
    }
}

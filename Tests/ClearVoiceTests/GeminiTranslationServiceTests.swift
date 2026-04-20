import Foundation
import Testing
@testable import ClearVoice

struct GeminiTranslationServiceTests {
    @Test
    func translateUsesGeminiGenerateContentAndReturnsModelText() async throws {
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
                              { "text": "Hello from ClearVoice" }
                            ]
                          }
                        }
                      ]
                    }
                    """.utf8)
                )
            ]
        )

        let service = GeminiTranslationService(
            client: GeminiDeveloperClient(
                apiKey: "gemini-test-key",
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
        let requestBody = String(decoding: requests[0].body ?? Data(), as: UTF8.self)

        #expect(translated == "Hello from ClearVoice")
        #expect(requests.count == 1)
        #expect(requests[0].request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent")
        #expect(requests[0].request.value(forHTTPHeaderField: "x-goog-api-key") == "gemini-test-key")
        #expect(requestBody.contains("Translate this spoken-audio transcript from Hindi (hi) to English (en)."))
        #expect(requestBody.contains("Output only the translated transcript"))
        #expect(requestBody.contains("नमस्ते दुनिया"))
    }

    @Test
    func translateShortCircuitsWhenSourceAndTargetLanguagesMatch() async throws {
        let transport = MockHTTPTransport(responses: [])
        let service = GeminiTranslationService(
            client: GeminiDeveloperClient(
                apiKey: "gemini-test-key",
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

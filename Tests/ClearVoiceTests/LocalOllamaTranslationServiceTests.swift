import Foundation
import Testing
@testable import ClearVoice

struct LocalOllamaTranslationServiceTests {
    @Test
    func translateDecodesEnglishResponse() async throws {
        let transport = MockHTTPTransport(
            responses: [
                .success(
                    statusCode: 200,
                    body: Data(#"{"response":"This is the English translation."}"#.utf8)
                )
            ]
        )
        let service = LocalOllamaTranslationService(
            model: "qwen3:14b",
            transport: transport
        )

        let translated = try await service.translate(
            text: "मराठी मजकूर",
            from: "mr",
            to: "en"
        )

        #expect(translated == "This is the English translation.")
    }

    @Test
    func translateRejectsClearlyNonEnglishOutput() async throws {
        let transport = MockHTTPTransport(
            responses: [
                .success(
                    statusCode: 200,
                    body: Data(#"{"response":"हा अजूनही मराठी मजकूर आहे."}"#.utf8)
                )
            ]
        )
        let service = LocalOllamaTranslationService(
            model: "qwen3:14b",
            transport: transport
        )

        await #expect(throws: ProcessingError.translationFailed("ClearVoice’s local translator did not return English text. Try rerunning with a stronger local Ollama model.")) {
            _ = try await service.translate(
                text: String(repeating: "हा मराठी उतारा आहे. ", count: 8),
                from: "mr",
                to: "en"
            )
        }
    }

    @Test
    func translateRejectsGenericAssistantReplies() async throws {
        let transport = MockHTTPTransport(
            responses: [
                .success(
                    statusCode: 200,
                    body: Data(#"{"response":"It seems your message may be garbled or unclear. Could you please clarify?"}"#.utf8)
                )
            ]
        )
        let service = LocalOllamaTranslationService(
            model: "qwen3:14b",
            transport: transport
        )

        await #expect(throws: ProcessingError.translationFailed("ClearVoice’s local translator answered with a generic assistant reply instead of an English transcript. Try rerunning with a stronger local model.")) {
            _ = try await service.translate(
                text: "मराठी मजकूर",
                from: "mr",
                to: "en"
            )
        }
    }

    @Test
    func translateSplitsLargeTranscriptsIntoMultipleRequests() async throws {
        let transport = MockHTTPTransport(
            responses: [
                .success(statusCode: 200, body: Data(#"{"response":"First English chunk."}"#.utf8)),
                .success(statusCode: 200, body: Data(#"{"response":"Second English chunk."}"#.utf8)),
                .success(statusCode: 200, body: Data(#"{"response":"Third English chunk."}"#.utf8)),
                .success(statusCode: 200, body: Data(#"{"response":"Fourth English chunk."}"#.utf8)),
            ]
        )
        let service = LocalOllamaTranslationService(
            model: "qwen3:14b",
            transport: transport,
            maxChunkCharacters: 160
        )
        let sourceText = Array(repeating: "हा एक मोठा मराठी उतारा आहे जो अनेक वाक्यांमध्ये विभागला जाईल.", count: 6)
            .joined(separator: " ")

        let translated = try await service.translate(
            text: sourceText,
            from: "mr",
            to: "en"
        )
        let capturedRequests = await transport.capturedRequests()

        #expect(capturedRequests.count > 1)
        #expect(translated.contains("First English chunk."))
        #expect(translated.contains("Second English chunk."))
    }

    @Test
    func translateTurnsTimeoutIntoActionableMessage() async throws {
        let transport = MockHTTPTransport(
            responses: [
                .failure(URLError(.timedOut)),
                .failure(URLError(.timedOut)),
                .failure(URLError(.timedOut)),
                .failure(URLError(.timedOut)),
                .failure(URLError(.timedOut)),
            ]
        )
        let service = LocalOllamaTranslationService(
            model: "qwen3:14b",
            transport: transport,
            retryPolicy: RetryPolicy(maxAttempts: 5, baseDelayMilliseconds: 0, maxJitterMilliseconds: 0)
        )

        await #expect(throws: ProcessingError.translationFailed("ClearVoice’s local Ollama translation timed out after 10 minutes. Try a smaller batch, lower concurrency, or a faster local model.")) {
            _ = try await service.translate(
                text: "मराठी मजकूर",
                from: "mr",
                to: "en"
            )
        }
    }
}

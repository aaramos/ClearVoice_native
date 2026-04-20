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
}

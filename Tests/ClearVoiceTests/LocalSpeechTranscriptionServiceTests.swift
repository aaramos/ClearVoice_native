import Foundation
import Testing
@testable import ClearVoice

struct LocalSpeechTranscriptionServiceTests {
    @Test
    func throwsLanguageNotSupportedWhenLocaleIsUnavailable() async {
        let service = LocalSpeechTranscriptionService(
            engine: StubLocalSpeechEngine(
                supportedLocale: nil,
                transcript: Transcript(text: "unused", detectedLanguage: "en", confidence: 1)
            )
        )

        await #expect(throws: TranscriptionError.languageNotSupported) {
            _ = try await service.transcribe(
                audio: URL(filePath: "/tmp/sample.wav"),
                language: .specific("gu")
            )
        }
    }

    @Test
    func returnsTranscriptForSupportedLocale() async throws {
        let expected = Transcript(text: "Hello world", detectedLanguage: "en", confidence: 0.91)
        let service = LocalSpeechTranscriptionService(
            engine: StubLocalSpeechEngine(
                supportedLocale: Locale(identifier: "en"),
                transcript: expected
            )
        )

        let result = try await service.transcribe(
            audio: URL(filePath: "/tmp/sample.wav"),
            language: .specific("en")
        )

        #expect(result == expected)
    }
}

private struct StubLocalSpeechEngine: LocalSpeechTranscriptionService.Engine {
    let supportedLocale: Locale?
    let transcript: Transcript

    func supportedLocale(for language: LanguageSelection) async -> Locale? {
        supportedLocale
    }

    func transcribe(audioURL: URL, locale: Locale) async throws -> Transcript {
        transcript
    }
}

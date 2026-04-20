import Foundation

protocol TranscriptionService: Sendable {
    func transcribe(
        audio: URL,
        language: LanguageSelection
    ) async throws -> Transcript
}

actor StubTranscriptionService: TranscriptionService {
    func transcribe(
        audio: URL,
        language: LanguageSelection
    ) async throws -> Transcript {
        let detectedLanguage: String

        switch language {
        case .auto:
            detectedLanguage = "en"
        case .specific(let code):
            detectedLanguage = code
        }

        let fileLabel = audio.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")

        return Transcript(
            text: "Stub original transcript for \(fileLabel).",
            detectedLanguage: detectedLanguage,
            confidence: 0.99
        )
    }
}

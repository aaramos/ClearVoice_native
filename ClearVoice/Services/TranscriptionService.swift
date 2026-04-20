import Foundation

enum ServiceError: Error, Equatable, Sendable {
    case cloudUnavailable
}

enum TranscriptionError: Error, Equatable, Sendable {
    case languageNotSupported
    case modelDownloading
}

protocol TranscriptionService: Sendable {
    /// Transcribes the supplied audio file and returns the detected-language metadata used by the rest of the pipeline.
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

actor UnavailableTranscriptionService: TranscriptionService {
    func transcribe(
        audio: URL,
        language: LanguageSelection
    ) async throws -> Transcript {
        throw ServiceError.cloudUnavailable
    }
}

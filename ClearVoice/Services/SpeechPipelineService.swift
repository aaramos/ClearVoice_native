import Foundation

struct SpeechPipelineOutput: Equatable, Sendable {
    let transcript: Transcript
    let englishTranslation: String
}

protocol SpeechPipelineService: Sendable {
    /// Processes a single clean audio file end-to-end and returns both the source-language transcript
    /// and the English translation transcript used for export.
    func process(
        audio: URL,
        language: LanguageSelection
    ) async throws -> SpeechPipelineOutput
}

actor StubSpeechPipelineService: SpeechPipelineService {
    func process(
        audio: URL,
        language: LanguageSelection
    ) async throws -> SpeechPipelineOutput {
        let transcript = try await StubTranscriptionService().transcribe(audio: audio, language: language)
        let english = "[translated to English] \(transcript.text)"
        return SpeechPipelineOutput(transcript: transcript, englishTranslation: english)
    }
}

actor ComposedSpeechPipelineService: SpeechPipelineService {
    private let transcription: any TranscriptionService
    private let translation: any TranslationService

    init(
        transcription: any TranscriptionService,
        translation: any TranslationService
    ) {
        self.transcription = transcription
        self.translation = translation
    }

    func process(
        audio: URL,
        language: LanguageSelection
    ) async throws -> SpeechPipelineOutput {
        let transcript = try await transcription.transcribe(audio: audio, language: language)
        let englishTranslation = try await translation.translate(
            text: transcript.text,
            from: transcript.detectedLanguage,
            to: "en"
        )
        return SpeechPipelineOutput(
            transcript: transcript,
            englishTranslation: englishTranslation
        )
    }
}

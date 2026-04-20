import AVFoundation
import Foundation
import Speech

actor LocalSpeechTranscriptionService: TranscriptionService {
    protocol Engine: Sendable {
        func supportedLocale(for language: LanguageSelection) async -> Locale?
        func transcribe(audioURL: URL, locale: Locale) async throws -> Transcript
    }

    private let engine: any Engine

    init(engine: any Engine = SpeechAnalyzerEngine()) {
        self.engine = engine
    }

    func transcribe(
        audio: URL,
        language: LanguageSelection
    ) async throws -> Transcript {
        guard let locale = await engine.supportedLocale(for: language) else {
            throw TranscriptionError.languageNotSupported
        }

        return try await engine.transcribe(audioURL: audio, locale: locale)
    }
}

private struct SpeechAnalyzerEngine: LocalSpeechTranscriptionService.Engine {
    func supportedLocale(for language: LanguageSelection) async -> Locale? {
        let requestedLocale: Locale?

        switch language {
        case .auto:
            requestedLocale = Locale.current.language.languageCode.map { Locale(identifier: $0.identifier) }
        case .specific(let identifier):
            requestedLocale = Locale(identifier: identifier)
        }

        guard let requestedLocale else {
            return nil
        }

        return await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale)
    }

    func transcribe(audioURL: URL, locale: Locale) async throws -> Transcript {
        let transcriber = SpeechTranscriber(
            locale: locale,
            preset: .transcription
        )

        let assetStatus = await AssetInventory.status(forModules: [transcriber])
        guard assetStatus != .unsupported else {
            throw TranscriptionError.languageNotSupported
        }

        guard assetStatus == .installed else {
            throw TranscriptionError.modelDownloading
        }

        let audioFile = try AVAudioFile(forReading: audioURL)
        let analyzer = SpeechAnalyzer(
            modules: [transcriber],
            options: SpeechAnalyzer.Options(
                priority: .userInitiated,
                modelRetention: .whileInUse
            )
        )

        try await analyzer.prepareToAnalyze(in: audioFile.processingFormat)

        let startTask = Task {
            try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)
        }

        var finalResult: SpeechTranscriber.Result?

        do {
            for try await result in transcriber.results {
                if result.isFinal {
                    finalResult = result
                }
            }
            try await startTask.value
        } catch {
            startTask.cancel()
            throw error
        }

        guard let finalResult else {
            throw ProcessingError.transcriptionFailed("ClearVoice didn’t receive a final local transcript.")
        }

        let transcriptText = String(finalResult.text.characters)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !transcriptText.isEmpty else {
            throw ProcessingError.transcriptionFailed("ClearVoice returned an empty local transcript.")
        }

        return Transcript(
            text: transcriptText,
            detectedLanguage: locale.language.languageCode?.identifier ?? locale.identifier,
            confidence: averageConfidence(in: finalResult.text) ?? 1
        )
    }

    private func averageConfidence(in text: AttributedString) -> Double? {
        let values = text.runs.compactMap { run in
            run.attributes[AttributeScopes.SpeechAttributes.ConfidenceAttribute.self]
        }

        guard !values.isEmpty else {
            return nil
        }

        let average = values.reduce(0, +) / Double(values.count)
        return min(max(average, 0), 1)
    }
}

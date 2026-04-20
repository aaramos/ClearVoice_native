import CoreML
import Foundation
import OSLog
import WhisperKit

actor WhisperKitSpeechPipelineService: SpeechPipelineService {
    private let modelName: String
    private let modelDirectory: URL
    private let logger = Logger(subsystem: "com.clearvoice.app", category: "whisperkit")
    private let languageConfidenceThreshold: Float

    init(
        modelName: String = "large-v3-v20240930_626MB",
        modelDirectory: URL? = nil,
        languageConfidenceThreshold: Float = 0.55
    ) {
        self.modelName = modelName
        self.modelDirectory = modelDirectory ?? Self.defaultModelDirectory()
        self.languageConfidenceThreshold = languageConfidenceThreshold
    }

    func process(
        audio: URL,
        language: LanguageSelection
    ) async throws -> SpeechPipelineOutput {
        let whisperKit = try await buildWhisperKit()

        do {
            let sourceLanguage = try await resolveSourceLanguage(
                using: whisperKit,
                audio: audio,
                requestedLanguage: language
            )
            let transcriptResults = try await whisperKit.transcribe(
                audioPath: audio.path,
                decodeOptions: transcribeOptions(sourceLanguage: sourceLanguage)
            )
            let originalText = consolidatedText(from: transcriptResults)

            guard !originalText.isEmpty else {
                throw ProcessingError.transcriptionFailed("ClearVoice returned an empty source transcript from the local speech model.")
            }

            let englishResults = try await whisperKit.transcribe(
                audioPath: audio.path,
                decodeOptions: translateOptions(sourceLanguage: sourceLanguage)
            )
            let englishText = consolidatedText(from: englishResults)

            guard !englishText.isEmpty else {
                throw ProcessingError.translationFailed("ClearVoice returned an empty English translation from the local speech model.")
            }

            let transcript = Transcript(
                text: originalText,
                detectedLanguage: transcriptResults.first?.language ?? sourceLanguage,
                confidence: confidence(from: transcriptResults)
            )

            await whisperKit.unloadModels()

            return SpeechPipelineOutput(
                transcript: transcript,
                englishTranslation: englishText
            )
        } catch {
            await whisperKit.unloadModels()
            throw map(error)
        }
    }

    private func buildWhisperKit() async throws -> WhisperKit {
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)

        let config = WhisperKitConfig(
            model: modelName,
            modelFolder: modelDirectory.path,
            computeOptions: ModelComputeOptions(
                melCompute: .cpuAndGPU,
                audioEncoderCompute: .cpuAndNeuralEngine,
                textDecoderCompute: .cpuAndNeuralEngine,
                prefillCompute: .cpuOnly
            ),
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true,
            download: true,
            useBackgroundDownloadSession: false
        )

        logger.debug("Loading WhisperKit model \(self.modelName, privacy: .public)")
        return try await WhisperKit(config)
    }

    private func resolveSourceLanguage(
        using whisperKit: WhisperKit,
        audio: URL,
        requestedLanguage: LanguageSelection
    ) async throws -> String {
        switch requestedLanguage {
        case .specific(let code):
            return code
        case .auto:
            let detection = try await whisperKit.detectLanguage(audioPath: audio.path)
            let confidence = detection.langProbs[detection.language] ?? detection.langProbs.values.max() ?? 0

            guard !detection.language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  confidence >= languageConfidenceThreshold else {
                throw TranscriptionError.languageDetectionFailed
            }

            return detection.language
        }
    }

    private func transcribeOptions(sourceLanguage: String) -> DecodingOptions {
        DecodingOptions(
            task: .transcribe,
            language: sourceLanguage,
            temperatureFallbackCount: 0,
            usePrefillPrompt: true,
            detectLanguage: false,
            wordTimestamps: true,
            concurrentWorkerCount: 1
        )
    }

    private func translateOptions(sourceLanguage: String) -> DecodingOptions {
        DecodingOptions(
            task: .translate,
            language: sourceLanguage,
            temperatureFallbackCount: 0,
            usePrefillPrompt: true,
            detectLanguage: false,
            concurrentWorkerCount: 1
        )
    }

    private func consolidatedText(from results: [TranscriptionResult]) -> String {
        results
            .map(\.text)
            .joined(separator: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func confidence(from results: [TranscriptionResult]) -> Double {
        let wordProbabilities = results
            .flatMap(\.allWords)
            .map(\.probability)
            .map(Double.init)

        if !wordProbabilities.isEmpty {
            let average = wordProbabilities.reduce(0, +) / Double(wordProbabilities.count)
            return min(max(average, 0), 1)
        }

        let segmentProbabilities = results
            .flatMap(\.segments)
            .map(\.avgLogprob)
            .map(Double.init)
            .map(exp)

        guard !segmentProbabilities.isEmpty else {
            return 0.75
        }

        let average = segmentProbabilities.reduce(0, +) / Double(segmentProbabilities.count)
        return min(max(average, 0), 1)
    }

    private func map(_ error: Error) -> Error {
        if let transcriptionError = error as? TranscriptionError {
            return transcriptionError
        }

        if let processingError = error as? ProcessingError {
            return processingError
        }

        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        if description.localizedCaseInsensitiveContains("download") {
            return ProcessingError.transcriptionFailed(
                "ClearVoice couldn’t load the local speech model yet. Connect this Mac to the internet once so the model can download, then try again."
            )
        }

        return ProcessingError.transcriptionFailed(
            "ClearVoice couldn’t run the local speech model: \(description)"
        )
    }

    private static func defaultModelDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)

        return base
            .appendingPathComponent("ClearVoice", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }
}

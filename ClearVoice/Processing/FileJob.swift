import Foundation
import OSLog

struct FileJob: Sendable {
    let config: BatchConfiguration
    let resolver: OutputPathResolver
    let services: ServiceBundle

    private let logger = Logger(subsystem: "com.clearvoice.app", category: "file-job")

    func run(
        item: AudioFileItem,
        update: @escaping @Sendable (AudioFileItem) async -> Void
    ) async {
        var item = item

        switch await resolver.resolve(basename: item.basename) {
        case .skip(let reason):
            item.stage = .skipped(reason: reason)
            await update(item)
            return
        case .use(let folder):
            item.outputFolderURL = folder
        }

        do {
            item.stage = .analyzing
            await update(item)
            try await simulatedStepDelay()

            item.stage = .analyzingFormat
            await update(item)

            let normalized = try await services.formatNormalizationService.normalize(item.sourceURL)
            let normalizedURL = normalized.url

            if normalized.requiresCleanup {
                item.stage = .normalizingFormat
                await update(item)
            }

            defer {
                if normalized.requiresCleanup {
                    try? FileManager.default.removeItem(at: normalizedURL)
                }
            }

            let cleanURL = item.outputFolderURL!.appendingPathComponent(
                "\(item.basename)_clean.\(normalizedURL.pathExtension)"
            )

            item.stage = .cleaning(progress: 0.1)
            await update(item)
            try await simulatedStepDelay()

            try await services.audioEnhancement.enhance(
                input: normalizedURL,
                output: cleanURL,
                intensity: config.intensity
            )

            item.stage = .cleaning(progress: 1.0)
            await update(item)

            let transcript = try await transcribe(
                item: &item,
                cleanURL: cleanURL,
                update: update
            )
            item.detectedLanguage = transcript.detectedLanguage
            item.originalTranscript = transcript.text
            item.stage = .transcribing(progress: 1.0)
            await update(item)

            item.stage = .translating
            await update(item)
            try await simulatedStepDelay()

            do {
                item.translatedTranscript = try await services.translationService(for: config).translate(
                    text: transcript.text,
                    from: transcript.detectedLanguage,
                    to: config.outputLanguage
                )
            } catch TranslationServiceError.pairUnavailable {
                logger.warning("Local translation unavailable for \(transcript.detectedLanguage, privacy: .public) -> \(config.outputLanguage, privacy: .public); passing transcript through untranslated")
                item.translatedTranscript = transcript.text
            }

            let summary: String?

            if config.processingMode.summarizationEnabled && services.apiKeyPresent {
                item.stage = .summarizing
                await update(item)
                try await simulatedStepDelay()

                do {
                    // FUTURE: Local summarization via FoundationModels (Apple Intelligence on-device LLM).
                    // Requires entitlement approval from Apple developer program.
                    // When available, replace UnavailableSummarizationService with a FoundationModelsSummarizationService
                    // that uses FoundationModels.LanguageModel to generate summaries without cloud dependency.
                    // A small CoreML model is a secondary fallback option if FoundationModels entitlement is unavailable.
                    summary = try await services.summarizationService(for: config).summarize(
                        text: item.translatedTranscript ?? transcript.text,
                        inLanguage: config.outputLanguage
                    )
                } catch let error as ProcessingError {
                    logger.warning("Summarization failed for \(item.sourceURL.lastPathComponent, privacy: .public); exporting transcript without summary: \(String(describing: error), privacy: .public)")
                    summary = nil
                } catch {
                    logger.warning("Summarization failed for \(item.sourceURL.lastPathComponent, privacy: .public); exporting transcript without summary: \(error.localizedDescription, privacy: .public)")
                    summary = nil
                }
            } else {
                summary = nil
            }

            item.summaryText = summary

            item.stage = .exporting
            await update(item)

            try await services.export.exportTranscript(
                to: item.outputFolderURL!,
                basename: item.basename,
                summary: summary,
                translated: item.translatedTranscript ?? transcript.text,
                original: item.originalTranscript ?? ""
            )

            item.stage = .complete
            await update(item)
        } catch let error as ProcessingError {
            try? await services.export.writeErrorLog(
                to: item.outputFolderURL ?? config.outputFolder,
                error: error,
                context: ["sourceFile": item.sourceURL.lastPathComponent]
            )
            item.stage = .failed(error: error)
            await update(item)
        } catch {
            let wrappedError = wrappedProcessingError(for: error)
            try? await services.export.writeErrorLog(
                to: item.outputFolderURL ?? config.outputFolder,
                error: wrappedError,
                context: ["sourceFile": item.sourceURL.lastPathComponent]
            )
            item.stage = .failed(error: wrappedError)
            await update(item)
        }
    }

    private func simulatedStepDelay() async throws {
        try await Task.sleep(for: .milliseconds(220))
    }

    private func transcribe(
        item: inout AudioFileItem,
        cleanURL: URL,
        update: @escaping @Sendable (AudioFileItem) async -> Void
    ) async throws -> Transcript {
        switch config.processingMode.transcription {
        case .cloud:
            return try await cloudTranscribe(
                item: &item,
                cleanURL: cleanURL,
                update: update
            )
        case .local:
            item.stage = .transcribing(progress: 0.3)
            await update(item)
            try await simulatedStepDelay()
            return try await services.transcriptionService(for: config).transcribe(
                audio: cleanURL,
                language: config.inputLanguage
            )
        }
    }

    private func cloudTranscribe(
        item: inout AudioFileItem,
        cleanURL: URL,
        update: @escaping @Sendable (AudioFileItem) async -> Void
    ) async throws -> Transcript {
        item.stage = .optimizingForUpload
        await update(item)

        let preparedURL = try await services.cloudPreparationService.prepare(cleanURL)
        defer {
            if preparedURL != cleanURL {
                try? FileManager.default.removeItem(at: preparedURL)
            }
        }

        item.stage = .transcribing(progress: 0.3)
        await update(item)
        try await simulatedStepDelay()

        return try await services.cloudTranscriptionService().transcribe(
            audio: preparedURL,
            language: config.inputLanguage
        )
    }

    private func wrappedProcessingError(for error: Error) -> ProcessingError {
        if let transcriptionError = error as? TranscriptionError {
            switch transcriptionError {
            case .languageNotSupported:
                return .transcriptionFailed("ClearVoice couldn’t transcribe this language on-device.")
            case .modelDownloading:
                return .transcriptionFailed("Speech support for this language is still downloading on this Mac.")
            }
        }

        if let serviceError = error as? ServiceError, serviceError == .cloudUnavailable {
            return .transcriptionFailed("Gemini is unavailable because no API key is configured.")
        }

        return .exportFailed(error.localizedDescription)
    }
}

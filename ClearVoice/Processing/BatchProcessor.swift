import Foundation

actor BatchProcessor {
    private let config: BatchConfiguration
    private let resolver: OutputPathResolver
    private let services: ServiceBundle
    private var stopAfterCurrent = false

    init(
        config: BatchConfiguration,
        resolver: OutputPathResolver,
        services: ServiceBundle
    ) {
        self.config = config
        self.resolver = resolver
        self.services = services
    }

    func requestStopAfterCurrent() {
        stopAfterCurrent = true
    }

    func run(
        files: [AudioFileItem],
        update: @escaping @Sendable (AudioFileItem) async -> Void
    ) async {
        let semaphore = AsyncSemaphore(value: config.maxConcurrency)
        let fileJob = FileJob(config: config, resolver: resolver, services: services)
        var completedItems: [AudioFileItem] = []

        await withTaskGroup(of: AudioFileItem.self) { group in
            for file in files {
                if stopAfterCurrent {
                    break
                }

                await semaphore.acquire()

                if stopAfterCurrent {
                    await semaphore.release()
                    break
                }

                group.addTask {
                    let result = await fileJob.run(item: file, update: update)
                    await semaphore.release()
                    return result
                }
            }

            for await item in group {
                completedItems.append(item)
            }
        }

        await runTranslationPhaseIfNeeded(for: completedItems, update: update)
    }

    private func runTranslationPhaseIfNeeded(
        for items: [AudioFileItem],
        update: @escaping @Sendable (AudioFileItem) async -> Void
    ) async {
        guard
            !stopAfterCurrent,
            config.transcriptionEnabled,
            let translationService = services.translation
        else {
            return
        }

        let orderedItems = items
            .filter { $0.stage == .complete }
            .sorted { $0.basename.localizedCaseInsensitiveCompare($1.basename) == .orderedAscending }

        for item in orderedItems {
            guard let transcript = item.transcript else {
                continue
            }

            if let translatedTranscript = item.translatedTranscript,
               !translatedTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }

            var translatedItem = item
            translatedItem.stage = .translating
            await update(translatedItem)

            do {
                let translatedResult = try await translateTranscript(
                    transcript,
                    using: translationService
                )
                translatedItem.transcript = translatedResult.transcript
                translatedItem.originalTranscript = translatedResult.transcript.exportText
                translatedItem.translatedTranscript = translatedResult.englishText

                translatedItem.stage = .exporting
                await update(translatedItem)

                try await services.export.exportTranscript(
                    to: translatedItem.outputFolderURL ?? config.outputFolder,
                    basename: translatedItem.basename,
                    summary: nil,
                    translated: translatedResult.englishText,
                    original: translatedResult.transcript
                )

                translatedItem.stage = .complete
                await update(translatedItem)
            } catch let error as ProcessingError {
                try? await services.export.writeErrorLog(
                    to: translatedItem.outputFolderURL ?? config.outputFolder,
                    error: error,
                    context: [
                        "sourceFile": translatedItem.sourceURL.lastPathComponent,
                        "phase": "translation",
                    ]
                )
                translatedItem.stage = .complete
                await update(translatedItem)
            } catch {
                let wrappedError = ProcessingError.translationFailed(error.localizedDescription)
                try? await services.export.writeErrorLog(
                    to: translatedItem.outputFolderURL ?? config.outputFolder,
                    error: wrappedError,
                    context: [
                        "sourceFile": translatedItem.sourceURL.lastPathComponent,
                        "phase": "translation",
                    ]
                )
                translatedItem.stage = .complete
                await update(translatedItem)
            }
        }
    }

    private func translateTranscript(
        _ transcript: Transcript,
        using translationService: any TranslationService
    ) async throws -> (transcript: Transcript, englishText: String) {
        if transcript.segments.isEmpty {
            let englishText = try await translationService.translate(
                text: transcript.text,
                from: transcript.detectedLanguage,
                to: config.outputLanguage
            )
            return (transcript, englishText)
        }

        var translatedSegments: [TranscriptSegment] = []
        translatedSegments.reserveCapacity(transcript.segments.count)

        for segment in transcript.segments {
            let englishText = try await translationService.translate(
                text: segment.text,
                from: transcript.detectedLanguage,
                to: config.outputLanguage
            )

            var translatedSegment = segment
            translatedSegment.translationEN = englishText.trimmingCharacters(in: .whitespacesAndNewlines)
            translatedSegments.append(translatedSegment)
        }

        var translatedTranscript = transcript
        translatedTranscript.segments = translatedSegments

        let englishText: String
        if let translatedExportText = translatedTranscript.translatedExportText {
            englishText = translatedExportText
        } else {
            englishText = try await translationService.translate(
                text: transcript.text,
                from: transcript.detectedLanguage,
                to: config.outputLanguage
            )
        }

        return (translatedTranscript, englishText)
    }
}

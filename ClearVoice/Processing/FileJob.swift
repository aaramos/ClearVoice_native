import Foundation

struct FileJob: Sendable {
    let config: BatchConfiguration
    let resolver: OutputPathResolver
    let services: ServiceBundle

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

            let cleanURL = item.outputFolderURL!.appendingPathComponent(
                "\(item.basename)_clean.\(item.sourceURL.pathExtension)"
            )

            item.stage = .cleaning(progress: 0.1)
            await update(item)
            try await simulatedStepDelay()

            try await services.audioEnhancement.enhance(
                input: item.sourceURL,
                output: cleanURL,
                intensity: config.intensity
            )

            item.stage = .cleaning(progress: 1.0)
            await update(item)

            item.stage = .transcribing(progress: 0.3)
            await update(item)
            try await simulatedStepDelay()

            let transcript = try await services.transcription.transcribe(
                audio: cleanURL,
                language: config.inputLanguage
            )
            item.detectedLanguage = transcript.detectedLanguage
            item.originalTranscript = transcript.text
            item.stage = .transcribing(progress: 1.0)
            await update(item)

            item.stage = .translating
            await update(item)
            try await simulatedStepDelay()

            item.translatedTranscript = try await services.translation.translate(
                text: transcript.text,
                from: transcript.detectedLanguage,
                to: config.outputLanguage
            )

            item.stage = .summarizing
            await update(item)
            try await simulatedStepDelay()

            item.summaryText = try await services.summarization.summarize(
                text: item.translatedTranscript ?? "",
                inLanguage: config.outputLanguage
            )

            item.stage = .exporting
            await update(item)

            try await services.export.exportTranscript(
                to: item.outputFolderURL!,
                basename: item.basename,
                summary: item.summaryText ?? "",
                translated: item.translatedTranscript ?? "",
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
            let wrappedError = ProcessingError.exportFailed(error.localizedDescription)
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
}

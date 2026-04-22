import Foundation

struct FileJob: Sendable {
    let config: BatchConfiguration
    let resolver: OutputPathResolver
    let services: ServiceBundle

    func run(
        item: AudioFileItem,
        update: @escaping @Sendable (AudioFileItem) async -> Void
    ) async -> AudioFileItem {
        var item = item
        let fileManager = FileManager.default

        let resolvedOutput = await resolver.resolve(
            sourceURL: item.sourceURL,
            enhancementSuffix: config.enhancementMethod.outputSuffix
        )
        item.outputFolderURL = resolvedOutput.folderURL
        item.processedAudioURL = resolvedOutput.enhancedFileURL

        do {
            try throwIfCancelled()

            item.stage = .analyzing
            await update(item)

            try throwIfCancelled()

            item.stage = .analyzingFormat
            await update(item)

            try throwIfCancelled()

            item.stage = .normalizingFormat
            await update(item)

            let normalized = try await services.formatNormalizationService.normalize(item.sourceURL)
            let normalizedURL = normalized.url

            let selectedEnhancements = services.comparisonEnhancements.filter {
                $0.outputSuffix == config.enhancementMethod.outputSuffix
            }

            guard !selectedEnhancements.isEmpty else {
                throw ProcessingError.enhancementFailed(
                    "ClearVoice couldn’t create the selected enhancement outputs because DeepFilterNet is unavailable on this Mac."
                )
            }

            let totalOutputs = selectedEnhancements.count

            defer {
                if normalized.requiresCleanup {
                    try? fileManager.removeItem(at: normalizedURL)
                }
            }

            for (offset, comparisonEnhancement) in selectedEnhancements.enumerated() {
                try throwIfCancelled()

                let outputURL = offset == 0
                    ? resolvedOutput.enhancedFileURL
                    : resolvedOutput.folderURL.appendingPathComponent(
                        "\(item.basename)_\(comparisonEnhancement.outputSuffix).\(AudioFormatSupport.cleanExportExtension)"
                    )

                let progress = Double(offset) / Double(totalOutputs)
                item.stage = .cleaning(progress: progress)
                await update(item)

                try await comparisonEnhancement.enhance(
                    input: normalizedURL,
                    output: outputURL
                )
            }

            try throwIfCancelled()

            item.stage = .cleaning(progress: 1.0)
            await update(item)

            item.stage = .complete
            await update(item)
            return item
        } catch ProcessingError.cancelled {
            removeProcessedAudioIfNeeded(for: item, fileManager: fileManager)
            item.stage = .cancelled
            await update(item)
            return item
        } catch is CancellationError {
            removeProcessedAudioIfNeeded(for: item, fileManager: fileManager)
            item.stage = .cancelled
            await update(item)
            return item
        } catch let error as ProcessingError {
            removeProcessedAudioIfNeeded(for: item, fileManager: fileManager)
            try? await services.export.writeErrorLog(
                to: item.outputFolderURL ?? config.outputFolder,
                error: error,
                context: ["sourceFile": item.sourceURL.lastPathComponent]
            )
            item.stage = .failed(error: error)
            await update(item)
            return item
        } catch {
            let wrappedError = wrappedProcessingError(for: error)
            removeProcessedAudioIfNeeded(for: item, fileManager: fileManager)
            try? await services.export.writeErrorLog(
                to: item.outputFolderURL ?? config.outputFolder,
                error: wrappedError,
                context: ["sourceFile": item.sourceURL.lastPathComponent]
            )
            item.stage = .failed(error: wrappedError)
            await update(item)
            return item
        }
    }

    private func wrappedProcessingError(for error: Error) -> ProcessingError {
        if error is CancellationError {
            return .cancelled
        }
        return .exportFailed(error.localizedDescription)
    }

    private func throwIfCancelled() throws {
        if Task.isCancelled {
            throw ProcessingError.cancelled
        }
    }

    private func removeProcessedAudioIfNeeded(
        for item: AudioFileItem,
        fileManager: FileManager
    ) {
        guard let processedAudioURL = item.processedAudioURL,
              fileManager.fileExists(atPath: processedAudioURL.path) else {
            return
        }

        try? fileManager.removeItem(at: processedAudioURL)
    }
}

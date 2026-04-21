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

            item.stage = .analyzingFormat
            await update(item)

            item.stage = .normalizingFormat
            await update(item)

            let normalized = try await services.formatNormalizationService.normalize(item.sourceURL)
            let normalizedURL = normalized.url

            guard !services.comparisonEnhancements.isEmpty else {
                throw ProcessingError.enhancementFailed(
                    "ClearVoice couldn’t create the selected enhancement outputs because DeepFilterNet is unavailable on this Mac."
                )
            }

            let totalOutputs = services.comparisonEnhancements.count
            var hybridOutputURL: URL?

            defer {
                if normalized.requiresCleanup {
                    try? FileManager.default.removeItem(at: normalizedURL)
                }
            }

            for (offset, comparisonEnhancement) in services.comparisonEnhancements.enumerated() {
                let outputURL = item.outputFolderURL!.appendingPathComponent(
                    "\(item.basename)_\(comparisonEnhancement.outputSuffix).\(AudioFormatSupport.cleanExportExtension)"
                )

                let progress = Double(offset) / Double(totalOutputs)
                item.stage = .cleaning(progress: progress)
                await update(item)

                try await comparisonEnhancement.enhance(
                    input: normalizedURL,
                    output: outputURL
                )

                if comparisonEnhancement.outputSuffix == DeepFilterNetVariant.hybrid.outputSuffix {
                    hybridOutputURL = outputURL
                }
            }

            item.stage = .cleaning(progress: 1.0)
            await update(item)

            if let hybridOutputURL {
                let preparedTranscriptionInput = try await services.transcriptionPreparationService.prepare(hybridOutputURL)
                if preparedTranscriptionInput.requiresCleanup {
                    try? FileManager.default.removeItem(at: preparedTranscriptionInput.url)
                }
            }

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

    private func wrappedProcessingError(for error: Error) -> ProcessingError {
        if let transcriptionError = error as? TranscriptionError {
            switch transcriptionError {
            case .languageNotSupported:
                return .transcriptionFailed("ClearVoice couldn’t transcribe this language with the local speech model.")
            case .languageDetectionFailed:
                return .transcriptionFailed("ClearVoice couldn’t detect the spoken language. Choose the source language manually and try again.")
            case .modelDownloading:
                return .transcriptionFailed("ClearVoice is still downloading the local speech model for this language.")
            case .modelNotInstalled:
                return .transcriptionFailed("ClearVoice needs the local speech model for this language before it can continue.")
            }
        }

        return .exportFailed(error.localizedDescription)
    }
}

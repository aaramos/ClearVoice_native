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

        switch await resolver.resolve(basename: item.basename) {
        case .skip(let reason):
            item.stage = .skipped(reason: reason)
            await update(item)
            return item
        case .use(let folder):
            item.outputFolderURL = folder
        }

        do {
            if let outputFolderURL = item.outputFolderURL {
                try copySourceFileIfNeeded(
                    from: item.sourceURL,
                    into: outputFolderURL,
                    fileManager: fileManager
                )
            }

            item.stage = .analyzing
            await update(item)

            item.stage = .analyzingFormat
            await update(item)

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
            }

            item.stage = .cleaning(progress: 1.0)
            await update(item)

            item.stage = .complete
            await update(item)
            return item
        } catch let error as ProcessingError {
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
        return .exportFailed(error.localizedDescription)
    }

    private func copySourceFileIfNeeded(
        from sourceURL: URL,
        into outputFolderURL: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(at: outputFolderURL, withIntermediateDirectories: true)

        let destinationURL = outputFolderURL.appendingPathComponent(sourceURL.lastPathComponent)
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            return
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }
}

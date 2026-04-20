import Foundation

struct FileJob: Sendable {
    let config: BatchConfiguration
    let resolver: OutputPathResolver
    let services: ServiceBundle

    private static let enhancementBands: [Intensity.Band] = [
        .minimal,
        .balanced,
        .strong,
        .maximum,
    ]

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

            defer {
                if normalized.requiresCleanup {
                    try? FileManager.default.removeItem(at: normalizedURL)
                }
            }

            for (index, band) in Self.enhancementBands.enumerated() {
                let outputURL = item.outputFolderURL!.appendingPathComponent(
                    "\(item.basename)_\(Self.outputSuffix(for: band)).\(AudioFormatSupport.cleanExportExtension)"
                )

                let progress = Double(index) / Double(Self.enhancementBands.count)
                item.stage = .cleaning(progress: progress)
                await update(item)

                try await services.audioEnhancement.enhance(
                    input: normalizedURL,
                    output: outputURL,
                    intensity: Intensity(band: band)
                )
            }

            item.stage = .cleaning(progress: 1.0)
            await update(item)

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

    private static func outputSuffix(for band: Intensity.Band) -> String {
        switch band {
        case .minimal:
            return "MIN"
        case .balanced:
            return "BALANCED"
        case .strong:
            return "STRONG"
        case .maximum:
            return "MAX"
        }
    }
}

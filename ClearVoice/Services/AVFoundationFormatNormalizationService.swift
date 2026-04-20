import AVFoundation
import Foundation
import OSLog

actor AVFoundationFormatNormalizationService: FormatNormalizationService {
    typealias Exporter = @Sendable (AVURLAsset, URL) async throws -> Void

    private let exporter: Exporter
    private let fileManager: FileManager
    private let logger = Logger(subsystem: "com.clearvoice.app", category: "normalize")

    init(
        fileManager: FileManager = .default,
        exporter: @escaping Exporter = AVFoundationFormatNormalizationService.defaultExporter
    ) {
        self.fileManager = fileManager
        self.exporter = exporter
    }

    func normalize(_ sourceURL: URL) async throws -> (url: URL, requiresCleanup: Bool) {
        let asset = AVURLAsset(url: sourceURL)
        let normalizedExtension = sourceURL.pathExtension.lowercased()

        guard !Self.supportedExtensions.contains(normalizedExtension) else {
            return (sourceURL, false)
        }

        let outputURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        logger.debug("Normalizing unsupported audio format at \(sourceURL.lastPathComponent, privacy: .public)")
        try await exporter(asset, outputURL)
        return (outputURL, true)
    }

    private static let supportedExtensions: Set<String> = [
        "wav",
        "mp3",
        "m4a",
        "aac",
        "flac",
    ]

    private static let defaultExporter: Exporter = { asset, destinationURL in
        try await AVFoundationFormatNormalizationService.exportToM4A(
            asset: asset,
            destinationURL: destinationURL
        )
    }

    private static func exportToM4A(asset: AVURLAsset, destinationURL: URL) async throws {
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw ProcessingError.enhancementFailed("ClearVoice couldn’t normalize this audio format.")
        }

        do {
            try await exportSession.export(to: destinationURL, as: .m4a)
        } catch is CancellationError {
            throw ProcessingError.cancelled
        } catch {
            throw ProcessingError.enhancementFailed("ClearVoice couldn’t normalize this audio format.")
        }
    }
}

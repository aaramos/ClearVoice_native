import Foundation
import OSLog

actor AVFoundationCloudPreparationService: CloudAudioPreparationService {
    typealias Runner = @Sendable (URL, URL) async throws -> Void

    private let fileManager: FileManager
    private let logger = Logger(subsystem: "com.clearvoice.app", category: "cloud-prep")
    private let runner: Runner

    init(
        fileManager: FileManager = .default,
        afconvertURL: URL = URL(fileURLWithPath: "/usr/bin/afconvert")
    ) {
        self.fileManager = fileManager
        self.runner = AVFoundationCloudPreparationService.defaultRunner(
            afconvertURL: afconvertURL
        )
    }

    init(
        fileManager: FileManager = .default,
        runner: @escaping Runner
    ) {
        self.fileManager = fileManager
        self.runner = runner
    }

    func prepare(_ sourceURL: URL) async throws -> URL {
        let destinationURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        logger.debug("Preparing cloud upload audio for \(sourceURL.lastPathComponent, privacy: .public)")

        do {
            try await runner(sourceURL, destinationURL)
            return destinationURL
        } catch {
            try? fileManager.removeItem(at: destinationURL)

            if Self.passthroughExtensions.contains(sourceURL.pathExtension.lowercased()) {
                logger.warning("Cloud upload optimization failed for \(sourceURL.lastPathComponent, privacy: .public); falling back to original audio: \(error.localizedDescription, privacy: .public)")
                return sourceURL
            }

            throw ProcessingError.transcriptionFailed(
                "ClearVoice couldn’t prepare audio for Gemini upload: \(error.localizedDescription)."
            )
        }
    }

    private static let passthroughExtensions: Set<String> = [
        "wav",
        "mp3",
        "aac",
        "flac",
    ]

    private static func defaultRunner(afconvertURL: URL) -> Runner {
        { sourceURL, destinationURL in
            let process = Process()
            process.executableURL = afconvertURL
            process.arguments = [
                sourceURL.path,
                "-o", destinationURL.path,
                "-f", "WAVE",
                "-d", "LEI16@16000",
                "-c", "1",
                "--mix",
            ]

            let errorPipe = Pipe()
            process.standardError = errorPipe

            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let detail = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if let detail, !detail.isEmpty {
                    throw PreparationError(detail)
                }

                throw PreparationError("Unknown conversion failure")
            }
        }
    }
}

private struct PreparationError: LocalizedError {
    let detail: String

    init(_ detail: String) {
        self.detail = detail
    }

    var errorDescription: String? {
        detail
    }
}

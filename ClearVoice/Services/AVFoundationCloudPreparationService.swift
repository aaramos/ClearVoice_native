import Foundation
import OSLog

actor AVFoundationCloudPreparationService: CloudAudioPreparationService {
    private let fileManager: FileManager
    private let logger = Logger(subsystem: "com.clearvoice.app", category: "cloud-prep")
    private let afconvertURL: URL

    init(
        fileManager: FileManager = .default,
        afconvertURL: URL = URL(fileURLWithPath: "/usr/bin/afconvert")
    ) {
        self.fileManager = fileManager
        self.afconvertURL = afconvertURL
    }

    func prepare(_ sourceURL: URL) async throws -> URL {
        let destinationURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        logger.debug("Preparing cloud upload audio for \(sourceURL.lastPathComponent, privacy: .public)")

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

            let message: String
            if let detail, !detail.isEmpty {
                message = "ClearVoice couldn’t prepare audio for Gemini upload: \(detail)."
            } else {
                message = "ClearVoice couldn’t prepare audio for Gemini upload."
            }

            throw ProcessingError.transcriptionFailed(
                message
            )
        }

        return destinationURL
    }
}

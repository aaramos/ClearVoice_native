import Foundation
import OSLog

actor FFmpegFormatNormalizationService: FormatNormalizationService {
    typealias Runner = @Sendable (URL, URL, URL) async throws -> Void

    private let fileManager: FileManager
    private let ffmpegURL: URL?
    private let runner: Runner
    private let logger = Logger(subsystem: "com.clearvoice.app", category: "normalize")

    init(
        fileManager: FileManager = .default,
        ffmpegURL: URL? = FFmpegFormatNormalizationService.resolveFFmpegURL(),
        runner: @escaping Runner = FFmpegFormatNormalizationService.defaultRunner
    ) {
        self.fileManager = fileManager
        self.ffmpegURL = ffmpegURL
        self.runner = runner
    }

    func normalize(_ sourceURL: URL) async throws -> (url: URL, requiresCleanup: Bool) {
        let sourceExtension = sourceURL.pathExtension.lowercased()

        guard AudioFormatSupport.requiresNormalization(for: sourceExtension) else {
            return (sourceURL, false)
        }

        guard let ffmpegURL else {
            throw ProcessingError.enhancementFailed(
                "ClearVoice couldn’t normalize this audio format because FFmpeg is unavailable on this Mac."
            )
        }

        let outputURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(AudioFormatSupport.normalizedOutputExtension)

        logger.debug("Normalizing audio format with FFmpeg at \(sourceURL.lastPathComponent, privacy: .public)")
        try await runner(ffmpegURL, sourceURL, outputURL)
        return (outputURL, true)
    }

    static func resolveFFmpegURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        var candidates: [String] = []

        if let explicitPath = environment["FFMPEG_PATH"], !explicitPath.isEmpty {
            candidates.append(explicitPath)
        }

        if let path = environment["PATH"] {
            candidates.append(
                contentsOf: path
                    .split(separator: ":")
                    .map { String($0) + "/ffmpeg" }
            )
        }

        candidates.append(contentsOf: [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg",
        ])

        for candidate in candidates {
            guard !candidate.isEmpty else { continue }
            let expandedPath = NSString(string: candidate).expandingTildeInPath

            if fileManager.isExecutableFile(atPath: expandedPath) {
                return URL(fileURLWithPath: expandedPath)
            }
        }

        return nil
    }

    private static let defaultRunner: Runner = { ffmpegURL, sourceURL, destinationURL in
        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = [
            "-hide_banner",
            "-loglevel", "error",
            "-y",
            "-i", sourceURL.path,
            "-vn",
            "-c:a", "aac",
            "-b:a", "128k",
            destinationURL.path,
        ]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw ProcessingError.enhancementFailed("ClearVoice couldn’t start FFmpeg: \(error.localizedDescription)")
        }

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let detail = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let detail, !detail.isEmpty {
                throw ProcessingError.enhancementFailed("ClearVoice couldn’t normalize this audio format: \(detail)")
            }

            throw ProcessingError.enhancementFailed("ClearVoice couldn’t normalize this audio format.")
        }
    }
}

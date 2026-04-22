import Foundation
import OSLog

actor FFmpegSpeechFormatNormalizationService: FormatNormalizationService {
    typealias Runner = @Sendable (URL, URL, URL) async throws -> Void

    private let fileManager: FileManager
    private let ffmpegURL: URL?
    private let runner: Runner
    private let logger = Logger(subsystem: "com.clearvoice.app", category: "normalize")

    init(
        fileManager: FileManager = .default,
        ffmpegURL: URL? = FFmpegSpeechFormatNormalizationService.resolveFFmpegURL(),
        runner: @escaping Runner = FFmpegSpeechFormatNormalizationService.defaultRunner
    ) {
        self.fileManager = fileManager
        self.ffmpegURL = ffmpegURL
        self.runner = runner
    }

    func normalize(_ sourceURL: URL) async throws -> (url: URL, requiresCleanup: Bool) {
        guard AudioFormatSupport.acceptedSourceExtensions.contains(sourceURL.pathExtension.lowercased()) else {
            throw ProcessingError.enhancementFailed(
                "ClearVoice couldn’t convert this audio format into the speech-processing format."
            )
        }

        guard let ffmpegURL else {
            throw ProcessingError.enhancementFailed(
                "ClearVoice couldn’t convert audio because FFmpeg is unavailable on this Mac."
            )
        }

        let outputURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        logger.debug("Converting source audio into speech-processing WAV for \(sourceURL.lastPathComponent, privacy: .public)")
        try await runner(ffmpegURL, sourceURL, outputURL)
        return (outputURL, true)
    }

    static func resolveFFmpegURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        var candidates: [String] = []

        let managedFFmpegPath = ManagedToolPaths.binaryURL(
            for: .ffmpeg,
            environment: environment,
            fileManager: fileManager
        ).path
        candidates.append(managedFFmpegPath)

        if let explicitPath = environment["FFMPEG_PATH"], !explicitPath.isEmpty {
            candidates.append(explicitPath)
        }

        if let path = environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map { String($0) + "/ffmpeg" })
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
        try await ExternalProcessRunner.run(
            executableURL: ffmpegURL,
            arguments: [
            "-hide_banner",
            "-loglevel", "error",
            "-y",
            "-i", sourceURL.path,
            "-vn",
            "-ac", "1",
            "-ar", "16000",
            "-c:a", "pcm_s16le",
            destinationURL.path,
            ],
            launchFailurePrefix: "ClearVoice couldn’t start FFmpeg",
            nonZeroExitPrefix: "ClearVoice couldn’t convert this audio file."
        )
    }
}

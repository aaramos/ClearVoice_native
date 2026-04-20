import Foundation

protocol AudioEnhancementService: Sendable {
    func enhance(
        input: URL,
        output: URL,
        intensity: Intensity
    ) async throws
}

actor StubAudioEnhancementService: AudioEnhancementService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func enhance(
        input: URL,
        output: URL,
        intensity: Intensity
    ) async throws {
        try fileManager.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: input, to: output)
    }
}

actor FFmpegAudioEnhancementService: AudioEnhancementService {
    typealias Runner = @Sendable (URL, URL, URL, String) async throws -> Void

    private let fileManager: FileManager
    private let ffmpegURL: URL?
    private let runner: Runner

    init(
        fileManager: FileManager = .default,
        ffmpegURL: URL? = FFmpegSpeechFormatNormalizationService.resolveFFmpegURL(),
        runner: @escaping Runner = FFmpegAudioEnhancementService.defaultRunner
    ) {
        self.fileManager = fileManager
        self.ffmpegURL = ffmpegURL
        self.runner = runner
    }

    func enhance(
        input: URL,
        output: URL,
        intensity: Intensity
    ) async throws {
        guard let ffmpegURL else {
            throw ProcessingError.enhancementFailed(
                "ClearVoice couldn’t enhance audio because FFmpeg is unavailable on this Mac."
            )
        }

        try fileManager.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: output.path) {
            try fileManager.removeItem(at: output)
        }

        try await runner(ffmpegURL, input, output, filterGraph(for: intensity))
    }

    private func filterGraph(for intensity: Intensity) -> String {
        switch intensity.band {
        case .minimal:
            return "highpass=f=90,lowpass=f=7600,afftdn=nf=-18,speechnorm=e=4.5:r=0.00008:l=1"
        case .balanced:
            return "highpass=f=90,lowpass=f=7600,afftdn=nf=-20,speechnorm=e=6:r=0.00008:l=1"
        case .strong:
            return "highpass=f=100,lowpass=f=7200,afftdn=nf=-24,speechnorm=e=8:r=0.00006:l=1"
        case .maximum:
            return "highpass=f=110,lowpass=f=7000,afftdn=nf=-28,speechnorm=e=10:r=0.00005:l=1"
        }
    }

    private static let defaultRunner: Runner = { ffmpegURL, inputURL, outputURL, filterGraph in
        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = [
            "-hide_banner",
            "-loglevel", "error",
            "-y",
            "-i", inputURL.path,
            "-vn",
            "-af", filterGraph,
            "-ac", "1",
            "-ar", "16000",
            "-c:a", "aac",
            "-b:a", "96k",
            outputURL.path,
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
                throw ProcessingError.enhancementFailed("ClearVoice couldn’t enhance this audio file: \(detail)")
            }

            throw ProcessingError.enhancementFailed("ClearVoice couldn’t enhance this audio file.")
        }
    }
}

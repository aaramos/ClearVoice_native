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
        let profile = profile(for: intensity)

        // Repair transient defects first so later denoise/gating stages do not smear pops or clipped peaks.
        return [
            "adeclick=window=20:overlap=75:arorder=2:threshold=\(profile.clickThreshold):burst=\(profile.clickBurst):method=save",
            "adeclip=window=55:overlap=75:arorder=8:threshold=\(profile.clipThreshold):hsize=1200:method=save",
            "highpass=f=\(profile.highpassFrequency)",
            "lowpass=f=\(profile.lowpassFrequency)",
            "afftdn=nr=\(profile.noiseReduction):nf=\(profile.noiseFloor):tn=1:gs=\(profile.gainSmooth)",
            "agate=threshold=\(profile.gateThreshold):ratio=\(profile.gateRatio):range=\(profile.gateRange):attack=\(profile.gateAttack):release=\(profile.gateRelease):detection=rms",
            "speechnorm=e=\(profile.speechExpansion):r=\(profile.speechRelease):l=1",
        ].joined(separator: ",")
    }

    private func profile(for intensity: Intensity) -> EnhancementProfile {
        switch intensity.band {
        case .minimal:
            return EnhancementProfile(
                highpassFrequency: 80,
                lowpassFrequency: 7_800,
                clickThreshold: 8,
                clickBurst: 1,
                clipThreshold: 14,
                noiseReduction: 10,
                noiseFloor: -48,
                gainSmooth: 4,
                gateThreshold: 0.018,
                gateRatio: 1.3,
                gateRange: 0.85,
                gateAttack: 15,
                gateRelease: 180,
                speechExpansion: 4.0,
                speechRelease: 0.00010
            )
        case .balanced:
            return EnhancementProfile(
                highpassFrequency: 90,
                lowpassFrequency: 7_600,
                clickThreshold: 6,
                clickBurst: 2,
                clipThreshold: 12,
                noiseReduction: 14,
                noiseFloor: -50,
                gainSmooth: 6,
                gateThreshold: 0.022,
                gateRatio: 1.6,
                gateRange: 0.65,
                gateAttack: 20,
                gateRelease: 240,
                speechExpansion: 6.0,
                speechRelease: 0.00008
            )
        case .strong:
            return EnhancementProfile(
                highpassFrequency: 100,
                lowpassFrequency: 7_200,
                clickThreshold: 4,
                clickBurst: 3,
                clipThreshold: 10,
                noiseReduction: 18,
                noiseFloor: -54,
                gainSmooth: 8,
                gateThreshold: 0.028,
                gateRatio: 2.2,
                gateRange: 0.45,
                gateAttack: 25,
                gateRelease: 320,
                speechExpansion: 8.0,
                speechRelease: 0.00006
            )
        case .maximum:
            return EnhancementProfile(
                highpassFrequency: 110,
                lowpassFrequency: 6_800,
                clickThreshold: 3,
                clickBurst: 4,
                clipThreshold: 8,
                noiseReduction: 22,
                noiseFloor: -58,
                gainSmooth: 10,
                gateThreshold: 0.035,
                gateRatio: 3.0,
                gateRange: 0.30,
                gateAttack: 30,
                gateRelease: 420,
                speechExpansion: 10.0,
                speechRelease: 0.00005
            )
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

private struct EnhancementProfile {
    let highpassFrequency: Int
    let lowpassFrequency: Int
    let clickThreshold: Int
    let clickBurst: Int
    let clipThreshold: Int
    let noiseReduction: Int
    let noiseFloor: Int
    let gainSmooth: Int
    let gateThreshold: Double
    let gateRatio: Double
    let gateRange: Double
    let gateAttack: Int
    let gateRelease: Int
    let speechExpansion: Double
    let speechRelease: Double
}

import Foundation

protocol AudioEnhancementService: Sendable {
    func enhance(
        input: URL,
        output: URL,
        intensity: Intensity
    ) async throws
}

protocol ComparisonEnhancementService: Sendable {
    var outputSuffix: String { get }

    func enhance(
        input: URL,
        output: URL
    ) async throws
}

struct DeepFilterNetVariant {
    let outputSuffix: String
    let preprocessFilterGraph: String
    let postprocessFilterGraph: String

    static let direct = DeepFilterNetVariant(
        outputSuffix: "DFN",
        preprocessFilterGraph: [
            "adeclick=window=20:overlap=75:arorder=2:threshold=3:burst=4:method=save",
            "adeclip=window=55:overlap=75:arorder=8:threshold=8:hsize=1200:method=save",
        ].joined(separator: ","),
        postprocessFilterGraph: [
            "highpass=f=80",
            "lowpass=f=7800",
            "speechnorm=e=4.0:r=0.0001:l=1",
        ].joined(separator: ",")
    )

    static let hybrid = DeepFilterNetVariant(
        outputSuffix: "HYBRID",
        preprocessFilterGraph: FFmpegAudioEnhancementService.filterGraph(for: .maximum),
        postprocessFilterGraph: [
            "highpass=f=80",
            "lowpass=f=7600",
            "speechnorm=e=4.0:r=0.0001:l=1",
        ].joined(separator: ",")
    )
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

actor DeepFilterNetAudioEnhancementService: ComparisonEnhancementService {
    typealias CommandRunner = @Sendable (URL, [String]) async throws -> Void

    let outputSuffix: String

    private let fileManager: FileManager
    private let ffmpegURL: URL?
    private let deepFilterURL: URL?
    private let ffmpegRunner: CommandRunner
    private let deepFilterRunner: CommandRunner
    private let variant: DeepFilterNetVariant

    init(
        fileManager: FileManager = .default,
        ffmpegURL: URL? = FFmpegSpeechFormatNormalizationService.resolveFFmpegURL(),
        deepFilterURL: URL? = DeepFilterNetAudioEnhancementService.resolveDeepFilterURL(),
        variant: DeepFilterNetVariant = .direct,
        ffmpegRunner: @escaping CommandRunner = DeepFilterNetAudioEnhancementService.defaultRunner,
        deepFilterRunner: @escaping CommandRunner = DeepFilterNetAudioEnhancementService.defaultRunner
    ) {
        self.fileManager = fileManager
        self.ffmpegURL = ffmpegURL
        self.deepFilterURL = deepFilterURL
        self.variant = variant
        self.outputSuffix = variant.outputSuffix
        self.ffmpegRunner = ffmpegRunner
        self.deepFilterRunner = deepFilterRunner
    }

    static func availableVariants(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> [any ComparisonEnhancementService] {
        guard let ffmpegURL = FFmpegSpeechFormatNormalizationService.resolveFFmpegURL(environment: environment, fileManager: fileManager),
              let deepFilterURL = resolveDeepFilterURL(environment: environment, fileManager: fileManager) else {
            return []
        }

        return [
            DeepFilterNetAudioEnhancementService(
                ffmpegURL: ffmpegURL,
                deepFilterURL: deepFilterURL,
                variant: .direct
            ),
            DeepFilterNetAudioEnhancementService(
                ffmpegURL: ffmpegURL,
                deepFilterURL: deepFilterURL,
                variant: .hybrid
            ),
        ]
    }

    func enhance(
        input: URL,
        output: URL
    ) async throws {
        guard let ffmpegURL else {
            throw ProcessingError.enhancementFailed(
                "ClearVoice couldn’t create the DeepFilterNet comparison because FFmpeg is unavailable on this Mac."
            )
        }

        guard let deepFilterURL else {
            throw ProcessingError.enhancementFailed(
                "ClearVoice couldn’t create the DeepFilterNet comparison because the deep-filter binary is unavailable on this Mac."
            )
        }

        try fileManager.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: output.path) {
            try fileManager.removeItem(at: output)
        }

        let workingDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repairedInputURL = workingDirectory.appendingPathComponent("deepfilter_input.wav")
        let deepFilterOutputDirectory = workingDirectory.appendingPathComponent("deepfilter_out", isDirectory: true)

        try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: deepFilterOutputDirectory, withIntermediateDirectories: true)

        defer {
            try? fileManager.removeItem(at: workingDirectory)
        }

        try await ffmpegRunner(ffmpegURL, Self.preprocessArguments(input: input, output: repairedInputURL, variant: variant))
        try await deepFilterRunner(deepFilterURL, Self.deepFilterArguments(input: repairedInputURL, outputDirectory: deepFilterOutputDirectory))

        guard let enhancedWAV = Self.locateDeepFilterOutput(
            expectedFilename: repairedInputURL.lastPathComponent,
            outputDirectory: deepFilterOutputDirectory,
            fileManager: fileManager
        ) else {
            throw ProcessingError.enhancementFailed(
                "ClearVoice ran DeepFilterNet but couldn’t find the enhanced WAV output."
            )
        }

        try await ffmpegRunner(ffmpegURL, Self.postprocessArguments(input: enhancedWAV, output: output, variant: variant))
    }

    static func resolveDeepFilterURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        var candidates: [String] = []

        let managedDeepFilterPath = ManagedToolPaths.binaryURL(
            for: .deepFilter,
            environment: environment,
            fileManager: fileManager
        ).path
        candidates.append(managedDeepFilterPath)

        if let explicitPath = environment["DEEP_FILTER_PATH"], !explicitPath.isEmpty {
            candidates.append(explicitPath)
        }

        if let path = environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map { String($0) + "/deep-filter" })
        }

        candidates.append(contentsOf: [
            "/opt/homebrew/bin/deep-filter",
            "/usr/local/bin/deep-filter",
            "/tmp/deep-filter",
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

    private static func preprocessArguments(input: URL, output: URL, variant: DeepFilterNetVariant) -> [String] {
        return [
            "-hide_banner",
            "-loglevel", "error",
            "-y",
            "-i", input.path,
            "-vn",
            "-af", variant.preprocessFilterGraph,
            "-ac", "1",
            "-ar", "48000",
            "-c:a", "pcm_s16le",
            output.path,
        ]
    }

    private static func deepFilterArguments(input: URL, outputDirectory: URL) -> [String] {
        [
            "--compensate-delay",
            "-o", outputDirectory.path,
            input.path,
        ]
    }

    private static func postprocessArguments(input: URL, output: URL, variant: DeepFilterNetVariant) -> [String] {
        return [
            "-hide_banner",
            "-loglevel", "error",
            "-y",
            "-i", input.path,
            "-vn",
            "-af", variant.postprocessFilterGraph,
            "-ac", "1",
            "-ar", "16000",
            "-c:a", "aac",
            "-b:a", "96k",
            output.path,
        ]
    }

    private static func locateDeepFilterOutput(
        expectedFilename: String,
        outputDirectory: URL,
        fileManager: FileManager
    ) -> URL? {
        let expected = outputDirectory.appendingPathComponent(expectedFilename)
        if fileManager.fileExists(atPath: expected.path) {
            return expected
        }

        guard let contents = try? fileManager.contentsOfDirectory(
            at: outputDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }

        return contents
            .filter { $0.pathExtension.lowercased() == "wav" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first
    }

    private static let defaultRunner: CommandRunner = { executableURL, arguments in
        try await ExternalProcessRunner.run(
            executableURL: executableURL,
            arguments: arguments,
            launchFailurePrefix: "ClearVoice couldn’t start \(executableURL.lastPathComponent)",
            nonZeroExitPrefix: "ClearVoice couldn’t run \(executableURL.lastPathComponent)"
        )
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

        try await runner(ffmpegURL, input, output, Self.filterGraph(for: intensity))
    }

    static func filterGraph(for intensity: Intensity) -> String {
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

    private static func profile(for intensity: Intensity) -> EnhancementProfile {
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
        try await ExternalProcessRunner.run(
            executableURL: ffmpegURL,
            arguments: [
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
            ],
            launchFailurePrefix: "ClearVoice couldn’t start FFmpeg",
            nonZeroExitPrefix: "ClearVoice couldn’t enhance this audio file."
        )
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

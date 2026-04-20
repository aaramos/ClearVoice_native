import Foundation
import Testing
@testable import ClearVoice

struct AudioEnhancementServiceTests {
    @Test
    func enhanceUsesRepairAndSuppressionFilters() async throws {
        let sourceURL = makeTemporaryAudioFile(named: "speech.wav")
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        let capture = FilterGraphCapture()

        let service = FFmpegAudioEnhancementService(
            ffmpegURL: URL(filePath: "/tmp/fake-ffmpeg"),
            runner: { _, inputURL, destinationURL, filterGraph in
                #expect(inputURL == sourceURL)
                await capture.record(filterGraph)
                try Data([0x01, 0x02, 0x03]).write(to: destinationURL)
            }
        )

        try await service.enhance(
            input: sourceURL,
            output: outputURL,
            intensity: .balanced
        )

        let filterGraph = await capture.value()
        #expect(filterGraph?.contains("adeclick=") == true)
        #expect(filterGraph?.contains("adeclip=") == true)
        #expect(filterGraph?.contains("afftdn=nr=14:nf=-50:tn=1:gs=6") == true)
        #expect(filterGraph?.contains("agate=threshold=0.022:ratio=1.6:range=0.65:attack=20:release=240:detection=rms") == true)
        #expect(filterGraph?.contains("speechnorm=e=6.0:r=8e-05:l=1") == true)
        #expect(FileManager.default.fileExists(atPath: outputURL.path))
    }

    @Test
    func maximumIntensityUsesMoreAggressiveSuppressionThanMinimal() async throws {
        let minimalGraph = try await filterGraph(for: .minimal)
        let maximumGraph = try await filterGraph(for: .maximum)

        #expect(minimalGraph.contains("afftdn=nr=10:nf=-48:tn=1:gs=4"))
        #expect(maximumGraph.contains("afftdn=nr=22:nf=-58:tn=1:gs=10"))
        #expect(minimalGraph.contains("agate=threshold=0.018:ratio=1.3:range=0.85"))
        #expect(maximumGraph.contains("agate=threshold=0.035:ratio=3.0:range=0.3"))
    }

    @Test
    func missingFFmpegProducesActionableEnhancementError() async {
        let sourceURL = makeTemporaryAudioFile(named: "speech.wav")
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        let service = FFmpegAudioEnhancementService(
            ffmpegURL: nil,
            runner: { _, _, _, _ in
                Issue.record("Runner should not be called when FFmpeg is missing.")
            }
        )

        await #expect(throws: ProcessingError.enhancementFailed("ClearVoice couldn’t enhance audio because FFmpeg is unavailable on this Mac.")) {
            try await service.enhance(
                input: sourceURL,
                output: outputURL,
                intensity: .balanced
            )
        }
    }

    @Test
    func deepFilterVariantRepairsBeforeModelAndWritesFinalOutput() async throws {
        let sourceURL = makeTemporaryAudioFile(named: "speech.wav")
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        let ffmpegCapture = CommandCapture()
        let deepFilterCapture = CommandCapture()

        let service = DeepFilterNetAudioEnhancementService(
            ffmpegURL: URL(filePath: "/tmp/fake-ffmpeg"),
            deepFilterURL: URL(filePath: "/tmp/fake-deep-filter"),
            ffmpegRunner: { _, arguments in
                await ffmpegCapture.record(arguments)
                if let destination = arguments.last {
                    try Data([0x01, 0x02]).write(to: URL(filePath: destination))
                }
            },
            deepFilterRunner: { _, arguments in
                await deepFilterCapture.record(arguments)
                let input = try #require(arguments.last)
                let outputDirectoryIndex = try #require(arguments.firstIndex(of: "-o"))
                let outputDirectory = URL(filePath: arguments[outputDirectoryIndex + 1])
                let enhancedURL = outputDirectory.appendingPathComponent(URL(filePath: input).lastPathComponent)
                try Data([0x0A, 0x0B]).write(to: enhancedURL)
            }
        )

        try await service.enhance(input: sourceURL, output: outputURL)

        let ffmpegCommands = await ffmpegCapture.values()
        let deepFilterCommands = await deepFilterCapture.values()

        #expect(ffmpegCommands.count == 2)
        #expect(ffmpegCommands[0].contains("-ar"))
        #expect(ffmpegCommands[0].contains("48000"))
        #expect(ffmpegCommands[0].contains("adeclick=window=20:overlap=75:arorder=2:threshold=3:burst=4:method=save,adeclip=window=55:overlap=75:arorder=8:threshold=8:hsize=1200:method=save"))
        #expect(deepFilterCommands.first?.contains("--compensate-delay") == true)
        #expect(ffmpegCommands[1].contains { $0.contains("speechnorm=e=4.0:r=0.0001:l=1") })
        #expect(FileManager.default.fileExists(atPath: outputURL.path))
    }

    @Test
    func missingDeepFilterProducesActionableError() async {
        let sourceURL = makeTemporaryAudioFile(named: "speech.wav")
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        let service = DeepFilterNetAudioEnhancementService(
            ffmpegURL: URL(filePath: "/tmp/fake-ffmpeg"),
            deepFilterURL: nil,
            ffmpegRunner: { _, _ in
                Issue.record("FFmpeg should not be called when deep-filter is missing.")
            },
            deepFilterRunner: { _, _ in
                Issue.record("DeepFilterNet runner should not be called when deep-filter is missing.")
            }
        )

        await #expect(throws: ProcessingError.enhancementFailed("ClearVoice couldn’t create the DeepFilterNet comparison because the deep-filter binary is unavailable on this Mac.")) {
            try await service.enhance(input: sourceURL, output: outputURL)
        }
    }

    private func filterGraph(for intensity: Intensity) async throws -> String {
        let sourceURL = makeTemporaryAudioFile(named: "capture.wav")
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        let capture = FilterGraphCapture()
        let service = FFmpegAudioEnhancementService(
            ffmpegURL: URL(filePath: "/tmp/fake-ffmpeg"),
            runner: { _, _, destinationURL, filterGraph in
                await capture.record(filterGraph)
                try Data([0xAA]).write(to: destinationURL)
            }
        )

        try await service.enhance(
            input: sourceURL,
            output: outputURL,
            intensity: intensity
        )

        return await capture.value() ?? ""
    }
}

private actor FilterGraphCapture {
    private var graph: String?

    func record(_ graph: String) {
        self.graph = graph
    }

    func value() -> String? {
        graph
    }
}

private actor CommandCapture {
    private var commands: [[String]] = []

    func record(_ command: [String]) {
        commands.append(command)
    }

    func values() -> [[String]] {
        commands
    }
}

private func makeTemporaryAudioFile(named filename: String) -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(filename)")
    try? Data([0x10, 0x20, 0x30]).write(to: url)
    return url
}

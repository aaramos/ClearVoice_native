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

private func makeTemporaryAudioFile(named filename: String) -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(filename)")
    try? Data([0x10, 0x20, 0x30]).write(to: url)
    return url
}

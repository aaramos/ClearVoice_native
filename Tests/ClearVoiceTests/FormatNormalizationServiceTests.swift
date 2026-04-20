import AVFoundation
import Foundation
import Testing
@testable import ClearVoice

struct FormatNormalizationServiceTests {
    @Test
    func supportedFormatReturnsOriginalURL() async throws {
        let sourceURL = makeTemporaryAudioFile(named: "sample.m4a")
        let service = FFmpegFormatNormalizationService(
            ffmpegURL: URL(filePath: "/tmp/fake-ffmpeg"),
            runner: { _, _, _ in
                Issue.record("Runner should not be called for passthrough formats.")
            }
        )

        let result = try await service.normalize(sourceURL)

        #expect(result.url == sourceURL)
        #expect(result.requiresCleanup == false)
    }

    @Test
    func wmaWritesTemporaryNormalizedURL() async throws {
        let sourceURL = makeTemporaryAudioFile(named: "sample.wma")
        let service = FFmpegFormatNormalizationService(
            ffmpegURL: URL(filePath: "/tmp/fake-ffmpeg"),
            runner: { _, _, destinationURL in
                try Data([0x01, 0x02, 0x03]).write(to: destinationURL)
            }
        )

        let result = try await service.normalize(sourceURL)

        #expect(result.url != sourceURL)
        #expect(result.url.pathExtension == "m4a")
        #expect(result.requiresCleanup)
        #expect(result.url.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        #expect(FileManager.default.fileExists(atPath: result.url.path))
    }

    @Test
    func missingFFmpegProducesActionableNormalizationError() async {
        let sourceURL = makeTemporaryAudioFile(named: "sample.wma")
        let service = FFmpegFormatNormalizationService(
            ffmpegURL: nil,
            runner: { _, _, _ in
                Issue.record("Runner should not be called when FFmpeg is missing.")
            }
        )

        await #expect(throws: ProcessingError.enhancementFailed("ClearVoice couldn’t normalize this audio format because FFmpeg is unavailable on this Mac.")) {
            _ = try await service.normalize(sourceURL)
        }
    }
}

private func makeTemporaryAudioFile(named filename: String) -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(filename)")
    try? Data([0x10, 0x20, 0x30]).write(to: url)
    return url
}

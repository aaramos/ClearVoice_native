import AVFoundation
import Foundation
import Testing
@testable import ClearVoice

struct FormatNormalizationServiceTests {
    @Test
    func acceptedFormatWritesTemporarySpeechProcessingWAV() async throws {
        let sourceURL = makeTemporaryAudioFile(named: "sample.m4a")
        let service = FFmpegSpeechFormatNormalizationService(
            ffmpegURL: URL(filePath: "/tmp/fake-ffmpeg"),
            runner: { _, sourceURL, destinationURL in
                #expect(sourceURL.pathExtension == "m4a")
                try Data([0x01, 0x02, 0x03]).write(to: destinationURL)
            }
        )

        let result = try await service.normalize(sourceURL)

        #expect(result.url != sourceURL)
        #expect(result.url.pathExtension == "wav")
        #expect(result.requiresCleanup)
        #expect(result.url.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        #expect(FileManager.default.fileExists(atPath: result.url.path))
    }

    @Test
    func wmaWritesTemporaryNormalizedURL() async throws {
        let sourceURL = makeTemporaryAudioFile(named: "sample.wma")
        let service = FFmpegSpeechFormatNormalizationService(
            ffmpegURL: URL(filePath: "/tmp/fake-ffmpeg"),
            runner: { _, _, destinationURL in
                try Data([0x01, 0x02, 0x03]).write(to: destinationURL)
            }
        )

        let result = try await service.normalize(sourceURL)

        #expect(result.url != sourceURL)
        #expect(result.url.pathExtension == "wav")
        #expect(result.requiresCleanup)
        #expect(result.url.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        #expect(FileManager.default.fileExists(atPath: result.url.path))
    }

    @Test
    func missingFFmpegProducesActionableNormalizationError() async {
        let sourceURL = makeTemporaryAudioFile(named: "sample.wma")
        let service = FFmpegSpeechFormatNormalizationService(
            ffmpegURL: nil,
            runner: { _, _, _ in
                Issue.record("Runner should not be called when FFmpeg is missing.")
            }
        )

        await #expect(throws: ProcessingError.enhancementFailed("ClearVoice couldn’t convert audio because FFmpeg is unavailable on this Mac.")) {
            _ = try await service.normalize(sourceURL)
        }
    }
}

private func makeTemporaryAudioFile(named filename: String) -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(filename)")
    try? Data([0x10, 0x20, 0x30]).write(to: url)
    return url
}

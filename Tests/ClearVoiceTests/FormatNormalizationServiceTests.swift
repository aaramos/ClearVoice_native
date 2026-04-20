import AVFoundation
import Foundation
import Testing
@testable import ClearVoice

struct FormatNormalizationServiceTests {
    @Test
    func supportedFormatReturnsOriginalURL() async throws {
        let sourceURL = makeTemporaryAudioFile(named: "sample.m4a")
        let service = AVFoundationFormatNormalizationService(
            exporter: { _, _ in
                Issue.record("Exporter should not be called for supported formats.")
            }
        )

        let result = try await service.normalize(sourceURL)

        #expect(result.url == sourceURL)
        #expect(result.requiresCleanup == false)
    }

    @Test
    func unsupportedFormatWritesTemporaryNormalizedURL() async throws {
        let sourceURL = makeTemporaryAudioFile(named: "sample.ogg")
        let service = AVFoundationFormatNormalizationService(
            exporter: { _, destinationURL in
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
}

private func makeTemporaryAudioFile(named filename: String) -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(filename)")
    try? Data([0x10, 0x20, 0x30]).write(to: url)
    return url
}

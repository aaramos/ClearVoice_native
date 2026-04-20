import AVFoundation
import Foundation
import Testing
@testable import ClearVoice

struct CloudAudioPreparationServiceTests {
    @Test
    func preparedAudioIsTemporaryWAVAtSixteenKilohertzMono() async throws {
        let sourceURL = try makeToneWAV()
        let service = AVFoundationCloudPreparationService()

        let outputURL = try await service.prepare(sourceURL)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        #expect(outputURL.pathExtension == "wav")
        #expect(outputURL.path.hasPrefix(FileManager.default.temporaryDirectory.path))

        let preparedFile = try AVAudioFile(forReading: outputURL)
        #expect(preparedFile.processingFormat.sampleRate == 16_000)
        #expect(preparedFile.processingFormat.channelCount == 1)
    }

    @Test
    func mp3FallsBackToOriginalAudioWhenOptimizationFails() async throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).mp3")
        try Data([0x01, 0x02, 0x03]).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let service = AVFoundationCloudPreparationService { _, _ in
            throw NSError(domain: "CloudPrep", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "ExtAudioFileRead failed ('bada')"
            ])
        }

        let outputURL = try await service.prepare(sourceURL)

        #expect(outputURL == sourceURL)
    }
}

private func makeToneWAV() throws -> URL {
    let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let frameCount: AVAudioFrameCount = 4_410
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
    buffer.frameLength = frameCount

    let leftChannel = buffer.floatChannelData![0]
    let rightChannel = buffer.floatChannelData![1]

    for index in 0..<Int(frameCount) {
        let sample = sin(Float(index) * 0.08)
        leftChannel[index] = sample
        rightChannel[index] = sample
    }

    try file.write(from: buffer)
    return url
}

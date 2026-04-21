import AVFoundation
import Foundation
import Testing
@testable import ClearVoice

struct TranscriptionPreparationServiceTests {
    @Test
    func prepareWritesTemporaryValidatedWAV() async throws {
        let sourceURL = makeTemporarySourceFile(named: "sample_HYBRID.m4a")
        let service = FFmpegTranscriptionPreparationService(
            ffmpegURL: URL(filePath: "/tmp/fake-ffmpeg"),
            runner: { _, _, destinationURL in
                try writeTestWAV(
                    to: destinationURL,
                    sampleRate: 16_000,
                    channels: 1
                )
            }
        )

        let result = try await service.prepare(sourceURL)

        #expect(result.url != sourceURL)
        #expect(result.url.pathExtension == "wav")
        #expect(result.requiresCleanup)
        #expect(result.url.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        #expect(FileManager.default.fileExists(atPath: result.url.path))
    }

    @Test
    func missingFFmpegProducesActionablePreparationError() async {
        let sourceURL = makeTemporarySourceFile(named: "sample_HYBRID.m4a")
        let service = FFmpegTranscriptionPreparationService(
            ffmpegURL: nil,
            runner: { _, _, _ in
                Issue.record("Runner should not be called when FFmpeg is missing.")
            }
        )

        await #expect(throws: ProcessingError.transcriptionFailed("ClearVoice couldn’t prepare the HYBRID audio for transcription because FFmpeg is unavailable on this Mac.")) {
            _ = try await service.prepare(sourceURL)
        }
    }

    @Test
    func invalidPreparedSampleRateFailsValidationAndRemovesTempOutput() async throws {
        let sourceURL = makeTemporarySourceFile(named: "sample_HYBRID.m4a")
        let recorder = PreparationOutputRecorder()
        let service = FFmpegTranscriptionPreparationService(
            ffmpegURL: URL(filePath: "/tmp/fake-ffmpeg"),
            runner: { _, _, destinationURL in
                await recorder.record(destinationURL)
                try writeTestWAV(
                    to: destinationURL,
                    sampleRate: 22_050,
                    channels: 1
                )
            }
        )

        await #expect(throws: ProcessingError.transcriptionFailed("ClearVoice prepared invalid transcription audio. Expected a 16 kHz transcription WAV.")) {
            _ = try await service.prepare(sourceURL)
        }

        let recordedURL = await recorder.url
        let destinationURL = try #require(recordedURL)
        #expect(!FileManager.default.fileExists(atPath: destinationURL.path))
    }

    @Test
    func invalidPreparedChannelCountFailsValidation() async {
        let sourceURL = makeTemporarySourceFile(named: "sample_HYBRID.m4a")
        let service = FFmpegTranscriptionPreparationService(
            ffmpegURL: URL(filePath: "/tmp/fake-ffmpeg"),
            runner: { _, _, destinationURL in
                try writeTestWAV(
                    to: destinationURL,
                    sampleRate: 16_000,
                    channels: 2
                )
            }
        )

        await #expect(throws: ProcessingError.transcriptionFailed("ClearVoice prepared invalid transcription audio. Expected mono audio for whisper.cpp.")) {
            _ = try await service.prepare(sourceURL)
        }
    }
}

private actor PreparationOutputRecorder {
    private(set) var url: URL?

    func record(_ url: URL) {
        self.url = url
    }
}

private func makeTemporarySourceFile(named filename: String) -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(filename)")
    try? Data([0x10, 0x20, 0x30]).write(to: url)
    return url
}

private func writeTestWAV(
    to url: URL,
    sampleRate: Double,
    channels: Int
) throws {
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: channels,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]

    let file = try AVAudioFile(forWriting: url, settings: settings)
    let format = file.processingFormat
    let frameCount: AVAudioFrameCount = 512
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
    buffer.frameLength = frameCount

    if let channelData = buffer.int16ChannelData {
        for channel in 0..<Int(format.channelCount) {
            channelData[channel].initialize(repeating: 0, count: Int(frameCount))
        }
    }

    try file.write(from: buffer)
}

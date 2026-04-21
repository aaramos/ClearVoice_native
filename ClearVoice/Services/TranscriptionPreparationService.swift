import AVFoundation
import Foundation
import OSLog

protocol TranscriptionPreparationService: Sendable {
    /// Returns a temporary WAV that is safe for local whisper.cpp transcription.
    /// The caller must clean up any returned temporary URL when `requiresCleanup` is true.
    func prepare(_ sourceURL: URL) async throws -> (url: URL, requiresCleanup: Bool)
}

actor StubTranscriptionPreparationService: TranscriptionPreparationService {
    func prepare(_ sourceURL: URL) async throws -> (url: URL, requiresCleanup: Bool) {
        (sourceURL, false)
    }
}

actor FFmpegTranscriptionPreparationService: TranscriptionPreparationService {
    typealias Runner = @Sendable (URL, URL, URL) async throws -> Void
    typealias Validator = @Sendable (URL) throws -> Void

    private let fileManager: FileManager
    private let ffmpegURL: URL?
    private let runner: Runner
    private let validator: Validator
    private let logger = Logger(subsystem: "com.clearvoice.app", category: "transcription-prep")

    init(
        fileManager: FileManager = .default,
        ffmpegURL: URL? = FFmpegSpeechFormatNormalizationService.resolveFFmpegURL(),
        runner: @escaping Runner = FFmpegTranscriptionPreparationService.defaultRunner,
        validator: @escaping Validator = FFmpegTranscriptionPreparationService.defaultValidator
    ) {
        self.fileManager = fileManager
        self.ffmpegURL = ffmpegURL
        self.runner = runner
        self.validator = validator
    }

    func prepare(_ sourceURL: URL) async throws -> (url: URL, requiresCleanup: Bool) {
        guard let ffmpegURL else {
            throw ProcessingError.transcriptionFailed(
                "ClearVoice couldn’t prepare the HYBRID audio for transcription because FFmpeg is unavailable on this Mac."
            )
        }

        let outputURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(AudioFormatSupport.speechProcessingExtension)

        logger.debug("Preparing HYBRID audio for whisper.cpp transcription: \(sourceURL.lastPathComponent, privacy: .public)")

        do {
            try await runner(ffmpegURL, sourceURL, outputURL)
            try validator(outputURL)
            return (outputURL, true)
        } catch {
            try? fileManager.removeItem(at: outputURL)

            if let processingError = error as? ProcessingError {
                throw processingError
            }

            throw ProcessingError.transcriptionFailed(error.localizedDescription)
        }
    }

    private static func validatePreparedInput(_ url: URL) throws {
        let file: AVAudioFile

        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw ProcessingError.transcriptionFailed(
                "ClearVoice couldn’t read the prepared transcription WAV."
            )
        }

        let settings = file.fileFormat.settings
        let formatID = (settings[AVFormatIDKey] as? NSNumber)?.uint32Value
            ?? file.fileFormat.streamDescription.pointee.mFormatID
        let sampleRate = (settings[AVSampleRateKey] as? NSNumber)?.doubleValue
            ?? file.fileFormat.sampleRate
        let channelCount = (settings[AVNumberOfChannelsKey] as? NSNumber)?.intValue
            ?? Int(file.fileFormat.channelCount)
        let bitDepth = (settings[AVLinearPCMBitDepthKey] as? NSNumber)?.intValue ?? 0

        guard formatID == kAudioFormatLinearPCM else {
            throw ProcessingError.transcriptionFailed(
                "ClearVoice prepared invalid transcription audio. Expected PCM WAV for whisper.cpp."
            )
        }

        guard Int(sampleRate.rounded()) == 16000 else {
            throw ProcessingError.transcriptionFailed(
                "ClearVoice prepared invalid transcription audio. Expected a 16 kHz transcription WAV."
            )
        }

        guard channelCount == 1 else {
            throw ProcessingError.transcriptionFailed(
                "ClearVoice prepared invalid transcription audio. Expected mono audio for whisper.cpp."
            )
        }

        guard bitDepth == 16 else {
            throw ProcessingError.transcriptionFailed(
                "ClearVoice prepared invalid transcription audio. Expected 16-bit PCM audio for whisper.cpp."
            )
        }
    }

    private static let defaultValidator: Validator = { url in
        try validatePreparedInput(url)
    }

    private static let defaultRunner: Runner = { ffmpegURL, sourceURL, destinationURL in
        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = [
            "-hide_banner",
            "-loglevel", "error",
            "-y",
            "-i", sourceURL.path,
            "-vn",
            "-ac", "1",
            "-ar", "16000",
            "-c:a", "pcm_s16le",
            destinationURL.path,
        ]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw ProcessingError.transcriptionFailed("ClearVoice couldn’t start FFmpeg: \(error.localizedDescription)")
        }

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let detail = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let detail, !detail.isEmpty {
                throw ProcessingError.transcriptionFailed("ClearVoice couldn’t prepare HYBRID audio for transcription: \(detail)")
            }

            throw ProcessingError.transcriptionFailed("ClearVoice couldn’t prepare HYBRID audio for transcription.")
        }
    }
}

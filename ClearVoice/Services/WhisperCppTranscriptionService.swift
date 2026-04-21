import Foundation
import OSLog

actor WhisperCppTranscriptionService: TranscriptionService {
    typealias Runner = @Sendable (URL, [String], [String: String]) async throws -> Void

    private let fileManager: FileManager
    private let executableURL: URL?
    private let modelDirectory: URL
    private let primaryModelName: String
    private let fallbackModelName: String
    private let decodeProfile: DecodeProfile
    private let vadModelNameCandidates: [String]
    private let threads: Int
    private let runner: Runner
    private let logger = Logger(subsystem: "com.clearvoice.app", category: "whisper.cpp")

    init(
        fileManager: FileManager = .default,
        executableURL: URL? = WhisperCppTranscriptionService.resolveExecutableURL(),
        modelDirectory: URL? = nil,
        primaryModelName: String = "ggml-large-v3-turbo.bin",
        fallbackModelName: String = "ggml-large-v3.bin",
        decodeProfile: DecodeProfile = .longFormNoisy,
        vadModelNameCandidates: [String] = [
            "ggml-silero-v6.2.0.bin",
            "ggml-silero-v5.1.2.bin",
        ],
        threads: Int = WhisperCppTranscriptionService.defaultThreadCount(),
        runner: @escaping Runner = WhisperCppTranscriptionService.defaultRunner
    ) {
        self.fileManager = fileManager
        self.executableURL = executableURL
        self.modelDirectory = modelDirectory ?? Self.defaultModelDirectory()
        self.primaryModelName = primaryModelName
        self.fallbackModelName = fallbackModelName
        self.decodeProfile = decodeProfile
        self.vadModelNameCandidates = vadModelNameCandidates
        self.threads = threads
        self.runner = runner
    }

    func transcribe(
        audio: URL,
        language: LanguageSelection
    ) async throws -> Transcript {
        guard let executableURL else {
            throw ProcessingError.transcriptionFailed(
                "ClearVoice couldn’t find the local whisper.cpp transcription engine on this Mac."
            )
        }

        let languageCode = try resolvedLanguageCode(for: language)
        try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)

        let primaryModelURL = modelDirectory.appendingPathComponent(primaryModelName)
        let fallbackModelURL = modelDirectory.appendingPathComponent(fallbackModelName)

        do {
            return try await transcribe(
                audio: audio,
                languageCode: languageCode,
                modelURL: primaryModelURL,
                executableURL: executableURL
            )
        } catch {
            guard fileManager.fileExists(atPath: fallbackModelURL.path) else {
                throw mapError(error)
            }

            logger.debug("Primary whisper.cpp model failed for \(audio.lastPathComponent, privacy: .public); retrying with fallback model")

            do {
                return try await transcribe(
                    audio: audio,
                    languageCode: languageCode,
                    modelURL: fallbackModelURL,
                    executableURL: executableURL
                )
            } catch {
                throw mapError(error)
            }
        }
    }

    private func transcribe(
        audio: URL,
        languageCode: String,
        modelURL: URL,
        executableURL: URL
    ) async throws -> Transcript {
        guard fileManager.fileExists(atPath: modelURL.path) else {
            throw ProcessingError.transcriptionFailed(
                "ClearVoice couldn’t find the local whisper.cpp model \(modelURL.lastPathComponent) on this Mac."
            )
        }

        let outputPrefix = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let jsonURL = outputPrefix.appendingPathExtension("json")

        defer {
            try? fileManager.removeItem(at: jsonURL)
        }

        let vadModelURL = resolveVADModelURL()
        let arguments = makeArguments(
            modelURL: modelURL,
            audioURL: audio,
            languageCode: languageCode,
            outputPrefix: outputPrefix,
            vadModelURL: vadModelURL
        )

        try await runner(
            executableURL,
            arguments,
            runtimeEnvironment(for: executableURL)
        )

        guard fileManager.fileExists(atPath: jsonURL.path) else {
            throw ProcessingError.transcriptionFailed(
                "ClearVoice ran whisper.cpp but couldn’t find the JSON transcript output."
            )
        }

        let data = try Data(contentsOf: jsonURL)
        let payload: WhisperCppPayload

        do {
            payload = try JSONDecoder().decode(WhisperCppPayload.self, from: data)
        } catch {
            logger.error("Failed to decode whisper.cpp JSON output for \(audio.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw ProcessingError.transcriptionFailed(
                "ClearVoice received transcript data from whisper.cpp, but the JSON output wasn’t in the format the app expected."
            )
        }

        let segments = payload.transcription.map { segment in
            TranscriptSegment(
                text: segment.text.trimmingCharacters(in: .whitespacesAndNewlines),
                startMilliseconds: segment.offsets.from,
                endMilliseconds: segment.offsets.to,
                tokens: segment.tokens
                    .unwrap(or: [])
                    .filter { !$0.text.hasPrefix("[_") }
                    .map {
                        TranscriptToken(
                            text: $0.text,
                            probability: $0.p,
                            startMilliseconds: $0.offsets?.from,
                            endMilliseconds: $0.offsets?.to
                        )
                    }
            )
        }
        .filter { !$0.text.isEmpty }

        let combinedText = segments
            .map(\.text)
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !combinedText.isEmpty else {
            throw ProcessingError.transcriptionFailed("ClearVoice returned an empty Marathi transcript.")
        }

        return Transcript(
            text: combinedText,
            detectedLanguage: languageCode,
            confidence: confidence(from: segments),
            segments: segments
        )
    }

    private func resolvedLanguageCode(for language: LanguageSelection) throws -> String {
        switch language {
        case .auto:
            return "mr"
        case .specific(let code):
            guard code == "mr" else {
                throw TranscriptionError.languageNotSupported
            }
            return code
        }
    }

    private func confidence(from segments: [TranscriptSegment]) -> Double {
        let probabilities = segments
            .flatMap(\.tokens)
            .map(\.probability)

        guard !probabilities.isEmpty else {
            return 0.75
        }

        let average = probabilities.reduce(0, +) / Double(probabilities.count)
        return min(max(average, 0), 1)
    }

    private func makeArguments(
        modelURL: URL,
        audioURL: URL,
        languageCode: String,
        outputPrefix: URL,
        vadModelURL: URL?
    ) -> [String] {
        var arguments: [String] = [
            "-m", modelURL.path,
            "-f", audioURL.path,
            "-l", languageCode,
            "-t", String(threads),
            "-oj",
            "-of", outputPrefix.path,
        ]

        arguments.append(contentsOf: decodeProfile.arguments(vadModelURL: vadModelURL))
        return arguments
    }

    private func resolveVADModelURL() -> URL? {
        for candidate in vadModelNameCandidates {
            let url = modelDirectory.appendingPathComponent(candidate)
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }

        if decodeProfile.enableVAD {
            logger.debug("No local whisper VAD model found in \(self.modelDirectory.path, privacy: .public); continuing without VAD")
        }

        return nil
    }

    private func runtimeEnvironment(for executableURL: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let libraryPaths = Self.librarySearchPaths(for: executableURL)
        if !libraryPaths.isEmpty {
            let current = environment["DYLD_LIBRARY_PATH"].map { [$0] } ?? []
            environment["DYLD_LIBRARY_PATH"] = (libraryPaths + current).joined(separator: ":")
        }
        return environment
    }

    private func mapError(_ error: Error) -> Error {
        if let transcriptionError = error as? TranscriptionError {
            return transcriptionError
        }

        if let processingError = error as? ProcessingError {
            return processingError
        }

        return ProcessingError.transcriptionFailed(
            "ClearVoice couldn’t run whisper.cpp: \(error.localizedDescription)"
        )
    }

    static func resolveExecutableURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        var candidates: [String] = []

        if let explicitPath = environment["WHISPER_CPP_CLI_PATH"], !explicitPath.isEmpty {
            candidates.append(explicitPath)
        }

        if let path = environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map { String($0) + "/whisper-cli" })
        }

        candidates.append(contentsOf: [
            "/tmp/clearvoice_whispercpp_build_v184/bin/whisper-cli",
            NSString(string: "~/Library/Application Support/ClearVoice/Tools/whisper.cpp/bin/whisper-cli").expandingTildeInPath,
            "/opt/homebrew/bin/whisper-cli",
            "/usr/local/bin/whisper-cli",
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

    private static func librarySearchPaths(for executableURL: URL) -> [String] {
        let buildRoot = executableURL.deletingLastPathComponent().deletingLastPathComponent()
        let candidates = [
            buildRoot.appendingPathComponent("src"),
            buildRoot.appendingPathComponent("ggml/src"),
            buildRoot.appendingPathComponent("ggml/src/ggml-blas"),
            buildRoot.appendingPathComponent("ggml/src/ggml-metal"),
        ]

        return candidates
            .map(\.path)
            .filter { FileManager.default.fileExists(atPath: $0) }
    }

    private static func defaultThreadCount() -> Int {
        let cpuCount = ProcessInfo.processInfo.activeProcessorCount
        if cpuCount >= 8 {
            return 8
        }
        if cpuCount >= 6 {
            return 6
        }
        return max(4, cpuCount)
    }

    private static func defaultModelDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)

        return base
            .appendingPathComponent("ClearVoice", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("whisper.cpp", isDirectory: true)
    }

    private static let defaultRunner: Runner = { executableURL, arguments, environment in
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw ProcessingError.transcriptionFailed("ClearVoice couldn’t start whisper.cpp: \(error.localizedDescription)")
        }

        guard process.terminationStatus == 0 else {
            let detail = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?
            .trimmingCharacters(in: .whitespacesAndNewlines)

            if let detail, !detail.isEmpty {
                throw ProcessingError.transcriptionFailed("ClearVoice couldn’t transcribe this file with whisper.cpp: \(detail)")
            }

            throw ProcessingError.transcriptionFailed("ClearVoice couldn’t transcribe this file with whisper.cpp.")
        }
    }
}

extension WhisperCppTranscriptionService {
    struct DecodeProfile: Sendable {
        let maxContextTokens: Int?
        let temperature: Double
        let temperatureIncrement: Double
        let entropyThreshold: Double
        let logprobThreshold: Double
        let noSpeechThreshold: Double
        let enableVAD: Bool
        let vadThreshold: Double
        let vadMinSpeechDurationMS: Int
        let vadMinSilenceDurationMS: Int

        static let longFormNoisy = DecodeProfile(
            maxContextTokens: 0,
            temperature: 0.0,
            temperatureIncrement: 0.2,
            entropyThreshold: 2.4,
            logprobThreshold: -1.0,
            noSpeechThreshold: 0.6,
            enableVAD: true,
            vadThreshold: 0.5,
            vadMinSpeechDurationMS: 250,
            vadMinSilenceDurationMS: 500
        )

        func arguments(vadModelURL: URL?) -> [String] {
            var arguments: [String] = []

            if let maxContextTokens {
                arguments.append(contentsOf: ["--max-context", String(maxContextTokens)])
            }

            arguments.append(contentsOf: [
                "--temperature", Self.format(temperature),
                "--temperature-inc", Self.format(temperatureIncrement),
                "--entropy-thold", Self.format(entropyThreshold),
                "--logprob-thold", Self.format(logprobThreshold),
                "--no-speech-thold", Self.format(noSpeechThreshold),
            ])

            if enableVAD, let vadModelURL {
                arguments.append(contentsOf: [
                    "--vad",
                    "--vad-model", vadModelURL.path,
                    "--vad-threshold", Self.format(vadThreshold),
                    "--vad-min-speech-duration-ms", String(vadMinSpeechDurationMS),
                    "--vad-min-silence-duration-ms", String(vadMinSilenceDurationMS),
                ])
            }

            return arguments
        }

        private static func format(_ value: Double) -> String {
            if value.rounded() == value {
                return String(format: "%.1f", value)
            }

            return String(value)
        }
    }
}

private struct WhisperCppPayload: Decodable {
    let transcription: [WhisperCppSegment]
}

private struct WhisperCppSegment: Decodable {
    let text: String
    let offsets: WhisperCppOffsets
    let tokens: [WhisperCppToken]?
}

private struct WhisperCppOffsets: Decodable {
    let from: Int
    let to: Int
}

private struct WhisperCppToken: Decodable {
    let text: String
    let p: Double
    let offsets: WhisperCppOffsets?
}

private extension Optional {
    func unwrap(or defaultValue: Wrapped) -> Wrapped {
        self ?? defaultValue
    }
}

import Foundation
import Testing
@testable import ClearVoice

struct WhisperCppTranscriptionServiceTests {
    @Test
    func transcribeParsesTimestampedMarathiSegments() async throws {
        let harness = try WhisperCppHarness()
        let expectedJSON = """
        {
          "transcription": [
            {
              "text": "नमस्कार! तुमचं नाव काय आहे?",
              "offsets": { "from": 0, "to": 2500 },
              "tokens": [
                { "text": "[_BEG_]", "p": 0.9, "offsets": { "from": 0, "to": 0 } },
                { "text": "नमस्कार", "p": 0.82, "offsets": { "from": 0, "to": 900 } },
                { "text": "तुमचं", "p": 0.87, "offsets": { "from": 900, "to": 1500 } },
                { "text": "नाव", "p": 0.9, "offsets": { "from": 1500, "to": 1900 } },
                { "text": "काय", "p": 0.91, "offsets": { "from": 1900, "to": 2200 } },
                { "text": "आहे?", "p": 0.93, "offsets": { "from": 2200, "to": 2500 } }
              ]
            }
          ]
        }
        """

        let service = WhisperCppTranscriptionService(
            executableURL: harness.executableURL,
            modelDirectory: harness.modelDirectory,
            runner: { _, arguments, _ in
                let outputPrefixArgument = try argumentValue(after: "-of", in: arguments)
                let outputPrefix = try #require(outputPrefixArgument)
                let jsonURL = URL(fileURLWithPath: outputPrefix).appendingPathExtension("json")
                let data = try #require(expectedJSON.data(using: .utf8))
                try data.write(to: jsonURL)
            }
        )

        let transcript = try await service.transcribe(
            audio: harness.audioURL,
            language: .specific("mr")
        )

        #expect(transcript.detectedLanguage == "mr")
        #expect(transcript.text == "नमस्कार! तुमचं नाव काय आहे?")
        #expect(transcript.segments.count == 1)
        #expect(transcript.segments.first?.startMilliseconds == 0)
        #expect(transcript.segments.first?.endMilliseconds == 2500)
        #expect(transcript.segments.first?.tokens.count == 5)
        #expect(transcript.exportText == "[00:00:00.000 --> 00:00:02.500]   नमस्कार! तुमचं नाव काय आहे?")
    }

    @Test
    func transcribeRetriesWithFallbackModelAfterPrimaryFailure() async throws {
        let harness = try WhisperCppHarness()
        let runner = FallbackRunner()
        let service = WhisperCppTranscriptionService(
            executableURL: harness.executableURL,
            modelDirectory: harness.modelDirectory,
            runner: { executableURL, arguments, environment in
                try await runner.run(executableURL: executableURL, arguments: arguments, environment: environment)
            }
        )

        let transcript = try await service.transcribe(
            audio: harness.audioURL,
            language: .specific("mr")
        )

        #expect(transcript.text == "फॉलबॅक यशस्वी झाला")
        let attemptedModels = await runner.attemptedModels
        #expect(attemptedModels == ["ggml-large-v3-turbo.bin", "ggml-large-v3.bin"])
    }

    @Test
    func nonMarathiSelectionThrowsLanguageNotSupported() async throws {
        let harness = try WhisperCppHarness()
        let service = WhisperCppTranscriptionService(
            executableURL: harness.executableURL,
            modelDirectory: harness.modelDirectory,
            runner: { _, _, _ in
                Issue.record("Runner should not be called for non-Marathi input selection.")
            }
        )

        await #expect(throws: TranscriptionError.languageNotSupported) {
            _ = try await service.transcribe(
                audio: harness.audioURL,
                language: .specific("hi")
            )
        }
    }

    @Test
    func missingExecutableProducesActionableError() async throws {
        let harness = try WhisperCppHarness()
        let service = WhisperCppTranscriptionService(
            executableURL: nil,
            modelDirectory: harness.modelDirectory,
            runner: { _, _, _ in
                Issue.record("Runner should not be called when whisper.cpp is missing.")
            }
        )

        await #expect(throws: ProcessingError.transcriptionFailed("ClearVoice couldn’t find the local whisper.cpp transcription engine on this Mac.")) {
            _ = try await service.transcribe(
                audio: harness.audioURL,
                language: .specific("mr")
            )
        }
    }
}

private struct WhisperCppHarness {
    let root: URL
    let modelDirectory: URL
    let audioURL: URL
    let executableURL: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        modelDirectory = root.appendingPathComponent("models", isDirectory: true)
        audioURL = root.appendingPathComponent("sample.wav")
        executableURL = root.appendingPathComponent("whisper-cli")

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: audioURL)
        try Data().write(to: modelDirectory.appendingPathComponent("ggml-large-v3-turbo.bin"))
        try Data().write(to: modelDirectory.appendingPathComponent("ggml-large-v3.bin"))
        try Data().write(to: executableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
    }
}

private actor FallbackRunner {
    private(set) var attemptedModels: [String] = []

    func run(executableURL _: URL, arguments: [String], environment _: [String: String]) async throws {
        let modelPathArgument = try argumentValue(after: "-m", in: arguments)
        let modelPath = try #require(modelPathArgument)
        attemptedModels.append(URL(fileURLWithPath: modelPath).lastPathComponent)

        if modelPath.hasSuffix("ggml-large-v3-turbo.bin") {
            throw ProcessingError.transcriptionFailed("Primary model failure")
        }

        let outputPrefixArgument = try argumentValue(after: "-of", in: arguments)
        let outputPrefix = try #require(outputPrefixArgument)
        let jsonURL = URL(fileURLWithPath: outputPrefix).appendingPathExtension("json")
        let json = """
        {
          "transcription": [
            {
              "text": "फॉलबॅक यशस्वी झाला",
              "offsets": { "from": 0, "to": 1800 },
              "tokens": [
                { "text": "फॉलबॅक", "p": 0.88, "offsets": { "from": 0, "to": 800 } },
                { "text": "यशस्वी", "p": 0.9, "offsets": { "from": 800, "to": 1300 } },
                { "text": "झाला", "p": 0.92, "offsets": { "from": 1300, "to": 1800 } }
              ]
            }
          ]
        }
        """
        let data = try #require(json.data(using: .utf8))
        try data.write(to: jsonURL)
    }
}

private func argumentValue(after flag: String, in arguments: [String]) throws -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
        return nil
    }

    return arguments[index + 1]
}

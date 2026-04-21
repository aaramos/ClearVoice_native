import Foundation
import Testing
@testable import ClearVoice

struct LocalNLLBTranslationServiceTests {
    @Test
    func translateSegmentsUsesNLLBLanguageCodesAndReturnsBatchedOutput() async throws {
        let harness = try RuntimeHarness()
        let recorder = RunnerRecorder(
            outputs: [
                #"{"translations":["Hello there","What is your name?"]}"#,
            ]
        )
        let service = LocalNLLBTranslationService(
            fileManager: .default,
            pythonExecutableURL: harness.pythonURL,
            helperScriptURL: harness.helperScriptURL,
            modelDirectory: harness.modelDirectory,
            maxBatchSegments: 4,
            maxBatchCharacters: 10_000
        ) { executableURL, arguments, stdinData, _ in
            try await recorder.run(executableURL: executableURL, arguments: arguments, stdinData: stdinData)
        }

        let translations = try await service.translateSegments(
            ["नमस्कार", "तुमचं नाव काय आहे?"],
            from: "mr",
            to: "en"
        )

        #expect(translations == ["Hello there", "What is your name?"])

        let invocation = try #require(await recorder.invocations.first)
        #expect(invocation.executableURL == harness.pythonURL)
        #expect(invocation.arguments.contains("--source-lang"))
        #expect(invocation.arguments.contains("mar_Deva"))
        #expect(invocation.arguments.contains("--target-lang"))
        #expect(invocation.arguments.contains("eng_Latn"))

        let request = try JSONDecoder().decode(RecordedRequest.self, from: invocation.stdinData)
        #expect(request.segments == ["नमस्कार", "तुमचं नाव काय आहे?"])
    }

    @Test
    func translateSegmentsSplitsLargeRequestsIntoMultipleBatches() async throws {
        let harness = try RuntimeHarness()
        let recorder = RunnerRecorder(
            outputs: [
                #"{"translations":["EN: one","EN: two"]}"#,
                #"{"translations":["EN: three"]}"#,
            ]
        )
        let service = LocalNLLBTranslationService(
            fileManager: .default,
            pythonExecutableURL: harness.pythonURL,
            helperScriptURL: harness.helperScriptURL,
            modelDirectory: harness.modelDirectory,
            maxBatchSegments: 2,
            maxBatchCharacters: 10_000
        ) { executableURL, arguments, stdinData, _ in
            try await recorder.run(executableURL: executableURL, arguments: arguments, stdinData: stdinData)
        }

        let translations = try await service.translateSegments(
            ["एक", "दोन", "तीन"],
            from: "mr",
            to: "en"
        )

        #expect(translations == ["EN: one", "EN: two", "EN: three"])
        #expect(await recorder.invocations.count == 2)
    }

    @Test
    func translateSegmentsRejectsUnexpectedTranslationCount() async throws {
        let harness = try RuntimeHarness()
        let service = LocalNLLBTranslationService(
            fileManager: .default,
            pythonExecutableURL: harness.pythonURL,
            helperScriptURL: harness.helperScriptURL,
            modelDirectory: harness.modelDirectory,
            maxBatchSegments: 4,
            maxBatchCharacters: 10_000
        ) { _, _, _, _ in
            Data(#"{"translations":["only one"]}"#.utf8)
        }

        await #expect(throws: ProcessingError.translationFailed("ClearVoice’s local NLLB translator returned an unexpected number of English segments.")) {
            _ = try await service.translateSegments(
                ["एक", "दोन"],
                from: "mr",
                to: "en"
            )
        }
    }

    @Test
    func translateSegmentsPreservesEmptySegmentPositions() async throws {
        let harness = try RuntimeHarness()
        let recorder = RunnerRecorder(
            outputs: [
                #"{"translations":["Hello there","How are you?"]}"#,
            ]
        )
        let service = LocalNLLBTranslationService(
            fileManager: .default,
            pythonExecutableURL: harness.pythonURL,
            helperScriptURL: harness.helperScriptURL,
            modelDirectory: harness.modelDirectory,
            maxBatchSegments: 4,
            maxBatchCharacters: 10_000
        ) { executableURL, arguments, stdinData, _ in
            try await recorder.run(executableURL: executableURL, arguments: arguments, stdinData: stdinData)
        }

        let translations = try await service.translateSegments(
            ["नमस्कार", "   ", "तू कसा आहेस?"],
            from: "mr",
            to: "en"
        )

        #expect(translations == ["Hello there", "", "How are you?"])

        let invocation = try #require(await recorder.invocations.first)
        let request = try JSONDecoder().decode(RecordedRequest.self, from: invocation.stdinData)
        #expect(request.segments == ["नमस्कार", "तू कसा आहेस?"])
    }
}

private struct RecordedRequest: Decodable {
    let segments: [String]
}

private struct RunnerInvocation: Sendable {
    let executableURL: URL
    let arguments: [String]
    let stdinData: Data
}

private actor RunnerRecorder {
    private(set) var invocations: [RunnerInvocation] = []
    private var outputs: [String]

    init(outputs: [String]) {
        self.outputs = outputs
    }

    func run(executableURL: URL, arguments: [String], stdinData: Data) async throws -> Data {
        invocations.append(
            RunnerInvocation(
                executableURL: executableURL,
                arguments: arguments,
                stdinData: stdinData
            )
        )

        guard !outputs.isEmpty else {
            throw ProcessingError.translationFailed("No stubbed translation output.")
        }

        let output = outputs.removeFirst()
        return Data(output.utf8)
    }
}

private struct RuntimeHarness {
    let root: URL
    let pythonURL: URL
    let helperScriptURL: URL
    let modelDirectory: URL

    init() throws {
        let fileManager = FileManager.default
        root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        pythonURL = root.appendingPathComponent("python")
        helperScriptURL = root.appendingPathComponent("nllb_translate.py")
        modelDirectory = root.appendingPathComponent("model", isDirectory: true)

        try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        try Data().write(to: pythonURL)
        try Data().write(to: helperScriptURL)
        try Data().write(to: modelDirectory.appendingPathComponent("model.bin"))
        try Data("{}".utf8).write(to: modelDirectory.appendingPathComponent("config.json"))
        try Data("{}".utf8).write(to: modelDirectory.appendingPathComponent("tokenizer.json"))
        try Data().write(to: modelDirectory.appendingPathComponent("sentencepiece.bpe.model"))
    }
}

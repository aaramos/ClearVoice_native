import Foundation
import Testing
@testable import ClearVoice

struct BatchProcessorTests {
    @Test
    func processorNeverExceedsConfiguredConcurrency() async throws {
        let harness = try BatchProcessorHarness(fileCount: 5, enhancementMethod: .dfn)
        let enhancement = TrackingComparisonEnhancementService(outputSuffix: "DFN", delayMilliseconds: 200)
        let services = ServiceBundle(
            audioEnhancement: StubAudioEnhancementService(),
            comparisonEnhancements: [enhancement],
            speechPipeline: StubSpeechPipelineService(),
            export: DefaultExportService()
        )
        let processor = try harness.makeProcessor(services: services, maxConcurrency: 3)
        let recorder = ItemRecorder()

        await processor.run(files: harness.items) { item in
            await recorder.record(item)
        }

        let maxActive = await enhancement.maxActiveCount
        let latestItems = await recorder.items()

        #expect(maxActive == 3)
        #expect(latestItems.count == 5)
        #expect(latestItems.allSatisfy { $0.stage == .complete })
    }

    @Test
    func processorIsolatesFailuresToTheImpactedFile() async throws {
        let harness = try BatchProcessorHarness(fileCount: 4, enhancementMethod: .dfn)
        let services = ServiceBundle(
            audioEnhancement: StubAudioEnhancementService(),
            comparisonEnhancements: [SelectiveFailureComparisonEnhancementService(outputSuffix: "DFN", failingBasename: "sample_2")],
            speechPipeline: StubSpeechPipelineService(),
            export: DefaultExportService()
        )
        let processor = try harness.makeProcessor(services: services, maxConcurrency: 3)
        let recorder = ItemRecorder()

        await processor.run(files: harness.items) { item in
            await recorder.record(item)
        }

        let latestItems = await recorder.itemsByBasename()

        #expect(latestItems["sample_2"]?.stage == .failed(error: .enhancementFailed("Stubbed enhancement failure")))
        #expect(latestItems["sample_1"]?.stage == .complete)
        #expect(latestItems["sample_3"]?.stage == .complete)
        #expect(latestItems["sample_4"]?.stage == .complete)
    }

    @Test
    func processingWritesConfiguredVariantWithoutTranscript() async throws {
        let harness = try BatchProcessorHarness(fileCount: 1, enhancementMethod: .hybrid)
        let services = ServiceBundle(
            audioEnhancement: StubAudioEnhancementService(),
            comparisonEnhancements: [
                StubComparisonEnhancementService(outputSuffix: "DFN"),
                StubComparisonEnhancementService(outputSuffix: "HYBRID"),
            ],
            speechPipeline: StubSpeechPipelineService(),
            summaryPlaceholder: "Placeholder summary.",
            export: DefaultExportService()
        )
        let processor = try harness.makeProcessor(services: services, maxConcurrency: 1)
        let recorder = ItemRecorder()

        await processor.run(files: harness.items) { item in
            await recorder.record(item)
        }

        let latestItems = await recorder.itemsByBasename()
        let item = try #require(latestItems["sample_1"])
        let outputFolder = try #require(item.outputFolderURL)

        #expect(item.stage == .complete)
        #expect(FileManager.default.fileExists(atPath: outputFolder.appendingPathComponent("sample_1_HYBRID.m4a").path))
        #expect(!FileManager.default.fileExists(atPath: outputFolder.appendingPathComponent("sample_1_DFN.m4a").path))
        #expect(!FileManager.default.fileExists(atPath: outputFolder.appendingPathComponent("sample_1_MIN.m4a").path))
        #expect(!FileManager.default.fileExists(atPath: outputFolder.appendingPathComponent("sample_1_MAX.m4a").path))
        #expect(!FileManager.default.fileExists(atPath: outputFolder.appendingPathComponent("sample_1_transcript.txt").path))
        #expect(item.originalTranscript == nil)
    }

    @Test
    func processingWritesOnlySelectedEnhancementVariant() async throws {
        let harness = try BatchProcessorHarness(fileCount: 1, enhancementMethod: .dfn)
        let services = ServiceBundle(
            audioEnhancement: StubAudioEnhancementService(),
            comparisonEnhancements: [
                StubComparisonEnhancementService(outputSuffix: "DFN"),
                StubComparisonEnhancementService(outputSuffix: "HYBRID"),
            ],
            speechPipeline: StubSpeechPipelineService(),
            export: DefaultExportService()
        )
        let processor = try harness.makeProcessor(services: services, maxConcurrency: 1)
        let recorder = ItemRecorder()

        await processor.run(files: harness.items) { item in
            await recorder.record(item)
        }

        let latestItems = await recorder.itemsByBasename()
        let item = try #require(latestItems["sample_1"])
        let outputFolder = try #require(item.outputFolderURL)

        #expect(item.stage == .complete)
        #expect(FileManager.default.fileExists(atPath: outputFolder.appendingPathComponent("sample_1_DFN.m4a").path))
        #expect(!FileManager.default.fileExists(atPath: outputFolder.appendingPathComponent("sample_1_HYBRID.m4a").path))
    }

    @Test
    func enhancementOnlyBatchDoesNotAttemptSpeechPipeline() async throws {
        let harness = try BatchProcessorHarness(fileCount: 1, enhancementMethod: .dfn, transcriptionEnabled: false)
        let transcriptionPrep = TrackingTranscriptionPreparationService()
        let speechPipeline = TrackingSpeechPipelineService()
        let services = ServiceBundle(
            audioEnhancement: StubAudioEnhancementService(),
            comparisonEnhancements: [
                StubComparisonEnhancementService(outputSuffix: "DFN"),
                StubComparisonEnhancementService(outputSuffix: "HYBRID"),
            ],
            transcriptionPreparationService: transcriptionPrep,
            speechPipeline: speechPipeline,
            export: DefaultExportService()
        )
        let processor = try harness.makeProcessor(services: services, maxConcurrency: 1)
        let recorder = ItemRecorder()

        await processor.run(files: harness.items) { item in
            await recorder.record(item)
        }

        let latestItems = await recorder.itemsByBasename()
        let item = try #require(latestItems["sample_1"])
        let outputFolder = try #require(item.outputFolderURL)

        #expect(item.stage == .complete)
        #expect(FileManager.default.fileExists(atPath: outputFolder.appendingPathComponent("sample_1_DFN.m4a").path))
        #expect(!FileManager.default.fileExists(atPath: outputFolder.appendingPathComponent("sample_1_transcript.txt").path))
        let preparedInputs = await transcriptionPrep.preparedInputs
        #expect(preparedInputs.isEmpty)
        let pipelineInputs = await speechPipeline.audioInputs
        #expect(pipelineInputs.isEmpty)
    }

    @Test
    func speechPipelineFailureDoesNotBlockEnhancementOnlyBatch() async throws {
        let harness = try BatchProcessorHarness(fileCount: 1, enhancementMethod: .dfn)
        let services = ServiceBundle(
            audioEnhancement: StubAudioEnhancementService(),
            comparisonEnhancements: [
                StubComparisonEnhancementService(outputSuffix: "DFN"),
                StubComparisonEnhancementService(outputSuffix: "HYBRID"),
            ],
            speechPipeline: FailingSpeechPipelineService(),
            export: DefaultExportService()
        )
        let processor = try harness.makeProcessor(services: services, maxConcurrency: 1)
        let recorder = ItemRecorder()

        await processor.run(files: harness.items) { item in
            await recorder.record(item)
        }

        let latestItems = await recorder.itemsByBasename()
        let item = try #require(latestItems["sample_1"])

        #expect(item.stage == .complete)
    }
}

private struct BatchProcessorHarness {
    let root: URL
    let sourceFolder: URL
    let outputFolder: URL
    let items: [AudioFileItem]
    let enhancementMethod: EnhancementMethod
    let transcriptionEnabled: Bool

    init(
        fileCount: Int,
        enhancementMethod: EnhancementMethod = .hybrid,
        transcriptionEnabled: Bool = false
    ) throws {
        let fileManager = FileManager.default
        root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        sourceFolder = root.appendingPathComponent("source", isDirectory: true)
        outputFolder = root.appendingPathComponent("output", isDirectory: true)
        self.enhancementMethod = enhancementMethod
        self.transcriptionEnabled = transcriptionEnabled

        try fileManager.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outputFolder, withIntermediateDirectories: true)

        var generatedItems: [AudioFileItem] = []

        for index in 1...fileCount {
            let basename = "sample_\(index)"
            let sourceURL = sourceFolder.appendingPathComponent("\(basename).wav")
            try Data("stub".utf8).write(to: sourceURL)
            generatedItems.append(
                AudioFileItem(
                    id: UUID(),
                    sourceURL: sourceURL,
                    durationSeconds: nil,
                    stage: .pending
                )
            )
        }

        items = generatedItems
    }

    func makeProcessor(services: ServiceBundle, maxConcurrency: Int) throws -> BatchProcessor {
        let configuration = BatchConfiguration(
            sourceFolder: sourceFolder,
            outputFolder: outputFolder,
            enhancementMethod: enhancementMethod,
            transcriptionEnabled: transcriptionEnabled,
            inputLanguage: .specific("mr"),
            outputLanguage: "en",
            maxConcurrency: maxConcurrency,
            recursiveScan: true,
            preserveChannels: false
        )
        let resolver = try OutputPathResolver(outputRoot: outputFolder)
        return BatchProcessor(config: configuration, resolver: resolver, services: services)
    }
}

private actor ItemRecorder {
    private var latestById: [UUID: AudioFileItem] = [:]

    func record(_ item: AudioFileItem) {
        latestById[item.id] = item
    }

    func items() -> [AudioFileItem] {
        latestById.values.sorted { $0.basename < $1.basename }
    }

    func itemsByBasename() -> [String: AudioFileItem] {
        Dictionary(uniqueKeysWithValues: latestById.values.map { ($0.basename, $0) })
    }
}

private actor TrackingComparisonEnhancementService: ComparisonEnhancementService {
    let outputSuffix: String
    private let delayMilliseconds: UInt64
    private var activeCount = 0
    private(set) var maxActiveCount = 0

    init(outputSuffix: String, delayMilliseconds: UInt64) {
        self.outputSuffix = outputSuffix
        self.delayMilliseconds = delayMilliseconds
    }

    func enhance(input: URL, output: URL) async throws {
        activeCount += 1
        maxActiveCount = max(maxActiveCount, activeCount)
        defer { activeCount -= 1 }

        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: output)
        try Data("clean".utf8).write(to: output)
        try await Task.sleep(for: .milliseconds(delayMilliseconds))
    }
}

private actor SelectiveFailureComparisonEnhancementService: ComparisonEnhancementService {
    let outputSuffix: String
    let failingBasename: String

    init(outputSuffix: String, failingBasename: String) {
        self.outputSuffix = outputSuffix
        self.failingBasename = failingBasename
    }

    func enhance(input: URL, output: URL) async throws {
        if output.lastPathComponent.hasPrefix("\(failingBasename)_") {
            throw ProcessingError.enhancementFailed("Stubbed enhancement failure")
        }

        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: output)
        try Data("clean".utf8).write(to: output)
    }
}

private actor TrackingSpeechPipelineService: SpeechPipelineService {
    private(set) var audioInputs: [String] = []

    func process(audio: URL, language: LanguageSelection) async throws -> SpeechPipelineOutput {
        audioInputs.append(audio.lastPathComponent)
        return SpeechPipelineOutput(
            transcript: Transcript(
                text: "नमस्कार! तुमचं नाव काय आहे?",
                detectedLanguage: "mr",
                confidence: 0.92,
                segments: [
                    TranscriptSegment(
                        text: "नमस्कार! तुमचं नाव काय आहे?",
                        startMilliseconds: 0,
                        endMilliseconds: 2500
                    )
                ]
            ),
            englishTranslation: nil
        )
    }
}

private actor CoordinatedSpeechPipelineService: SpeechPipelineService {
    private let coordinator: TranslationPhaseCoordinator

    init(coordinator: TranslationPhaseCoordinator) {
        self.coordinator = coordinator
    }

    func process(audio: URL, language: LanguageSelection) async throws -> SpeechPipelineOutput {
        await coordinator.transcriptionStarted()
        try await Task.sleep(for: .milliseconds(50))
        await coordinator.transcriptionFinished()

        return SpeechPipelineOutput(
            transcript: Transcript(
                text: "नमस्कार! तुमचं नाव काय आहे?",
                detectedLanguage: "mr",
                confidence: 0.92,
                segments: [
                    TranscriptSegment(
                        text: "नमस्कार! तुमचं नाव काय आहे?",
                        startMilliseconds: 0,
                        endMilliseconds: 2500
                    )
                ]
            ),
            englishTranslation: nil
        )
    }
}

private actor FailingSpeechPipelineService: SpeechPipelineService {
    func process(audio: URL, language: LanguageSelection) async throws -> SpeechPipelineOutput {
        throw ProcessingError.transcriptionFailed("Stubbed speech pipeline failure")
    }
}

private actor StubComparisonEnhancementService: ComparisonEnhancementService {
    let outputSuffix: String

    init(outputSuffix: String) {
        self.outputSuffix = outputSuffix
    }

    func enhance(input: URL, output: URL) async throws {
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: output)
        try Data("deepfilter".utf8).write(to: output)
    }
}

private actor TrackingTranscriptionPreparationService: TranscriptionPreparationService {
    private(set) var preparedInputs: [(source: URL, prepared: URL)] = []

    func prepare(_ sourceURL: URL) async throws -> (url: URL, requiresCleanup: Bool) {
        let preparedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        try Data("prepared".utf8).write(to: preparedURL)
        preparedInputs.append((sourceURL, preparedURL))
        return (preparedURL, true)
    }
}

private actor PrefixTranslationService: TranslationService {
    func translate(text: String, from sourceLanguage: String, to targetLanguage: String) async throws -> String {
        "EN: \(text)"
    }
}

private actor CoordinatedTranslationService: TranslationService {
    private let coordinator: TranslationPhaseCoordinator

    init(coordinator: TranslationPhaseCoordinator) {
        self.coordinator = coordinator
    }

    func translate(text: String, from sourceLanguage: String, to targetLanguage: String) async throws -> String {
        await coordinator.translationStarted()
        return "EN: \(text)"
    }
}

private actor TranslationPhaseCoordinator {
    let totalFiles: Int
    private(set) var completedTranscriptions = 0
    private(set) var translationStartedBeforeAllTranscriptions = false
    private(set) var translationInvocationCount = 0

    init(totalFiles: Int) {
        self.totalFiles = totalFiles
    }

    func transcriptionStarted() {}

    func transcriptionFinished() {
        completedTranscriptions += 1
    }

    func translationStarted() {
        translationInvocationCount += 1
        if completedTranscriptions < totalFiles {
            translationStartedBeforeAllTranscriptions = true
        }
    }
}

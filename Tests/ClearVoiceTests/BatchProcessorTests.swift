import Foundation
import Testing
@testable import ClearVoice

struct BatchProcessorTests {
    @Test
    func processorNeverExceedsConfiguredConcurrency() async throws {
        let harness = try BatchProcessorHarness(fileCount: 5)
        let enhancement = TrackingEnhancementService(delayMilliseconds: 200)
        let services = ServiceBundle(
            audioEnhancement: enhancement,
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
        let harness = try BatchProcessorHarness(fileCount: 4)
        let services = ServiceBundle(
            audioEnhancement: SelectiveFailureEnhancementService(failingBasename: "sample_2"),
            speechPipeline: FailingIfCalledSpeechPipelineService(),
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
    func enhancementOnlyWritesAllVariantsAndSkipsTranscriptExport() async throws {
        let harness = try BatchProcessorHarness(fileCount: 1)
        let services = ServiceBundle(
            audioEnhancement: StubAudioEnhancementService(),
            speechPipeline: FailingIfCalledSpeechPipelineService(),
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
        #expect(FileManager.default.fileExists(atPath: outputFolder.appendingPathComponent("sample_1_MIN.m4a").path))
        #expect(FileManager.default.fileExists(atPath: outputFolder.appendingPathComponent("sample_1_BALANCED.m4a").path))
        #expect(FileManager.default.fileExists(atPath: outputFolder.appendingPathComponent("sample_1_STRONG.m4a").path))
        #expect(FileManager.default.fileExists(atPath: outputFolder.appendingPathComponent("sample_1_MAX.m4a").path))
        #expect(!FileManager.default.fileExists(atPath: outputFolder.appendingPathComponent("sample_1_transcript.txt").path))
    }

    @Test
    func enhancementOnlyWritesDeepFilterVariantWhenConfigured() async throws {
        let harness = try BatchProcessorHarness(fileCount: 1)
        let services = ServiceBundle(
            audioEnhancement: StubAudioEnhancementService(),
            comparisonEnhancements: [
                StubComparisonEnhancementService(outputSuffix: "DFN"),
                StubComparisonEnhancementService(outputSuffix: "HYBRID"),
            ],
            speechPipeline: FailingIfCalledSpeechPipelineService(),
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
        #expect(FileManager.default.fileExists(atPath: outputFolder.appendingPathComponent("sample_1_HYBRID.m4a").path))
    }

    @Test
    func speechPipelineIsNotInvokedDuringEnhancementOnlyRuns() async throws {
        let harness = try BatchProcessorHarness(fileCount: 1)
        let services = ServiceBundle(
            audioEnhancement: StubAudioEnhancementService(),
            speechPipeline: FailingIfCalledSpeechPipelineService(),
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

    init(fileCount: Int) throws {
        let fileManager = FileManager.default
        root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        sourceFolder = root.appendingPathComponent("source", isDirectory: true)
        outputFolder = root.appendingPathComponent("output", isDirectory: true)

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
            intensity: .balanced,
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

private actor TrackingEnhancementService: AudioEnhancementService {
    private let delayMilliseconds: UInt64
    private var activeCount = 0
    private(set) var maxActiveCount = 0

    init(delayMilliseconds: UInt64) {
        self.delayMilliseconds = delayMilliseconds
    }

    func enhance(input: URL, output: URL, intensity: Intensity) async throws {
        activeCount += 1
        maxActiveCount = max(maxActiveCount, activeCount)
        defer { activeCount -= 1 }

        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: output)
        try Data("clean".utf8).write(to: output)
        try await Task.sleep(for: .milliseconds(delayMilliseconds))
    }
}

private actor SelectiveFailureEnhancementService: AudioEnhancementService {
    let failingBasename: String

    init(failingBasename: String) {
        self.failingBasename = failingBasename
    }

    func enhance(input: URL, output: URL, intensity: Intensity) async throws {
        if output.lastPathComponent.hasPrefix("\(failingBasename)_") {
            throw ProcessingError.enhancementFailed("Stubbed enhancement failure")
        }

        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: output)
        try Data("clean".utf8).write(to: output)
    }
}

private actor FailingIfCalledSpeechPipelineService: SpeechPipelineService {
    func process(audio: URL, language: LanguageSelection) async throws -> SpeechPipelineOutput {
        Issue.record("Speech pipeline should not be called in enhancement-only mode.")
        throw ProcessingError.transcriptionFailed("Speech pipeline should not be called.")
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

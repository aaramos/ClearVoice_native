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
    func processingWritesConfiguredVariantWithoutExtraTextArtifacts() async throws {
        let harness = try BatchProcessorHarness(fileCount: 1, enhancementMethod: .hybrid)
        let services = ServiceBundle(
            audioEnhancement: StubAudioEnhancementService(),
            comparisonEnhancements: [
                StubComparisonEnhancementService(outputSuffix: "DFN"),
                StubComparisonEnhancementService(outputSuffix: "HYBRID"),
            ],
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
        let processedAudioURL = try #require(item.processedAudioURL)

        #expect(item.stage == .complete)
        #expect(outputFolder == harness.outputFolder)
        #expect(FileManager.default.fileExists(atPath: processedAudioURL.path))
        #expect(FileManager.default.fileExists(atPath: outputFolder.appendingPathComponent("sample_1_HYBRID.m4a").path))
        #expect(!FileManager.default.fileExists(atPath: outputFolder.appendingPathComponent("sample_1_DFN.m4a").path))
        #expect(!FileManager.default.fileExists(atPath: outputFolder.appendingPathComponent("sample_1_MIN.m4a").path))
        #expect(!FileManager.default.fileExists(atPath: outputFolder.appendingPathComponent("sample_1_MAX.m4a").path))
        #expect(!FileManager.default.fileExists(atPath: outputFolder.appendingPathComponent("sample_1.wav").path))
        #expect(!FileManager.default.fileExists(atPath: outputFolder.appendingPathComponent("sample_1_transcript.txt").path))
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
        let processedAudioURL = try #require(item.processedAudioURL)

        #expect(item.stage == .complete)
        #expect(outputFolder == harness.outputFolder)
        #expect(FileManager.default.fileExists(atPath: processedAudioURL.path))
        #expect(FileManager.default.fileExists(atPath: outputFolder.appendingPathComponent("sample_1_DFN.m4a").path))
        #expect(!FileManager.default.fileExists(atPath: outputFolder.appendingPathComponent("sample_1_HYBRID.m4a").path))
        #expect(!FileManager.default.fileExists(atPath: outputFolder.appendingPathComponent("sample_1.wav").path))
    }

    @Test
    func cancellingOneFileStopsThatFileAndCleansItsPartialOutput() async throws {
        let harness = try BatchProcessorHarness(fileCount: 2, enhancementMethod: .dfn)
        let enhancement = CancellableComparisonEnhancementService(outputSuffix: "DFN")
        let services = ServiceBundle(
            audioEnhancement: StubAudioEnhancementService(),
            comparisonEnhancements: [enhancement],
            export: DefaultExportService()
        )
        let processor = try harness.makeProcessor(services: services, maxConcurrency: 1)
        let recorder = ItemRecorder()

        let runTask = Task {
            await processor.run(files: harness.items) { item in
                await recorder.record(item)
            }
        }

        try await waitUntil { await enhancement.activeCount == 1 }
        await processor.cancelFile(id: harness.items[0].id)
        await runTask.value

        let latestItems = await recorder.itemsByBasename()

        #expect(latestItems["sample_1"]?.stage == .cancelled)
        #expect(latestItems["sample_2"]?.stage == .complete)
        #expect(!FileManager.default.fileExists(atPath: harness.outputFolder.appendingPathComponent("sample_1_DFN.m4a").path))
        #expect(FileManager.default.fileExists(atPath: harness.outputFolder.appendingPathComponent("sample_2_DFN.m4a").path))
    }

    @Test
    func cancellingBatchStopsRunningAndPendingFiles() async throws {
        let harness = try BatchProcessorHarness(fileCount: 3, enhancementMethod: .dfn)
        let enhancement = CancellableComparisonEnhancementService(outputSuffix: "DFN")
        let services = ServiceBundle(
            audioEnhancement: StubAudioEnhancementService(),
            comparisonEnhancements: [enhancement],
            export: DefaultExportService()
        )
        let processor = try harness.makeProcessor(services: services, maxConcurrency: 1)
        let recorder = ItemRecorder()

        let runTask = Task {
            await processor.run(files: harness.items) { item in
                await recorder.record(item)
            }
        }

        try await waitUntil { await enhancement.activeCount == 1 }
        await processor.cancelAll()
        await runTask.value

        let latestItems = await recorder.itemsByBasename()

        #expect(latestItems["sample_1"]?.stage == .cancelled)
        #expect(latestItems["sample_2"]?.stage == .cancelled)
        #expect(latestItems["sample_3"]?.stage == .cancelled)
        #expect(!FileManager.default.fileExists(atPath: harness.outputFolder.appendingPathComponent("sample_1_DFN.m4a").path))
        #expect(!FileManager.default.fileExists(atPath: harness.outputFolder.appendingPathComponent("sample_2_DFN.m4a").path))
        #expect(!FileManager.default.fileExists(atPath: harness.outputFolder.appendingPathComponent("sample_3_DFN.m4a").path))
    }

}

private struct BatchProcessorHarness {
    let root: URL
    let sourceFolder: URL
    let outputFolder: URL
    let items: [AudioFileItem]
    let enhancementMethod: EnhancementMethod

    init(
        fileCount: Int,
        enhancementMethod: EnhancementMethod = .hybrid
    ) throws {
        let fileManager = FileManager.default
        root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        sourceFolder = root.appendingPathComponent("source", isDirectory: true)
        outputFolder = root.appendingPathComponent("output", isDirectory: true)
        self.enhancementMethod = enhancementMethod

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
            maxConcurrency: maxConcurrency,
            recursiveScan: true,
            preserveChannels: false
        )
        let resolver = try OutputPathResolver(sourceRoot: sourceFolder, outputRoot: outputFolder)
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

private actor CancellableComparisonEnhancementService: ComparisonEnhancementService {
    let outputSuffix: String
    private(set) var activeCount = 0

    init(outputSuffix: String) {
        self.outputSuffix = outputSuffix
    }

    func enhance(input: URL, output: URL) async throws {
        activeCount += 1
        defer { activeCount -= 1 }

        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: output)
        try Data("partial".utf8).write(to: output)
        try await Task.sleep(for: .seconds(5))
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

private struct WaitTimeoutError: Error {}

private func waitUntil(
    timeoutMilliseconds: UInt64 = 1_000,
    condition: @escaping @Sendable () async -> Bool
) async throws {
    let deadline = ContinuousClock.now + .milliseconds(timeoutMilliseconds)

    while ContinuousClock.now < deadline {
        if await condition() {
            return
        }

        try await Task.sleep(for: .milliseconds(20))
    }

    throw WaitTimeoutError()
}

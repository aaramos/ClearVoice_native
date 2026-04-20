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
            audioEnhancement: StubAudioEnhancementService(),
            speechPipeline: SelectiveFailureSpeechPipelineService(failingBasename: "sample_2_clean"),
            export: DefaultExportService()
        )
        let processor = try harness.makeProcessor(services: services, maxConcurrency: 3)
        let recorder = ItemRecorder()

        await processor.run(files: harness.items) { item in
            await recorder.record(item)
        }

        let latestItems = await recorder.itemsByBasename()

        #expect(latestItems["sample_2"]?.stage == .failed(error: .transcriptionFailed("Stubbed failure")))
        #expect(latestItems["sample_1"]?.stage == .complete)
        #expect(latestItems["sample_3"]?.stage == .complete)
        #expect(latestItems["sample_4"]?.stage == .complete)
    }

    @Test
    func summaryPlaceholderIsExported() async throws {
        let harness = try BatchProcessorHarness(fileCount: 1)
        let services = ServiceBundle(
            audioEnhancement: StubAudioEnhancementService(),
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
        let transcriptURL = try #require(item.outputFolderURL?
            .appendingPathComponent("sample_1_transcript.txt"))
        let transcript = try String(contentsOf: transcriptURL, encoding: .utf8)

        #expect(item.stage == .complete)
        #expect(item.summaryText == "Placeholder summary.")
        #expect(transcript.contains("SUMMARY"))
        #expect(transcript.contains("Placeholder summary."))
        #expect(transcript.contains("TRANSLATED TRANSCRIPT"))
        #expect(transcript.contains("ORIGINAL TRANSCRIPT"))
    }

    @Test
    func languageDetectionFailureUsesActionableMessage() async throws {
        let harness = try BatchProcessorHarness(fileCount: 1)
        let services = ServiceBundle(
            audioEnhancement: StubAudioEnhancementService(),
            speechPipeline: DetectionFailingSpeechPipelineService(),
            export: DefaultExportService()
        )
        let processor = try harness.makeProcessor(services: services, maxConcurrency: 1)
        let recorder = ItemRecorder()

        await processor.run(files: harness.items) { item in
            await recorder.record(item)
        }

        let latestItems = await recorder.itemsByBasename()
        let item = try #require(latestItems["sample_1"])

        #expect(item.stage == .failed(error: .transcriptionFailed("ClearVoice couldn’t detect the spoken language. Choose the source language manually and try again.")))
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

private actor SelectiveFailureSpeechPipelineService: SpeechPipelineService {
    let failingBasename: String

    init(failingBasename: String) {
        self.failingBasename = failingBasename
    }

    func process(audio: URL, language: LanguageSelection) async throws -> SpeechPipelineOutput {
        if audio.deletingPathExtension().lastPathComponent == failingBasename {
            throw ProcessingError.transcriptionFailed("Stubbed failure")
        }

        let transcript = Transcript(text: "Original \(audio.lastPathComponent)", detectedLanguage: "mr", confidence: 0.9)
        return SpeechPipelineOutput(
            transcript: transcript,
            englishTranslation: "English \(audio.lastPathComponent)"
        )
    }
}

private actor DetectionFailingSpeechPipelineService: SpeechPipelineService {
    func process(audio: URL, language: LanguageSelection) async throws -> SpeechPipelineOutput {
        throw TranscriptionError.languageDetectionFailed
    }
}

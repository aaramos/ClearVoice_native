import Foundation
import Testing
@testable import ClearVoice

struct BatchProcessorTests {
    @Test
    func processorNeverExceedsConfiguredConcurrency() async throws {
        let harness = try BatchProcessorHarness(fileCount: 5)
        let enhancement = TrackingEnhancementService(delayMilliseconds: 250)
        let services = ServiceBundle(
            audioEnhancement: enhancement,
            transcription: StubTranscriptionService(),
            translation: StubTranslationService(),
            summarization: StubSummarizationService(),
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
            transcription: SelectiveFailureTranscriptionService(failingBasename: "sample_2"),
            translation: StubTranslationService(),
            summarization: StubSummarizationService(),
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
    func stopAfterCurrentPreventsNewFilesFromStarting() async throws {
        let harness = try BatchProcessorHarness(fileCount: 6)
        let enhancement = TrackingEnhancementService(delayMilliseconds: 300)
        let services = ServiceBundle(
            audioEnhancement: enhancement,
            transcription: StubTranscriptionService(),
            translation: StubTranslationService(),
            summarization: StubSummarizationService(),
            export: DefaultExportService()
        )
        let processor = try harness.makeProcessor(services: services, maxConcurrency: 3)
        let recorder = ItemRecorder()

        let runTask = Task {
            await processor.run(files: harness.items) { item in
                await recorder.record(item)
            }
        }

        await enhancement.waitUntilActiveCount(atLeast: 3)
        await processor.requestStopAfterCurrent()
        await runTask.value

        let latestItems = await recorder.items()

        #expect(latestItems.count == 3)
        #expect(latestItems.allSatisfy { $0.stage == .complete })
    }

    @Test
    func summarizationFailureExportsTranscriptWithoutSummary() async throws {
        let harness = try BatchProcessorHarness(fileCount: 1)
        let services = ServiceBundle(
            apiKeyPresent: true,
            audioEnhancement: StubAudioEnhancementService(),
            transcription: StubTranscriptionService(),
            translation: StubTranslationService(),
            summarization: FailingSummarizationService(),
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
        #expect(item.summaryText == nil)
        #expect(!transcript.contains("SUMMARY"))
        #expect(transcript.contains("TRANSLATED TRANSCRIPT"))
        #expect(transcript.contains("ORIGINAL TRANSCRIPT"))
    }

    @Test
    func disabledSummarizationSkipsSummaryGeneration() async throws {
        let harness = try BatchProcessorHarness(fileCount: 1)
        let services = ServiceBundle(
            apiKeyPresent: true,
            audioEnhancement: StubAudioEnhancementService(),
            transcription: StubTranscriptionService(),
            translation: StubTranslationService(),
            summarization: FailingSummarizationService(),
            export: DefaultExportService()
        )
        let configuration = BatchConfiguration(
            sourceFolder: harness.sourceFolder,
            outputFolder: harness.outputFolder,
            intensity: .balanced,
            inputLanguage: .auto,
            outputLanguage: "en",
            maxConcurrency: 1,
            recursiveScan: true,
            preserveChannels: false,
            processingMode: ProcessingModeConfiguration(
                transcription: .local,
                translation: .local,
                summarizationEnabled: false
            )
        )
        let resolver = try OutputPathResolver(outputRoot: harness.outputFolder)
        let processor = BatchProcessor(config: configuration, resolver: resolver, services: services)
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
        #expect(item.summaryText == nil)
        #expect(!transcript.contains("SUMMARY"))
        #expect(transcript.contains("TRANSLATED TRANSCRIPT"))
    }

    @Test
    func localTranscriptionStaysLocalWhenSpeechAssetsAreUnavailable() async throws {
        let harness = try BatchProcessorHarness(fileCount: 1)
        let cloudPreparation = RecordingCloudPreparationService()
        let services = ServiceBundle(
            apiKeyPresent: true,
            audioEnhancement: StubAudioEnhancementService(),
            formatNormalizationService: StubFormatNormalizationService(),
            cloudPreparationService: cloudPreparation,
            localTranscription: DownloadingLocalTranscriptionService(),
            cloudTranscription: StubTranscriptionService(),
            localTranslation: StubTranslationService(),
            cloudTranslation: StubTranslationService(),
            localSummarization: StubSummarizationService(),
            cloudSummarization: StubSummarizationService(),
            export: DefaultExportService()
        )
        let processor = try harness.makeProcessor(services: services, maxConcurrency: 1)
        let recorder = ItemRecorder()

        await processor.run(files: harness.items) { item in
            await recorder.record(item)
        }

        let latestItems = await recorder.itemsByBasename()
        let item = try #require(latestItems["sample_1"])
        let preparedInputs = await cloudPreparation.inputs

        #expect(item.stage == .failed(error: .transcriptionFailed("Speech support for this language is still downloading on this Mac.")))
        #expect(preparedInputs.isEmpty)
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
            let url = sourceFolder.appendingPathComponent("sample_\(index).m4a")
            try Data([0x01, 0x02, 0x03]).write(to: url)
            generatedItems.append(
                AudioFileItem(
                    id: UUID(),
                    sourceURL: url,
                    durationSeconds: nil,
                    stage: .pending
                )
            )
        }

        items = generatedItems
    }

    func makeProcessor(
        services: ServiceBundle,
        maxConcurrency: Int
    ) throws -> BatchProcessor {
        let configuration = BatchConfiguration(
            sourceFolder: sourceFolder,
            outputFolder: outputFolder,
            intensity: .balanced,
            inputLanguage: .auto,
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
    private var latestByID: [UUID: AudioFileItem] = [:]

    func record(_ item: AudioFileItem) {
        latestByID[item.id] = item
    }

    func items() -> [AudioFileItem] {
        Array(latestByID.values)
    }

    func itemsByBasename() -> [String: AudioFileItem] {
        Dictionary(uniqueKeysWithValues: latestByID.values.map { ($0.basename, $0) })
    }
}

private actor TrackingEnhancementService: AudioEnhancementService {
    private let delayNanoseconds: UInt64
    private var activeCount = 0
    private var waiter: (target: Int, continuation: CheckedContinuation<Void, Never>)?
    private(set) var maxActiveCount = 0

    init(delayMilliseconds: UInt64) {
        self.delayNanoseconds = delayMilliseconds * 1_000_000
    }

    func enhance(
        input: URL,
        output: URL,
        intensity: Intensity
    ) async throws {
        activeCount += 1
        maxActiveCount = max(maxActiveCount, activeCount)

        if let waiter, activeCount >= waiter.target {
            self.waiter = nil
            waiter.continuation.resume()
        }

        defer { activeCount -= 1 }

        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contentsOf: input).write(to: output)
        try await Task.sleep(nanoseconds: delayNanoseconds)
    }

    func waitUntilActiveCount(atLeast target: Int) async {
        if activeCount >= target {
            return
        }

        await withCheckedContinuation { continuation in
            waiter = (target, continuation)
        }
    }
}

private actor SelectiveFailureTranscriptionService: TranscriptionService {
    let failingBasename: String

    init(failingBasename: String) {
        self.failingBasename = failingBasename
    }

    func transcribe(
        audio: URL,
        language: LanguageSelection
    ) async throws -> Transcript {
        let originalBasename = audio
            .deletingPathExtension()
            .lastPathComponent
            .replacingOccurrences(of: "_clean", with: "")

        if originalBasename == failingBasename {
            throw ProcessingError.transcriptionFailed("Stubbed failure")
        }

        return Transcript(
            text: "Stub transcript for \(audio.lastPathComponent)",
            detectedLanguage: "en",
            confidence: 0.99
        )
    }
}

private actor FailingSummarizationService: SummarizationService {
    func summarize(
        text: String,
        inLanguage targetLanguage: String
    ) async throws -> String {
        throw ProcessingError.summarizationFailed("Gemini summarization failed with status 503.")
    }
}

private actor DownloadingLocalTranscriptionService: TranscriptionService {
    func transcribe(
        audio: URL,
        language: LanguageSelection
    ) async throws -> Transcript {
        throw TranscriptionError.modelDownloading
    }
}

private actor RecordingCloudPreparationService: CloudAudioPreparationService {
    private(set) var inputs: [URL] = []

    func prepare(_ sourceURL: URL) async throws -> URL {
        inputs.append(sourceURL)
        return sourceURL
    }
}

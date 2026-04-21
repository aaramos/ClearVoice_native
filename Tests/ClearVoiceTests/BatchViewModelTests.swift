import Foundation
import Testing
@testable import ClearVoice

@MainActor
struct BatchViewModelTests {
    @Test
    func enhancementOnlyRunsFinishWithoutLanguagePrompt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceFolder = root.appendingPathComponent("source", isDirectory: true)
        let outputFolder = root.appendingPathComponent("output", isDirectory: true)
        let sourceURL = sourceFolder.appendingPathComponent("sample.wav")

        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        try Data("stub".utf8).write(to: sourceURL)

        let viewModel = BatchViewModel(
            services: ServiceBundle(
                audioEnhancement: StubAudioEnhancementService(),
                comparisonEnhancements: [
                    LocalStubComparisonEnhancementService(outputSuffix: "DFN"),
                    LocalStubComparisonEnhancementService(outputSuffix: "HYBRID"),
                ],
                speechPipeline: FailingIfCalledSpeechPipelineService(),
                export: DefaultExportService()
            )
        )
        let configuration = BatchConfiguration(
            sourceFolder: sourceFolder,
            outputFolder: outputFolder,
            intensity: .balanced,
            inputLanguage: .auto,
            outputLanguage: "en",
            maxConcurrency: 1,
            recursiveScan: true,
            preserveChannels: false
        )

        viewModel.configureRun(files: [sourceURL], configuration: configuration)
        viewModel.startIfNeeded()

        while !viewModel.didFinish {
            await Task.yield()
        }

        #expect(viewModel.languageSelectionPrompt == nil)
        #expect(viewModel.statusText.contains("DeepFilterNet and Hybrid outputs"))
    }
}

private actor FailingIfCalledSpeechPipelineService: SpeechPipelineService {
    func process(audio: URL, language: LanguageSelection) async throws -> SpeechPipelineOutput {
        Issue.record("Speech pipeline should not be called in enhancement-only mode.")
        throw ProcessingError.transcriptionFailed("Speech pipeline should not be called.")
    }
}

private actor LocalStubComparisonEnhancementService: ComparisonEnhancementService {
    let outputSuffix: String

    init(outputSuffix: String) {
        self.outputSuffix = outputSuffix
    }

    func enhance(input: URL, output: URL) async throws {
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: output)
        try Data("comparison".utf8).write(to: output)
    }
}

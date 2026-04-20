import Foundation
import Testing
@testable import ClearVoice

@MainActor
struct BatchViewModelTests {
    @Test
    func languageDetectionFailuresExposeManualLanguagePrompt() async throws {
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
                speechPipeline: DetectionFailureSpeechPipelineService(),
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

        #expect(viewModel.languageSelectionPrompt?.contains("choose the source language manually") == true)
        #expect(viewModel.statusText.contains("manually selected source language"))
    }
}

private actor DetectionFailureSpeechPipelineService: SpeechPipelineService {
    func process(audio: URL, language: LanguageSelection) async throws -> SpeechPipelineOutput {
        throw TranscriptionError.languageDetectionFailed
    }
}

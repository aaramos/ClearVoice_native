import Foundation
import Testing
@testable import ClearVoice

@MainActor
struct BatchViewModelTests {
    @Test
    func processingRunsFinishWithoutLanguagePrompt() async throws {
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
                export: DefaultExportService()
            )
        )
        let configuration = BatchConfiguration(
            sourceFolder: sourceFolder,
            outputFolder: outputFolder,
            enhancementMethod: .hybrid,
            maxConcurrency: 1,
            recursiveScan: true,
            preserveChannels: false
        )

        viewModel.configureRun(
            files: [ScannedAudioFile(url: sourceURL, durationSeconds: 0)],
            configuration: configuration
        )
        viewModel.startIfNeeded()

        while !viewModel.didFinish {
            await Task.yield()
        }

        #expect(viewModel.statusText.contains("Hybrid"))
        #expect(viewModel.statusText.contains("audio output"))
        #expect(viewModel.runFinishedAt != nil)
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

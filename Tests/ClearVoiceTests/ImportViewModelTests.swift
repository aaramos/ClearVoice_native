import Foundation
import Testing
@testable import ClearVoice

@MainActor
struct ImportViewModelTests {
    @Test
    func outputInsideSourceIsRejected() async throws {
        let folders = try NestedTemporaryFolders()
        let viewModel = ImportViewModel(fileScanner: MockScanner(result: .empty))

        viewModel.selectOutputFolder(folders.outputInsideSource)
        viewModel.selectSourceFolder(folders.source)
        await viewModel.waitForScheduledScan()

        #expect(viewModel.validationMessages.contains("Output folder can’t be inside the source folder."))
        #expect(!viewModel.canProceed)
    }

    @Test
    func supportedFilesEnableProgress() async throws {
        let folders = try NestedTemporaryFolders()
        let result = ScanResult(
            supported: [folders.source.appendingPathComponent("speech.wav")],
            skipped: [],
            totalDurationSeconds: 600
        )
        let viewModel = ImportViewModel(fileScanner: MockScanner(result: result))

        viewModel.selectOutputFolder(folders.outputSibling)
        viewModel.selectSourceFolder(folders.source)
        await viewModel.waitForScheduledScan()

        #expect(viewModel.supportedFileCount == 1)
        #expect(viewModel.formattedDuration == "10m")
        #expect(viewModel.canProceed)
    }
}

private struct NestedTemporaryFolders {
    let root: URL
    let source: URL
    let outputInsideSource: URL
    let outputSibling: URL

    init() throws {
        let fileManager = FileManager.default
        root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        source = root.appendingPathComponent("source", isDirectory: true)
        outputInsideSource = source.appendingPathComponent("output", isDirectory: true)
        outputSibling = root.appendingPathComponent("output", isDirectory: true)

        try fileManager.createDirectory(at: outputInsideSource, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outputSibling, withIntermediateDirectories: true)
    }
}

private actor MockScanner: FileScanner {
    let result: ScanResult

    init(result: ScanResult) {
        self.result = result
    }

    func scan(folder: URL, recursive: Bool) async throws -> ScanResult {
        result
    }
}

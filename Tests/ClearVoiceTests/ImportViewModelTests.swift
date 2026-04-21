import Foundation
import Testing
@testable import ClearVoice

@MainActor
struct ImportViewModelTests {
    @Test
    func sourceSelectionGeneratesDesktopOutputPreview() async throws {
        let folders = try NestedTemporaryFolders()
        let viewModel = ImportViewModel(fileScanner: MockScanner(result: .empty))

        viewModel.selectSourceFolder(folders.source)
        await viewModel.waitForScheduledScan()

        #expect(viewModel.outputFolderURL != nil)
        #expect(viewModel.plannedOutputFolderDisplayPath.contains("output_"))
        #expect(!viewModel.canProceed)
    }

    @Test
    func supportedFilesEnableProgress() async throws {
        let folders = try NestedTemporaryFolders()
        let result = ScanResult(
            supported: [ScannedAudioFile(url: folders.source.appendingPathComponent("speech.wav"), durationSeconds: 600)],
            skipped: [],
            totalDurationSeconds: 600
        )
        let viewModel = ImportViewModel(fileScanner: MockScanner(result: result))

        viewModel.selectSourceFolder(folders.source)
        await viewModel.waitForScheduledScan()

        #expect(viewModel.supportedFileCount == 1)
        #expect(viewModel.formattedDuration == "10m")
        #expect(viewModel.canProceed)
    }

    @Test
    func realScannerAdmitsWMAForNormalization() async throws {
        let folders = try NestedTemporaryFolders()
        let sourceFile = folders.source.appendingPathComponent("legacy_note.wma")
        try Data([0x01, 0x02, 0x03]).write(to: sourceFile)

        let viewModel = ImportViewModel(fileScanner: LocalFileScanner())

        viewModel.selectSourceFolder(folders.source)
        await viewModel.waitForScheduledScan()

        #expect(viewModel.supportedFileCount == 1)
        #expect(viewModel.skippedFileCount == 0)
        #expect(viewModel.canProceed)
    }
}

private struct NestedTemporaryFolders {
    let root: URL
    let source: URL

    init() throws {
        let fileManager = FileManager.default
        root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        source = root.appendingPathComponent("source", isDirectory: true)

        try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
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

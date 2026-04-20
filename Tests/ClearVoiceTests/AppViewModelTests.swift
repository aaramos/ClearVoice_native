import Foundation
import Testing
@testable import ClearVoice

@MainActor
struct AppViewModelTests {
    @Test
    func forwardNavigationMovesThroughShellSteps() async throws {
        let folders = try TemporaryFolders()
        let importViewModel = ImportViewModel(fileScanner: MockFileScanner())
        importViewModel.selectOutputFolder(folders.output)
        importViewModel.selectSourceFolder(folders.source)
        await importViewModel.waitForScheduledScan()

        let viewModel = AppViewModel(importViewModel: importViewModel)

        #expect(viewModel.state == .importing)

        viewModel.goForward()
        #expect(viewModel.state == .configuring)

        viewModel.goForward()
        #expect(viewModel.state == .processing)
    }

    @Test
    func backNavigationReturnsToPreviousScreen() async throws {
        let folders = try TemporaryFolders()
        let importViewModel = ImportViewModel(fileScanner: MockFileScanner())
        importViewModel.selectOutputFolder(folders.output)
        importViewModel.selectSourceFolder(folders.source)
        await importViewModel.waitForScheduledScan()

        let viewModel = AppViewModel(importViewModel: importViewModel)

        viewModel.goForward()
        viewModel.goForward()
        viewModel.goBack()

        #expect(viewModel.state == .configuring)
    }

    @Test
    func reviewPlaceholderCanReturnToNewBatch() {
        let viewModel = AppViewModel()

        viewModel.revealReviewPlaceholder()
        #expect(viewModel.state == .review)

        viewModel.startNewBatch()
        #expect(viewModel.state == .importing)
    }
}

private struct TemporaryFolders {
    let root: URL
    let source: URL
    let output: URL

    init() throws {
        let fileManager = FileManager.default
        root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        source = root.appendingPathComponent("source", isDirectory: true)
        output = root.appendingPathComponent("output", isDirectory: true)

        try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: output, withIntermediateDirectories: true)
    }
}

private actor MockFileScanner: FileScanner {
    func scan(folder: URL, recursive: Bool) async throws -> ScanResult {
        let file = folder.appendingPathComponent("sample.m4a")
        return ScanResult(
            supported: [file],
            skipped: [folder.appendingPathComponent("notes.txt")],
            totalDurationSeconds: 1260
        )
    }
}

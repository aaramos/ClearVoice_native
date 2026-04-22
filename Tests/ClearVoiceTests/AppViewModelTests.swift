import Foundation
import Testing
@testable import ClearVoice

@MainActor
struct AppViewModelTests {
    @Test
    func forwardNavigationMovesThroughShellSteps() async throws {
        let folders = try TemporaryFolders()
        let importViewModel = ImportViewModel(fileScanner: MockFileScanner())
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
        importViewModel.selectSourceFolder(folders.source)
        await importViewModel.waitForScheduledScan()

        let viewModel = AppViewModel(importViewModel: importViewModel)

        viewModel.goForward()
        viewModel.goForward()
        viewModel.goBack()

        #expect(viewModel.state == .configuring)
    }

    @Test
    func showResultsWaitsForFinishedBatch() async throws {
        let folders = try TemporaryFolders()
        let importViewModel = ImportViewModel(fileScanner: MockFileScanner())
        importViewModel.selectSourceFolder(folders.source)
        await importViewModel.waitForScheduledScan()

        let batchViewModel = BatchViewModel()
        let viewModel = AppViewModel(
            importViewModel: importViewModel,
            batchViewModel: batchViewModel
        )

        viewModel.goForward()
        viewModel.goForward()
        #expect(viewModel.state == .processing)

        viewModel.showResults()
        #expect(viewModel.state == .processing)

        batchViewModel.startIfNeeded()
        while !batchViewModel.didFinish {
            await Task.yield()
        }

        viewModel.showResults()
        #expect(viewModel.state == .review)
    }

    @Test
    func resultsScreenCanReturnToNewBatch() async throws {
        let defaults = UserDefaults(suiteName: "clearvoice.app-view.\(UUID().uuidString)")!
        let configureViewModel = ConfigureViewModel(
            preferences: ConfigurePreferencesStore(defaults: defaults)
        )
        configureViewModel.enhancementMethod = .dfn
        configureViewModel.maxConcurrency = 8

        let folders = try TemporaryFolders()
        let importViewModel = ImportViewModel(fileScanner: MockFileScanner())
        importViewModel.selectSourceFolder(folders.source)
        await importViewModel.waitForScheduledScan()

        let batchViewModel = BatchViewModel()
        let viewModel = AppViewModel(
            importViewModel: importViewModel,
            configureViewModel: configureViewModel,
            batchViewModel: batchViewModel
        )

        viewModel.goForward()
        viewModel.goForward()
        batchViewModel.startIfNeeded()
        while !batchViewModel.didFinish {
            await Task.yield()
        }
        viewModel.showResults()
        #expect(viewModel.state == .review)

        viewModel.startNewBatch()
        #expect(viewModel.state == .importing)
        #expect(viewModel.configureViewModel.enhancementMethod == .dfn)
        #expect(viewModel.configureViewModel.maxConcurrency == 8)
    }
}

private struct TemporaryFolders {
    let root: URL
    let source: URL

    init() throws {
        let fileManager = FileManager.default
        root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        source = root.appendingPathComponent("source", isDirectory: true)

        try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
    }
}

private actor MockFileScanner: FileScanner {
    func scan(folder: URL, recursive: Bool) async throws -> ScanResult {
        let file = folder.appendingPathComponent("sample.m4a")
        return ScanResult(
            supported: [ScannedAudioFile(url: file, durationSeconds: 1260)],
            skipped: [folder.appendingPathComponent("notes.txt")],
            totalDurationSeconds: 1260
        )
    }
}

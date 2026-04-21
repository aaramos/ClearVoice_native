import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var state: AppState = .importing

    let importViewModel: ImportViewModel
    let configureViewModel: ConfigureViewModel
    let batchViewModel: BatchViewModel

    init(
        importViewModel: ImportViewModel = ImportViewModel(),
        configureViewModel: ConfigureViewModel = ConfigureViewModel(),
        batchViewModel: BatchViewModel = BatchViewModel()
    ) {
        self.importViewModel = importViewModel
        self.configureViewModel = configureViewModel
        self.batchViewModel = batchViewModel
    }

    var canGoBack: Bool {
        switch state {
        case .importing:
            false
        case .configuring, .review:
            true
        case .processing:
            !batchViewModel.isRunning
        }
    }

    var canGoForward: Bool {
        switch state {
        case .importing:
            importViewModel.canProceed
        case .configuring:
            configureViewModel.canStart
        case .processing, .review:
            false
        }
    }

    func goBack() {
        switch state {
        case .importing:
            return
        case .configuring:
            state = .importing
        case .processing:
            state = .configuring
        case .review:
            state = .processing
        }
    }

    func goForward() {
        switch state {
        case .importing:
            guard importViewModel.canProceed else { return }
            state = .configuring
        case .configuring:
            guard let configuration = makeBatchConfiguration() else { return }
            batchViewModel.configureRun(
                files: importViewModel.scanResult.supported,
                configuration: configuration
            )
            state = .processing
        case .processing, .review:
            return
        }
    }

    func showResults() {
        state = .review
    }

    func startNewBatch() {
        batchViewModel.reset()
        configureViewModel.reset()
        importViewModel.reset()
        state = .importing
    }

    private func makeBatchConfiguration() -> BatchConfiguration? {
        guard
            let sourceFolder = importViewModel.sourceFolderURL,
            let outputFolder = importViewModel.outputFolderURL
        else {
            return nil
        }

        return BatchConfiguration(
            sourceFolder: sourceFolder,
            outputFolder: outputFolder,
            enhancementMethod: configureViewModel.enhancementMethod,
            maxConcurrency: configureViewModel.maxConcurrency,
            recursiveScan: true,
            preserveChannels: false
        )
    }
}

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
        case .configuring, .processing, .review:
            true
        }
    }

    var canGoForward: Bool {
        switch state {
        case .importing:
            importViewModel.canProceed
        case .configuring:
            true
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
            state = .processing
        case .processing, .review:
            return
        }
    }

    func revealReviewPlaceholder() {
        state = .review
    }

    func startNewBatch() {
        state = .importing
    }
}

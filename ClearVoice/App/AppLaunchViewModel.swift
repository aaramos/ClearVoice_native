import Foundation

@MainActor
final class AppLaunchViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case ready
        case failed
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var appViewModel: AppViewModel?
    @Published private(set) var launchError: LaunchRequirementsError?

    private let makeAppViewModel: @MainActor () -> AppViewModel

    init(
        makeAppViewModel: @escaping @MainActor () -> AppViewModel = {
            AppServicesFactory.makeAppViewModel()
        }
    ) {
        self.makeAppViewModel = makeAppViewModel
        bootstrap()
    }

    func retryBootstrap() {
        bootstrap()
    }

    private func bootstrap() {
        appViewModel = nil
        launchError = nil
        phase = .loading

        appViewModel = makeAppViewModel()
        phase = .ready
    }
}

import Foundation

@MainActor
final class AppLaunchViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case setupConsent
        case setup
        case ready
        case failed
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var appViewModel: AppViewModel?
    @Published private(set) var launchError: LaunchRequirementsError?
    @Published private(set) var dependencySetupViewModel: DependencySetupViewModel?

    private let makeAppViewModel: @MainActor () -> AppViewModel
    private let makeDependencySetupViewModel: @MainActor (@escaping @MainActor () -> Void) -> DependencySetupViewModel
    private let approvalStore: DependencySetupApprovalStore

    init(
        makeAppViewModel: @escaping @MainActor () -> AppViewModel = {
            AppServicesFactory.makeAppViewModel()
        },
        makeDependencySetupViewModel: @escaping @MainActor (@escaping @MainActor () -> Void) -> DependencySetupViewModel = { onReady in
            DependencySetupViewModel(onReady: onReady)
        },
        approvalStore: DependencySetupApprovalStore = DependencySetupApprovalStore()
    ) {
        self.makeAppViewModel = makeAppViewModel
        self.makeDependencySetupViewModel = makeDependencySetupViewModel
        self.approvalStore = approvalStore
        bootstrap()
    }

    func retryBootstrap() {
        bootstrap()
    }

    func approveDependencySetup() {
        approvalStore.markApproved()
        startDependencySetup()
    }

    private func bootstrap() {
        appViewModel = nil
        launchError = nil
        dependencySetupViewModel = nil

        if approvalStore.hasApprovedSetup {
            startDependencySetup()
        } else {
            phase = .setupConsent
        }
    }

    private func startDependencySetup() {
        phase = .setup

        let setupViewModel = makeDependencySetupViewModel { [weak self] in
            self?.finishLaunch()
        }

        dependencySetupViewModel = setupViewModel
    }

    private func finishLaunch() {
        appViewModel = makeAppViewModel()
        phase = .ready
    }
}

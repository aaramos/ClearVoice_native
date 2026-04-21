import Foundation
import Testing
@testable import ClearVoice

@MainActor
struct AppLaunchViewModelTests {
    @Test
    func bootstrapShowsSetupConsentBeforeApproval() {
        let appViewModel = AppViewModel()
        let defaults = UserDefaults(suiteName: "clearvoice.launch.\(UUID().uuidString)")!
        let approvalStore = DependencySetupApprovalStore(defaults: defaults)
        let viewModel = AppLaunchViewModel(
            makeAppViewModel: {
                appViewModel
            },
            approvalStore: approvalStore
        )

        #expect(viewModel.phase == AppLaunchViewModel.Phase.setupConsent)
        #expect(viewModel.appViewModel == nil)
    }

    @Test
    func approvingSetupTransitionsIntoInstallerFlow() {
        let appViewModel = AppViewModel()
        let defaults = UserDefaults(suiteName: "clearvoice.launch.\(UUID().uuidString)")!
        let approvalStore = DependencySetupApprovalStore(defaults: defaults)
        let viewModel = AppLaunchViewModel(
            makeAppViewModel: {
                appViewModel
            },
            makeDependencySetupViewModel: { onReady in
                DependencySetupViewModel(
                    manager: DependencySetupManager(descriptors: []),
                    onReady: onReady
                )
            },
            approvalStore: approvalStore
        )

        viewModel.approveDependencySetup()

        #expect(approvalStore.hasApprovedSetup)
        #expect(viewModel.phase == AppLaunchViewModel.Phase.setup)
        #expect(viewModel.dependencySetupViewModel != nil)
    }

    @Test
    func bootstrapUsesInstallerFlowAfterApprovalWasPreviouslyGranted() {
        let defaults = UserDefaults(suiteName: "clearvoice.launch.\(UUID().uuidString)")!
        let approvalStore = DependencySetupApprovalStore(defaults: defaults)
        approvalStore.markApproved()

        let appViewModel = AppViewModel()
        let viewModel = AppLaunchViewModel(
            makeAppViewModel: {
                appViewModel
            },
            makeDependencySetupViewModel: { onReady in
                DependencySetupViewModel(
                    manager: DependencySetupManager(descriptors: []),
                    onReady: onReady
                )
            },
            approvalStore: approvalStore
        )

        #expect(viewModel.phase == AppLaunchViewModel.Phase.setup)
        #expect(viewModel.dependencySetupViewModel != nil)
    }
}

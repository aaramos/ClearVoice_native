import AppKit
import SwiftUI

@main
struct ClearVoiceApp: App {
    @NSApplicationDelegateAdaptor(ClearVoiceAppDelegate.self) private var appDelegate
    @StateObject private var launchViewModel = AppLaunchViewModel()

    var body: some Scene {
        WindowGroup {
            Group {
                switch launchViewModel.phase {
                case .loading:
                    ProgressView("Starting ClearVoice…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.regularMaterial)
                case .setupConsent:
                    DependencySetupConsentView(
                        dependencies: ToolDependencyDescriptor.defaults(),
                        installRootDescription: ManagedToolPaths.userFacingPath(ManagedToolPaths.toolsRoot())
                    ) {
                        launchViewModel.approveDependencySetup()
                    } onQuit: {
                        NSApp.terminate(nil)
                    }
                case .setup:
                    if let setupViewModel = launchViewModel.dependencySetupViewModel {
                        DependencySetupView(
                            viewModel: setupViewModel
                        ) {
                            NSApp.terminate(nil)
                        }
                    } else {
                        ProgressView("Preparing setup…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.regularMaterial)
                    }
                case .ready:
                    if let appViewModel = launchViewModel.appViewModel {
                        RootView(viewModel: appViewModel)
                    } else {
                        ProgressView("Starting ClearVoice…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.regularMaterial)
                    }
                case .failed:
                    LaunchFailureView(
                        error: launchViewModel.launchError ?? LaunchRequirementsError.unexpectedStartupFailure("Unknown launch state.")
                    ) {
                        NSApp.terminate(nil)
                    }
                }
            }
            .frame(minWidth: 920, minHeight: 640)
            .preferredColorScheme(.light)
            .task {
                appDelegate.launchViewModelProvider = { launchViewModel }
            }
        }
        .windowResizability(.contentMinSize)
    }
}

final class ClearVoiceAppDelegate: NSObject, NSApplicationDelegate {
    var launchViewModelProvider: (() -> AppLaunchViewModel?)?
    private var terminationTask: Task<Void, Never>?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard terminationTask == nil else {
            return .terminateLater
        }

        guard let launchViewModel = launchViewModelProvider?() else {
            return .terminateNow
        }

        terminationTask = Task { @MainActor [weak self] in
            await launchViewModel.prepareForTermination()
            self?.terminationTask = nil
            NSApp.reply(toApplicationShouldTerminate: true)
        }

        return .terminateLater
    }
}

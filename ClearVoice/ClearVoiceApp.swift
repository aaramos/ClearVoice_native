import AppKit
import SwiftUI

@main
struct ClearVoiceApp: App {
    @StateObject private var launchViewModel = AppLaunchViewModel()

    var body: some Scene {
        WindowGroup {
            Group {
                switch launchViewModel.phase {
                case .loading:
                    ProgressView("Starting ClearVoice…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.regularMaterial)
                case .needsAPIKey:
                    APIKeySetupView(viewModel: launchViewModel) {
                        NSApp.terminate(nil)
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
        }
        .windowResizability(.contentMinSize)
    }
}

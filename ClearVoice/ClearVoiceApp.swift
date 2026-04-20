import AppKit
import SwiftUI

@main
struct ClearVoiceApp: App {
    @StateObject private var appViewModel: AppViewModel
    private let launchRequirementsError: LaunchRequirementsError?

    init() {
        do {
            let viewModel = try AppServicesFactory.makeLiveAppViewModel()
            _appViewModel = StateObject(wrappedValue: viewModel)
            launchRequirementsError = nil
        } catch let error as LaunchRequirementsError {
            _appViewModel = StateObject(wrappedValue: AppViewModel())
            launchRequirementsError = error
        } catch {
            _appViewModel = StateObject(wrappedValue: AppViewModel())
            launchRequirementsError = LaunchRequirementsError(
                title: "Couldn’t Start ClearVoice",
                message: "ClearVoice hit an unexpected startup error: \(error.localizedDescription)"
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let launchRequirementsError {
                    LaunchFailureView(error: launchRequirementsError) {
                        NSApp.terminate(nil)
                    }
                } else {
                    RootView(viewModel: appViewModel)
                }
            }
            .frame(minWidth: 920, minHeight: 640)
        }
        .windowResizability(.contentMinSize)
    }
}

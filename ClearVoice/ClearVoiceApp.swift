import SwiftUI

@main
struct ClearVoiceApp: App {
    @StateObject private var appViewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            RootView(viewModel: appViewModel)
                .frame(minWidth: 920, minHeight: 640)
        }
        .windowResizability(.contentMinSize)
    }
}

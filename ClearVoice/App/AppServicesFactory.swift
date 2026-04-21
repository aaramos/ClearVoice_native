import Foundation

enum AppServicesFactory {
    @MainActor
    static func makeAppViewModel() -> AppViewModel {
        let serviceBundle = makeServiceBundle()

        return AppViewModel(
            configureViewModel: ConfigureViewModel(),
            batchViewModel: BatchViewModel(services: serviceBundle)
        )
    }

    static func makeServiceBundle() -> ServiceBundle {
        .live()
    }
}

struct LaunchRequirementsError: Error, Equatable {
    let title: String
    let message: String

    static func unexpectedStartupFailure(_ detail: String) -> LaunchRequirementsError {
        LaunchRequirementsError(
            title: "Couldn’t Start ClearVoice",
            message: "ClearVoice hit an unexpected startup error: \(detail)"
        )
    }

    static func dependencyInstallFailed(_ detail: String) -> LaunchRequirementsError {
        LaunchRequirementsError(
            title: "Couldn’t Finish Setup",
            message: "ClearVoice couldn’t finish preparing the required audio tools: \(detail)"
        )
    }
}

import Darwin
import Foundation

enum HostArchitecture: Sendable, Equatable {
    case arm64
    case x86_64

    static var current: HostArchitecture {
        var arm64Flag: Int32 = 0
        var size = MemoryLayout.size(ofValue: arm64Flag)
        let result = sysctlbyname("hw.optional.arm64", &arm64Flag, &size, nil, 0)

        if result == 0, arm64Flag == 1 {
            return .arm64
        }

        return .x86_64
    }
}

enum ManagedToolPaths {
    static func applicationSupportRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        if let overridePath = environment["CLEARVOICE_APP_SUPPORT_ROOT"], !overridePath.isEmpty {
            return URL(fileURLWithPath: NSString(string: overridePath).expandingTildeInPath, isDirectory: true)
        }

        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSString(string: "~/Library/Application Support").expandingTildeInPath)

        return root.appendingPathComponent("ClearVoice", isDirectory: true)
    }

    static func toolsRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        applicationSupportRoot(environment: environment, fileManager: fileManager)
            .appendingPathComponent("Tools", isDirectory: true)
    }

    static func downloadsRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        applicationSupportRoot(environment: environment, fileManager: fileManager)
            .appendingPathComponent("Downloads", isDirectory: true)
    }

    static func installDirectory(
        for dependency: ToolDependencyDescriptor,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        toolsRoot(environment: environment, fileManager: fileManager)
            .appendingPathComponent(dependency.installDirectoryName, isDirectory: true)
    }

    static func binaryURL(
        for dependencyID: ToolDependencyID,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        let directoryName = switch dependencyID {
        case .ffmpeg:
            "ffmpeg"
        case .deepFilter:
            "deep-filter"
        }

        return toolsRoot(environment: environment, fileManager: fileManager)
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(dependencyID.binaryName, isDirectory: false)
    }

    static func binaryURL(
        for dependency: ToolDependencyDescriptor,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        installDirectory(for: dependency, environment: environment, fileManager: fileManager)
            .appendingPathComponent(dependency.id.binaryName, isDirectory: false)
    }

    static func isManagedTool(
        _ url: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> Bool {
        let managedRoot = toolsRoot(environment: environment, fileManager: fileManager).standardizedFileURL.path
        return url.standardizedFileURL.path.hasPrefix(managedRoot)
    }

    static func userFacingPath(
        _ url: URL,
        fileManager: FileManager = .default
    ) -> String {
        let standardizedPath = url.standardizedFileURL.path
        let homePath = fileManager.homeDirectoryForCurrentUser.standardizedFileURL.path

        guard standardizedPath.hasPrefix(homePath) else {
            return standardizedPath
        }

        let suffix = standardizedPath.dropFirst(homePath.count)
        if suffix.isEmpty {
            return "~"
        }

        return "~\(suffix)"
    }
}

struct DependencySetupApprovalStore {
    private let defaults: UserDefaults
    private let approvalKey = "clearvoice.dependencySetupApproved"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasApprovedSetup: Bool {
        defaults.bool(forKey: approvalKey)
    }

    func markApproved() {
        defaults.set(true, forKey: approvalKey)
    }
}

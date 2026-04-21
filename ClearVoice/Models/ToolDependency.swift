import Foundation

enum ToolDependencyID: String, CaseIterable, Sendable {
    case ffmpeg
    case deepFilter

    var binaryName: String {
        switch self {
        case .ffmpeg:
            "ffmpeg"
        case .deepFilter:
            "deep-filter"
        }
    }
}

enum ToolDependencyPackaging: Sendable, Equatable {
    case directBinary
    case zipArchive
}

enum ToolDependencySource: Sendable, Equatable {
    case managedByClearVoice
    case existingSystemInstall
}

struct ToolDownloadProgress: Sendable, Equatable {
    let receivedBytes: Int64
    let expectedBytes: Int64?
    let bytesPerSecond: Double
    let estimatedTimeRemaining: TimeInterval?

    var fractionCompleted: Double? {
        guard let expectedBytes, expectedBytes > 0 else {
            return nil
        }

        return min(max(Double(receivedBytes) / Double(expectedBytes), 0), 1)
    }
}

enum ToolDependencyStatus: Sendable, Equatable {
    case waiting
    case checking
    case installed(version: String, location: URL, source: ToolDependencySource)
    case missing
    case downloading(ToolDownloadProgress)
    case extracting
    case verifying
    case failed(String)
}

struct ToolDependencyDescriptor: Sendable, Equatable, Identifiable {
    let id: ToolDependencyID
    let displayName: String
    let purpose: String
    let downloadURL: URL
    let packaging: ToolDependencyPackaging
    let installDirectoryName: String

    static func defaults(
        architecture: HostArchitecture = .current
    ) -> [ToolDependencyDescriptor] {
        [
            ffmpeg(for: architecture),
            deepFilter(for: architecture),
        ]
    }

    private static func ffmpeg(for architecture: HostArchitecture) -> ToolDependencyDescriptor {
        let architectureSegment = architecture == .arm64 ? "arm64" : "amd64"

        return ToolDependencyDescriptor(
            id: .ffmpeg,
            displayName: "FFmpeg",
            purpose: "Converts source audio into the formats ClearVoice needs for enhancement and export.",
            downloadURL: URL(string: "https://ffmpeg.martin-riedl.de/redirect/latest/macos/\(architectureSegment)/release/ffmpeg.zip")!,
            packaging: .zipArchive,
            installDirectoryName: "ffmpeg"
        )
    }

    private static func deepFilter(for architecture: HostArchitecture) -> ToolDependencyDescriptor {
        let assetName = switch architecture {
        case .arm64:
            "deep-filter-0.5.6-aarch64-apple-darwin"
        case .x86_64:
            "deep-filter-0.5.6-x86_64-apple-darwin"
        }

        return ToolDependencyDescriptor(
            id: .deepFilter,
            displayName: "DeepFilterNet",
            purpose: "Runs the speech-cleanup model that powers ClearVoice enhancement.",
            downloadURL: URL(string: "https://github.com/Rikorose/DeepFilterNet/releases/download/v0.5.6/\(assetName)")!,
            packaging: .directBinary,
            installDirectoryName: "deep-filter"
        )
    }
}

struct ToolDependencyRecord: Sendable, Equatable, Identifiable {
    let descriptor: ToolDependencyDescriptor
    let status: ToolDependencyStatus

    var id: ToolDependencyID {
        descriptor.id
    }
}


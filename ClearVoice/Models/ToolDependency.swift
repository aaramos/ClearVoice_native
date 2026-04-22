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
    let downloadSHA256: String
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
        let download: (url: URL, sha256: String) = switch architecture {
        case .arm64:
            (
                URL(string: "https://ffmpeg.martin-riedl.de/download/macos/arm64/1774549676_8.1/ffmpeg.zip")!,
                "cc3a7e0cce36c5eca6c17eeb93830984c657637a8e710dc98f19c8051201fa3a"
            )
        case .x86_64:
            (
                URL(string: "https://ffmpeg.martin-riedl.de/download/macos/amd64/1774556648_8.1/ffmpeg.zip")!,
                "eaa8aa619f8eccc7f548a730097f5d299cbf2d418888421c137557344d821130"
            )
        }

        return ToolDependencyDescriptor(
            id: .ffmpeg,
            displayName: "FFmpeg",
            purpose: "Converts source audio into the formats ClearVoice needs for enhancement and export.",
            downloadURL: download.url,
            downloadSHA256: download.sha256,
            packaging: .zipArchive,
            installDirectoryName: "ffmpeg"
        )
    }

    private static func deepFilter(for architecture: HostArchitecture) -> ToolDependencyDescriptor {
        let download: (url: URL, sha256: String) = switch architecture {
        case .arm64:
            (
                URL(string: "https://github.com/Rikorose/DeepFilterNet/releases/download/v0.5.6/deep-filter-0.5.6-aarch64-apple-darwin")!,
                "4601e7f4e4c03e59a4c5b5000216ef3add3e808799cfccd95e14e83ea4611081"
            )
        case .x86_64:
            (
                URL(string: "https://github.com/Rikorose/DeepFilterNet/releases/download/v0.5.6/deep-filter-0.5.6-x86_64-apple-darwin")!,
                "d3be84003acb7c23e738ad7f70a158ec779a8d233a82e7fa3e717d112eb5b50f"
            )
        }

        return ToolDependencyDescriptor(
            id: .deepFilter,
            displayName: "DeepFilterNet",
            purpose: "Runs the speech-cleanup model that powers ClearVoice enhancement.",
            downloadURL: download.url,
            downloadSHA256: download.sha256,
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

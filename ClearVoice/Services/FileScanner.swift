import AVFoundation
import Foundation

/// Scans a folder for supported audio files and computes a total duration estimate.
protocol FileScanner: Sendable {
    func scan(folder: URL, recursive: Bool) async throws -> ScanResult
}

struct ScanResult: Equatable, Sendable {
    let supported: [URL]
    let skipped: [URL]
    let totalDurationSeconds: TimeInterval

    static let empty = ScanResult(supported: [], skipped: [], totalDurationSeconds: 0)
}

actor LocalFileScanner: FileScanner {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func scan(folder: URL, recursive: Bool) async throws -> ScanResult {
        let urls = try fileURLs(in: folder, recursive: recursive)
        var supported: [URL] = []
        var skipped: [URL] = []
        var totalDurationSeconds: TimeInterval = 0

        for url in urls {
            guard AudioFormatSupport.acceptedSourceExtensions.contains(url.pathExtension.lowercased()) else {
                skipped.append(url)
                continue
            }

            supported.append(url)
            totalDurationSeconds += await duration(for: url)
        }

        supported.sort(by: LocalFileScanner.audioSort(lhs:rhs:))
        skipped.sort(by: LocalFileScanner.audioSort(lhs:rhs:))

        return ScanResult(
            supported: supported,
            skipped: skipped,
            totalDurationSeconds: totalDurationSeconds
        )
    }

    private func fileURLs(in folder: URL, recursive: Bool) throws -> [URL] {
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey]

        if recursive {
            let enumerator = fileManager.enumerator(
                at: folder,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )

            guard let enumerator else { return [] }

            var collected: [URL] = []

            for case let url as URL in enumerator {
                let values = try url.resourceValues(forKeys: Set(resourceKeys))
                if values.isDirectory == true {
                    continue
                }
                collected.append(url)
            }

            return collected
        }

        return try fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        )
        .filter { url in
            (try? url.resourceValues(forKeys: Set(resourceKeys)).isDirectory) != true
        }
    }

    private func duration(for url: URL) async -> TimeInterval {
        let asset = AVURLAsset(url: url)

        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            return seconds.isFinite ? seconds : 0
        } catch {
            return 0
        }
    }

    private static func audioSort(lhs: URL, rhs: URL) -> Bool {
        let lhsBase = lhs.deletingPathExtension().lastPathComponent.localizedLowercase
        let rhsBase = rhs.deletingPathExtension().lastPathComponent.localizedLowercase

        if lhsBase != rhsBase {
            return lhsBase < rhsBase
        }

        let lhsExtension = lhs.pathExtension.localizedLowercase
        let rhsExtension = rhs.pathExtension.localizedLowercase

        if lhsExtension != rhsExtension {
            return lhsExtension < rhsExtension
        }

        return lhs.lastPathComponent.localizedLowercase < rhs.lastPathComponent.localizedLowercase
    }
}

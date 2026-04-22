import CryptoKit
import Foundation
import Testing
@testable import ClearVoice

struct DependencySetupManagerTests {
    @Test
    func inspectAllFindsManagedFFmpegInstall() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let environment = mergedEnvironment(appSupportRoot: rootURL)
        let ffmpegURL = ManagedToolPaths.binaryURL(
            for: .ffmpeg,
            environment: environment,
            fileManager: fileManager
        )

        try fileManager.createDirectory(at: ffmpegURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeExecutable(at: ffmpegURL, contents: "fake ffmpeg")

        let manager = DependencySetupManager(
            descriptors: [ToolDependencyDescriptor.defaults().first { $0.id == .ffmpeg }!],
            fileManager: fileManager,
            environment: environment,
            processRunner: { _, _ in
                "ffmpeg version 8.1 Copyright"
            }
        )

        let records = await manager.inspectAll()
        let record = try #require(records.first)

        #expect(record.id == .ffmpeg)
        #expect(record.status == .installed(version: "8.1", location: ffmpegURL, source: .managedByClearVoice))
    }

    @Test
    func installWritesManagedDeepFilterBinary() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let environment = mergedEnvironment(appSupportRoot: rootURL)
        let descriptor = withExpectedSHA256(
            ToolDependencyDescriptor.defaults().first { $0.id == .deepFilter }!,
            for: Data("downloaded".utf8)
        )
        let expectedBinary = ManagedToolPaths.binaryURL(
            for: descriptor,
            environment: environment,
            fileManager: fileManager
        )

        let manager = DependencySetupManager(
            descriptors: [descriptor],
            fileManager: fileManager,
            environment: environment,
            downloader: { _, destinationURL, progress in
                try "downloaded".write(to: destinationURL, atomically: true, encoding: .utf8)
                await progress(
                    ToolDownloadProgress(
                        receivedBytes: 9,
                        expectedBytes: 9,
                        bytesPerSecond: 9,
                        estimatedTimeRemaining: 0
                    )
                )
            },
            processRunner: { _, _ in
                "deep_filter 0.5.6"
            }
        )

        let record = try await manager.install(descriptor) { _ in }

        #expect(fileManager.fileExists(atPath: expectedBinary.path))
        #expect(record.status == .installed(version: "0.5.6", location: expectedBinary, source: .managedByClearVoice))
    }

    @Test
    func installUnpacksZipArchivesIntoManagedLocation() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let environment = mergedEnvironment(appSupportRoot: rootURL)
        let descriptor = withExpectedSHA256(
            ToolDependencyDescriptor.defaults().first { $0.id == .ffmpeg }!,
            for: Data("zip-data".utf8)
        )
        let expectedBinary = ManagedToolPaths.binaryURL(
            for: descriptor,
            environment: environment,
            fileManager: fileManager
        )

        let manager = DependencySetupManager(
            descriptors: [descriptor],
            fileManager: fileManager,
            environment: environment,
            downloader: { _, destinationURL, progress in
                try "zip-data".write(to: destinationURL, atomically: true, encoding: .utf8)
                await progress(
                    ToolDownloadProgress(
                        receivedBytes: 8,
                        expectedBytes: 8,
                        bytesPerSecond: 8,
                        estimatedTimeRemaining: 0
                    )
                )
            },
            archiveExtractor: { _, destinationDirectory in
                let binaryURL = destinationDirectory.appendingPathComponent("ffmpeg", isDirectory: false)
                try writeExecutable(at: binaryURL, contents: "fake ffmpeg")
            },
            processRunner: { _, _ in
                "ffmpeg version 8.1 Copyright"
            }
        )

        let record = try await manager.install(descriptor) { _ in }

        #expect(fileManager.fileExists(atPath: expectedBinary.path))
        #expect(record.status == .installed(version: "8.1", location: expectedBinary, source: .managedByClearVoice))
    }

    @Test
    func installRejectsChecksumMismatchWithoutRemovingExistingFiles() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let environment = mergedEnvironment(appSupportRoot: rootURL)
        let descriptor = ToolDependencyDescriptor.defaults().first { $0.id == .ffmpeg }!
        let installDirectory = ManagedToolPaths.installDirectory(
            for: descriptor,
            environment: environment,
            fileManager: fileManager
        )
        let sentinelURL = installDirectory.appendingPathComponent("keep.txt", isDirectory: false)

        try fileManager.createDirectory(at: installDirectory, withIntermediateDirectories: true)
        try "keep me".write(to: sentinelURL, atomically: true, encoding: .utf8)

        let manager = DependencySetupManager(
            descriptors: [descriptor],
            fileManager: fileManager,
            environment: environment,
            downloader: { _, destinationURL, progress in
                try "tampered".write(to: destinationURL, atomically: true, encoding: .utf8)
                await progress(
                    ToolDownloadProgress(
                        receivedBytes: 8,
                        expectedBytes: 8,
                        bytesPerSecond: 8,
                        estimatedTimeRemaining: 0
                    )
                )
            },
            archiveExtractor: { _, _ in
                Issue.record("Archive extractor should not run when checksum verification fails.")
            },
            processRunner: { _, _ in
                Issue.record("Process runner should not run when checksum verification fails.")
                return ""
            }
        )

        await #expect(throws: LaunchRequirementsError.dependencyInstallFailed("FFmpeg failed download verification and wasn’t installed.")) {
            _ = try await manager.install(descriptor) { _ in }
        }

        #expect(fileManager.fileExists(atPath: sentinelURL.path))
    }

    private func mergedEnvironment(appSupportRoot: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["CLEARVOICE_APP_SUPPORT_ROOT"] = appSupportRoot.path
        return environment
    }

    private func withExpectedSHA256(
        _ descriptor: ToolDependencyDescriptor,
        for data: Data
    ) -> ToolDependencyDescriptor {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        return ToolDependencyDescriptor(
            id: descriptor.id,
            displayName: descriptor.displayName,
            purpose: descriptor.purpose,
            downloadURL: descriptor.downloadURL,
            downloadSHA256: digest,
            packaging: descriptor.packaging,
            installDirectoryName: descriptor.installDirectoryName
        )
    }

    private func writeExecutable(at url: URL, contents: String) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}

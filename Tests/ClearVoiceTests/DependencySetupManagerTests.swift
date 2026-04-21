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
        let descriptor = ToolDependencyDescriptor.defaults().first { $0.id == .deepFilter }!
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
        let descriptor = ToolDependencyDescriptor.defaults().first { $0.id == .ffmpeg }!
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

    private func mergedEnvironment(appSupportRoot: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["CLEARVOICE_APP_SUPPORT_ROOT"] = appSupportRoot.path
        return environment
    }

    private func writeExecutable(at url: URL, contents: String) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}

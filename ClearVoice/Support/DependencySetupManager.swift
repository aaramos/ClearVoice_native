import Foundation

actor DependencySetupManager {
    typealias DownloadProgressHandler = @Sendable (ToolDownloadProgress) async -> Void
    typealias Downloader = @Sendable (URL, URL, DownloadProgressHandler) async throws -> Void
    typealias ArchiveExtractor = @Sendable (URL, URL) async throws -> Void
    typealias ProcessRunner = @Sendable (URL, [String]) async throws -> String

    nonisolated let plannedDependencies: [ToolDependencyDescriptor]
    private let fileManager: FileManager
    private let downloader: Downloader
    private let archiveExtractor: ArchiveExtractor
    private let processRunner: ProcessRunner
    private let environment: [String: String]

    init(
        descriptors: [ToolDependencyDescriptor] = ToolDependencyDescriptor.defaults(),
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        downloader: @escaping Downloader = DependencySetupManager.defaultDownloader,
        archiveExtractor: @escaping ArchiveExtractor = DependencySetupManager.defaultArchiveExtractor,
        processRunner: @escaping ProcessRunner = DependencySetupManager.defaultProcessRunner
    ) {
        self.plannedDependencies = descriptors
        self.fileManager = fileManager
        self.environment = environment
        self.downloader = downloader
        self.archiveExtractor = archiveExtractor
        self.processRunner = processRunner
    }

    func inspectAll() async -> [ToolDependencyRecord] {
        var records: [ToolDependencyRecord] = []

        for descriptor in plannedDependencies {
            records.append(await inspect(descriptor))
        }

        return records
    }

    func install(
        _ dependency: ToolDependencyDescriptor,
        progressHandler: @escaping @Sendable (ToolDependencyStatus) async -> Void
    ) async throws -> ToolDependencyRecord {
        let installDirectory = ManagedToolPaths.installDirectory(
            for: dependency,
            environment: environment,
            fileManager: fileManager
        )
        let downloadDirectory = ManagedToolPaths.downloadsRoot(
            environment: environment,
            fileManager: fileManager
        )

        try fileManager.createDirectory(at: installDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)

        let temporaryDownloadURL = downloadDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)

        do {
            try await progressHandler(.downloading(
                ToolDownloadProgress(
                    receivedBytes: 0,
                    expectedBytes: nil,
                    bytesPerSecond: 0,
                    estimatedTimeRemaining: nil
                )
            ))

            try await downloader(dependency.downloadURL, temporaryDownloadURL) { progress in
                await progressHandler(.downloading(progress))
            }

            try? fileManager.removeItem(at: installDirectory)
            try fileManager.createDirectory(at: installDirectory, withIntermediateDirectories: true)

            switch dependency.packaging {
            case .directBinary:
                let destinationURL = ManagedToolPaths.binaryURL(
                    for: dependency,
                    environment: environment,
                    fileManager: fileManager
                )
                try? fileManager.removeItem(at: destinationURL)
                try fileManager.moveItem(at: temporaryDownloadURL, to: destinationURL)
            case .zipArchive:
                await progressHandler(.extracting)
                try await archiveExtractor(temporaryDownloadURL, installDirectory)
            }

            let binaryURL = ManagedToolPaths.binaryURL(
                for: dependency,
                environment: environment,
                fileManager: fileManager
            )
            try markExecutable(binaryURL)

            await progressHandler(.verifying)

            let version = try await installedVersion(
                for: dependency,
                at: binaryURL
            )

            try? fileManager.removeItem(at: temporaryDownloadURL)

            return ToolDependencyRecord(
                descriptor: dependency,
                status: .installed(version: version, location: binaryURL, source: .managedByClearVoice)
            )
        } catch {
            try? fileManager.removeItem(at: temporaryDownloadURL)
            try? fileManager.removeItem(at: installDirectory)
            throw error
        }
    }

    private func inspect(_ dependency: ToolDependencyDescriptor) async -> ToolDependencyRecord {
        guard let location = resolvedBinaryURL(for: dependency) else {
            return ToolDependencyRecord(descriptor: dependency, status: .missing)
        }

        do {
            let version = try await installedVersion(for: dependency, at: location)
            let source: ToolDependencySource = ManagedToolPaths.isManagedTool(
                location,
                environment: environment,
                fileManager: fileManager
            )
                ? .managedByClearVoice
                : .existingSystemInstall

            return ToolDependencyRecord(
                descriptor: dependency,
                status: .installed(version: version, location: location, source: source)
            )
        } catch {
            return ToolDependencyRecord(
                descriptor: dependency,
                status: .failed(error.localizedDescription)
            )
        }
    }

    private func resolvedBinaryURL(for dependency: ToolDependencyDescriptor) -> URL? {
        switch dependency.id {
        case .ffmpeg:
            FFmpegSpeechFormatNormalizationService.resolveFFmpegURL(
                environment: environment,
                fileManager: fileManager
            )
        case .deepFilter:
            DeepFilterNetAudioEnhancementService.resolveDeepFilterURL(
                environment: environment,
                fileManager: fileManager
            )
        }
    }

    private func installedVersion(
        for dependency: ToolDependencyDescriptor,
        at binaryURL: URL
    ) async throws -> String {
        let output: String

        switch dependency.id {
        case .ffmpeg:
            output = try await processRunner(binaryURL, ["-version"])
            return parseFFmpegVersion(from: output)
        case .deepFilter:
            output = try await processRunner(binaryURL, ["--version"])
            return parseDeepFilterVersion(from: output)
        }
    }

    private func markExecutable(_ binaryURL: URL) throws {
        try fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: binaryURL.path
        )
    }

    private func parseFFmpegVersion(from output: String) -> String {
        guard let firstLine = output
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) else {
            return "Unknown Version"
        }

        if let range = firstLine.range(of: "ffmpeg version ") {
            let suffix = firstLine[range.upperBound...]
            return suffix.split(separator: " ").first.map(String.init) ?? firstLine
        }

        return firstLine
    }

    private func parseDeepFilterVersion(from output: String) -> String {
        let firstLine = output
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "Unknown Version"

        if let version = firstLine.split(separator: " ").last {
            return String(version)
        }

        return firstLine
    }

    private static let defaultDownloader: Downloader = { downloadURL, destinationURL, progressHandler in
        let request = URLRequest(url: downloadURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        let expectedBytes = response.expectedContentLength > 0 ? response.expectedContentLength : nil

        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: destinationURL.path, contents: nil)

        let handle = try FileHandle(forWritingTo: destinationURL)
        defer { try? handle.close() }

        var receivedBytes: Int64 = 0
        var buffer = [UInt8]()
        buffer.reserveCapacity(64 * 1024)
        let startTime = Date()
        var lastUpdate = startTime

        for try await byte in bytes {
            buffer.append(byte)

            if buffer.count >= 64 * 1024 {
                let data = Data(buffer)
                try handle.write(contentsOf: data)
                receivedBytes += Int64(data.count)
                buffer.removeAll(keepingCapacity: true)

                let now = Date()
                if now.timeIntervalSince(lastUpdate) >= 0.12 {
                    lastUpdate = now
                    let elapsed = max(now.timeIntervalSince(startTime), 0.001)
                    let bytesPerSecond = Double(receivedBytes) / elapsed
                    let eta = expectedBytes.map { expected -> TimeInterval in
                        guard bytesPerSecond > 0 else { return .infinity }
                        return Double(max(expected - receivedBytes, 0)) / bytesPerSecond
                    }

                    await progressHandler(
                        ToolDownloadProgress(
                            receivedBytes: receivedBytes,
                            expectedBytes: expectedBytes,
                            bytesPerSecond: bytesPerSecond,
                            estimatedTimeRemaining: eta
                        )
                    )
                }
            }
        }

        if !buffer.isEmpty {
            let data = Data(buffer)
            try handle.write(contentsOf: data)
            receivedBytes += Int64(data.count)
        }

        let elapsed = max(Date().timeIntervalSince(startTime), 0.001)
        let bytesPerSecond = Double(receivedBytes) / elapsed

        await progressHandler(
            ToolDownloadProgress(
                receivedBytes: receivedBytes,
                expectedBytes: expectedBytes,
                bytesPerSecond: bytesPerSecond,
                estimatedTimeRemaining: 0
            )
        )
    }

    private static let defaultArchiveExtractor: ArchiveExtractor = { archiveURL, destinationDirectory in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = [
            "-o",
            archiveURL.path,
            "-d",
            destinationDirectory.path,
        ]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let detail = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw LaunchRequirementsError.dependencyInstallFailed(
                "ClearVoice couldn’t unpack FFmpeg\(detail.map { ": \($0)" } ?? ".")"
            )
        }
    }

    private static let defaultProcessRunner: ProcessRunner = { executableURL, arguments in
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let combined = outputData + errorData

        guard process.terminationStatus == 0 else {
            let detail = String(data: combined, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? "Unknown tool verification failure."
            throw LaunchRequirementsError.dependencyInstallFailed(detail)
        }

        return String(data: combined, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
    }
}

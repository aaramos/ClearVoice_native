import Foundation

@MainActor
final class ImportViewModel: ObservableObject {
    @Published private(set) var sourceFolderURL: URL?
    @Published private(set) var outputFolderURL: URL?
    @Published private(set) var scanResult: ScanResult = .empty
    @Published private(set) var validationMessages: [String] = [
        "Choose a source folder to begin.",
    ]
    @Published private(set) var isScanning = false
    @Published private(set) var scanErrorMessage: String?

    private let fileScanner: any FileScanner
    private let fileManager: FileManager
    private var scanTask: Task<Void, Never>?

    init(
        fileScanner: any FileScanner = LocalFileScanner(),
        fileManager: FileManager = .default
    ) {
        self.fileScanner = fileScanner
        self.fileManager = fileManager
    }

    var canProceed: Bool {
        !isScanning && scanErrorMessage == nil && validationMessages.isEmpty && !scanResult.supported.isEmpty
    }

    var supportedFileCount: Int {
        scanResult.supported.count
    }

    var skippedFileCount: Int {
        scanResult.skipped.count
    }

    var formattedDuration: String {
        DurationFormatter.formattedDuration(seconds: scanResult.totalDurationSeconds)
    }

    var readyFiles: [ScannedAudioFile] {
        scanResult.supported
    }

    var plannedOutputFolderDisplayPath: String {
        outputFolderURL?.path(percentEncoded: false) ?? ""
    }

    func reset() {
        scanTask?.cancel()
        scanTask = nil
        sourceFolderURL = nil
        outputFolderURL = nil
        scanResult = .empty
        validationMessages = ["Choose a source folder to begin."]
        isScanning = false
        scanErrorMessage = nil
    }

    func selectSourceFolder(_ url: URL) {
        sourceFolderURL = standardizedDirectoryURL(url)
        outputFolderURL = makeDesktopOutputFolderURL()
        scheduleScan()
    }

    func waitForScheduledScan() async {
        await scanTask?.value
    }

    private func scheduleScan() {
        scanTask?.cancel()
        scanErrorMessage = nil
        scanResult = .empty
        evaluateValidation()

        guard let sourceFolderURL else { return }

        isScanning = true
        let recursiveScan = true

        scanTask = Task { [fileScanner] in
            do {
                let result = try await fileScanner.scan(folder: sourceFolderURL, recursive: recursiveScan)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    self.scanResult = result
                    self.isScanning = false
                    self.scanErrorMessage = nil
                    self.evaluateValidation()
                }
            } catch {
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    self.scanResult = .empty
                    self.isScanning = false
                    self.scanErrorMessage = "Couldn’t scan the selected folder. Check that it’s readable and try again."
                    self.evaluateValidation()
                }
            }
        }
    }

    private func evaluateValidation() {
        var messages: [String] = []

        if let sourceFolderURL {
            messages.append(contentsOf: validationMessages(forSourceFolder: sourceFolderURL))
        } else {
            messages.append("Choose a source folder to begin.")
        }

        if let sourceFolderURL, let outputFolderURL {
            let sourcePath = sourceFolderURL.resolvingSymlinksInPath().standardizedFileURL.path
            let outputPath = outputFolderURL.resolvingSymlinksInPath().standardizedFileURL.path

            if sourcePath == outputPath {
                messages.append("Source and output folders must be different.")
            } else if outputPath.hasPrefix(sourcePath + "/") {
                messages.append("Output folder can’t be inside the source folder.")
            }

            messages.append(contentsOf: validationMessages(forPlannedOutputFolder: outputFolderURL))
        }

        if scanErrorMessage != nil {
            messages.append("Scanning failed. Choose a readable source folder and try again.")
        } else if sourceFolderURL != nil && !isScanning && scanResult.supported.isEmpty {
            messages.append("No supported audio files were found in the selected source folder.")
        }

        validationMessages = Array(NSOrderedSet(array: messages)) as? [String] ?? messages
    }

    private func validationMessages(forSourceFolder url: URL) -> [String] {
        directoryValidationMessages(
            for: url,
            readableRequirement: true,
            writableRequirement: false,
            missingMessage: "Source folder must exist and be readable."
        )
    }

    private func validationMessages(forPlannedOutputFolder url: URL) -> [String] {
        let parentURL = url.deletingLastPathComponent()
        let parentPath = parentURL.path(percentEncoded: false)
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: parentPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            return ["ClearVoice couldn’t access the Desktop output location."]
        }

        guard fileManager.isWritableFile(atPath: parentPath) else {
            return ["ClearVoice needs write access to the Desktop output location."]
        }

        return []
    }

    private func directoryValidationMessages(
        for url: URL,
        readableRequirement: Bool,
        writableRequirement: Bool,
        missingMessage: String
    ) -> [String] {
        var messages: [String] = []
        let path = url.path(percentEncoded: false)
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            messages.append(missingMessage)
            return messages
        }

        if readableRequirement && !fileManager.isReadableFile(atPath: path) {
            messages.append(missingMessage)
        }

        if writableRequirement && !fileManager.isWritableFile(atPath: path) {
            messages.append(missingMessage)
        }

        return messages
    }

    private func standardizedDirectoryURL(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }

    private func makeDesktopOutputFolderURL(now: Date = Date()) -> URL {
        let desktopURL = fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
        let timestamp = Self.outputTimestampFormatter.string(from: now)
        return desktopURL.appendingPathComponent("output_\(timestamp)", isDirectory: true)
    }

    private static let outputTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()
}

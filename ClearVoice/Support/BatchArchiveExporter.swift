import Foundation

enum BatchArchiveExportError: LocalizedError {
    case missingOutputFolder
    case archiveFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingOutputFolder:
            return "ClearVoice couldn’t find the batch output folder to archive."
        case .archiveFailed(let message):
            return message
        }
    }
}

struct BatchArchiveExporter: Sendable {
    func exportArchive(for outputFolderURL: URL) throws -> URL {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: outputFolderURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw BatchArchiveExportError.missingOutputFolder
        }

        let archiveURL = outputFolderURL.deletingPathExtension().appendingPathExtension("zip")
        if fileManager.fileExists(atPath: archiveURL.path) {
            try fileManager.removeItem(at: archiveURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [
            "-c",
            "-k",
            "--sequesterRsrc",
            "--keepParent",
            outputFolderURL.path,
            archiveURL.path,
        ]

        let stderr = Pipe()
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw BatchArchiveExportError.archiveFailed(
                message?.isEmpty == false
                    ? message!
                    : "ClearVoice couldn’t create the ZIP archive for this batch."
            )
        }

        return archiveURL
    }
}

import Foundation

protocol ExportService: Sendable {
    func exportCleanAudio(from tempURL: URL, to finalURL: URL) async throws
    func exportTranscript(
        to folderURL: URL,
        basename: String,
        summary: String?,
        translated: String?,
        original: Transcript
    ) async throws
    func writeErrorLog(
        to folderURL: URL,
        error: ProcessingError,
        context: [String: String]
    ) async throws
}

actor DefaultExportService: ExportService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func exportCleanAudio(from tempURL: URL, to finalURL: URL) async throws {
        try ensureParentDirectory(for: finalURL)
        try fileManager.copyItem(at: tempURL, to: finalURL)
    }

    func exportTranscript(
        to folderURL: URL,
        basename: String,
        summary: String?,
        translated: String?,
        original: Transcript
    ) async throws {
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let transcriptURL = folderURL.appendingPathComponent("\(basename)_transcript.txt")
        let transcript = transcriptContents(
            summary: summary,
            translated: translated,
            original: original
        )

        guard let data = transcript.data(using: .utf8) else {
            throw ProcessingError.exportFailed("Couldn’t encode the transcript as UTF-8.")
        }

        try data.write(to: transcriptURL, options: .atomic)
    }

    func writeErrorLog(
        to folderURL: URL,
        error: ProcessingError,
        context: [String: String]
    ) async throws {
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let logURL = folderURL.appendingPathComponent("_error.log")
        var lines = [
            "CLEARVOICE ERROR",
            "error: \(String(describing: error))",
        ]

        for key in context.keys.sorted() {
            if let value = context[key] {
                lines.append("\(key): \(value)")
            }
        }

        guard let data = lines.joined(separator: "\n").data(using: .utf8) else {
            throw ProcessingError.exportFailed("Couldn’t encode the error log as UTF-8.")
        }

        try data.write(to: logURL, options: .atomic)
    }

    private func ensureParentDirectory(for url: URL) throws {
        let parentURL = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
    }

    private func transcriptContents(
        summary: String?,
        translated: String?,
        original: Transcript
    ) -> String {
        var sections: [String] = []

        if let summary {
            sections.append(contentsOf: [
                "SUMMARY",
                summary,
                "",
            ])
        }

        if let translated {
            sections.append(contentsOf: [
                "TRANSLATED TRANSCRIPT",
                translated,
                "",
            ])
        }

        sections.append(contentsOf: [
            "ORIGINAL TRANSCRIPT",
            original.exportText,
        ])

        return sections.joined(separator: "\n") + "\n"
    }
}

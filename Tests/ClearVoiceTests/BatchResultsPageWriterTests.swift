import Foundation
import Testing
@testable import ClearVoice

struct BatchResultsPageWriterTests {
    @Test
    func writePageIncludesAudioLinksAndFailureDetails() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let outputFolder = root.appendingPathComponent("output_20260421_120000", isDirectory: true)
        let completedFolder = outputFolder.appendingPathComponent("Sample One", isDirectory: true)
        let failedFolder = outputFolder.appendingPathComponent("Sample Two", isDirectory: true)

        try fileManager.createDirectory(at: completedFolder, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: failedFolder, withIntermediateDirectories: true)

        let audioURL = completedFolder.appendingPathComponent("Sample One_HYBRID.m4a")
        try Data("audio".utf8).write(to: audioURL)
        let sourceCopyURL = completedFolder.appendingPathComponent("Sample One.wav")
        try Data("source".utf8).write(to: sourceCopyURL)

        let files = [
            AudioFileItem(
                id: UUID(),
                sourceURL: root.appendingPathComponent("Sample One.wav"),
                durationSeconds: 61,
                outputFolderURL: completedFolder,
                stage: .complete
            ),
            AudioFileItem(
                id: UUID(),
                sourceURL: root.appendingPathComponent("Sample Two.wav"),
                durationSeconds: 42,
                outputFolderURL: failedFolder,
                stage: .failed(error: .enhancementFailed("DeepFilterNet failed on this file."))
            ),
        ]

        let writer = BatchResultsPageWriter(fileManager: fileManager)
        let pageURL = try writer.writePage(
            into: outputFolder,
            files: files,
            enhancementMethod: .hybrid
        )

        let html = try String(contentsOf: pageURL)

        #expect(fileManager.fileExists(atPath: pageURL.path))
        #expect(html.contains("ClearVoice Results"))
        #expect(html.contains("Sample One"))
        #expect(html.contains("Sample%20One/Sample%20One_HYBRID.m4a"))
        #expect(html.contains("Sample%20One/Sample%20One.wav"))
        #expect(html.contains("Browse folder"))
        #expect(html.contains("Open enhanced file"))
        #expect(html.contains("Open source file"))
        #expect(html.contains("Starts on enhanced audio and switches at the same playback position."))
        #expect(html.contains("data-audio-toggle=\"enhanced\""))
        #expect(html.contains("data-audio-toggle=\"source\""))
        #expect(html.contains("DeepFilterNet failed on this file."))
        #expect(html.contains("Enhanced with Hybrid"))
        #expect(!html.contains("Batch Folder"))
    }
}

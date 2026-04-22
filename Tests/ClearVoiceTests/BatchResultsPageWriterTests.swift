import Foundation
import Testing
@testable import ClearVoice

struct BatchResultsPageWriterTests {
    @Test
    func writePageIncludesMirroredEnhancedLinksAndOriginalSourceLinks() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceFolder = root.appendingPathComponent("source", isDirectory: true)
        let outputFolder = root.appendingPathComponent("source_enhanced", isDirectory: true)
        let completedSourceFolder = sourceFolder.appendingPathComponent("Session A", isDirectory: true)
        let completedOutputFolder = outputFolder.appendingPathComponent("Session A", isDirectory: true)
        let failedSourceFolder = sourceFolder.appendingPathComponent("Session B", isDirectory: true)
        let failedOutputFolder = outputFolder.appendingPathComponent("Session B", isDirectory: true)

        try fileManager.createDirectory(at: completedSourceFolder, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: completedOutputFolder, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: failedSourceFolder, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: failedOutputFolder, withIntermediateDirectories: true)

        let sourceAudioURL = completedSourceFolder.appendingPathComponent("Sample One.wav")
        try Data("source".utf8).write(to: sourceAudioURL)

        let enhancedAudioURL = completedOutputFolder.appendingPathComponent("Sample One_HYBRID.m4a")
        try Data("audio".utf8).write(to: enhancedAudioURL)

        let files = [
            AudioFileItem(
                id: UUID(),
                sourceURL: sourceAudioURL,
                durationSeconds: 61,
                outputFolderURL: completedOutputFolder,
                processedAudioURL: enhancedAudioURL,
                stage: .complete
            ),
            AudioFileItem(
                id: UUID(),
                sourceURL: failedSourceFolder.appendingPathComponent("Sample Two.wav"),
                durationSeconds: 42,
                outputFolderURL: failedOutputFolder,
                stage: .failed(error: .enhancementFailed("DeepFilterNet failed on this file."))
            ),
        ]

        let writer = BatchResultsPageWriter(fileManager: fileManager)
        let pageURL = try writer.writePage(
            into: outputFolder,
            sourceFolderURL: sourceFolder,
            files: files,
            enhancementMethod: .hybrid
        )

        let html = try String(contentsOf: pageURL)

        #expect(fileManager.fileExists(atPath: pageURL.path))
        #expect(html.contains("ClearVoice Results"))
        #expect(html.contains("Sample One"))
        #expect(html.contains("Session%20A/Sample%20One_HYBRID.m4a"))
        #expect(html.contains("../source/Session%20A/Sample%20One.wav"))
        #expect(html.contains("Browse folder"))
        #expect(html.contains("Open enhanced file"))
        #expect(html.contains("Open source file"))
        #expect(html.contains("Starts on enhanced audio and switches at the same playback position."))
        #expect(html.contains("data-audio-toggle=\"enhanced\""))
        #expect(html.contains("data-audio-toggle=\"source\""))
        #expect(html.contains("DeepFilterNet failed on this file."))
        #expect(html.contains("Enhanced with Hybrid"))
        #expect(html.contains("Source playback links back to the original source folder"))
    }
}

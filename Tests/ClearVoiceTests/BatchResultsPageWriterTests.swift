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
        #expect(!html.contains("Open enhanced file"))
        #expect(!html.contains("Open source file"))
        #expect(html.contains("justify-content: flex-end;"))
        #expect(html.contains("Starts on enhanced audio and switches at the same playback position."))
        #expect(html.contains("data-audio-toggle=\"enhanced\""))
        #expect(html.contains("data-audio-toggle=\"source\""))
        #expect(html.contains("DeepFilterNet failed on this file."))
        #expect(html.contains("Enhanced with Hybrid"))
        #expect(html.contains("Source playback links back to the original source folder"))
    }

    @Test
    func writePageDecodesPercentEncodedDisplayNames() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceFolder = root.appendingPathComponent("source", isDirectory: true)
        let outputFolder = root.appendingPathComponent("source_enhanced", isDirectory: true)
        let sourceSubfolder = sourceFolder.appendingPathComponent("Archive%20A", isDirectory: true)
        let outputSubfolder = outputFolder.appendingPathComponent("Archive%20A", isDirectory: true)

        try fileManager.createDirectory(at: sourceSubfolder, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outputSubfolder, withIntermediateDirectories: true)

        let sourceAudioURL = sourceSubfolder.appendingPathComponent("010.%2011%20may%201980%20ch23%20v53.mp3")
        let enhancedAudioURL = outputSubfolder.appendingPathComponent("010.%2011%20may%201980%20ch23%20v53_DFN.m4a")

        try Data("source".utf8).write(to: sourceAudioURL)
        try Data("audio".utf8).write(to: enhancedAudioURL)

        let files = [
            AudioFileItem(
                id: UUID(),
                sourceURL: sourceAudioURL,
                durationSeconds: 61,
                outputFolderURL: outputSubfolder,
                processedAudioURL: enhancedAudioURL,
                stage: .complete
            ),
        ]

        let writer = BatchResultsPageWriter(fileManager: fileManager)
        let pageURL = try writer.writePage(
            into: outputFolder,
            sourceFolderURL: sourceFolder,
            files: files,
            enhancementMethod: .dfn
        )

        let html = try String(contentsOf: pageURL)

        #expect(html.contains("010. 11 may 1980 ch23 v53.mp3"))
        #expect(html.contains("Archive A/010. 11 may 1980 ch23 v53.mp3"))
        #expect(html.contains("Archive%2520A/010.%252011%2520may%25201980%2520ch23%2520v53_DFN.m4a"))
    }
}

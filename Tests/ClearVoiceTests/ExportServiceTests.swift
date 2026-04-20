import Foundation
import Testing
@testable import ClearVoice

struct ExportServiceTests {
    @Test
    func transcriptExportMatchesGoldenFile() async throws {
        let harness = try ExportHarness()
        let service = DefaultExportService()

        try await service.exportTranscript(
            to: harness.outputFolder,
            basename: "meeting01",
            summary: "Concise summary in English.",
            translated: "This is the translated transcript.",
            original: "यह मूल प्रतिलेख है।"
        )

        let exportedURL = harness.outputFolder.appendingPathComponent("meeting01_transcript.txt")
        let expectedURL = fixtureURL(named: "expected_transcript.txt")

        let exportedData = try Data(contentsOf: exportedURL)
        let expectedData = try Data(contentsOf: expectedURL)

        #expect(exportedData == expectedData)
        #expect(!exportedData.starts(with: [0xEF, 0xBB, 0xBF]))
        #expect(String(decoding: exportedData, as: UTF8.self).contains("\r") == false)
    }

    @Test
    func cleanAudioExportCopiesBytesToTheFinalLocation() async throws {
        let harness = try ExportHarness()
        let service = DefaultExportService()
        let tempAudioURL = harness.root.appendingPathComponent("scratch_clean_audio.m4a")
        let finalAudioURL = harness.outputFolder.appendingPathComponent("meeting01_clean.m4a")
        let audioBytes = Data([0x43, 0x4C, 0x56, 0x31, 0x00, 0xA4])

        try audioBytes.write(to: tempAudioURL)
        try await service.exportCleanAudio(from: tempAudioURL, to: finalAudioURL)

        #expect(try Data(contentsOf: finalAudioURL) == audioBytes)
    }

    @Test
    func transcriptExportOmitsSummarySectionWhenSummaryIsNil() async throws {
        let harness = try ExportHarness()
        let service = DefaultExportService()

        try await service.exportTranscript(
            to: harness.outputFolder,
            basename: "meeting02",
            summary: nil,
            translated: "Translated text only.",
            original: "Original text only."
        )

        let exportedURL = harness.outputFolder.appendingPathComponent("meeting02_transcript.txt")
        let transcript = try String(contentsOf: exportedURL, encoding: .utf8)

        #expect(!transcript.contains("SUMMARY"))
        #expect(transcript.hasPrefix("TRANSLATED TRANSCRIPT\nTranslated text only.\n\nORIGINAL TRANSCRIPT\nOriginal text only.\n"))
    }
}

private struct ExportHarness {
    let root: URL
    let outputFolder: URL

    init() throws {
        let fileManager = FileManager.default
        root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        outputFolder = root.appendingPathComponent("export", isDirectory: true)
        try fileManager.createDirectory(at: outputFolder, withIntermediateDirectories: true)
    }
}

private func fixtureURL(named name: String) -> URL {
    URL(filePath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures", isDirectory: true)
        .appendingPathComponent(name)
}

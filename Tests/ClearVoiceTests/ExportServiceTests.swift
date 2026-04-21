import Foundation
import Testing
@testable import ClearVoice

struct ExportServiceTests {
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
    func writeErrorLogIncludesSortedContextFields() async throws {
        let harness = try ExportHarness()
        let service = DefaultExportService()

        try await service.writeErrorLog(
            to: harness.outputFolder,
            error: .enhancementFailed("DeepFilterNet missing"),
            context: [
                "sourceFile": "meeting02.wav",
                "stage": "enhancing",
            ]
        )

        let exportedURL = harness.outputFolder.appendingPathComponent("_error.log")
        let logContents = try String(contentsOf: exportedURL, encoding: .utf8)

        #expect(logContents == """
        CLEARVOICE ERROR
        error: enhancementFailed(\"DeepFilterNet missing\")
        sourceFile: meeting02.wav
        stage: enhancing
        """)
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

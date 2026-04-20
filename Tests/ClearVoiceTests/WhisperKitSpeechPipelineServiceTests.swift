import Foundation
import Testing
@testable import ClearVoice

struct WhisperKitSpeechPipelineServiceTests {
    @Test
    func configUsesDownloadBaseInsteadOfLocalModelFolder() async {
        let modelDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let service = WhisperKitSpeechPipelineService(modelDirectory: modelDirectory)

        let config = await service.makeConfig()

        #expect(config.downloadBase?.path == modelDirectory.path)
        #expect(config.modelFolder == nil)
        #expect(config.load == true)
        #expect(config.download)
    }

    @Test
    func missingMelSpectrogramMapsToActionableTranscriptionError() async throws {
        let service = WhisperKitSpeechPipelineService()
        let error = NSError(
            domain: "WhisperKit",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "Model file not found at /tmp/MelSpectrogram.mlmodelc"
            ]
        )

        let mapped = await service.mapError(error)
        let processingError = try #require(mapped as? ProcessingError)

        #expect(
            processingError == .transcriptionFailed(
                "ClearVoice couldn’t finish setting up the local speech model on this Mac. Keep the Mac online and try again so the Whisper model can download completely."
            )
        )
    }
}

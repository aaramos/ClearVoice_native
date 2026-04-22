import Testing
@testable import ClearVoice

struct ProcessingErrorTests {
    @Test
    func diskFullFailuresUseFriendlyDisplayMessage() {
        let error = ProcessingError.enhancementFailed(
            "ClearVoice couldn’t run ffmpeg: Error writing trailer: No space left on device"
        )

        #expect(error.displayMessage.contains("ran out of free disk space"))
        #expect(error.displayMessage.contains("1 file at a time"))
    }

    @Test
    func nonDiskFailuresKeepOriginalMessage() {
        let error = ProcessingError.enhancementFailed("DeepFilterNet missing")

        #expect(error.displayMessage == "DeepFilterNet missing")
    }
}

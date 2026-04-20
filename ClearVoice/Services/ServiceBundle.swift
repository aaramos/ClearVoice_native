import Foundation

struct ServiceBundle: Sendable {
    let audioEnhancement: any AudioEnhancementService
    let transcription: any TranscriptionService
    let translation: any TranslationService
    let summarization: any SummarizationService
    let export: any ExportService

    static let stub = ServiceBundle(
        audioEnhancement: StubAudioEnhancementService(),
        transcription: StubTranscriptionService(),
        translation: StubTranslationService(),
        summarization: StubSummarizationService(),
        export: DefaultExportService()
    )
}

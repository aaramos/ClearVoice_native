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

    static func live(
        geminiAPIKey: String,
        transport: any HTTPTransport = URLSessionHTTPTransport(),
        retryPolicy: RetryPolicy = .default
    ) -> ServiceBundle {
        let geminiClient = GeminiDeveloperClient(
            apiKey: geminiAPIKey,
            transport: transport,
            retryPolicy: retryPolicy
        )

        return ServiceBundle(
            audioEnhancement: StubAudioEnhancementService(),
            transcription: GeminiTranscriptionService(client: geminiClient),
            translation: GeminiTranslationService(client: geminiClient),
            summarization: GeminiSummarizationService(client: geminiClient),
            export: DefaultExportService()
        )
    }
}

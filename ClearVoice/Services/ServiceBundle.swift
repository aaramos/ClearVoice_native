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
        openAIAPIKey: String,
        ollamaAPIKey: String,
        transport: any HTTPTransport = URLSessionHTTPTransport(),
        retryPolicy: RetryPolicy = .default
    ) -> ServiceBundle {
        let ollamaClient = OllamaCloudChatClient(
            apiKey: ollamaAPIKey,
            transport: transport,
            retryPolicy: retryPolicy
        )

        return ServiceBundle(
            audioEnhancement: StubAudioEnhancementService(),
            transcription: OpenAIWhisperTranscriptionService(
                apiKey: openAIAPIKey,
                transport: transport,
                retryPolicy: retryPolicy
            ),
            translation: OllamaTranslationService(chatClient: ollamaClient),
            summarization: OllamaSummarizationService(chatClient: ollamaClient),
            export: DefaultExportService()
        )
    }
}

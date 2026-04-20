import Foundation

struct ServiceBundle: Sendable {
    let apiKeyPresent: Bool
    let audioEnhancement: any AudioEnhancementService
    let formatNormalizationService: any FormatNormalizationService
    let cloudPreparationService: any CloudAudioPreparationService
    private let localTranscription: any TranscriptionService
    private let cloudTranscription: any TranscriptionService
    private let localTranslation: any TranslationService
    private let cloudTranslation: any TranslationService
    private let localSummarization: any SummarizationService
    private let cloudSummarization: any SummarizationService
    let export: any ExportService

    init(
        apiKeyPresent: Bool = false,
        audioEnhancement: any AudioEnhancementService,
        formatNormalizationService: any FormatNormalizationService = StubFormatNormalizationService(),
        cloudPreparationService: any CloudAudioPreparationService = NoOpCloudAudioPreparationService(),
        localTranscription: any TranscriptionService,
        cloudTranscription: any TranscriptionService,
        localTranslation: any TranslationService,
        cloudTranslation: any TranslationService,
        localSummarization: any SummarizationService,
        cloudSummarization: any SummarizationService,
        export: any ExportService
    ) {
        self.apiKeyPresent = apiKeyPresent
        self.audioEnhancement = audioEnhancement
        self.formatNormalizationService = formatNormalizationService
        self.cloudPreparationService = cloudPreparationService
        self.localTranscription = localTranscription
        self.cloudTranscription = cloudTranscription
        self.localTranslation = localTranslation
        self.cloudTranslation = cloudTranslation
        self.localSummarization = localSummarization
        self.cloudSummarization = cloudSummarization
        self.export = export
    }

    init(
        apiKeyPresent: Bool = false,
        audioEnhancement: any AudioEnhancementService,
        transcription: any TranscriptionService,
        translation: any TranslationService,
        summarization: any SummarizationService,
        export: any ExportService,
        formatNormalizationService: any FormatNormalizationService = StubFormatNormalizationService(),
        cloudPreparationService: any CloudAudioPreparationService = NoOpCloudAudioPreparationService()
    ) {
        self.init(
            apiKeyPresent: apiKeyPresent,
            audioEnhancement: audioEnhancement,
            formatNormalizationService: formatNormalizationService,
            cloudPreparationService: cloudPreparationService,
            localTranscription: transcription,
            cloudTranscription: transcription,
            localTranslation: translation,
            cloudTranslation: translation,
            localSummarization: summarization,
            cloudSummarization: summarization,
            export: export
        )
    }

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
            apiKeyPresent: true,
            audioEnhancement: StubAudioEnhancementService(),
            formatNormalizationService: FFmpegFormatNormalizationService(),
            cloudPreparationService: AVFoundationCloudPreparationService(),
            localTranscription: LocalSpeechTranscriptionService(),
            cloudTranscription: GeminiTranscriptionService(client: geminiClient),
            localTranslation: LocalTranslationService(),
            cloudTranslation: GeminiTranslationService(client: geminiClient),
            localSummarization: UnavailableSummarizationService(),
            cloudSummarization: GeminiSummarizationService(client: geminiClient),
            export: DefaultExportService()
        )
    }

    func transcriptionService(for config: BatchConfiguration) -> any TranscriptionService {
        config.processingMode.transcription == .cloud ? cloudTranscription : localTranscription
    }

    func cloudTranscriptionService() -> any TranscriptionService {
        cloudTranscription
    }

    func translationService(for config: BatchConfiguration) -> any TranslationService {
        config.processingMode.translation == .cloud ? cloudTranslation : localTranslation
    }

    func cloudTranslationService() -> any TranslationService {
        cloudTranslation
    }

    func summarizationService(for config: BatchConfiguration) -> any SummarizationService {
        config.processingMode.summarizationEnabled ? cloudSummarization : localSummarization
    }
}

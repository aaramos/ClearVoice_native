import Foundation

struct ServiceBundle: Sendable {
    let audioEnhancement: any AudioEnhancementService
    let formatNormalizationService: any FormatNormalizationService
    let speechPipeline: any SpeechPipelineService
    let summaryPlaceholder: String
    let export: any ExportService

    init(
        audioEnhancement: any AudioEnhancementService,
        formatNormalizationService: any FormatNormalizationService = StubFormatNormalizationService(),
        speechPipeline: any SpeechPipelineService,
        summaryPlaceholder: String = SummaryPlaceholders.pendingImplementation,
        export: any ExportService
    ) {
        self.audioEnhancement = audioEnhancement
        self.formatNormalizationService = formatNormalizationService
        self.speechPipeline = speechPipeline
        self.summaryPlaceholder = summaryPlaceholder
        self.export = export
    }

    init(
        audioEnhancement: any AudioEnhancementService,
        transcription: any TranscriptionService,
        translation: any TranslationService,
        summarization: any SummarizationService,
        export: any ExportService,
        formatNormalizationService: any FormatNormalizationService = StubFormatNormalizationService(),
        summaryPlaceholder: String = SummaryPlaceholders.pendingImplementation
    ) {
        self.init(
            audioEnhancement: audioEnhancement,
            formatNormalizationService: formatNormalizationService,
            speechPipeline: ComposedSpeechPipelineService(
                transcription: transcription,
                translation: translation
            ),
            summaryPlaceholder: summaryPlaceholder,
            export: export
        )
    }

    static let stub = ServiceBundle(
        audioEnhancement: StubAudioEnhancementService(),
        speechPipeline: StubSpeechPipelineService(),
        export: DefaultExportService()
    )

    static func live(
        modelDirectory: URL? = nil
    ) -> ServiceBundle {
        let translationService = LocalOllamaTranslationService()

        return ServiceBundle(
            audioEnhancement: FFmpegAudioEnhancementService(),
            formatNormalizationService: FFmpegSpeechFormatNormalizationService(),
            speechPipeline: WhisperKitSpeechPipelineService(
                modelDirectory: modelDirectory,
                translationService: translationService
            ),
            export: DefaultExportService()
        )
    }
}

enum SummaryPlaceholders {
    static let pendingImplementation = "Summary placeholder: local summarization is not included in this release yet."
}

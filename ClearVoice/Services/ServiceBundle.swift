import Foundation

struct ServiceBundle: Sendable {
    let audioEnhancement: any AudioEnhancementService
    let comparisonEnhancements: [any ComparisonEnhancementService]
    let formatNormalizationService: any FormatNormalizationService
    let transcriptionPreparationService: any TranscriptionPreparationService
    let speechPipeline: any SpeechPipelineService
    let summaryPlaceholder: String
    let export: any ExportService

    init(
        audioEnhancement: any AudioEnhancementService,
        comparisonEnhancements: [any ComparisonEnhancementService] = [],
        formatNormalizationService: any FormatNormalizationService = StubFormatNormalizationService(),
        transcriptionPreparationService: any TranscriptionPreparationService = StubTranscriptionPreparationService(),
        speechPipeline: any SpeechPipelineService,
        summaryPlaceholder: String = SummaryPlaceholders.pendingImplementation,
        export: any ExportService
    ) {
        self.audioEnhancement = audioEnhancement
        self.comparisonEnhancements = comparisonEnhancements
        self.formatNormalizationService = formatNormalizationService
        self.transcriptionPreparationService = transcriptionPreparationService
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
        transcriptionPreparationService: any TranscriptionPreparationService = StubTranscriptionPreparationService(),
        summaryPlaceholder: String = SummaryPlaceholders.pendingImplementation
    ) {
        self.init(
            audioEnhancement: audioEnhancement,
            formatNormalizationService: formatNormalizationService,
            transcriptionPreparationService: transcriptionPreparationService,
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
        return ServiceBundle(
            audioEnhancement: FFmpegAudioEnhancementService(),
            comparisonEnhancements: DeepFilterNetAudioEnhancementService.availableVariants(),
            formatNormalizationService: FFmpegSpeechFormatNormalizationService(),
            transcriptionPreparationService: FFmpegTranscriptionPreparationService(),
            speechPipeline: TranscriptionOnlySpeechPipelineService(
                transcription: WhisperCppTranscriptionService(
                    modelDirectory: modelDirectory?.appendingPathComponent("whisper.cpp", isDirectory: true)
                )
            ),
            export: DefaultExportService()
        )
    }
}

enum SummaryPlaceholders {
    static let pendingImplementation = "Summary placeholder: local summarization is not included in this release yet."
}

import Foundation

struct ServiceBundle: Sendable {
    let audioEnhancement: any AudioEnhancementService
    let comparisonEnhancements: [any ComparisonEnhancementService]
    let formatNormalizationService: any FormatNormalizationService
    let export: any ExportService

    init(
        audioEnhancement: any AudioEnhancementService,
        comparisonEnhancements: [any ComparisonEnhancementService] = [],
        formatNormalizationService: any FormatNormalizationService = StubFormatNormalizationService(),
        export: any ExportService
    ) {
        self.audioEnhancement = audioEnhancement
        self.comparisonEnhancements = comparisonEnhancements
        self.formatNormalizationService = formatNormalizationService
        self.export = export
    }

    static let stub = ServiceBundle(
        audioEnhancement: StubAudioEnhancementService(),
        export: DefaultExportService()
    )

    static func live() -> ServiceBundle {
        return ServiceBundle(
            audioEnhancement: FFmpegAudioEnhancementService(),
            comparisonEnhancements: DeepFilterNetAudioEnhancementService.availableVariants(),
            formatNormalizationService: FFmpegSpeechFormatNormalizationService(),
            export: DefaultExportService()
        )
    }
}

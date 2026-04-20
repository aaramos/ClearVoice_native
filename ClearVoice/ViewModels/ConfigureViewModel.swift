import Foundation
import Speech

@MainActor
final class ConfigureViewModel: ObservableObject {
    @Published var intensity = Intensity.balanced
    @Published var inputLanguage = Language.autoDetect {
        didSet {
            Task { await updateRoutingForLanguage(inputLanguage) }
        }
    }
    @Published var outputLanguage = Language.english
    @Published var maxConcurrency = 3
    @Published var preserveChannels = false
    @Published var transcriptionMode: ProcessingMode {
        didSet { persistProcessingModes() }
    }
    @Published var translationMode: ProcessingMode {
        didSet { persistProcessingModes() }
    }
    @Published private(set) var canToggleTranscription: Bool
    @Published private(set) var canStart: Bool

    let apiKeyPresent: Bool

    private let processingModeStore: ProcessingModeStore
    private let onRequestAPIKeySetup: @MainActor () -> Void
    private let localSpeechSupportProvider: @Sendable () async -> [Locale]

    init(
        apiKeyPresent: Bool = false,
        processingModeStore: ProcessingModeStore = .shared,
        onRequestAPIKeySetup: @escaping @MainActor () -> Void = {},
        localSpeechSupportProvider: @escaping @Sendable () async -> [Locale] = { await SpeechTranscriber.supportedLocales }
    ) {
        self.apiKeyPresent = apiKeyPresent
        self.processingModeStore = processingModeStore
        self.onRequestAPIKeySetup = onRequestAPIKeySetup
        self.localSpeechSupportProvider = localSpeechSupportProvider

        let storedModes = processingModeStore.load()
        self.transcriptionMode = storedModes.transcription
        self.translationMode = storedModes.translation
        self.canToggleTranscription = apiKeyPresent
        self.canStart = true

        Task { await updateRoutingForLanguage(inputLanguage) }
    }

    var summarizationMode: ProcessingMode {
        .cloud
    }

    var canToggleTranslation: Bool {
        apiKeyPresent
    }

    var intensityBand: Intensity.Band {
        get { intensity.band }
        set { intensity = Intensity(band: newValue) }
    }

    var inputLanguageOptions: [Language] {
        Language.prioritized
    }

    var outputLanguageOptions: [Language] {
        Language.prioritized.filter { $0 != .autoDetect }
    }

    var helperText: String {
        let sourceLanguage = inputLanguage == .autoDetect ? "auto-detect the source language" : "transcribe in \(inputLanguage.displayName)"
        return "ClearVoice will \(sourceLanguage), translate into \(outputLanguage.displayName), and process up to \(maxConcurrency) files in parallel."
    }

    var intensityDescription: String {
        switch intensity.band {
        case .minimal:
            return "Light cleanup for already-usable recordings."
        case .balanced:
            return "Recommended for most voice notes and interviews."
        case .strong:
            return "More aggressive noise reduction for rougher captures."
        case .maximum:
            return "Highest cleanup intensity for difficult recordings."
        }
    }

    var advancedSummary: String {
        let channelSummary = preserveChannels ? "Preserve original channels when possible." : "Downmix when the pipeline benefits from it."
        return "\(channelSummary) Parallelism is capped at \(maxConcurrency) file\(maxConcurrency == 1 ? "" : "s")."
    }

    var selectedInputLanguage: LanguageSelection {
        inputLanguage.id == Language.autoDetect.id ? .auto : .specific(inputLanguage.id)
    }

    var batchProcessingModeConfiguration: ProcessingModeConfiguration {
        var configuration = ProcessingModeConfiguration()
        configuration.transcription = effectiveTranscriptionMode
        configuration.translation = apiKeyPresent ? translationMode : .local
        configuration.summarization = .cloud
        return configuration
    }

    var processingSummaryText: String {
        if !apiKeyPresent {
            return "All steps run on this Mac. No audio leaves your device."
        }

        let cloudSteps = batchCloudSteps

        if cloudSteps.isEmpty {
            return "All steps run on this Mac. No audio leaves your device."
        }

        if cloudSteps.contains("Transcription") {
            return "Audio will be sent to Gemini for \(cloudSteps.joinedList). Other steps run on this Mac."
        }

        return "Text will be sent to Gemini for \(cloudSteps.joinedList). Audio stays on this Mac."
    }

    var batchCloudSteps: [String] {
        var steps: [String] = []

        if batchProcessingModeConfiguration.transcription == .cloud {
            steps.append("Transcription")
        }

        if batchProcessingModeConfiguration.translation == .cloud {
            steps.append("Translation")
        }

        if apiKeyPresent {
            steps.append("Summarization")
        }

        return steps
    }

    var shouldOptimizeUpload: Bool {
        batchProcessingModeConfiguration.transcription == .cloud
    }

    func selectInputLanguage(id: String) {
        if let match = inputLanguageOptions.first(where: { $0.id == id }) {
            inputLanguage = match
        }
    }

    func selectOutputLanguage(id: String) {
        if let match = outputLanguageOptions.first(where: { $0.id == id }) {
            outputLanguage = match
        }
    }

    func requestAPIKeySetup() {
        onRequestAPIKeySetup()
    }

    func updateRoutingForLanguage(_ language: Language) async {
        let supportedLocales = await localSpeechSupportProvider()
        Language.updateLocalSpeechSupport(with: supportedLocales)

        let isSupportedLocally = language.isSupportedLocally

        if !isSupportedLocally {
            transcriptionMode = .cloud
            canToggleTranscription = false
            canStart = apiKeyPresent
            return
        }

        canToggleTranscription = apiKeyPresent

        if !apiKeyPresent {
            transcriptionMode = .local
        }

        canStart = true
    }

    private var effectiveTranscriptionMode: ProcessingMode {
        if !inputLanguage.isSupportedLocally {
            return .cloud
        }

        return apiKeyPresent ? transcriptionMode : .local
    }

    private func persistProcessingModes() {
        processingModeStore.save(
            ProcessingModeConfiguration(
                transcription: transcriptionMode,
                translation: translationMode,
                summarization: .cloud
            )
        )
    }
}

private extension Array where Element == String {
    var joinedList: String {
        switch count {
        case 0:
            return ""
        case 1:
            return self[0].lowercased()
        case 2:
            return "\(self[0].lowercased()) and \(self[1].lowercased())"
        default:
            let head = dropLast().map { $0.lowercased() }.joined(separator: ", ")
            guard let tail = last?.lowercased() else {
                return head
            }

            return "\(head), and \(tail)"
        }
    }
}

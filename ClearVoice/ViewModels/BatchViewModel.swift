import Foundation

@MainActor
final class BatchViewModel: ObservableObject {
    @Published private(set) var files: [AudioFileItem] = []
    @Published private(set) var statusText = "Choose folders and start a batch to see processing progress."
    @Published private(set) var isRunning = false
    @Published private(set) var didFinish = false
    @Published private(set) var languageSelectionPrompt: String?
    @Published private(set) var runStartedAt: Date?

    private let services: ServiceBundle
    private var configuration: BatchConfiguration?
    private var runTask: Task<Void, Never>?
    private var processor: BatchProcessor?

    init(services: ServiceBundle = .stub) {
        self.services = services
    }

    var completedCount: Int {
        files.filter { $0.stage == .complete }.count
    }

    var processingCount: Int {
        files.filter {
            switch $0.stage {
            case .analyzing, .analyzingFormat, .normalizingFormat, .cleaning, .optimizingForUpload, .transcribing, .translating, .summarizing, .exporting:
                return true
            default:
                return false
            }
        }.count
    }

    var pendingCount: Int {
        files.filter { $0.stage == .pending }.count
    }

    var failedCount: Int {
        files.filter {
            if case .failed = $0.stage {
                return true
            }
            return false
        }.count
    }

    var skippedCount: Int {
        files.filter {
            if case .skipped = $0.stage {
                return true
            }
            return false
        }.count
    }

    var overallProgressFraction: Double {
        guard !files.isEmpty else {
            return 0
        }

        let total = files.reduce(0.0) { partial, file in
            partial + progressFraction(for: file.stage)
        }
        return min(max(total / Double(files.count), 0), 1)
    }

    var outputFolderURL: URL? {
        configuration?.outputFolder
    }

    var selectedEnhancementMethod: EnhancementMethod? {
        configuration?.enhancementMethod
    }

    var transcriptionEnabled: Bool {
        configuration?.transcriptionEnabled ?? true
    }

    func configureRun(files sourceFiles: [ScannedAudioFile], configuration: BatchConfiguration) {
        self.configuration = configuration
        self.files = sourceFiles.map {
            AudioFileItem(
                id: UUID(),
                sourceURL: $0.url,
                durationSeconds: $0.durationSeconds,
                stage: .pending
            )
        }
        statusText = "Starting batch processing."
        didFinish = false
        languageSelectionPrompt = nil
        runStartedAt = nil
    }

    func startIfNeeded() {
        guard !isRunning, !didFinish, !files.isEmpty, let configuration else { return }

        isRunning = true
        runStartedAt = Date()
        runTask = Task { [files, services] in
            let resolver = try? OutputPathResolver(outputRoot: configuration.outputFolder)

            guard let resolver else {
                await MainActor.run {
                    self.statusText = "ClearVoice couldn’t prepare the output folder."
                    self.isRunning = false
                }
                return
            }

            let processor = BatchProcessor(
                config: configuration,
                resolver: resolver,
                services: services
            )

            await MainActor.run {
                self.processor = processor
            }

            await processor.run(files: files) { updatedItem in
                await MainActor.run {
                    self.apply(updatedItem)
                }
            }

            await MainActor.run {
                self.processor = nil
                self.isRunning = false
                self.didFinish = true
                let failureCount = self.failedCount
                let skippedCount = self.skippedCount

                if failureCount > 0 || skippedCount > 0 {
                    if self.hasLanguageSelectionFailure {
                        self.languageSelectionPrompt = "ClearVoice couldn’t detect the spoken language for one or more files. Go back, choose the source language manually, and run the batch again."
                        self.statusText = "Processing stopped because ClearVoice needs a manually selected source language for one or more files."
                    } else {
                        self.statusText = "Processing finished with \(failureCount) failed and \(skippedCount) skipped. See the file rows below for details."
                    }
                } else {
                    if configuration.transcriptionEnabled {
                        self.statusText = "Processing complete. Each file folder now contains the \(configuration.enhancementMethod.title) audio output and a Marathi transcript."
                    } else {
                        self.statusText = "Processing complete. Each file folder now contains the \(configuration.enhancementMethod.title) audio output."
                    }
                }
            }
        }
    }

    func reset() {
        runTask?.cancel()
        runTask = nil
        files = []
        statusText = "Choose folders and start a batch to see processing progress."
        isRunning = false
        didFinish = false
        languageSelectionPrompt = nil
        configuration = nil
        processor = nil
        runStartedAt = nil
    }

    private func apply(_ updatedItem: AudioFileItem) {
        guard let index = files.firstIndex(where: { $0.id == updatedItem.id }) else { return }
        files[index] = updatedItem

        if isRunning {
            statusText = "\(completedCount) complete • \(processingCount) processing • \(pendingCount) pending"
        }
    }

    private var hasLanguageSelectionFailure: Bool {
        files.contains { item in
            guard case .failed(let error) = item.stage else {
                return false
            }

            return error.requiresManualLanguageSelection
        }
    }

    private func progressFraction(for stage: ProcessingStage) -> Double {
        switch stage {
        case .pending:
            return 0
        case .analyzing:
            return 0.08
        case .analyzingFormat:
            return 0.14
        case .normalizingFormat:
            return 0.24
        case .cleaning(let progress):
            return 0.24 + (0.34 * progress)
        case .optimizingForUpload:
            return 0.62
        case .transcribing(let progress):
            return 0.62 + (0.22 * progress)
        case .translating:
            return 0.86
        case .summarizing:
            return 0.92
        case .exporting:
            return 0.96
        case .complete, .failed, .skipped:
            return 1
        }
    }
}

private extension ProcessingError {
    var requiresManualLanguageSelection: Bool {
        guard case .transcriptionFailed(let message) = self else {
            return false
        }

        return message.localizedCaseInsensitiveContains("choose the source language manually")
    }
}

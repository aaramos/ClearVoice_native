import Foundation

@MainActor
final class BatchViewModel: ObservableObject {
    @Published private(set) var files: [AudioFileItem] = []
    @Published private(set) var statusText = "Choose folders and start a batch to see processing progress."
    @Published private(set) var isRunning = false
    @Published private(set) var didFinish = false
    @Published private(set) var languageSelectionPrompt: String?

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

    func configureRun(files sourceFiles: [URL], configuration: BatchConfiguration) {
        self.configuration = configuration
        self.files = sourceFiles.map {
            AudioFileItem(
                id: UUID(),
                sourceURL: $0,
                durationSeconds: nil,
                stage: .pending
            )
        }
        statusText = "Starting batch processing."
        didFinish = false
        languageSelectionPrompt = nil
    }

    func startIfNeeded() {
        guard !isRunning, !didFinish, !files.isEmpty, let configuration else { return }

        isRunning = true
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
                let failureCount = self.files.filter {
                    if case .failed = $0.stage { return true }
                    return false
                }.count
                let skippedCount = self.files.filter {
                    if case .skipped = $0.stage { return true }
                    return false
                }.count

                if failureCount > 0 || skippedCount > 0 {
                    if self.hasLanguageSelectionFailure {
                        self.languageSelectionPrompt = "ClearVoice couldn’t detect the spoken language for one or more files. Go back, choose the source language manually, and run the batch again."
                        self.statusText = "Processing stopped because ClearVoice needs a manually selected source language for one or more files."
                    } else {
                        self.statusText = "Processing finished with \(failureCount) failed and \(skippedCount) skipped. See the file rows below for details."
                    }
                } else {
                    if self.services.comparisonEnhancements.count >= 2 {
                        self.statusText = "Processing complete. Each file folder now contains the DeepFilterNet output, Hybrid output, and Marathi transcript."
                    } else if self.services.comparisonEnhancements.count == 1 {
                        self.statusText = "Processing complete. Each file folder now contains one enhancement output and a Marathi transcript."
                    } else {
                        self.statusText = "Processing finished, but ClearVoice could not create any enhancement outputs."
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
}

private extension ProcessingError {
    var requiresManualLanguageSelection: Bool {
        guard case .transcriptionFailed(let message) = self else {
            return false
        }

        return message.localizedCaseInsensitiveContains("choose the source language manually")
    }
}

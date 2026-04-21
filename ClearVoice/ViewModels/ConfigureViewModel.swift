import Foundation

@MainActor
final class ConfigureViewModel: ObservableObject {
    @Published var enhancementMethod: EnhancementMethod = .hybrid
    @Published var maxConcurrency: Int

    private let processorCount: Int

    init(processorCount: Int = ProcessInfo.processInfo.activeProcessorCount) {
        self.processorCount = processorCount
        self.maxConcurrency = Self.recommendedConcurrency(for: processorCount)
    }

    static func recommendedConcurrency(for processorCount: Int) -> Int {
        min(5, max(1, processorCount / 2))
    }

    var canStart: Bool {
        true
    }

    var helperText: String {
        "ClearVoice will process each file with the selected enhancement method and export one cleaned audio file per source folder."
    }

    var advancedSummary: String {
        "All processing runs on this Mac. ClearVoice starts at \(Self.recommendedConcurrency(for: processorCount)) files based on available CPU power. Slide left for fewer files or right for more."
    }

    func reset() {
        enhancementMethod = .hybrid
        maxConcurrency = Self.recommendedConcurrency(for: processorCount)
    }
}

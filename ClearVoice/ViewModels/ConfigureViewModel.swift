import Foundation

@MainActor
final class ConfigureViewModel: ObservableObject {
    static let minimumConcurrency = 1
    static let maximumConcurrency = 20
    static let defaultConcurrency = 5

    @Published var enhancementMethod: EnhancementMethod = .hybrid
    @Published var maxConcurrency: Int

    init() {
        self.maxConcurrency = Self.defaultConcurrency
    }

    static func recommendedConcurrency(for processorCount: Int) -> Int {
        defaultConcurrency
    }

    var canStart: Bool {
        true
    }

    var helperText: String {
        "ClearVoice will process each file with the selected enhancement method and export one cleaned audio file per source folder."
    }

    var advancedSummary: String {
        "All processing runs on this Mac. ClearVoice starts at \(Self.defaultConcurrency) files at a time, and you can tune the batch anywhere from \(Self.minimumConcurrency) to \(Self.maximumConcurrency) files."
    }

    func reset() {
        enhancementMethod = .hybrid
        maxConcurrency = Self.defaultConcurrency
    }
}

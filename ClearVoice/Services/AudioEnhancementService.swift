import Foundation

protocol AudioEnhancementService: Sendable {
    func enhance(
        input: URL,
        output: URL,
        intensity: Intensity
    ) async throws
}

actor StubAudioEnhancementService: AudioEnhancementService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func enhance(
        input: URL,
        output: URL,
        intensity: Intensity
    ) async throws {
        try fileManager.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: input, to: output)
    }
}

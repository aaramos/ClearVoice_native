import Foundation

struct AudioFileItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let sourceURL: URL
    let durationSeconds: TimeInterval?
    var outputFolderURL: URL? = nil
    var stage: ProcessingStage
    var errorLogURL: URL? = nil

    var basename: String {
        sourceURL.deletingPathExtension().lastPathComponent
    }
}

import Foundation

struct AudioFileItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let sourceURL: URL
    let durationSeconds: TimeInterval?
    var transcript: Transcript? = nil
    var detectedLanguage: String? = nil
    var outputFolderURL: URL? = nil
    var stage: ProcessingStage
    var summaryText: String? = nil
    var translatedTranscript: String? = nil
    var originalTranscript: String? = nil
    var errorLogURL: URL? = nil

    var basename: String {
        sourceURL.deletingPathExtension().lastPathComponent
    }
}

import Foundation

enum ProcessingStage: Equatable, Sendable {
    case pending
    case analyzing
    case analyzingFormat
    case normalizingFormat
    case cleaning(progress: Double)
    case optimizingForUpload
    case transcribing(progress: Double)
    case translating
    case summarizing
    case exporting
    case complete
    case failed(error: ProcessingError)
    case skipped(reason: SkipReason)
}

enum SkipReason: Equatable, Sendable {
    case outputFolderExists(URL)
}

enum ProcessingError: Error, Equatable, Sendable {
    case audioUnreadable
    case enhancementFailed(String)
    case transcriptionFailed(String)
    case translationFailed(String)
    case summarizationFailed(String)
    case exportFailed(String)
    case cancelled
}

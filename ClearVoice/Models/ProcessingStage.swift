import Foundation

enum ProcessingStage: Equatable, Sendable {
    case pending
    case analyzing
    case analyzingFormat
    case normalizingFormat
    case cleaning(progress: Double)
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

extension ProcessingError {
    var displayMessage: String {
        switch self {
        case .audioUnreadable:
            return "ClearVoice couldn’t read this audio file."
        case .enhancementFailed(let message),
                .transcriptionFailed(let message),
                .translationFailed(let message),
                .summarizationFailed(let message),
                .exportFailed(let message):
            return message
        case .cancelled:
            return "Processing stopped before this file finished."
        }
    }
}

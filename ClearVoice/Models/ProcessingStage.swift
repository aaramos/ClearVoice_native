import Foundation

enum ProcessingStage: Equatable, Sendable {
    case pending
    case analyzing
    case analyzingFormat
    case normalizingFormat
    case cleaning(progress: Double)
    case exporting
    case complete
    case cancelled
    case failed(error: ProcessingError)
    case skipped(reason: SkipReason)
}

enum SkipReason: Equatable, Sendable {
    case outputFolderExists(URL)
}

enum ProcessingError: Error, Equatable, Sendable {
    case audioUnreadable
    case enhancementFailed(String)
    case exportFailed(String)
    case cancelled
}

extension ProcessingError {
    var displayMessage: String {
        switch self {
        case .audioUnreadable:
            return "ClearVoice couldn’t read this audio file."
        case .enhancementFailed(let message),
                .exportFailed(let message):
            if Self.isDiskSpaceFailure(message) {
                return "ClearVoice ran out of free disk space while processing this file. Free up storage, then try again with Processing Speed set to 1 file at a time."
            }
            return message
        case .cancelled:
            return "Processing stopped before this file finished."
        }
    }

    private static func isDiskSpaceFailure(_ message: String) -> Bool {
        let normalized = message.localizedLowercase
        return normalized.contains("no space left on device")
            || normalized.contains("not enough free space")
            || normalized.contains("disk full")
    }
}

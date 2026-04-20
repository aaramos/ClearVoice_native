import Foundation

enum AudioFormatSupport {
    static let passthroughExtensions: Set<String> = [
        "wav",
        "mp3",
        "m4a",
        "aac",
        "flac",
    ]

    static let ffmpegNormalizedExtensions: Set<String> = [
        "wma",
    ]

    static let acceptedSourceExtensions = passthroughExtensions.union(ffmpegNormalizedExtensions)
    static let speechProcessingExtension = "wav"
    static let cleanExportExtension = "m4a"
}

protocol FormatNormalizationService: Sendable {
    /// Returns a URL that the rest of the audio pipeline can process safely.
    /// The caller must clean up any returned temporary URL when `requiresCleanup` is true.
    func normalize(_ sourceURL: URL) async throws -> (url: URL, requiresCleanup: Bool)
}

actor StubFormatNormalizationService: FormatNormalizationService {
    func normalize(_ sourceURL: URL) async throws -> (url: URL, requiresCleanup: Bool) {
        (sourceURL, false)
    }
}

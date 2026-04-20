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
    static let normalizedOutputExtension = "m4a"

    static func requiresNormalization(for pathExtension: String) -> Bool {
        ffmpegNormalizedExtensions.contains(pathExtension.lowercased())
    }
}

protocol FormatNormalizationService: Sendable {
    /// Returns a URL that the rest of the audio pipeline can process safely.
    /// The original URL is returned unchanged when no normalization is required.
    /// The caller must clean up any returned temporary URL when `requiresCleanup` is true.
    func normalize(_ sourceURL: URL) async throws -> (url: URL, requiresCleanup: Bool)
}

actor StubFormatNormalizationService: FormatNormalizationService {
    func normalize(_ sourceURL: URL) async throws -> (url: URL, requiresCleanup: Bool) {
        (sourceURL, false)
    }
}

import Foundation

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

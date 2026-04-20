import Foundation

protocol CloudAudioPreparationService: Sendable {
    /// Prepares an audio file for cloud transcription and writes the result to a temporary location.
    /// The caller is responsible for deleting the returned file when processing finishes.
    func prepare(_ sourceURL: URL) async throws -> URL
}

actor NoOpCloudAudioPreparationService: CloudAudioPreparationService {
    func prepare(_ sourceURL: URL) async throws -> URL {
        sourceURL
    }
}

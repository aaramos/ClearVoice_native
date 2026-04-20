import Foundation
import OSLog

actor OpenAIWhisperTranscriptionService: TranscriptionService {
    private let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    private let apiKey: String
    private let httpClient: CloudHTTPClient
    private let maxUploadBytes = 25 * 1_024 * 1_024

    init(
        apiKey: String,
        transport: any HTTPTransport = URLSessionHTTPTransport(),
        retryPolicy: RetryPolicy = .default
    ) {
        self.apiKey = apiKey
        self.httpClient = CloudHTTPClient(
            transport: transport,
            retryPolicy: retryPolicy,
            logger: Logger(subsystem: "com.clearvoice.app", category: "transcribe")
        )
    }

    func transcribe(
        audio: URL,
        language: LanguageSelection
    ) async throws -> Transcript {
        do {
            let fileData = try Data(contentsOf: audio)

            guard fileData.count <= maxUploadBytes else {
                throw ProcessingError.transcriptionFailed(
                    "\(audio.lastPathComponent) is larger than OpenAI's 25 MB transcription limit."
                )
            }

            let multipart = MultipartFormDataBuilder.build(
                fileFieldName: "file",
                filename: audio.lastPathComponent,
                mimeType: Self.mimeType(for: audio),
                fileData: fileData,
                textFields: requestFields(for: language)
            )

            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue(multipart.contentType, forHTTPHeaderField: "Content-Type")

            let data = try await httpClient.send(request: request, body: multipart.body)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            let response = try decoder.decode(WhisperVerboseResponse.self, from: data)
            let transcriptText = response.text.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !transcriptText.isEmpty else {
                throw ProcessingError.transcriptionFailed(
                    "OpenAI returned an empty transcript for \(audio.lastPathComponent)."
                )
            }

            return Transcript(
                text: transcriptText,
                detectedLanguage: response.language ?? fallbackLanguage(for: language),
                confidence: Self.confidence(from: response)
            )
        } catch let error as ProcessingError {
            throw error
        } catch let error as CloudHTTPClient.RequestError {
            throw ProcessingError.transcriptionFailed(Self.message(for: error))
        } catch let error as URLError {
            throw ProcessingError.transcriptionFailed("OpenAI transcription request failed: \(error.localizedDescription)")
        } catch {
            throw ProcessingError.transcriptionFailed(error.localizedDescription)
        }
    }

    private func requestFields(for language: LanguageSelection) -> [(name: String, value: String)] {
        var fields: [(name: String, value: String)] = [
            ("model", "whisper-1"),
            ("response_format", "verbose_json"),
            ("temperature", "0")
        ]

        if case .specific(let languageCode) = language {
            fields.append(("language", languageCode))
        }

        return fields
    }

    private func fallbackLanguage(for selection: LanguageSelection) -> String {
        switch selection {
        case .auto:
            return "und"
        case .specific(let code):
            return code
        }
    }

    private static func confidence(from response: WhisperVerboseResponse) -> Double {
        let logProbabilities = response.segments?.compactMap(\.avgLogprob) ?? []

        guard !logProbabilities.isEmpty else {
            return 0.75
        }

        let probabilities = logProbabilities.map { exp($0) }
        let averageProbability = probabilities.reduce(0, +) / Double(probabilities.count)
        return min(max(averageProbability, 0), 1)
    }

    private static func mimeType(for audio: URL) -> String {
        switch audio.pathExtension.lowercased() {
        case "mp3", "mpga", "mpeg":
            return "audio/mpeg"
        case "m4a", "mp4":
            return "audio/mp4"
        case "wav":
            return "audio/wav"
        case "flac":
            return "audio/flac"
        case "aac":
            return "audio/aac"
        case "webm":
            return "audio/webm"
        default:
            return "application/octet-stream"
        }
    }

    private static func message(for error: CloudHTTPClient.RequestError) -> String {
        switch error {
        case .invalidResponse:
            return "OpenAI returned an unreadable transcription response."
        case .unsuccessfulStatus(let code, let bodySnippet):
            let trimmedBody = bodySnippet.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedBody.isEmpty {
                return "OpenAI transcription failed with status \(code)."
            }
            return "OpenAI transcription failed with status \(code): \(trimmedBody)"
        }
    }
}

private struct WhisperVerboseResponse: Decodable {
    let text: String
    let language: String?
    let segments: [WhisperSegment]?
}

private struct WhisperSegment: Decodable {
    let avgLogprob: Double?
}

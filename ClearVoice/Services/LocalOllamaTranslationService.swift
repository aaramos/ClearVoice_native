import Foundation
import OSLog

actor LocalOllamaTranslationService: TranslationService {
    private let endpoint: URL
    private let model: String
    private let httpClient: CloudHTTPClient
    private let maxChunkCharacters: Int

    init(
        endpoint: URL = URL(string: "http://127.0.0.1:11434/api/generate")!,
        model: String = ProcessInfo.processInfo.environment["CLEARVOICE_OLLAMA_TRANSLATION_MODEL"] ?? "qwen3:14b",
        transport: (any HTTPTransport)? = nil,
        retryPolicy: RetryPolicy = .default,
        maxChunkCharacters: Int = 3_500
    ) {
        self.endpoint = endpoint
        self.model = model
        self.maxChunkCharacters = maxChunkCharacters
        self.httpClient = CloudHTTPClient(
            transport: transport ?? URLSessionHTTPTransport(session: Self.translationSession()),
            retryPolicy: retryPolicy,
            logger: Logger(subsystem: "com.clearvoice.app", category: "ollama-local")
        )
    }

    func translate(
        text: String,
        from sourceLanguage: String,
        to targetLanguage: String
    ) async throws -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard sourceLanguage != targetLanguage else {
            return trimmedText
        }

        do {
            let chunks = Self.translationChunks(from: trimmedText, maxChunkCharacters: maxChunkCharacters)
            var translatedChunks: [String] = []
            translatedChunks.reserveCapacity(chunks.count)

            for (index, chunk) in chunks.enumerated() {
                translatedChunks.append(
                    try await translateChunk(
                        chunk,
                        chunkIndex: index + 1,
                        totalChunks: chunks.count,
                        sourceLanguage: sourceLanguage,
                        targetLanguage: targetLanguage
                    )
                )
            }

            return translatedChunks
                .joined(separator: "\n\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as CloudHTTPClient.RequestError {
            throw ProcessingError.translationFailed(Self.message(for: error, model: model))
        } catch let error as URLError {
            if error.code == .timedOut {
                throw ProcessingError.translationFailed(
                    "ClearVoice’s local Ollama translation timed out after 10 minutes. Try a smaller batch, lower concurrency, or a faster local model."
                )
            }

            throw ProcessingError.translationFailed(
                "ClearVoice couldn’t reach Ollama on this Mac (\(error.localizedDescription)). Make sure Ollama is running and try again."
            )
        } catch let error as ProcessingError {
            throw error
        } catch {
            throw ProcessingError.translationFailed(
                "ClearVoice couldn’t run the local English translation model: \(error.localizedDescription)"
            )
        }
    }

    private func translateChunk(
        _ chunk: String,
        chunkIndex: Int,
        totalChunks: Int,
        sourceLanguage: String,
        targetLanguage: String
    ) async throws -> String {
        let prompt = """
        Translate the following spoken-audio transcript chunk into natural English.
        Preserve meaning, sentence order, speaker intent, and named entities.
        This is chunk \(chunkIndex) of \(totalChunks).
        Output only the translated English transcript for this chunk.
        Never ask for clarification.
        Never apologize.
        Never describe the text as garbled.
        If a phrase is unclear, keep a best-effort English rendering and use [unclear] only where needed.

        Source language: \(Language.displayName(for: sourceLanguage)) (\(sourceLanguage))
        Target language: English (\(targetLanguage))

        Transcript chunk:
        \(chunk)
        """

        let payload = OllamaGenerateRequest(
            model: model,
            prompt: prompt,
            stream: false
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data = try await httpClient.send(
            request: request,
            body: try JSONEncoder().encode(payload)
        )

        let response = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
        let translated = response.response.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !translated.isEmpty else {
            throw ProcessingError.translationFailed("ClearVoice’s local translator returned an empty English translation.")
        }

        if Self.isGenericAssistantReply(translated) {
            throw ProcessingError.translationFailed(
                "ClearVoice’s local translator answered with a generic assistant reply instead of an English transcript. Try rerunning with a stronger local model."
            )
        }

        guard Self.looksLikeEnglish(translated) else {
            throw ProcessingError.translationFailed(
                "ClearVoice’s local translator did not return English text. Try rerunning with a stronger local Ollama model."
            )
        }

        return translated
    }

    private static func message(for error: CloudHTTPClient.RequestError, model: String) -> String {
        switch error {
        case .invalidResponse:
            return "ClearVoice couldn’t read the local Ollama translation response."
        case .unsuccessfulStatus(_, let bodySnippet, _):
            let trimmedBody = bodySnippet.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedBody.localizedCaseInsensitiveContains("not found"),
               trimmedBody.localizedCaseInsensitiveContains("model") {
                return "ClearVoice couldn’t find the local Ollama translation model '\(model)'. Pull that model locally and try again."
            }

            if trimmedBody.isEmpty {
                return "ClearVoice’s local Ollama translator failed without a readable error message."
            }

            return "ClearVoice’s local Ollama translator failed: \(trimmedBody)"
        }
    }

    private static func translationChunks(from text: String, maxChunkCharacters: Int) -> [String] {
        guard text.count > maxChunkCharacters else {
            return [text]
        }

        var chunks: [String] = []
        var current = ""

        for segment in segments(from: text) {
            if current.isEmpty {
                current = segment
                continue
            }

            if current.count + 1 + segment.count <= maxChunkCharacters {
                current.append(" ")
                current.append(segment)
                continue
            }

            chunks.append(current)

            if segment.count <= maxChunkCharacters {
                current = segment
            } else {
                chunks.append(contentsOf: hardWrappedChunks(from: segment, maxChunkCharacters: maxChunkCharacters))
                current = ""
            }
        }

        if !current.isEmpty {
            chunks.append(current)
        }

        return chunks.filter { !$0.isEmpty }
    }

    private static func segments(from text: String) -> [String] {
        let separators = CharacterSet(charactersIn: ".?!\n\r।")
        let rawSegments = text.components(separatedBy: separators)
        let trimmed = rawSegments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if trimmed.isEmpty {
            return text.split(separator: " ").map(String.init)
        }

        return trimmed
    }

    private static func hardWrappedChunks(from text: String, maxChunkCharacters: Int) -> [String] {
        var chunks: [String] = []
        var current = ""

        for word in text.split(separator: " ") {
            let word = String(word)

            if current.isEmpty {
                current = word
                continue
            }

            if current.count + 1 + word.count <= maxChunkCharacters {
                current.append(" ")
                current.append(word)
            } else {
                chunks.append(current)
                current = word
            }
        }

        if !current.isEmpty {
            chunks.append(current)
        }

        return chunks
    }

    private static func looksLikeEnglish(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }

        guard letters.count >= 20 else {
            return true
        }

        let latinCount = letters.filter { scalar in
            switch scalar.value {
            case 0x0041...0x005A,
                    0x0061...0x007A,
                    0x00C0...0x024F:
                return true
            default:
                return false
            }
        }.count

        return Double(latinCount) / Double(letters.count) >= 0.65
    }

    private static func isGenericAssistantReply(_ text: String) -> Bool {
        let normalized = text.lowercased()

        return [
            "could you please clarify",
            "please clarify your question",
            "provide more context",
            "it seems your message may be garbled",
            "i'm here to help",
            "how can i help",
            "your message appears",
        ].contains { normalized.contains($0) }
    }

    private static func translationSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 600
        configuration.timeoutIntervalForResource = 600
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }
}

private struct OllamaGenerateRequest: Encodable {
    let model: String
    let prompt: String
    let stream: Bool
}

private struct OllamaGenerateResponse: Decodable {
    let response: String
}

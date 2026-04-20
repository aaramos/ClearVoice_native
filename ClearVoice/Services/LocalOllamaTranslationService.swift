import Foundation
import OSLog

actor LocalOllamaTranslationService: TranslationService {
    private let endpoint: URL
    private let model: String
    private let httpClient: CloudHTTPClient

    init(
        endpoint: URL = URL(string: "http://127.0.0.1:11434/api/generate")!,
        model: String = ProcessInfo.processInfo.environment["CLEARVOICE_OLLAMA_TRANSLATION_MODEL"] ?? "qwen3:14b",
        transport: any HTTPTransport = URLSessionHTTPTransport(),
        retryPolicy: RetryPolicy = .default
    ) {
        self.endpoint = endpoint
        self.model = model
        self.httpClient = CloudHTTPClient(
            transport: transport,
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

        let systemPrompt = """
        You translate spoken-audio transcripts into natural English.
        Preserve meaning, sentence order, speaker intent, and named entities.
        Output only the translated English transcript.
        Do not summarize, explain, add headings, or add notes.
        """

        let prompt = """
        \(systemPrompt)

        Source language: \(Language.displayName(for: sourceLanguage)) (\(sourceLanguage))
        Target language: English (en)

        Transcript:
        \(trimmedText)
        """

        let payload = OllamaGenerateRequest(
            model: model,
            prompt: prompt,
            stream: false
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let data = try await httpClient.send(
                request: request,
                body: try JSONEncoder().encode(payload)
            )

            let response = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
            let translated = response.response.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !translated.isEmpty else {
                throw ProcessingError.translationFailed("ClearVoice’s local translator returned an empty English translation.")
            }

            guard Self.looksLikeEnglish(translated) else {
                throw ProcessingError.translationFailed(
                    "ClearVoice’s local translator did not return English text. Try rerunning with a stronger local Ollama model."
                )
            }

            return translated
        } catch let error as CloudHTTPClient.RequestError {
            throw ProcessingError.translationFailed(Self.message(for: error, model: model))
        } catch let error as URLError {
            throw ProcessingError.translationFailed(
                "ClearVoice couldn’t reach Ollama on this Mac (\(error.localizedDescription)). Start Ollama and try again."
            )
        } catch let error as ProcessingError {
            throw error
        } catch {
            throw ProcessingError.translationFailed(
                "ClearVoice couldn’t run the local English translation model: \(error.localizedDescription)"
            )
        }
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
}

private struct OllamaGenerateRequest: Encodable {
    let model: String
    let prompt: String
    let stream: Bool
}

private struct OllamaGenerateResponse: Decodable {
    let response: String
}

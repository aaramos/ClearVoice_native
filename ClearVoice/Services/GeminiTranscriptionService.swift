import Foundation

actor GeminiTranscriptionService: TranscriptionService {
    private let client: GeminiDeveloperClient
    private let model: String

    init(
        client: GeminiDeveloperClient,
        model: String = "gemini-3-flash-preview"
    ) {
        self.client = client
        self.model = model
    }

    func transcribe(
        audio: URL,
        language: LanguageSelection
    ) async throws -> Transcript {
        let uploadedFile = try await client.uploadFile(from: audio)

        do {
            let prompt = transcriptionPrompt(for: language)
            let responseText = try await client.generateText(
                model: model,
                prompt: prompt,
                file: uploadedFile,
                responseMIMEType: "application/json",
                responseSchema: transcriptionSchema
            )
            let transcription = try JSONDecoder().decode(GeminiTranscriptionPayload.self, from: Data(responseText.utf8))

            try? await client.deleteFile(named: uploadedFile.name)

            let transcriptText = transcription.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcriptText.isEmpty else {
                throw ProcessingError.transcriptionFailed("Gemini returned an empty transcript for \(audio.lastPathComponent).")
            }

            return Transcript(
                text: transcriptText,
                detectedLanguage: transcription.languageCode,
                confidence: min(max(transcription.confidenceEstimate, 0), 1)
            )
        } catch let error as ProcessingError {
            try? await client.deleteFile(named: uploadedFile.name)
            throw error
        } catch let error as CloudHTTPClient.RequestError {
            try? await client.deleteFile(named: uploadedFile.name)
            throw ProcessingError.transcriptionFailed(Self.message(for: error))
        } catch let error as URLError {
            try? await client.deleteFile(named: uploadedFile.name)
            throw ProcessingError.transcriptionFailed("Gemini transcription request failed: \(error.localizedDescription)")
        } catch {
            try? await client.deleteFile(named: uploadedFile.name)
            throw ProcessingError.transcriptionFailed(error.localizedDescription)
        }
    }

    private func transcriptionPrompt(for language: LanguageSelection) -> String {
        let languageHint: String

        switch language {
        case .auto:
            languageHint = "Language hint: auto-detect."
        case .specific(let code):
            languageHint = "Language hint: the spoken language is likely \(Language.displayName(for: code)) (\(code))."
        }

        return """
        Transcribe the spoken words from this audio file.
        \(languageHint)
        Requirements:
        1. Return only JSON matching the provided schema.
        2. Preserve the spoken wording and do not translate.
        3. `language_code` must be the primary spoken language as a BCP-47 code.
        4. `confidence_estimate` must be a number between 0 and 1.
        """
    }

    private var transcriptionSchema: GeminiSchema {
        GeminiSchema(
            type: .object,
            properties: [
                "transcript": GeminiSchema(type: .string, description: "The verbatim transcript of the audio."),
                "language_code": GeminiSchema(type: .string, description: "Primary spoken language as a BCP-47 code."),
                "confidence_estimate": GeminiSchema(type: .number, description: "Estimated confidence from 0.0 to 1.0.")
            ],
            required: ["transcript", "language_code", "confidence_estimate"]
        )
    }

    private static func message(for error: CloudHTTPClient.RequestError) -> String {
        switch error {
        case .invalidResponse:
            return "Gemini returned an unreadable transcription response."
        case .unsuccessfulStatus(let code, let bodySnippet):
            let trimmedBody = bodySnippet.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedBody.isEmpty {
                return "Gemini transcription failed with status \(code)."
            }
            return "Gemini transcription failed with status \(code): \(trimmedBody)"
        }
    }
}

private struct GeminiTranscriptionPayload: Decodable {
    let transcript: String
    let languageCode: String
    let confidenceEstimate: Double

    enum CodingKeys: String, CodingKey {
        case transcript
        case languageCode = "language_code"
        case confidenceEstimate = "confidence_estimate"
    }
}

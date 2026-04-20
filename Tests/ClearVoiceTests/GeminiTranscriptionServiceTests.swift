import Foundation
import Testing
@testable import ClearVoice

struct GeminiTranscriptionServiceTests {
    @Test
    func transcribeUploadsAudioGeneratesStructuredTranscriptAndDeletesRemoteFile() async throws {
        let generateResponseBody = """
        {
          "candidates": [
            {
              "content": {
                "parts": [
                  {
                    "text": "{\\"transcript\\":\\"Namaste world\\",\\"language_code\\":\\"hi\\",\\"confidence_estimate\\":0.82}"
                  }
                ]
              }
            }
          ]
        }
        """

        let transport = MockHTTPTransport(
            responses: [
                .success(
                    statusCode: 200,
                    body: Data("{}".utf8),
                    headers: ["X-Goog-Upload-URL": "https://upload.example.com/resumable"]
                ),
                .success(
                    statusCode: 200,
                    body: Data("""
                    {
                      "file": {
                        "name": "files/abc-123",
                        "uri": "https://generativelanguage.googleapis.com/v1beta/files/abc-123",
                        "mimeType": "audio/mp4"
                      }
                    }
                    """.utf8)
                ),
                .success(statusCode: 200, body: Data(generateResponseBody.utf8)),
                .success(statusCode: 200, body: Data("{}".utf8))
            ]
        )

        let service = GeminiTranscriptionService(
            client: GeminiDeveloperClient(
                apiKey: "gemini-test-key",
                transport: transport,
                retryPolicy: RetryPolicy(maxAttempts: 1, baseDelayMilliseconds: 0, maxJitterMilliseconds: 0)
            )
        )
        let audioURL = try makeTemporaryAudioFile(named: "sample", extension: "m4a")

        let transcript = try await service.transcribe(
            audio: audioURL,
            language: .specific("hi")
        )

        let requests = await transport.capturedRequests()
        let startBody = String(decoding: requests[0].body ?? Data(), as: UTF8.self)
        let generateRequestBody = try #require(requests[2].body)
        let generatePayload = try JSONDecoder().decode(GeminiGenerateRequestPayload.self, from: generateRequestBody)
        let uploadedBytes = try #require(requests[1].body)
        let prompt = try #require(generatePayload.contents.first?.parts.last?.text)
        let fileURI = try #require(generatePayload.contents.first?.parts.first?.fileData?.fileURI)

        #expect(transcript.text == "Namaste world")
        #expect(transcript.detectedLanguage == "hi")
        #expect(abs(transcript.confidence - 0.82) < 0.0001)
        #expect(requests.count == 4)
        #expect(requests[0].request.url?.absoluteString == "https://generativelanguage.googleapis.com/upload/v1beta/files")
        #expect(requests[0].request.value(forHTTPHeaderField: "x-goog-api-key") == "gemini-test-key")
        #expect(requests[0].request.value(forHTTPHeaderField: "X-Goog-Upload-Protocol") == "resumable")
        #expect(startBody.contains("sample.m4a"))
        #expect(requests[1].request.url?.absoluteString == "https://upload.example.com/resumable")
        #expect(uploadedBytes == Data("test-audio".utf8))
        #expect(requests[2].request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:generateContent")
        #expect(generatePayload.generationConfig?.responseMIMEType == "application/json")
        #expect(generatePayload.generationConfig?.responseSchema?.properties?.keys.contains("language_code") == true)
        #expect(fileURI == "https://generativelanguage.googleapis.com/v1beta/files/abc-123")
        #expect(prompt.contains("spoken language is likely Hindi"))
        #expect(requests[3].request.httpMethod == "DELETE")
        #expect(requests[3].request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/files/abc-123")
    }

    private func makeTemporaryAudioFile(
        named basename: String,
        extension pathExtension: String
    ) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let fileURL = folder.appendingPathComponent("\(basename).\(pathExtension)")
        try Data("test-audio".utf8).write(to: fileURL)
        return fileURL
    }
}

private struct GeminiGenerateRequestPayload: Decodable {
    let contents: [GeminiGenerateRequestContent]
    let generationConfig: GeminiGenerateRequestConfig?

    enum CodingKeys: String, CodingKey {
        case contents
        case generationConfig = "generation_config"
    }
}

private struct GeminiGenerateRequestContent: Decodable {
    let parts: [GeminiGenerateRequestPart]
}

private struct GeminiGenerateRequestPart: Decodable {
    let text: String?
    let fileData: GeminiGenerateRequestFileData?

    enum CodingKeys: String, CodingKey {
        case text
        case fileData = "file_data"
    }
}

private struct GeminiGenerateRequestFileData: Decodable {
    let fileURI: String

    enum CodingKeys: String, CodingKey {
        case fileURI = "file_uri"
    }
}

private struct GeminiGenerateRequestConfig: Decodable {
    let responseMIMEType: String?
    let responseSchema: GeminiGenerateRequestSchema?

    enum CodingKeys: String, CodingKey {
        case responseMIMEType = "response_mime_type"
        case responseSchema = "response_schema"
    }
}

private struct GeminiGenerateRequestSchema: Decodable {
    let properties: [String: GeminiGenerateRequestProperty]?
}

private struct GeminiGenerateRequestProperty: Decodable {}

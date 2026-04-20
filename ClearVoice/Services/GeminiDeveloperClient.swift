import Foundation
import OSLog

actor GeminiDeveloperClient {
    private let apiKey: String
    private let httpClient: CloudHTTPClient

    init(
        apiKey: String,
        transport: any HTTPTransport = URLSessionHTTPTransport(),
        retryPolicy: RetryPolicy = .default
    ) {
        self.apiKey = apiKey
        self.httpClient = CloudHTTPClient(
            transport: transport,
            retryPolicy: retryPolicy,
            logger: Logger(subsystem: "com.clearvoice.app", category: "gemini")
        )
    }

    func uploadFile(from sourceURL: URL) async throws -> GeminiUploadedFile {
        let fileData = try Data(contentsOf: sourceURL)
        let mimeType = GeminiAudioMimeTypeResolver.mimeType(for: sourceURL)

        var startRequest = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/upload/v1beta/files")!)
        startRequest.httpMethod = "POST"
        startRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        startRequest.setValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        startRequest.setValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
        startRequest.setValue(String(fileData.count), forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length")
        startRequest.setValue(mimeType, forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")
        startRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let metadata = try JSONEncoder().encode(
            GeminiUploadMetadata(file: GeminiUploadFile(displayName: sourceURL.lastPathComponent))
        )
        let (_, startResponse) = try await httpClient.sendWithResponse(request: startRequest, body: metadata)

        guard
            let uploadURLString = startResponse.value(forHTTPHeaderField: "x-goog-upload-url"),
            let uploadURL = URL(string: uploadURLString)
        else {
            throw CloudHTTPClient.RequestError.invalidResponse
        }

        var uploadRequest = URLRequest(url: uploadURL)
        uploadRequest.httpMethod = "POST"
        uploadRequest.setValue(String(fileData.count), forHTTPHeaderField: "Content-Length")
        uploadRequest.setValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")
        uploadRequest.setValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")

        let responseData = try await httpClient.send(request: uploadRequest, body: fileData)
        return try JSONDecoder().decode(GeminiUploadResponse.self, from: responseData).file
    }

    func deleteFile(named name: String) async throws {
        var request = URLRequest(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/\(name)")!
        )
        request.httpMethod = "DELETE"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        _ = try await httpClient.send(request: request, body: nil)
    }

    func generateText(
        model: String,
        prompt: String,
        file: GeminiUploadedFile? = nil,
        responseMIMEType: String? = nil,
        responseSchema: GeminiSchema? = nil
    ) async throws -> String {
        let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!

        let requestBody = GeminiGenerateContentRequest(
            contents: [
                GeminiContent(parts: requestParts(prompt: prompt, file: file))
            ],
            generationConfig: GeminiGenerationConfig(
                responseMIMEType: responseMIMEType,
                responseSchema: responseSchema
            )
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let responseData = try await httpClient.send(
            request: request,
            body: try JSONEncoder().encode(requestBody)
        )
        let response = try JSONDecoder().decode(GeminiGenerateContentResponse.self, from: responseData)

        guard
            let text = response.candidates.first?.content.parts.compactMap(\.text).first?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else {
            throw CloudHTTPClient.RequestError.invalidResponse
        }

        return text
    }

    private func requestParts(prompt: String, file: GeminiUploadedFile?) -> [GeminiPart] {
        var parts: [GeminiPart] = []

        if let file {
            parts.append(
                GeminiPart(
                    text: nil,
                    fileData: GeminiFileData(
                        mimeType: file.mimeType,
                        fileURI: file.uri
                    )
                )
            )
        }

        parts.append(GeminiPart(text: prompt, fileData: nil))
        return parts
    }
}

struct GeminiUploadedFile: Decodable, Sendable {
    let name: String
    let uri: String
    let mimeType: String
}

struct GeminiSchema: Encodable, Sendable {
    enum ValueType: String, Encodable, Sendable {
        case object = "OBJECT"
        case string = "STRING"
        case number = "NUMBER"
    }

    let type: ValueType
    var properties: [String: GeminiSchema]? = nil
    var required: [String]? = nil
    var description: String? = nil
    var enumValues: [String]? = nil

    enum CodingKeys: String, CodingKey {
        case type
        case properties
        case required
        case description
        case enumValues = "enum"
    }
}

private struct GeminiUploadMetadata: Encodable {
    let file: GeminiUploadFile
}

private struct GeminiUploadFile: Encodable {
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

private struct GeminiUploadResponse: Decodable {
    let file: GeminiUploadedFile
}

private struct GeminiGenerateContentRequest: Encodable {
    let contents: [GeminiContent]
    let generationConfig: GeminiGenerationConfig?

    enum CodingKeys: String, CodingKey {
        case contents
        case generationConfig = "generation_config"
    }
}

private struct GeminiContent: Encodable {
    let parts: [GeminiPart]
}

private struct GeminiPart: Encodable {
    let text: String?
    let fileData: GeminiFileData?

    enum CodingKeys: String, CodingKey {
        case text
        case fileData = "file_data"
    }
}

private struct GeminiFileData: Encodable {
    let mimeType: String
    let fileURI: String

    enum CodingKeys: String, CodingKey {
        case mimeType = "mime_type"
        case fileURI = "file_uri"
    }
}

private struct GeminiGenerationConfig: Encodable {
    let responseMIMEType: String?
    let responseSchema: GeminiSchema?

    enum CodingKeys: String, CodingKey {
        case responseMIMEType = "response_mime_type"
        case responseSchema = "response_schema"
    }
}

private struct GeminiGenerateContentResponse: Decodable {
    let candidates: [GeminiCandidate]
}

private struct GeminiCandidate: Decodable {
    let content: GeminiResponseContent
}

private struct GeminiResponseContent: Decodable {
    let parts: [GeminiResponsePart]
}

private struct GeminiResponsePart: Decodable {
    let text: String?
}

private enum GeminiAudioMimeTypeResolver {
    static func mimeType(for audioURL: URL) -> String {
        switch audioURL.pathExtension.lowercased() {
        case "mp3":
            return "audio/mpeg"
        case "m4a", "mp4":
            return "audio/mp4"
        case "wav":
            return "audio/wav"
        case "flac":
            return "audio/flac"
        case "aac":
            return "audio/aac"
        default:
            return "application/octet-stream"
        }
    }
}

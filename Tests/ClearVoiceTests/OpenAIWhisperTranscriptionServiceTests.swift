import Foundation
import Testing
@testable import ClearVoice

struct OpenAIWhisperTranscriptionServiceTests {
    @Test
    func transcribeBuildsMultipartRequestAndDecodesVerboseJSON() async throws {
        let responseBody = """
        {
          "text": "Namaste world",
          "language": "hi",
          "segments": [
            { "avg_logprob": -0.2 },
            { "avg_logprob": -0.4 }
          ]
        }
        """

        let transport = MockHTTPTransport(
            responses: [.success(statusCode: 200, body: Data(responseBody.utf8))]
        )
        let service = OpenAIWhisperTranscriptionService(
            apiKey: "openai-test-key",
            transport: transport,
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelayMilliseconds: 0, maxJitterMilliseconds: 0)
        )
        let audioURL = try makeTemporaryAudioFile(named: "sample", extension: "m4a")

        let transcript = try await service.transcribe(
            audio: audioURL,
            language: .specific("hi")
        )

        let expectedConfidence = (exp(-0.2) + exp(-0.4)) / 2
        let requests = await transport.capturedRequests()
        let bodyString = String(decoding: requests[0].body ?? Data(), as: UTF8.self)

        #expect(transcript.text == "Namaste world")
        #expect(transcript.detectedLanguage == "hi")
        #expect(abs(transcript.confidence - expectedConfidence) < 0.0001)
        #expect(requests.count == 1)
        #expect(requests[0].request.value(forHTTPHeaderField: "Authorization") == "Bearer openai-test-key")
        #expect(requests[0].request.value(forHTTPHeaderField: "Content-Type")?.contains("multipart/form-data; boundary=") == true)
        #expect(bodyString.contains("name=\"model\""))
        #expect(bodyString.contains("whisper-1"))
        #expect(bodyString.contains("name=\"response_format\""))
        #expect(bodyString.contains("verbose_json"))
        #expect(bodyString.contains("name=\"language\""))
        #expect(bodyString.contains("\r\nhi\r\n"))
        #expect(bodyString.contains("filename=\"sample.m4a\""))
    }

    @Test
    func transcribeRetriesTransientServerFailuresBeforeSucceeding() async throws {
        let transport = MockHTTPTransport(
            responses: [
                .success(statusCode: 500, body: Data("{\"error\":\"temporary\"}".utf8)),
                .success(statusCode: 200, body: Data("{\"text\":\"Recovered\",\"language\":\"en\",\"segments\":[{\"avg_logprob\":-0.1}]}".utf8))
            ]
        )
        let service = OpenAIWhisperTranscriptionService(
            apiKey: "openai-test-key",
            transport: transport,
            retryPolicy: RetryPolicy(maxAttempts: 3, baseDelayMilliseconds: 0, maxJitterMilliseconds: 0)
        )
        let audioURL = try makeTemporaryAudioFile(named: "retry", extension: "wav")

        let transcript = try await service.transcribe(
            audio: audioURL,
            language: .auto
        )

        let requests = await transport.capturedRequests()

        #expect(transcript.text == "Recovered")
        #expect(requests.count == 2)
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

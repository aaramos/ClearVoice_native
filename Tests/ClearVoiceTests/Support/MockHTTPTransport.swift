import Foundation
@testable import ClearVoice

actor MockHTTPTransport: HTTPTransport {
    enum Response: Sendable {
        case success(statusCode: Int, body: Data)
        case failure(URLError)
    }

    struct CapturedRequest: Sendable {
        let request: URLRequest
        let body: Data?
    }

    private var responses: [Response]
    private var capturedRequestsStorage: [CapturedRequest] = []

    init(responses: [Response]) {
        self.responses = responses
    }

    func data(for request: URLRequest, body: Data?) async throws -> (Data, HTTPURLResponse) {
        capturedRequestsStorage.append(CapturedRequest(request: request, body: body))

        guard !responses.isEmpty else {
            throw URLError(.badServerResponse)
        }

        let nextResponse = responses.removeFirst()

        switch nextResponse {
        case .success(let statusCode, let body):
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            return (body, response)
        case .failure(let error):
            throw error
        }
    }

    func capturedRequests() -> [CapturedRequest] {
        capturedRequestsStorage
    }
}

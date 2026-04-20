import Foundation
import OSLog

protocol HTTPTransport: Sendable {
    func data(for request: URLRequest, body: Data?) async throws -> (Data, HTTPURLResponse)
}

actor URLSessionHTTPTransport: HTTPTransport {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest, body: Data?) async throws -> (Data, HTTPURLResponse) {
        var request = request
        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        return (data, httpResponse)
    }
}

struct RetryPolicy: Sendable {
    let maxAttempts: Int
    let baseDelayMilliseconds: UInt64
    let maxJitterMilliseconds: UInt64

    static let `default` = RetryPolicy(
        maxAttempts: 3,
        baseDelayMilliseconds: 400,
        maxJitterMilliseconds: 250
    )
}

actor CloudHTTPClient {
    enum RequestError: Error, Sendable {
        case invalidResponse
        case unsuccessfulStatus(code: Int, bodySnippet: String)

        var isRetriable: Bool {
            switch self {
            case .invalidResponse:
                return true
            case .unsuccessfulStatus(let code, _):
                return code == 429 || (500...599).contains(code)
            }
        }
    }

    private let transport: any HTTPTransport
    private let retryPolicy: RetryPolicy
    private let logger: Logger
    private let sleep: @Sendable (UInt64) async throws -> Void
    private let jitterMilliseconds: @Sendable () -> UInt64

    init(
        transport: any HTTPTransport = URLSessionHTTPTransport(),
        retryPolicy: RetryPolicy = .default,
        logger: Logger,
        sleep: @escaping @Sendable (UInt64) async throws -> Void = { milliseconds in
            try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
        },
        jitterMilliseconds: (@Sendable () -> UInt64)? = nil
    ) {
        self.transport = transport
        self.retryPolicy = retryPolicy
        self.logger = logger
        self.sleep = sleep
        self.jitterMilliseconds = jitterMilliseconds ?? {
            UInt64.random(in: 0...retryPolicy.maxJitterMilliseconds)
        }
    }

    func send(request: URLRequest, body: Data?) async throws -> Data {
        let (data, _) = try await sendWithResponse(request: request, body: body)
        return data
    }

    func sendWithResponse(request: URLRequest, body: Data?) async throws -> (Data, HTTPURLResponse) {
        var lastError: Error?

        for attempt in 1...retryPolicy.maxAttempts {
            do {
                let (data, response) = try await transport.data(for: request, body: body)

                guard (200...299).contains(response.statusCode) else {
                    throw RequestError.unsuccessfulStatus(
                        code: response.statusCode,
                        bodySnippet: String(decoding: data.prefix(240), as: UTF8.self)
                    )
                }

                return (data, response)
            } catch let error as RequestError {
                lastError = error

                guard error.isRetriable, attempt < retryPolicy.maxAttempts else {
                    throw error
                }

                let delay = delayMilliseconds(forAttempt: attempt)
                logger.warning("Retrying request after \(delay, privacy: .public)ms due to transient response.")
                try await sleep(delay)
            } catch let error as URLError {
                lastError = error

                guard isRetriable(error: error), attempt < retryPolicy.maxAttempts else {
                    throw error
                }

                let delay = delayMilliseconds(forAttempt: attempt)
                logger.warning("Retrying request after \(delay, privacy: .public)ms due to transport error.")
                try await sleep(delay)
            } catch {
                throw error
            }
        }

        throw lastError ?? RequestError.invalidResponse
    }

    private func delayMilliseconds(forAttempt attempt: Int) -> UInt64 {
        let exponentialDelay = retryPolicy.baseDelayMilliseconds * UInt64(1 << (attempt - 1))
        let cappedJitter = min(jitterMilliseconds(), retryPolicy.maxJitterMilliseconds)
        return exponentialDelay + cappedJitter
    }

    private func isRetriable(error: URLError) -> Bool {
        switch error.code {
        case .timedOut,
                .networkConnectionLost,
                .notConnectedToInternet,
                .cannotConnectToHost,
                .cannotFindHost,
                .dnsLookupFailed,
                .resourceUnavailable:
            return true
        default:
            return false
        }
    }
}

import Darwin
import Foundation

actor AsyncSemaphore {
    private var availablePermits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) {
        self.availablePermits = value
    }

    func acquire() async {
        if availablePermits > 0 {
            availablePermits -= 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if let continuation = waiters.first {
            waiters.removeFirst()
            continuation.resume()
        } else {
            availablePermits += 1
        }
    }
}

enum ExternalProcessRunner {
    static func run(
        executableURL: URL,
        arguments: [String],
        launchFailurePrefix: String,
        nonZeroExitPrefix: String
    ) async throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let errorPipe = Pipe()
        process.standardError = errorPipe

        let state = ProcessExecutionState(process: process)

        do {
            try Task.checkCancellation()

            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    process.terminationHandler = { process in
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let detail = String(data: errorData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)

                        guard !state.markResumed() else {
                            return
                        }

                        if state.wasCancelled {
                            continuation.resume(throwing: ProcessingError.cancelled)
                            return
                        }

                        if process.terminationStatus == 0 {
                            continuation.resume()
                            return
                        }

                        if let detail, !detail.isEmpty {
                            continuation.resume(
                                throwing: ProcessingError.enhancementFailed(processFailureMessage(prefix: nonZeroExitPrefix, detail: detail))
                            )
                        } else {
                            continuation.resume(throwing: ProcessingError.enhancementFailed(nonZeroExitPrefix))
                        }
                    }

                    do {
                        try process.run()
                    } catch {
                        guard !state.markResumed() else {
                            return
                        }

                        continuation.resume(
                            throwing: ProcessingError.enhancementFailed("\(launchFailurePrefix): \(error.localizedDescription)")
                        )
                    }
                }
            } onCancel: {
                state.cancel()
            }
        } catch is CancellationError {
            throw ProcessingError.cancelled
        }
    }
}

private func processFailureMessage(prefix: String, detail: String) -> String {
    let trimmedPrefix = prefix.hasSuffix(".") ? String(prefix.dropLast()) : prefix
    return "\(trimmedPrefix): \(detail)"
}

private final class ProcessExecutionState: @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()
    private var cancelled = false
    private var resumed = false

    init(process: Process) {
        self.process = process
    }

    var wasCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func markResumed() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if resumed {
            return true
        }

        resumed = true
        return false
    }

    func cancel() {
        let processIdentifier: pid_t?

        lock.lock()
        cancelled = true
        processIdentifier = process.isRunning ? process.processIdentifier : nil
        lock.unlock()

        guard let processIdentifier else {
            return
        }

        process.terminate()

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            if self.process.isRunning {
                kill(processIdentifier, SIGKILL)
            }
        }
    }
}

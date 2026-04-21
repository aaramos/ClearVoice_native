import Foundation

actor LocalNLLBTranslationService: TranslationService {
    typealias Runner = @Sendable (URL, [String], Data, TimeInterval) async throws -> Data

    private let fileManager: FileManager
    private let pythonExecutableURL: URL?
    private let helperScriptURL: URL
    private let modelDirectory: URL
    private let maxBatchSegments: Int
    private let maxBatchCharacters: Int
    private let timeoutSeconds: TimeInterval
    private let runner: Runner

    init(
        fileManager: FileManager = .default,
        pythonExecutableURL: URL? = LocalNLLBTranslationService.defaultPythonExecutableURL(),
        helperScriptURL: URL = LocalNLLBTranslationService.defaultHelperScriptURL(),
        modelDirectory: URL = LocalNLLBTranslationService.defaultModelDirectory(),
        maxBatchSegments: Int = 16,
        maxBatchCharacters: Int = 4_000,
        timeoutSeconds: TimeInterval = 600,
        runner: @escaping Runner = LocalNLLBTranslationService.processRunner
    ) {
        self.fileManager = fileManager
        self.pythonExecutableURL = pythonExecutableURL
        self.helperScriptURL = helperScriptURL
        self.modelDirectory = modelDirectory
        self.maxBatchSegments = maxBatchSegments
        self.maxBatchCharacters = maxBatchCharacters
        self.timeoutSeconds = timeoutSeconds
        self.runner = runner
    }

    static func isRuntimeAvailable(
        fileManager: FileManager = .default,
        pythonExecutableURL: URL? = defaultPythonExecutableURL(),
        helperScriptURL: URL = defaultHelperScriptURL(),
        modelDirectory: URL = defaultModelDirectory()
    ) -> Bool {
        guard let pythonExecutableURL else {
            return false
        }

        return fileManager.fileExists(atPath: pythonExecutableURL.path)
            && fileManager.fileExists(atPath: helperScriptURL.path)
            && fileManager.fileExists(atPath: modelDirectory.appendingPathComponent("model.bin").path)
            && fileManager.fileExists(atPath: modelDirectory.appendingPathComponent("config.json").path)
            && fileManager.fileExists(atPath: modelDirectory.appendingPathComponent("tokenizer.json").path)
            && fileManager.fileExists(atPath: modelDirectory.appendingPathComponent("sentencepiece.bpe.model").path)
    }

    func translate(
        text: String,
        from sourceLanguage: String,
        to targetLanguage: String
    ) async throws -> String {
        let results = try await translateSegments(
            [text],
            from: sourceLanguage,
            to: targetLanguage
        )

        guard let first = results.first else {
            throw ProcessingError.translationFailed("ClearVoice’s local NLLB translator returned no English text.")
        }

        return first
    }

    func translateSegments(
        _ segments: [String],
        from sourceLanguage: String,
        to targetLanguage: String
    ) async throws -> [String] {
        let preparedSegments = segments.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard preparedSegments.contains(where: { !$0.isEmpty }) else {
            return Array(repeating: "", count: segments.count)
        }

        guard sourceLanguage != targetLanguage else {
            return preparedSegments
        }

        guard let pythonExecutableURL else {
            throw ProcessingError.translationFailed(
                "ClearVoice couldn’t find the local Python runtime for Marathi-to-English translation."
            )
        }

        guard fileManager.fileExists(atPath: pythonExecutableURL.path) else {
            throw ProcessingError.translationFailed(
                "ClearVoice couldn’t find the local Python runtime for Marathi-to-English translation."
            )
        }

        guard fileManager.fileExists(atPath: helperScriptURL.path) else {
            throw ProcessingError.translationFailed(
                "ClearVoice couldn’t find the local NLLB translation helper script."
            )
        }

        guard Self.isRuntimeAvailable(
            fileManager: fileManager,
            pythonExecutableURL: pythonExecutableURL,
            helperScriptURL: helperScriptURL,
            modelDirectory: modelDirectory
        ) else {
            throw ProcessingError.translationFailed(
                "ClearVoice couldn’t find the local NLLB translation model files on this Mac."
            )
        }

        guard let sourceNLLB = Language.nllbCode(for: sourceLanguage),
              let targetNLLB = Language.nllbCode(for: targetLanguage) else {
            throw ProcessingError.translationFailed(
                "ClearVoice doesn’t have an NLLB language mapping for \(sourceLanguage) -> \(targetLanguage)."
            )
        }

        var outputs = Array(repeating: "", count: preparedSegments.count)
        let nonEmptySegments = preparedSegments.enumerated().compactMap { index, segment in
            segment.isEmpty ? nil : IndexedSegment(index: index, text: segment)
        }

        for batch in Self.segmentBatches(
            from: nonEmptySegments,
            maxBatchSegments: maxBatchSegments,
            maxBatchCharacters: maxBatchCharacters
        ) {
            let request = NLLBTranslationRequest(segments: batch.map(\.text))
            let requestData = try JSONEncoder().encode(request)

            let stdout = try await runner(
                pythonExecutableURL,
                [
                    helperScriptURL.path,
                    "--model-dir", modelDirectory.path,
                    "--source-lang", sourceNLLB,
                    "--target-lang", targetNLLB,
                ],
                requestData,
                timeoutSeconds
            )

            let response: NLLBTranslationResponse
            do {
                response = try JSONDecoder().decode(NLLBTranslationResponse.self, from: stdout)
            } catch {
                throw ProcessingError.translationFailed(
                    "ClearVoice couldn’t read the local NLLB translation output."
                )
            }

            guard response.translations.count == batch.count else {
                throw ProcessingError.translationFailed(
                    "ClearVoice’s local NLLB translator returned an unexpected number of English segments."
                )
            }

            for (indexedSegment, translation) in zip(batch, response.translations) {
                outputs[indexedSegment.index] = translation.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return outputs
    }

    static func defaultPythonExecutableURL() -> URL? {
        let env = ProcessInfo.processInfo.environment
        if let override = env["CLEARVOICE_TRANSLATION_PYTHON"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }

        let candidate = defaultRuntimeRoot()
            .appendingPathComponent("venv", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python")

        return candidate
    }

    static func defaultHelperScriptURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Support", isDirectory: true)
            .appendingPathComponent("nllb_translate.py")
    }

    static func defaultModelDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["CLEARVOICE_TRANSLATION_MODEL_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }

        return defaultRuntimeRoot()
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("nllb-200-distilled-600M-int8", isDirectory: true)
    }

    private static func defaultRuntimeRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("local_translation", isDirectory: true)
    }

    private static func segmentBatches(
        from segments: [IndexedSegment],
        maxBatchSegments: Int,
        maxBatchCharacters: Int
    ) -> [[IndexedSegment]] {
        var batches: [[IndexedSegment]] = []
        var currentBatch: [IndexedSegment] = []
        var currentCharacters = 0

        for segment in segments {
            let proposedCharacters = currentCharacters + segment.text.count
            let wouldOverflowCount = currentBatch.count >= maxBatchSegments
            let wouldOverflowCharacters = !currentBatch.isEmpty && proposedCharacters > maxBatchCharacters

            if wouldOverflowCount || wouldOverflowCharacters {
                batches.append(currentBatch)
                currentBatch = []
                currentCharacters = 0
            }

            currentBatch.append(segment)
            currentCharacters += segment.text.count
        }

        if !currentBatch.isEmpty {
            batches.append(currentBatch)
        }

        return batches
    }

    private static let processRunner: Runner = { executableURL, arguments, stdinData, timeoutSeconds in
        try await runProcess(
            executableURL: executableURL,
            arguments: arguments,
            stdinData: stdinData,
            timeoutSeconds: timeoutSeconds
        )
    }

    private static func runProcess(
        executableURL: URL,
        arguments: [String],
        stdinData: Data,
        timeoutSeconds: TimeInterval
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let stdinPipe = Pipe()

            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.standardInput = stdinPipe

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ProcessingError.translationFailed(error.localizedDescription))
                return
            }

            stdinPipe.fileHandleForWriting.write(stdinData)
            try? stdinPipe.fileHandleForWriting.close()

            let timeoutTask = Task {
                let nanoseconds = UInt64(max(timeoutSeconds, 0) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                if process.isRunning {
                    process.terminate()
                }
            }

            process.terminationHandler = { process in
                timeoutTask.cancel()

                let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                if process.terminationStatus == 0 {
                    continuation.resume(returning: stdout)
                    return
                }

                let message = String(data: stderr, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                continuation.resume(
                    throwing: ProcessingError.translationFailed(
                        message?.isEmpty == false
                            ? "ClearVoice’s local NLLB translator failed: \(message!)"
                            : "ClearVoice’s local NLLB translator exited with status \(process.terminationStatus)."
                    )
                )
            }
        }
    }
}

private struct NLLBTranslationRequest: Codable {
    let segments: [String]
}

private struct NLLBTranslationResponse: Codable {
    let translations: [String]
}

private struct IndexedSegment: Sendable {
    let index: Int
    let text: String
}

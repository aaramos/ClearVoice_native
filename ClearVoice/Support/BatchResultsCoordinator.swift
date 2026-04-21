import AppKit
import Foundation

struct BatchResultsPresentation: Sendable {
    let pageFileURL: URL
    let browserURL: URL
}

enum BatchResultsPresentationError: LocalizedError {
    case missingOutputFolder

    var errorDescription: String? {
        switch self {
        case .missingOutputFolder:
            return "ClearVoice couldn’t find the batch output folder for the browser results page."
        }
    }
}

@MainActor
final class BatchResultsCoordinator {
    static let shared = BatchResultsCoordinator()

    private let fileManager: FileManager
    private let pageWriter: BatchResultsPageWriter
    private let browserOpener: (URL) -> Bool

    init(
        fileManager: FileManager = .default,
        pageWriter: BatchResultsPageWriter = BatchResultsPageWriter(),
        browserOpener: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) {
        self.fileManager = fileManager
        self.pageWriter = pageWriter
        self.browserOpener = browserOpener
    }

    func preparePresentation(
        outputFolderURL: URL,
        files: [AudioFileItem],
        enhancementMethod: EnhancementMethod
    ) async throws -> BatchResultsPresentation {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: outputFolderURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw BatchResultsPresentationError.missingOutputFolder
        }

        let pageFileURL = try pageWriter.writePage(
            into: outputFolderURL,
            files: files,
            enhancementMethod: enhancementMethod
        )

        return BatchResultsPresentation(pageFileURL: pageFileURL, browserURL: pageFileURL)
    }

    func openBrowser(at url: URL) -> Bool {
        browserOpener(url)
    }
}

struct BatchResultsPageWriter {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func writePage(
        into outputFolderURL: URL,
        files: [AudioFileItem],
        enhancementMethod: EnhancementMethod
    ) throws -> URL {
        try fileManager.createDirectory(at: outputFolderURL, withIntermediateDirectories: true)

        let pageURL = outputFolderURL.appendingPathComponent("index.html")
        let html = pageHTML(
            files: files.sorted { $0.sourceURL.lastPathComponent.localizedCaseInsensitiveCompare($1.sourceURL.lastPathComponent) == .orderedAscending },
            outputFolderURL: outputFolderURL,
            enhancementMethod: enhancementMethod
        )

        guard let data = html.data(using: .utf8) else {
            throw ProcessingError.exportFailed("ClearVoice couldn’t encode the browser results page as UTF-8.")
        }

        try data.write(to: pageURL, options: .atomic)
        return pageURL
    }

    private func pageHTML(
        files: [AudioFileItem],
        outputFolderURL: URL,
        enhancementMethod: EnhancementMethod
    ) -> String {
        let completedCount = files.filter { $0.stage == .complete }.count
        let failedCount = files.filter {
            if case .failed = $0.stage { return true }
            return false
        }.count
        let skippedCount = files.filter {
            if case .skipped = $0.stage { return true }
            return false
        }.count

        let cards = files.map { file in
            resultCardHTML(for: file, outputFolderURL: outputFolderURL, enhancementMethod: enhancementMethod)
        }.joined(separator: "\n")

        let generatedAt = escaped(DateFormatter.localizedString(from: .now, dateStyle: .medium, timeStyle: .short))

        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>ClearVoice Results</title>
          <style>
            :root {
              color-scheme: light;
              --bg: #f6f8fc;
              --panel: #ffffff;
              --border: rgba(18, 24, 38, 0.12);
              --text: #172033;
              --muted: #65708a;
              --accent: #1f7aec;
              --success: #1f9d57;
              --warning: #c7791f;
              --danger: #c93d35;
            }
            * { box-sizing: border-box; }
            body {
              margin: 0;
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
              background: linear-gradient(180deg, #fbfcff 0%, var(--bg) 100%);
              color: var(--text);
            }
            main {
              max-width: 1080px;
              margin: 0 auto;
              padding: 40px 28px 56px;
            }
            .hero {
              display: flex;
              justify-content: space-between;
              align-items: flex-start;
              gap: 24px;
              margin-bottom: 28px;
            }
            .hero h1 {
              margin: 0 0 8px;
              font-size: 2.2rem;
              line-height: 1.1;
            }
            .hero p {
              margin: 0;
              color: var(--muted);
              max-width: 720px;
              line-height: 1.5;
            }
            .badge {
              display: inline-flex;
              align-items: center;
              gap: 8px;
              padding: 10px 14px;
              border-radius: 999px;
              background: rgba(31, 122, 236, 0.09);
              color: var(--accent);
              font-weight: 600;
              white-space: nowrap;
            }
            .summary {
              display: grid;
              grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
              gap: 14px;
              margin-bottom: 28px;
            }
            .summary-card, .result-card {
              background: var(--panel);
              border: 1px solid var(--border);
              border-radius: 18px;
              box-shadow: 0 12px 30px rgba(14, 25, 47, 0.04);
            }
            .summary-card {
              padding: 18px;
            }
            .summary-card .label {
              color: var(--muted);
              font-size: 0.92rem;
              margin-bottom: 6px;
            }
            .summary-card .value {
              font-size: 1.35rem;
              font-weight: 700;
            }
            .results-grid {
              display: grid;
              gap: 16px;
            }
            .result-card {
              padding: 22px;
            }
            .result-header {
              display: flex;
              justify-content: space-between;
              gap: 18px;
              align-items: flex-start;
              margin-bottom: 12px;
            }
            .file-name {
              font-size: 1.15rem;
              font-weight: 650;
              margin: 0 0 4px;
            }
            .meta {
              color: var(--muted);
              font-size: 0.94rem;
            }
            .status {
              padding: 7px 12px;
              border-radius: 999px;
              font-weight: 600;
              font-size: 0.88rem;
            }
            .status.complete { color: var(--success); background: rgba(31, 157, 87, 0.09); }
            .status.failed { color: var(--danger); background: rgba(201, 61, 53, 0.10); }
            .status.skipped { color: var(--warning); background: rgba(199, 121, 31, 0.10); }
            .status.pending { color: var(--muted); background: rgba(101, 112, 138, 0.10); }
            .detail {
              color: var(--muted);
              margin: 10px 0 0;
              line-height: 1.5;
            }
            audio {
              width: 100%;
              margin-top: 14px;
            }
            .actions {
              display: flex;
              flex-wrap: wrap;
              gap: 10px;
              margin-top: 14px;
            }
            .actions a {
              color: var(--accent);
              text-decoration: none;
              font-weight: 600;
            }
            .toggle-row {
              display: flex;
              flex-wrap: wrap;
              align-items: center;
              justify-content: space-between;
              gap: 12px;
              margin-top: 14px;
            }
            .toggle-group {
              display: inline-flex;
              padding: 4px;
              border-radius: 999px;
              background: #edf2fb;
              border: 1px solid var(--border);
            }
            .toggle-group button {
              border: 0;
              background: transparent;
              color: var(--muted);
              font: inherit;
              font-weight: 600;
              border-radius: 999px;
              padding: 8px 14px;
              cursor: pointer;
            }
            .toggle-group button.active {
              background: white;
              color: var(--text);
              box-shadow: 0 1px 4px rgba(14, 25, 47, 0.08);
            }
            .toggle-note {
              color: var(--muted);
              font-size: 0.9rem;
            }
            footer {
              margin-top: 26px;
              color: var(--muted);
              font-size: 0.92rem;
              line-height: 1.5;
            }
          </style>
        </head>
        <body>
          <main>
            <section class="hero">
              <div>
                <h1>ClearVoice Results</h1>
                <p>Review the enhanced files from this batch outside the app. Use the built-in audio controls, open the processed folders, or hand the entire output folder to someone else with this page included.</p>
              </div>
              <div class="badge">Enhanced with \(escaped(enhancementMethod.title))</div>
            </section>

            <section class="summary">
              <div class="summary-card">
                <div class="label">Completed</div>
                <div class="value">\(completedCount)</div>
              </div>
              <div class="summary-card">
                <div class="label">Failed</div>
                <div class="value">\(failedCount)</div>
              </div>
              <div class="summary-card">
                <div class="label">Skipped</div>
                <div class="value">\(skippedCount)</div>
              </div>
            </section>

            <section class="results-grid">
              \(cards)
            </section>

            <footer>
              Generated \(generatedAt). This page lives inside the batch output folder so the results stay portable with the processed audio.
            </footer>
          </main>
          <script>
            function setActiveToggle(card, activeKind) {
              const buttons = card.querySelectorAll('[data-audio-toggle]');
              buttons.forEach((button) => {
                button.classList.toggle('active', button.dataset.audioToggle === activeKind);
              });
            }

            document.addEventListener('click', (event) => {
              const button = event.target.closest('[data-audio-toggle]');
              if (!button) return;

              const card = button.closest('.result-card');
              const audio = card ? card.querySelector('audio') : null;
              if (!audio) return;

              const nextKind = button.dataset.audioToggle;
              const nextSource = nextKind === 'source' ? audio.dataset.sourceSrc : audio.dataset.enhancedSrc;
              if (!nextSource || audio.dataset.currentKind === nextKind) return;

              const wasPaused = audio.paused;
              const currentTime = Number.isFinite(audio.currentTime) ? audio.currentTime : 0;
              const playbackRate = audio.playbackRate || 1;

              audio.dataset.pendingTime = String(currentTime);
              audio.dataset.pendingPaused = wasPaused ? 'true' : 'false';
              audio.dataset.pendingRate = String(playbackRate);
              audio.dataset.currentKind = nextKind;
              audio.src = nextSource;
              audio.load();
              setActiveToggle(card, nextKind);
            });

            document.querySelectorAll('.result-card audio').forEach((audio) => {
              audio.addEventListener('loadedmetadata', () => {
                const pendingTime = Number(audio.dataset.pendingTime || '0');
                const pendingPaused = audio.dataset.pendingPaused === 'true';
                const pendingRate = Number(audio.dataset.pendingRate || '1');

                if (Number.isFinite(pendingTime) && pendingTime > 0) {
                  const safeTime = Number.isFinite(audio.duration) && audio.duration > 0
                    ? Math.min(pendingTime, Math.max(audio.duration - 0.05, 0))
                    : pendingTime;
                  audio.currentTime = safeTime;
                }

                if (Number.isFinite(pendingRate) && pendingRate > 0) {
                  audio.playbackRate = pendingRate;
                }

                if (!pendingPaused) {
                  const playPromise = audio.play();
                  if (playPromise && typeof playPromise.catch === 'function') {
                    playPromise.catch(() => {});
                  }
                }
              });
            });
          </script>
        </body>
        </html>
        """
    }

    private func resultCardHTML(
        for file: AudioFileItem,
        outputFolderURL: URL,
        enhancementMethod: EnhancementMethod
    ) -> String {
        let duration = escaped(file.durationSeconds.map { DurationFormatter.formattedDuration(seconds: $0) } ?? "—")
        let fileName = escaped(file.sourceURL.lastPathComponent)
        let statusLabel = escaped(stageLabel(for: file.stage))
        let statusClass = statusClass(for: file.stage)
        let sourceAudioURL = sourceAudioURL(for: file)
        let processedAudioURL = processedAudioURL(for: file, enhancementMethod: enhancementMethod)

        let audioSection: String
        let actionsSection: String

        if let defaultAudioURL = processedAudioURL ?? sourceAudioURL {
            let audioPath = relativePath(from: outputFolderURL, to: defaultAudioURL)
            let folderPath = file.outputFolderURL.map { relativePath(from: outputFolderURL, to: $0).appending("/") } ?? ""
            let sourcePath = sourceAudioURL.map { relativePath(from: outputFolderURL, to: $0) }
            let enhancedPath = processedAudioURL.map { relativePath(from: outputFolderURL, to: $0) }
            let currentKind = processedAudioURL != nil ? "enhanced" : "source"
            let toggleSection: String

            if let sourcePath, let enhancedPath {
                toggleSection = """
                <div class="toggle-row">
                  <div class="toggle-group" role="group" aria-label="Choose source or enhanced audio">
                    <button type="button" class="\(currentKind == "enhanced" ? "active" : "")" data-audio-toggle="enhanced">Enhanced</button>
                    <button type="button" class="\(currentKind == "source" ? "active" : "")" data-audio-toggle="source">Source</button>
                  </div>
                  <div class="toggle-note">Starts on enhanced audio and switches at the same playback position.</div>
                </div>
                <audio controls preload="none" src="\(audioPath)" data-current-kind="\(currentKind)" data-source-src="\(sourcePath)" data-enhanced-src="\(enhancedPath)"></audio>
                """
            } else {
                toggleSection = "<audio controls preload=\"none\" src=\"\(audioPath)\"></audio>"
            }

            audioSection = toggleSection
            actionsSection = """
            <div class="actions">
              \(processedAudioURL.map { "<a href=\"\(relativePath(from: outputFolderURL, to: $0))\">Open enhanced file</a>" } ?? "")
              \(sourceAudioURL.map { "<a href=\"\(relativePath(from: outputFolderURL, to: $0))\">Open source file</a>" } ?? "")
              \(folderPath.isEmpty ? "" : "<a href=\"\(folderPath)\">Browse folder</a>")
            </div>
            """
        } else {
            audioSection = ""
            actionsSection = ""
        }

        let detail = stageDetail(for: file.stage).map { "<p class=\"detail\">\(escaped($0))</p>" } ?? ""

        return """
        <article class="result-card">
          <div class="result-header">
            <div>
              <p class="file-name">\(fileName)</p>
              <div class="meta">Duration \(duration)</div>
            </div>
            <span class="status \(statusClass)">\(statusLabel)</span>
          </div>
          \(audioSection)
          \(actionsSection)
          \(detail)
        </article>
        """
    }

    private func processedAudioURL(for file: AudioFileItem, enhancementMethod: EnhancementMethod) -> URL? {
        guard let folderURL = file.outputFolderURL else {
            return nil
        }

        let url = folderURL.appendingPathComponent("\(file.basename)_\(enhancementMethod.outputSuffix).m4a")
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    private func sourceAudioURL(for file: AudioFileItem) -> URL? {
        guard let folderURL = file.outputFolderURL else {
            return nil
        }

        let url = folderURL.appendingPathComponent(file.sourceURL.lastPathComponent)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    private func stageLabel(for stage: ProcessingStage) -> String {
        switch stage {
        case .complete:
            return "Finished"
        case .failed:
            return "Error"
        case .skipped:
            return "Skipped"
        default:
            return "Processing"
        }
    }

    private func statusClass(for stage: ProcessingStage) -> String {
        switch stage {
        case .complete:
            return "complete"
        case .failed:
            return "failed"
        case .skipped:
            return "skipped"
        default:
            return "pending"
        }
    }

    private func stageDetail(for stage: ProcessingStage) -> String? {
        switch stage {
        case .failed(let error):
            return error.displayMessage
        case .skipped(let reason):
            switch reason {
            case .outputFolderExists(let folderURL):
                return "Skipped because \(folderURL.lastPathComponent) already existed in the batch output folder."
            }
        case .complete:
            return nil
        default:
            return "This file is still processing."
        }
    }

    private func relativePath(from baseURL: URL, to targetURL: URL) -> String {
        let baseComponents = baseURL.standardizedFileURL.pathComponents
        let targetComponents = targetURL.standardizedFileURL.pathComponents
        let relativeComponents = targetComponents.dropFirst(baseComponents.count)

        return relativeComponents
            .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0 }
            .joined(separator: "/")
    }

    private func escaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

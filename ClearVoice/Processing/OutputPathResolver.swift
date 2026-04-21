import Foundation

enum ResolvedOutput: Equatable, Sendable {
    case use(folder: URL)
    case skip(reason: SkipReason)
}

actor OutputPathResolver {
    private let outputRoot: URL
    private let preexistingFolders: Set<URL>
    private var reservedThisBatch: Set<URL> = []
    private var occurrenceCounts: [String: Int] = [:]

    init(outputRoot: URL, fileManager: FileManager = .default) throws {
        self.outputRoot = outputRoot.resolvingSymlinksInPath().standardizedFileURL

        try fileManager.createDirectory(
            at: self.outputRoot,
            withIntermediateDirectories: true
        )

        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey]
        let contents = try fileManager.contentsOfDirectory(
            at: self.outputRoot,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        )

        self.preexistingFolders = Set(
            contents.compactMap { url in
                guard (try? url.resourceValues(forKeys: resourceKeys).isDirectory) == true else {
                    return nil
                }

                return url.resolvingSymlinksInPath().standardizedFileURL
            }
        )
    }

    func resolve(basename: String) -> ResolvedOutput {
        let nextOccurrence = (occurrenceCounts[basename] ?? 0) + 1
        occurrenceCounts[basename] = nextOccurrence

        // Queue-order collision numbering comes first. We then apply the
        // skip-on-preexisting rule to that assigned candidate so the behavior
        // matches the handoff's precedence rules and test matrix.
        let assignedCandidate = folderURL(for: basename, suffix: nextOccurrence)

        if preexistingFolders.contains(assignedCandidate) {
            return .skip(reason: .outputFolderExists(assignedCandidate))
        }

        var candidate = assignedCandidate
        var spilloverSuffix = nextOccurrence

        while reservedThisBatch.contains(candidate) || preexistingFolders.contains(candidate) {
            spilloverSuffix += 1
            candidate = folderURL(for: basename, suffix: spilloverSuffix)
        }

        reservedThisBatch.insert(candidate)
        return .use(folder: candidate)
    }

    private func folderURL(for basename: String, suffix: Int) -> URL {
        let folderName = suffix == 1 ? basename : "\(basename)_\(suffix)"
        return outputRoot.appendingPathComponent(folderName, isDirectory: true)
    }
}

import Foundation

struct ResolvedOutput: Equatable, Sendable {
    let folderURL: URL
    let enhancedFileURL: URL
}

actor OutputPathResolver {
    private let sourceRoot: URL
    private let outputRoot: URL
    private let fileManager: FileManager
    private var reservedEnhancedFiles: Set<URL> = []

    init(
        sourceRoot: URL,
        outputRoot: URL,
        fileManager: FileManager = .default
    ) throws {
        self.sourceRoot = sourceRoot.resolvingSymlinksInPath().standardizedFileURL
        self.outputRoot = outputRoot.resolvingSymlinksInPath().standardizedFileURL
        self.fileManager = fileManager

        try fileManager.createDirectory(
            at: self.outputRoot,
            withIntermediateDirectories: true
        )
    }

    func resolve(sourceURL: URL, enhancementSuffix: String) -> ResolvedOutput {
        let standardizedSourceURL = sourceURL.resolvingSymlinksInPath().standardizedFileURL
        let relativeDirectoryComponents = relativeDirectoryComponents(for: standardizedSourceURL)
        let outputFolderURL = relativeDirectoryComponents.reduce(outputRoot) { partialURL, component in
            partialURL.appendingPathComponent(component, isDirectory: true)
        }

        var candidate = preferredEnhancedFileURL(
            for: standardizedSourceURL,
            in: outputFolderURL,
            enhancementSuffix: enhancementSuffix
        )

        if reservedEnhancedFiles.contains(candidate) || fileManager.fileExists(atPath: candidate.path) {
            candidate = disambiguatedEnhancedFileURL(
                for: standardizedSourceURL,
                in: outputFolderURL,
                enhancementSuffix: enhancementSuffix
            )
        }

        reservedEnhancedFiles.insert(candidate)
        return ResolvedOutput(folderURL: outputFolderURL, enhancedFileURL: candidate)
    }

    private func relativeDirectoryComponents(for sourceURL: URL) -> [String] {
        let sourceDirectoryComponents = sourceURL.deletingLastPathComponent().pathComponents
        let sourceRootComponents = sourceRoot.pathComponents

        guard sourceDirectoryComponents.starts(with: sourceRootComponents) else {
            return []
        }

        return Array(sourceDirectoryComponents.dropFirst(sourceRootComponents.count))
    }

    private func preferredEnhancedFileURL(
        for sourceURL: URL,
        in outputFolderURL: URL,
        enhancementSuffix: String
    ) -> URL {
        outputFolderURL.appendingPathComponent(
            "\(sourceURL.deletingPathExtension().lastPathComponent)_\(enhancementSuffix).\(AudioFormatSupport.cleanExportExtension)"
        )
    }

    private func disambiguatedEnhancedFileURL(
        for sourceURL: URL,
        in outputFolderURL: URL,
        enhancementSuffix: String
    ) -> URL {
        let basename = sourceURL.deletingPathExtension().lastPathComponent
        let sourceExtension = sourceURL.pathExtension.lowercased()
        let extensionSegment = sourceExtension.isEmpty ? "audio" : sourceExtension
        var counter = 1

        while true {
            let suffixSegment = counter == 1 ? extensionSegment : "\(extensionSegment)_\(counter)"
            let candidate = outputFolderURL.appendingPathComponent(
                "\(basename)_\(suffixSegment)_\(enhancementSuffix).\(AudioFormatSupport.cleanExportExtension)"
            )

            if !reservedEnhancedFiles.contains(candidate) && !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }

            counter += 1
        }
    }
}

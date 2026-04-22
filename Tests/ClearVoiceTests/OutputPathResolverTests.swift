import Foundation
import Testing
@testable import ClearVoice

struct OutputPathResolverTests {
    @Test
    func resolveMirrorsNestedSourceDirectories() async throws {
        let harness = try ResolverHarness()
        let sourceURL = try harness.createSourceFile(at: ["Archive", "1980"], named: "alpha.wav")
        let resolver = try OutputPathResolver(sourceRoot: harness.sourceRoot, outputRoot: harness.outputRoot)

        let resolved = await resolver.resolve(sourceURL: sourceURL, enhancementSuffix: "HYBRID")

        #expect(resolved.folderURL == harness.outputRoot.appendingPathComponent("Archive/1980", isDirectory: true))
        #expect(resolved.enhancedFileURL == harness.outputRoot.appendingPathComponent("Archive/1980/alpha_HYBRID.m4a"))
    }

    @Test
    func filesInDifferentSourceFoldersKeepSeparateOutputFolders() async throws {
        let harness = try ResolverHarness()
        let firstSourceURL = try harness.createSourceFile(at: ["Disc 1"], named: "audio.wav")
        let secondSourceURL = try harness.createSourceFile(at: ["Disc 2"], named: "audio.wav")
        let resolver = try OutputPathResolver(sourceRoot: harness.sourceRoot, outputRoot: harness.outputRoot)

        let first = await resolver.resolve(sourceURL: firstSourceURL, enhancementSuffix: "DFN")
        let second = await resolver.resolve(sourceURL: secondSourceURL, enhancementSuffix: "DFN")

        #expect(first.folderURL == harness.outputRoot.appendingPathComponent("Disc 1", isDirectory: true))
        #expect(first.enhancedFileURL == harness.outputRoot.appendingPathComponent("Disc 1/audio_DFN.m4a"))
        #expect(second.folderURL == harness.outputRoot.appendingPathComponent("Disc 2", isDirectory: true))
        #expect(second.enhancedFileURL == harness.outputRoot.appendingPathComponent("Disc 2/audio_DFN.m4a"))
    }

    @Test
    func sameFolderBasenameCollisionUsesExtensionDisambiguation() async throws {
        let harness = try ResolverHarness()
        let wavSourceURL = try harness.createSourceFile(at: ["Transfers"], named: "audio.wav")
        let mp3SourceURL = try harness.createSourceFile(at: ["Transfers"], named: "audio.mp3")
        let resolver = try OutputPathResolver(sourceRoot: harness.sourceRoot, outputRoot: harness.outputRoot)

        let first = await resolver.resolve(sourceURL: wavSourceURL, enhancementSuffix: "DFN")
        let second = await resolver.resolve(sourceURL: mp3SourceURL, enhancementSuffix: "DFN")

        #expect(first.enhancedFileURL == harness.outputRoot.appendingPathComponent("Transfers/audio_DFN.m4a"))
        #expect(second.enhancedFileURL == harness.outputRoot.appendingPathComponent("Transfers/audio_mp3_DFN.m4a"))
    }

    @Test
    func missingOutputRootIsCreatedAutomatically() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceRoot = root.appendingPathComponent("source", isDirectory: true)
        let outputRoot = root.appendingPathComponent("source_enhanced", isDirectory: true)

        try fileManager.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let sourceURL = sourceRoot.appendingPathComponent("audio.wav")
        try Data("stub".utf8).write(to: sourceURL)

        let resolver = try OutputPathResolver(sourceRoot: sourceRoot, outputRoot: outputRoot)
        let resolved = await resolver.resolve(sourceURL: sourceURL, enhancementSuffix: "DFN")

        var isDirectory: ObjCBool = false
        #expect(fileManager.fileExists(atPath: outputRoot.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(resolved.folderURL.standardizedFileURL.path == outputRoot.standardizedFileURL.path)
        #expect(resolved.enhancedFileURL == outputRoot.appendingPathComponent("audio_DFN.m4a"))
    }
}

private struct ResolverHarness {
    let root: URL
    let sourceRoot: URL
    let outputRoot: URL

    init() throws {
        let fileManager = FileManager.default
        root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        sourceRoot = root.appendingPathComponent("source", isDirectory: true)
        outputRoot = root.appendingPathComponent("source_enhanced", isDirectory: true)
        try fileManager.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
    }

    func createSourceFile(at pathComponents: [String], named fileName: String) throws -> URL {
        let fileManager = FileManager.default
        let folderURL = pathComponents.reduce(sourceRoot) { partialURL, component in
            partialURL.appendingPathComponent(component, isDirectory: true)
        }

        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let fileURL = folderURL.appendingPathComponent(fileName)
        try Data("stub".utf8).write(to: fileURL)
        return fileURL
    }
}

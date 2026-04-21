import Foundation
import Testing
@testable import ClearVoice

struct OutputPathResolverTests {
    @Test
    func uniqueBasenamesUseUnsuffixedFolders() async throws {
        let harness = try ResolverHarness()
        let resolver = try OutputPathResolver(outputRoot: harness.outputRoot)

        let alpha = await resolver.resolve(basename: "alpha")
        let beta = await resolver.resolve(basename: "beta")

        #expect(alpha == .use(folder: harness.outputRoot.appendingPathComponent("alpha", isDirectory: true)))
        #expect(beta == .use(folder: harness.outputRoot.appendingPathComponent("beta", isDirectory: true)))
    }

    @Test
    func twoFilesWithTheSameBasenameAssignTheSecondSuffix() async throws {
        let harness = try ResolverHarness()
        let resolver = try OutputPathResolver(outputRoot: harness.outputRoot)

        let first = await resolver.resolve(basename: "audio")
        let second = await resolver.resolve(basename: "audio")

        #expect(first == .use(folder: harness.outputRoot.appendingPathComponent("audio", isDirectory: true)))
        #expect(second == .use(folder: harness.outputRoot.appendingPathComponent("audio_2", isDirectory: true)))
    }

    @Test
    func threeFilesWithTheSameBasenameAssignSequentialSuffixes() async throws {
        let harness = try ResolverHarness()
        let resolver = try OutputPathResolver(outputRoot: harness.outputRoot)

        let first = await resolver.resolve(basename: "audio")
        let second = await resolver.resolve(basename: "audio")
        let third = await resolver.resolve(basename: "audio")

        #expect(first == .use(folder: harness.outputRoot.appendingPathComponent("audio", isDirectory: true)))
        #expect(second == .use(folder: harness.outputRoot.appendingPathComponent("audio_2", isDirectory: true)))
        #expect(third == .use(folder: harness.outputRoot.appendingPathComponent("audio_3", isDirectory: true)))
    }

    @Test
    func preexistingNaturalFolderSkipsIndependentFilesWithoutRerouting() async throws {
        let firstHarness = try ResolverHarness(preexistingFolders: ["audio"])
        let firstResolver = try OutputPathResolver(outputRoot: firstHarness.outputRoot)
        let first = await firstResolver.resolve(basename: "audio")

        let secondHarness = try ResolverHarness(preexistingFolders: ["audio"])
        let secondResolver = try OutputPathResolver(outputRoot: secondHarness.outputRoot)
        let second = await secondResolver.resolve(basename: "audio")

        #expect(first == .skip(reason: .outputFolderExists(firstHarness.outputRoot.appendingPathComponent("audio", isDirectory: true))))
        #expect(second == .skip(reason: .outputFolderExists(secondHarness.outputRoot.appendingPathComponent("audio", isDirectory: true))))
    }

    @Test
    func preexistingNaturalFolderWithCollisionPairSkipsFirstAndUsesAudio2ForSecond() async throws {
        let harness = try ResolverHarness(preexistingFolders: ["audio"])
        let resolver = try OutputPathResolver(outputRoot: harness.outputRoot)

        let first = await resolver.resolve(basename: "audio")
        let second = await resolver.resolve(basename: "audio")

        #expect(first == .skip(reason: .outputFolderExists(harness.outputRoot.appendingPathComponent("audio", isDirectory: true))))
        #expect(second == .use(folder: harness.outputRoot.appendingPathComponent("audio_2", isDirectory: true)))
    }

    @Test
    func preexistingAudioAndAudio2SkipFirstTwoAndUseAudio3ForThird() async throws {
        let harness = try ResolverHarness(preexistingFolders: ["audio", "audio_2"])
        let resolver = try OutputPathResolver(outputRoot: harness.outputRoot)

        let first = await resolver.resolve(basename: "audio")
        let second = await resolver.resolve(basename: "audio")
        let third = await resolver.resolve(basename: "audio")

        #expect(first == .skip(reason: .outputFolderExists(harness.outputRoot.appendingPathComponent("audio", isDirectory: true))))
        #expect(second == .skip(reason: .outputFolderExists(harness.outputRoot.appendingPathComponent("audio_2", isDirectory: true))))
        #expect(third == .use(folder: harness.outputRoot.appendingPathComponent("audio_3", isDirectory: true)))
    }

    @Test
    func missingOutputRootIsCreatedAutomatically() async throws {
        let fileManager = FileManager.default
        let missingRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)

        let resolver = try OutputPathResolver(outputRoot: missingRoot)
        let first = await resolver.resolve(basename: "audio")

        var isDirectory: ObjCBool = false
        #expect(fileManager.fileExists(atPath: missingRoot.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(first == .use(folder: missingRoot.appendingPathComponent("audio", isDirectory: true)))
    }
}

private struct ResolverHarness {
    let outputRoot: URL

    init(preexistingFolders: [String] = []) throws {
        let fileManager = FileManager.default
        outputRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: outputRoot, withIntermediateDirectories: true)

        for folder in preexistingFolders {
            try fileManager.createDirectory(
                at: outputRoot.appendingPathComponent(folder, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }
}

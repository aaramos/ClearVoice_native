import Foundation
import Testing
@testable import ClearVoice

struct ProcessingModeConfigurationTests {
    @Test
    func defaultsUseLocalModesWithSummarizationEnabled() {
        let configuration = ProcessingModeConfiguration()

        #expect(configuration.transcription == .local)
        #expect(configuration.translation == .local)
        #expect(configuration.summarizationEnabled)
    }

    @Test
    func codableRoundTripPreservesValues() throws {
        let configuration = ProcessingModeConfiguration(
            transcription: .cloud,
            translation: .local,
            summarizationEnabled: false
        )

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(ProcessingModeConfiguration.self, from: data)

        #expect(decoded == configuration)
    }

    @Test
    func storeLoadsDefaultWhenNothingPersisted() {
        let (defaults, suiteName) = makeDefaults()
        defaults.removePersistentDomain(forName: suiteName)

        let store = ProcessingModeStore(userDefaults: defaults)
        let configuration = store.load()

        #expect(configuration == ProcessingModeConfiguration())
    }

    @Test
    func storePersistsTranscriptionAndTranslationModes() {
        let (defaults, suiteName) = makeDefaults()
        defaults.removePersistentDomain(forName: suiteName)

        let store = ProcessingModeStore(userDefaults: defaults)
        store.save(
            ProcessingModeConfiguration(
                transcription: .cloud,
                translation: .cloud,
                summarizationEnabled: false
            )
        )

        let loaded = store.load()

        #expect(loaded.transcription == .cloud)
        #expect(loaded.translation == .cloud)
        #expect(loaded.summarizationEnabled == false)
    }
}

private func makeDefaults() -> (UserDefaults, String) {
    let suiteName = "ProcessingModeConfigurationTests.\(UUID().uuidString)"
    return (UserDefaults(suiteName: suiteName)!, suiteName)
}

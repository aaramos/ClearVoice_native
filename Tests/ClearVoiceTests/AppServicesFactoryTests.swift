import Testing
@testable import ClearVoice

struct AppServicesFactoryTests {
    @Test
    func resolvedGeminiAPIKeyPrefersEnvironmentVariable() throws {
        let key = try AppServicesFactory.resolvedGeminiAPIKey(
            environment: ["GEMINI_API_KEY": "env-key"],
            apiKeyStore: MockAPIKeyStore(storedKey: "saved-key")
        )

        #expect(key == "env-key")
    }

    @Test
    func resolvedGeminiAPIKeyFallsBackToKeychainWhenEnvironmentMissing() throws {
        let key = try AppServicesFactory.resolvedGeminiAPIKey(
            environment: [:],
            apiKeyStore: MockAPIKeyStore(storedKey: "saved-key")
        )

        #expect(key == "saved-key")
    }

    @Test
    func keychainLaunchErrorExplainsStorageLocation() {
        let error = LaunchRequirementsError.keychainAccessFailed("Keychain access is unavailable.")

        #expect(error.title == "Couldn’t Access Your Saved API Key")
        #expect(error.message.contains("Keychain"))
    }
}

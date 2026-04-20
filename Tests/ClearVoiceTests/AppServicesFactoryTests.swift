import Testing
@testable import ClearVoice

struct AppServicesFactoryTests {
    @Test
    func makeLiveServiceBundleFailsFastWhenRequiredKeysAreMissing() {
        #expect(throws: LaunchRequirementsError.self) {
            try AppServicesFactory.makeLiveServiceBundle(environment: [:])
        }
    }

    @Test
    func missingKeysErrorNamesBothVariables() {
        let error = LaunchRequirementsError.missingEnvironmentVariables([
            "OPENAI_API_KEY",
            "OLLAMA_API_KEY"
        ])

        #expect(error.title == "Missing API Keys")
        #expect(error.message.contains("OPENAI_API_KEY"))
        #expect(error.message.contains("OLLAMA_API_KEY"))
    }
}

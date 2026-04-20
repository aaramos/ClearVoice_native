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
    func missingKeysErrorNamesGeminiVariable() {
        let error = LaunchRequirementsError.missingEnvironmentVariables([
            "GEMINI_API_KEY"
        ])

        #expect(error.title == "Missing API Keys")
        #expect(error.message.contains("GEMINI_API_KEY"))
    }
}

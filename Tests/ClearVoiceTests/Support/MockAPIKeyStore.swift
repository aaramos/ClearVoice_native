@testable import ClearVoice

final class MockAPIKeyStore: APIKeyStore {
    var storedKey: String?
    var readError: APIKeyStoreError?
    var saveError: APIKeyStoreError?
    var savedKeys: [String] = []
    var readCount = 0

    init(storedKey: String? = nil) {
        self.storedKey = storedKey
    }

    func readGeminiAPIKey() throws -> String? {
        readCount += 1

        if let readError {
            throw readError
        }

        return storedKey
    }

    func saveGeminiAPIKey(_ apiKey: String) throws {
        if let saveError {
            throw saveError
        }

        savedKeys.append(apiKey)
        storedKey = apiKey
    }
}

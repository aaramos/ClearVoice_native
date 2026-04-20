import Foundation
import Security

protocol APIKeyStore {
    func readGeminiAPIKey() throws -> String?
    func saveGeminiAPIKey(_ apiKey: String) throws
}

enum APIKeyStoreError: Error, LocalizedError, Equatable {
    case invalidInput
    case unexpectedData
    case readFailed(status: OSStatus)
    case saveFailed(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidInput:
            return "Enter a Gemini API key before continuing."
        case .unexpectedData:
            return "ClearVoice found a saved Gemini API key in Keychain, but couldn’t read it back safely."
        case .readFailed(let status):
            return "ClearVoice couldn’t read your Gemini API key from Keychain. \(Self.statusMessage(for: status))"
        case .saveFailed(let status):
            return "ClearVoice couldn’t save your Gemini API key to Keychain. \(Self.statusMessage(for: status))"
        }
    }

    private static func statusMessage(for status: OSStatus) -> String {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return message
        }

        return "OSStatus \(status)."
    }
}

struct KeychainGeminiAPIKeyStore: APIKeyStore {
    private enum Backend {
        case dataProtection
        case legacyLoginKeychain
    }

    private let service: String
    private let account: String
    private let label: String

    init(
        service: String = "com.clearvoice.ClearVoice",
        account: String = "gemini_api_key",
        label: String = "ClearVoice Gemini API Key"
    ) {
        self.service = service
        self.account = account
        self.label = label
    }

    func readGeminiAPIKey() throws -> String? {
        do {
            if let key = try readGeminiAPIKey(using: .dataProtection) {
                return key
            }
        } catch APIKeyStoreError.readFailed(let status) where status != errSecMissingEntitlement {
            throw APIKeyStoreError.readFailed(status: status)
        }

        return try readGeminiAPIKey(using: .legacyLoginKeychain)
    }

    func saveGeminiAPIKey(_ apiKey: String) throws {
        guard let trimmedKey = apiKey.trimmedNonEmpty else {
            throw APIKeyStoreError.invalidInput
        }

        do {
            try saveGeminiAPIKey(trimmedKey, using: .dataProtection)
        } catch APIKeyStoreError.saveFailed(let status) where status == errSecMissingEntitlement {
            try saveGeminiAPIKey(trimmedKey, using: .legacyLoginKeychain)
        }
    }

    private func readGeminiAPIKey(using backend: Backend) throws -> String? {
        var query = baseQuery(for: backend)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard
                let data = item as? Data,
                let apiKey = String(data: data, encoding: .utf8)?.trimmedNonEmpty
            else {
                throw APIKeyStoreError.unexpectedData
            }

            return apiKey
        case errSecItemNotFound:
            return nil
        default:
            throw APIKeyStoreError.readFailed(status: status)
        }
    }

    private func saveGeminiAPIKey(_ apiKey: String, using backend: Backend) throws {
        let keyData = Data(apiKey.utf8)
        var addQuery = baseQuery(for: backend)
        addQuery[kSecAttrLabel as String] = label
        addQuery[kSecValueData as String] = keyData

        if case .dataProtection = backend {
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }

        let status = SecItemAdd(addQuery as CFDictionary, nil)

        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            var attributesToUpdate: [String: Any] = [
                kSecAttrLabel as String: label,
                kSecValueData as String: keyData
            ]

            if case .dataProtection = backend {
                attributesToUpdate[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            }

            let updateStatus = SecItemUpdate(
                baseQuery(for: backend) as CFDictionary,
                attributesToUpdate as CFDictionary
            )

            guard updateStatus == errSecSuccess else {
                throw APIKeyStoreError.saveFailed(status: updateStatus)
            }
        default:
            throw APIKeyStoreError.saveFailed(status: status)
        }
    }

    private func baseQuery(for backend: Backend) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        switch backend {
        case .dataProtection:
            query[kSecAttrSynchronizable as String] = kCFBooleanFalse as Any
            query[kSecUseDataProtectionKeychain as String] = true
        case .legacyLoginKeychain:
            break
        }

        return query
    }
}

import Foundation
import Security

/// Simple wrapper around the macOS Keychain for storing sensitive data like API keys.
enum KeychainHelper {

    private static let service = "com.justin.timesink"

    /// Saves a string value to the Keychain.
    static func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]

        let existingStatus = SecItemCopyMatching(baseQuery as CFDictionary, nil)

        switch existingStatus {
        case errSecSuccess:
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.saveFailed(updateStatus)
            }
        case errSecItemNotFound:
            var addQuery = baseQuery
            attributes.forEach { addQuery[$0.key] = $0.value }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.saveFailed(addStatus)
            }
        default:
            throw KeychainError.lookupFailed(existingStatus)
        }
    }

    /// Loads a string value from the Keychain.
    static func load(key: String) -> String? {
        try? loadRequired(key: key)
    }

    /// Loads a string value from the Keychain and throws a descriptive error on failure.
    static func loadRequired(key: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            break
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        default:
            throw KeychainError.lookupFailed(status)
        }

        if let data = result as? Data, let string = String(data: data, encoding: .utf8) {
            return string
        }

        if let string = result as? String {
            return string
        }

        throw KeychainError.unexpectedResultType
    }

    /// Deletes a value from the Keychain.
    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Whether a key exists in the Keychain.
    static func exists(key: String) -> Bool {
        load(key: key) != nil
    }
}

// MARK: - Well-Known Keys

extension KeychainHelper {
    /// The Keychain key for the Anthropic API key.
    static let anthropicAPIKeyKey = "anthropic_api_key"
    static let openAIAPIKeyKey = "openai_api_key"
    static let geminiAPIKeyKey = "gemini_api_key"

    /// Convenience: get/set the Anthropic API key.
    static var anthropicAPIKey: String? {
        get { load(key: anthropicAPIKeyKey) }
        set {
            if let value = newValue {
                try? save(key: anthropicAPIKeyKey, value: value)
            } else {
                delete(key: anthropicAPIKeyKey)
            }
        }
    }

    static func apiKey(for provider: AIProvider) -> String? {
        load(key: provider.keychainKey)
    }

    static func setAPIKey(_ value: String?, for provider: AIProvider) throws {
        if let value, !value.isEmpty {
            try save(key: provider.keychainKey, value: value)
        } else {
            delete(key: provider.keychainKey)
        }
    }
}

// MARK: - KeychainError

enum KeychainError: LocalizedError, Sendable {
    case encodingFailed
    case saveFailed(OSStatus)
    case lookupFailed(OSStatus)
    case itemNotFound
    case unexpectedResultType

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode value for Keychain storage"
        case .saveFailed(let status):
            return "Keychain save failed: \(statusMessage(for: status))"
        case .lookupFailed(let status):
            return "Keychain lookup failed: \(statusMessage(for: status))"
        case .itemNotFound:
            return "Keychain item not found"
        case .unexpectedResultType:
            return "Keychain returned an unexpected result type"
        }
    }

    private func statusMessage(for status: OSStatus) -> String {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return "\(message) (\(status))"
        }
        return "status \(status)"
    }
}

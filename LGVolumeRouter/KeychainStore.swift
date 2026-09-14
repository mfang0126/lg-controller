import Foundation
import Security

struct KeychainStore {
    enum StoreError: LocalizedError {
        case unexpectedStatus(OSStatus)
        case invalidStoredValue

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                return "Keychain operation failed (status \(status))."
            case .invalidStoredValue:
                return "The saved LG client key is not valid text."
            }
        }
    }

    private let service: String

    /// Client keys are scoped by host so a pairing for one TV cannot authenticate to another.
    init(service: String = ProductConfiguration.bundleIdentifier) {
        self.service = service
    }

    func clientKey(forHost host: String) throws -> String? {
        guard !host.isEmpty else { return nil }

        var query = baseQuery(forHost: host)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw StoreError.unexpectedStatus(status)
        }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            throw StoreError.invalidStoredValue
        }
        return value
    }

    func saveClientKey(_ clientKey: String, forHost host: String) throws {
        guard !host.isEmpty, !clientKey.isEmpty else {
            throw StoreError.invalidStoredValue
        }

        let query = baseQuery(forHost: host)
        let data = Data(clientKey.utf8)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw StoreError.unexpectedStatus(updateStatus)
        }

        var item = query
        item[kSecValueData as String] = data
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw StoreError.unexpectedStatus(addStatus)
        }
    }

    func deleteClientKey(forHost host: String) throws {
        guard !host.isEmpty else { return }
        let status = SecItemDelete(baseQuery(forHost: host) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(forHost host: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: host
        ]
    }
}

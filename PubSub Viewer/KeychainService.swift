//
//  KeychainService.swift
//  PubSub Viewer
//
//  Minimal Keychain wrapper for storing per-server credentials.
//

import Foundation
import Security

enum KeychainService {
    enum CredentialKind: String {
        case password
        case token
    }

    private static var serviceName: String {
        Bundle.main.bundleIdentifier ?? "PubSubViewer"
    }

    static func key(for serverId: UUID, kind: CredentialKind) -> String {
        "\(serverId.uuidString).\(kind.rawValue)"
    }

    static func storeString(_ value: String, key: String) throws {
        let data = Data(value.utf8)

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: key
        ]

        // Replace any existing item.
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData] = data

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.storeFailed(status: status)
        }
    }

    static func readString(key: String) throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.readFailed(status: status)
        }

        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status: status)
        }
    }

    enum KeychainError: Error {
        case storeFailed(status: OSStatus)
        case readFailed(status: OSStatus)
        case deleteFailed(status: OSStatus)
    }
}


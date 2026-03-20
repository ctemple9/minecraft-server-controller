//
//  KeychainManager.swift
//

import Foundation
import Security

/// Handles reading and writing sensitive credentials to the macOS Keychain.
///
/// Two values are managed here:
///   - The Remote API owner token (one global value)
///   - The Xbox Broadcast alt-account password (one value per server, keyed by server ID)
///
/// Both use `kSecClassGenericPassword`, which is the correct Keychain item class
/// for application secrets that are not internet credentials.
final class KeychainManager {

    static let shared = KeychainManager()
    private init() {}

    // MARK: - Service identifiers

    /// Keychain service name for the Remote API owner token.
    private static let remoteAPITokenService = "com.camerontemple.minecraftservercontroller.remoteapitoken"

    /// Keychain service name for per-server Xbox Broadcast alt-account passwords.
    private static let xboxBroadcastPasswordService = "com.camerontemple.minecraftservercontroller.xboxbroadcast.altpassword"

    /// Fixed account name for the Remote API token (there is only one owner token).
    private static let remoteAPITokenAccount = "owner"

    // MARK: - Remote API Token

    func readRemoteAPIToken() -> String? {
        return read(service: Self.remoteAPITokenService, account: Self.remoteAPITokenAccount)
    }

    /// Writes the token to Keychain. Passing `nil` deletes the existing entry.
    @discardableResult
    func writeRemoteAPIToken(_ token: String?) -> Bool {
        guard let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return delete(service: Self.remoteAPITokenService, account: Self.remoteAPITokenAccount)
        }
        return write(value: token, service: Self.remoteAPITokenService, account: Self.remoteAPITokenAccount)
    }

    // MARK: - Xbox Broadcast Alt Password

    /// Account key is the server's UUID, so each server stores its own password independently.
    func readXboxBroadcastAltPassword(forServerId serverId: String) -> String? {
        return read(service: Self.xboxBroadcastPasswordService, account: serverId)
    }

    /// Writes the password for `serverId`. Passing `nil` or an empty string deletes the entry.
    @discardableResult
    func writeXboxBroadcastAltPassword(_ password: String?, forServerId serverId: String) -> Bool {
        guard let password, !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return delete(service: Self.xboxBroadcastPasswordService, account: serverId)
        }
        return write(value: password, service: Self.xboxBroadcastPasswordService, account: serverId)
    }

    // MARK: - Reset helpers

    /// Deletes the global Remote API token and every per-server Xbox Broadcast alt password.
    /// Returns true when all deletions succeed (missing items count as success).
    @discardableResult
    func deleteAllMSCSecrets(serverIDs: [String]) -> Bool {
        var allSucceeded = true

        if !delete(service: Self.remoteAPITokenService, account: Self.remoteAPITokenAccount) {
            allSucceeded = false
        }

        for serverID in serverIDs {
            if !delete(service: Self.xboxBroadcastPasswordService, account: serverID) {
                allSucceeded = false
            }
        }

        return allSucceeded
    }

    // MARK: - Generic Keychain primitives

    private func read(service: String, account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      account,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    /// Upsert: updates if the item exists, adds if it does not.
    @discardableResult
    private func write(value: String, service: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]

        let attributes: [CFString: Any] = [
            kSecValueData: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            // Item doesn't exist yet — add it.
            var addQuery = query
            addQuery[kSecValueData] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                #if DEBUG
                print("KeychainManager: SecItemAdd failed (status \(addStatus)) for service=\(service) account=\(account)")
                #endif
                return false
            }
        } else if updateStatus != errSecSuccess {
            #if DEBUG
            print("KeychainManager: SecItemUpdate failed (status \(updateStatus)) for service=\(service) account=\(account)")
            #endif
            return false
        }

        return true
    }

    @discardableResult
    private func delete(service: String, account: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        // errSecItemNotFound is acceptable — the item was already absent.
        return status == errSecSuccess || status == errSecItemNotFound
    }
}


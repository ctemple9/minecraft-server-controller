//
//  ConfigManager.swift
//

import Foundation

/// Loads and persists `AppConfig` to Application Support.
///
/// Sensitive fields (like Remote API tokens and per-server passwords) are stored in Keychain and
/// rehydrated into the in-memory config on load.
final class ConfigManager {

    static let shared = ConfigManager()

    // MARK: - Stored state

    /// The current in-memory configuration model.
    var config: AppConfig

    /// Location of the persisted JSON config on disk.
    let configURL: URL

    // MARK: - Initialization

    private init() {
        let fm = FileManager.default

        let appSupportDir: URL
        do {
            appSupportDir = try fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            let home = fm.homeDirectoryForCurrentUser
            appSupportDir = home
        }

        let appDir = appSupportDir.appendingPathComponent("MinecraftServerController", isDirectory: true)

        do {
            try fm.createDirectory(at: appDir, withIntermediateDirectories: true)
        } catch {
            #if DEBUG
            print("ConfigManager: Failed to create app directory \(error)")
            #endif
        }

        self.configURL = appDir.appendingPathComponent("server_config_swift.json", isDirectory: false)

        if fm.fileExists(atPath: configURL.path) {
            do {
                let data = try Data(contentsOf: configURL)
                let jsonText = String(data: data, encoding: .utf8) ?? ""

                // ── One-time migration ────────────────────────────────────────
                // If the JSON still contains the old plaintext token or password
                // keys, read them, move them to Keychain, then let the save()
                // below strip them from the file.
                if jsonText.contains("\"remote_api_token\""),
                   let rawJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let oldToken = rawJSON["remote_api_token"] as? String,
                   !oldToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    KeychainManager.shared.writeRemoteAPIToken(oldToken)
                }

                // Password migration is per-server; handled after decoding servers below.

                let decoder = JSONDecoder()
                self.config = try decoder.decode(AppConfig.self, from: data)

                // Migrate per-server plaintext passwords that may still be in JSON.
                if let rawJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let serversArray = rawJSON["servers"] as? [[String: Any]] {
                    for serverDict in serversArray {
                        if let serverId = serverDict["id"] as? String,
                           let oldPassword = serverDict["xbox_broadcast_alt_password"] as? String,
                           !oldPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            KeychainManager.shared.writeXboxBroadcastAltPassword(oldPassword, forServerId: serverId)
                        }
                    }
                }

                // ── Validate port ─────────────────────────────────────────────
                if config.remoteAPIPort < 1 || config.remoteAPIPort > 65535 {
                    config.remoteAPIPort = AppConfig.defaultRemoteAPIPort
                }

                // ── Populate sensitive fields from Keychain ───────────────────
                populateSecretsFromKeychain()

                save()

            } catch {
                #if DEBUG
                print("ConfigManager: Failed to load config, using defaults \(error)")
                #endif
                self.config = AppConfig.defaultConfig()
                populateSecretsFromKeychain()
                save()
            }
        } else {
            self.config = AppConfig.defaultConfig()
            populateSecretsFromKeychain()
            save()
        }
    }

    // MARK: - Reload / Save

    /// Reload the JSON config from disk and re-populate Keychain-backed fields.
    func reload() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: configURL.path) else {
            self.config = AppConfig.defaultConfig()
            populateSecretsFromKeychain()
            save()
            return
        }

        do {
            let data = try Data(contentsOf: configURL)

            let decoder = JSONDecoder()
            self.config = try decoder.decode(AppConfig.self, from: data)

            // Ensure reasonable port range.
            if config.remoteAPIPort < 1 || config.remoteAPIPort > 65535 {
                config.remoteAPIPort = AppConfig.defaultRemoteAPIPort
                save()
            }

            // Re-populate sensitive fields from Keychain after every reload.
            populateSecretsFromKeychain()

        } catch {
            #if DEBUG
            print("ConfigManager: reload error \(error)")
            #endif
        }
    }

    /// Persist the current config to disk, ensuring Keychain-backed fields are stored first.
    func save() {
        // Persist sensitive credentials to Keychain before writing JSON.
        // This ensures that if the token was just regenerated in-memory (e.g.
        // from PreferencesView), it gets durably stored.
        let trimmedToken = config.remoteAPIToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedToken.isEmpty {
            KeychainManager.shared.writeRemoteAPIToken(trimmedToken)
        } else if KeychainManager.shared.readRemoteAPIToken() == nil {
            // No token anywhere — generate one now and write it.
            let newToken = AppConfig.generateRemoteAPIToken()
            config.remoteAPIToken = newToken
            KeychainManager.shared.writeRemoteAPIToken(newToken)
        }

        // Persist each server's alt-account password to Keychain.
        for server in config.servers {
            KeychainManager.shared.writeXboxBroadcastAltPassword(
                server.xboxBroadcastAltPassword,
                forServerId: server.id
            )
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)

            let dir = configURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            try data.write(to: configURL, options: [.atomic])
        } catch {
            #if DEBUG
            print("ConfigManager: save error \(error)")
            #endif
        }
    }

    // MARK: - Keychain helpers

    /// Reads the Remote API token and each server's Xbox alt-account password
    /// from Keychain and places them into the in-memory config.
    ///
    /// Call this after any JSON decode. The JSON model intentionally omits
    /// these fields; Keychain is the authoritative source.
    private func populateSecretsFromKeychain() {
        // Remote API token: generate a fresh one if this is a brand-new install.
        if let storedToken = KeychainManager.shared.readRemoteAPIToken(),
           !storedToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            config.remoteAPIToken = storedToken
        } else {
            let newToken = AppConfig.generateRemoteAPIToken()
            config.remoteAPIToken = newToken
            KeychainManager.shared.writeRemoteAPIToken(newToken)
        }

        // Per-server passwords.
        for i in config.servers.indices {
            config.servers[i].xboxBroadcastAltPassword =
                KeychainManager.shared.readXboxBroadcastAltPassword(forServerId: config.servers[i].id)
        }
    }

    // MARK: - URL helpers

    /// Root directory where server folders are stored.
    var serversRootURL: URL {
        URL(fileURLWithPath: config.serversRoot, isDirectory: true)
    }

    /// Directory containing plugin templates for new servers.
    var pluginTemplateDirURL: URL {
        URL(fileURLWithPath: config.pluginTemplateDir, isDirectory: true)
    }

    /// Directory containing Paper JAR templates for new servers.
    var paperTemplateDirURL: URL {
        URL(fileURLWithPath: config.paperTemplateDir, isDirectory: true)
    }

    /// The app’s Application Support directory for this app.
    var appDirectoryURL: URL {
        configURL.deletingLastPathComponent()
    }

    func backupsDirectoryURL(forServerDirectory serverDir: String) -> URL {
        let serverURL = URL(fileURLWithPath: serverDir, isDirectory: true)
        return serverURL.appendingPathComponent("backups", isDirectory: true)
    }

    // MARK: - Mutating helpers

    /// Update the configured DuckDNS hostname (or clear it) and persist to disk.
    func setDuckDNS(_ hostname: String?) {
        config.duckdnsHostname = hostname
        save()
    }

    // Xbox Broadcast JAR path
    func setXboxBroadcastJarPath(_ path: String?) {
        config.xboxBroadcastJarPath = path
        save()
    }

    // Bedrock Connect JAR path
        func setBedrockConnectJarPath(_ path: String?) {
            config.bedrockConnectJarPath = path
            save()
        }

        func setBedrockConnectDNSPort(_ port: Int?) {
            config.bedrockConnectDNSPort = port
            save()
        }

    func setXboxBroadcastAutoStartEnabled(_ enabled: Bool) {
            config.xboxBroadcastAutoStartEnabled = enabled
            save()
        }

        func setBedrockConnectAutoStartEnabled(_ enabled: Bool) {
            config.bedrockConnectAutoStartEnabled = enabled
            save()
        }

    /// Default XboxBroadcast configuration directory for the given server.
    ///
    /// This is where the controller stores per-server XboxBroadcast files under Application Support.
    func xboxBroadcastConfigDirectoryURL(forServerId id: String) -> URL {
        let base = appDirectoryURL.appendingPathComponent("MCXboxBroadcast", isDirectory: true)
        return base.appendingPathComponent(id, isDirectory: true)
    }
}


//
//  AppViewModel+BedrockProperties.swift
//  MinecraftServerController
//
//
//  Mirrors the existing saveServerPropertiesModel pattern used for Java servers.
//  Call sites in ServerSettingsView use these methods exactly as they call the
//  Java equivalent — the view never needs to know which manager is underneath.
//

import Foundation

extension AppViewModel {

    // MARK: - Read

    /// Load the current BedrockPropertiesModel for the given server.
    /// Returns defaults when server.properties does not yet exist (new server).
    func bedrockPropertiesModel(for server: ConfigServer) -> BedrockPropertiesModel {
        BedrockPropertiesManager.readModel(serverDir: server.serverDir)
    }

    // MARK: - Write

    /// Persist a BedrockPropertiesModel to the server's server.properties file.
       /// Throws on any file I/O error.
       func saveBedrockPropertiesModel(_ model: BedrockPropertiesModel, for server: ConfigServer) throws {
           do {
               try BedrockPropertiesManager.writeModel(model, serverDir: server.serverDir)
               logAppMessage("[App] Updated server.properties for \(server.displayName).")
           } catch {
               logAppMessage("[App] Failed to save server.properties for \(server.displayName): \(error.localizedDescription)")
               throw error
           }

           // Keep the persisted ConfigServer port in sync with the Bedrock game port on disk.
           // Reassign through a full AppConfig copy so the save path is explicit and durable.
           var appConfig = configManager.config
           if let idx = appConfig.servers.firstIndex(where: { $0.id == server.id }) {
               appConfig.servers[idx].bedrockPort = model.serverPort
               configManager.config = appConfig
               configManager.save()
               reloadServersFromConfig()
               logAppMessage("[App] Synced Bedrock game port for \(server.displayName) to \(model.serverPort).")
           }

           // Refresh live settings/connection info for the currently selected server so the
           // UI reflects the newly saved UDP port immediately.
           if let current = selectedServer, current.id == server.id {
               loadServerSettings()
           }
      
    }

    // MARK: - Allowlist helpers (convenience wrappers)

    func bedrockAllowlist(for server: ConfigServer) -> [BedrockAllowlistEntry] {
        BedrockPropertiesManager.readAllowlist(serverDir: server.serverDir)
    }

    func addToBedrockAllowlist(name: String, xuid: String? = nil, for server: ConfigServer) throws {
        try BedrockPropertiesManager.addToAllowlist(name: name, xuid: xuid, serverDir: server.serverDir)
    }

    func removeFromBedrockAllowlist(name: String, for server: ConfigServer) throws {
        try BedrockPropertiesManager.removeFromAllowlist(name: name, serverDir: server.serverDir)
    }

    // MARK: - Permissions helpers (convenience wrappers)

    func bedrockPermissions(for server: ConfigServer) -> [BedrockPermissionsEntry] {
        BedrockPropertiesManager.readPermissions(serverDir: server.serverDir)
    }

    func setBedrockPermission(xuid: String, level: BedrockPermissionLevel, for server: ConfigServer) throws {
        try BedrockPropertiesManager.setPermission(xuid: xuid, level: level, serverDir: server.serverDir)
    }

    func removeBedrockPermission(xuid: String, for server: ConfigServer) throws {
        try BedrockPropertiesManager.removePermission(xuid: xuid, serverDir: server.serverDir)
    }
}

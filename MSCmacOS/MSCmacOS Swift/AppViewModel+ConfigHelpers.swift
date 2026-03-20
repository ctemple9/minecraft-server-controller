//
//  AppViewModel+ConfigHelpers.swift
//  MinecraftServerController
//

import Foundation

// MARK: - Config / servers list sync helpers

extension AppViewModel {

    func reloadServersFromConfig() {
        let cfg = configManager.config
        let mapped: [Server] = cfg.servers.map { configServer in
            Server(id: configServer.id, name: configServer.displayName, directory: configServer.serverDir)
        }
        servers = mapped
        let preferredId = selectedServer?.id ?? cfg.activeServerId
        if let preferredId, let match = servers.first(where: { $0.id == preferredId }) {
            selectedServer = match
        } else {
            selectedServer = servers.first
        }
    }

    func upsertServer(_ configServer: ConfigServer) {
        var appConfig = configManager.config
        if let idx = appConfig.servers.firstIndex(where: { $0.id == configServer.id }) {
            let existing = appConfig.servers[idx]
            var merged = existing
            merged.displayName = configServer.displayName
            merged.serverDir = configServer.serverDir
            merged.paperJarPath = configServer.paperJarPath
            merged.minRam = configServer.minRam
            merged.maxRam = configServer.maxRam
            merged.notes = configServer.notes
            appConfig.servers[idx] = merged
        } else {
            appConfig.servers.append(configServer)
        }
        configManager.config = appConfig
        configManager.save()
        reloadServersFromConfig()
    }

    func setActiveServer(withId id: String) {
        var appConfig = configManager.config
        appConfig.activeServerId = id
        configManager.config = appConfig
        configManager.save()
        if let match = servers.first(where: { $0.id == id }) {
            selectedServer = match
        }
    }
}

// MARK: - ConfigServer access helpers

extension AppViewModel {

    var configServers: [ConfigServer] {
        configManager.config.servers
    }

    func deleteServer(withId id: String) {
        var appConfig = configManager.config
        guard let idx = appConfig.servers.firstIndex(where: { $0.id == id }) else {
            logAppMessage("[App] Tried to delete unknown server id \(id) from config.")
            return
        }
        let removed = appConfig.servers.remove(at: idx)
        logAppMessage("[App] Removed server \"\(removed.displayName)\" from config.")
        if appConfig.activeServerId == id {
            appConfig.activeServerId = appConfig.servers.first?.id
        }
        configManager.config = appConfig
        configManager.save()
        reloadServersFromConfig()
    }

    func deleteServerFromDisk(withId id: String) throws {
        let appConfig = configManager.config
        guard let server = appConfig.servers.first(where: { $0.id == id }) else {
            logAppMessage("[App] Tried to delete unknown server id \(id) from disk.")
            return
        }
        if isServerRunning, appConfig.activeServerId == id {
            let message = "Stop the server before deleting it from disk."
            logAppMessage("[Server] \(message)")
            throw NSError(
                domain: "MinecraftServerController.ServerDeletion",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
        let folderURL = URL(fileURLWithPath: server.serverDir, isDirectory: true)
        let fm = FileManager.default
        if fm.fileExists(atPath: folderURL.path) {
            try fm.removeItem(at: folderURL)
            logAppMessage("[Server] Deleted server folder at \(folderURL.path).")
        } else {
            logAppMessage("[Server] Server folder was already missing at \(folderURL.path). Removing it from the controller anyway.")
        }
        deleteServer(withId: id)
    }
}

// MARK: - App reset helpers

extension AppViewModel {

    enum AppResetError: LocalizedError {
        case serverRunning
        case unsafeDeletionPath(String)
        case appSupportPathUnavailable
        case keychainDeleteFailed

        var errorDescription: String? {
            switch self {
            case .serverRunning:
                return "Stop the currently running server before resetting MSC."
            case .unsafeDeletionPath(let path):
                return "Refusing to delete an unsafe path: \(path)"
            case .appSupportPathUnavailable:
                return "MSC could not resolve its Application Support folder."
            case .keychainDeleteFailed:
                return "MSC could not clear one or more saved secrets from Keychain."
            }
        }
    }

    func resetApplicationForTesting() throws {
        guard !isServerRunning, activeBackend?.isRunning != true else {
            throw AppResetError.serverRunning
        }
        let fm = FileManager.default
        let serverIDs = configManager.config.servers.map(\.id)
        let appDirectoryURL = configManager.appDirectoryURL.standardizedFileURL
        let serversRootURL = configManager.serversRootURL.standardizedFileURL

        try validateResetDeletionTarget(appDirectoryURL, label: "Application Support folder")
        try validateResetDeletionTarget(serversRootURL, label: "servers root folder")

        let keychainCleared = KeychainManager.shared.deleteAllMSCSecrets(serverIDs: serverIDs)
                if !keychainCleared {
                    logAppMessage("[App] Warning: could not clear one or more Keychain secrets. Continuing reset.")
                }

        if fm.fileExists(atPath: appDirectoryURL.path) {
            try fm.removeItem(at: appDirectoryURL)
            logAppMessage("[App] Deleted MSC Application Support folder at \(appDirectoryURL.path).")
        } else {
            logAppMessage("[App] MSC Application Support folder was already absent at \(appDirectoryURL.path).")
        }

        if fm.fileExists(atPath: serversRootURL.path) {
            try fm.removeItem(at: serversRootURL)
            logAppMessage("[App] Deleted MSC servers root folder at \(serversRootURL.path).")
        } else {
            logAppMessage("[App] MSC servers root folder was already absent at \(serversRootURL.path).")
        }

        clearMSCUserDefaultsForFreshInstall()
        clearInMemoryStateAfterReset()
        logAppMessage("[App] MSC reset completed. The app should now quit.")
    }

    private func validateResetDeletionTarget(_ url: URL, label: String) throws {
        let standardized = url.standardizedFileURL
        let path = standardized.path
        let homePath = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        guard !path.isEmpty,
              path != "/",
              path != homePath,
              path != "/Applications",
              path != NSHomeDirectory() else {
            throw AppResetError.unsafeDeletionPath(path)
        }
        let appSupportRoot = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ).standardizedFileURL.path) ?? ""
        if label == "Application Support folder" {
            guard !appSupportRoot.isEmpty, path.hasPrefix(appSupportRoot + "/") || path == appSupportRoot else {
                throw AppResetError.appSupportPathUnavailable
            }
            guard standardized.lastPathComponent == "MinecraftServerController" else {
                throw AppResetError.unsafeDeletionPath(path)
            }
        }
    }

    private func clearMSCUserDefaultsForFreshInstall() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: MSCSuppressQuitWarningKey)
        defaults.removeObject(forKey: "MSC.mainWindowContentWidth")
        defaults.removeObject(forKey: "MSC.mainWindowContentHeight")
        defaults.synchronize()
    }

    private func clearInMemoryStateAfterReset() {
        servers = []
        selectedServer = nil
        isShowingWelcomeGuide = false
        isShowingInitialSetup = false
        isShowingCreateServer = false
        isServerRunning = false
        isXboxBroadcastRunning = false
        isBedrockConnectRunning = false
        pendingBroadcastAuthPrompt = nil
        firstStartNotice = nil
        onlinePlayers = []
        backupItems = []
        worldSlots = []
    }
}

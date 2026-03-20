//
//  AppViewModel+Broadcasting.swift
//  MinecraftServerController
//

import Foundation

extension AppViewModel {

    // MARK: - Broadcast config generation

    private var broadcastRootDirectoryURL: URL {
        let appSupport = configManager.configURL.deletingLastPathComponent()
        return appSupport.appendingPathComponent("MCXboxBroadcast", isDirectory: true)
    }

    private func broadcastHostForConfig(for server: ConfigServer) -> String {
        return previewBroadcastHost(for: server, mode: server.xboxBroadcastIPMode)
    }

    func previewBroadcastHost(for server: ConfigServer, mode: XboxBroadcastIPMode) -> String {
        if let override = server.xboxBroadcastHostOverride?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty { return override }

        let duck = configManager.config.duckdnsHostname
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
        let publicIP = cachedPublicIPAddress
        let privateIP = AppUtilities.localIPAddress()

        switch mode {
        case .auto:    return duck ?? publicIP ?? privateIP ?? "0.0.0.0"
        case .publicIP:  return publicIP ?? privateIP ?? "0.0.0.0"
        case .privateIP: return privateIP ?? "0.0.0.0"
        }
    }

    private func broadcastPortForConfig(for server: ConfigServer) -> Int? {
        if let override = server.xboxBroadcastPortOverride { return override }
        return effectiveBedrockPort(for: server)
    }

    private func broadcastPersistClosure(for server: ConfigServer) -> (String) -> Void {
        { [weak self] path in
            guard let self,
                  let idx = self.configManager.config.servers.firstIndex(where: { $0.id == server.id })
            else { return }
            self.configManager.config.servers[idx].xboxBroadcastConfigPath = path
            self.configManager.save()
        }
    }

    @discardableResult
    func syncBroadcastConfig(for server: ConfigServer) -> URL? {
        BroadcastConfigManager.syncConfig(
            for: server,
            rootURL: broadcastRootDirectoryURL,
            host: broadcastHostForConfig(for: server),
            port: broadcastPortForConfig(for: server),
            log: { [weak self] msg in self?.logAppMessage(msg) },
            persistPath: broadcastPersistClosure(for: server)
        )
    }

    private func ensureBroadcastConfigDirectory(for server: ConfigServer) -> URL? {
        BroadcastConfigManager.ensureConfigDirectory(
            for: server,
            rootURL: broadcastRootDirectoryURL,
            log: { [weak self] msg in self?.logAppMessage(msg) },
            persistPath: broadcastPersistClosure(for: server)
        )
    }

    // MARK: - Broadcast profile

    func updateBroadcastProfile(
        for serverId: String,
        enabled: Bool,
        ipMode: XboxBroadcastIPMode,
        altEmail: String,
        altGamertag: String,
        altPassword: String,
        altAvatarPath: String
    ) {
        var appConfig = configManager.config
        guard let idx = appConfig.servers.firstIndex(where: { $0.id == serverId }) else {
            logAppMessage("[Broadcast] Tried to update profile for unknown server id \(serverId).")
            return
        }
        appConfig.servers[idx].xboxBroadcastEnabled = enabled
        appConfig.servers[idx].xboxBroadcastIPMode = ipMode
        let trimmedEmail = altEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        appConfig.servers[idx].xboxBroadcastAltEmail = trimmedEmail.isEmpty ? nil : trimmedEmail
        let trimmedGamertag = altGamertag.trimmingCharacters(in: .whitespacesAndNewlines)
        appConfig.servers[idx].xboxBroadcastAltGamertag = trimmedGamertag.isEmpty ? nil : trimmedGamertag
        let trimmedPassword = altPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPassword: String? = trimmedPassword.isEmpty ? nil : trimmedPassword
        appConfig.servers[idx].xboxBroadcastAltPassword = normalizedPassword
        KeychainManager.shared.writeXboxBroadcastAltPassword(normalizedPassword, forServerId: appConfig.servers[idx].id)
        let trimmedAvatar = altAvatarPath.trimmingCharacters(in: .whitespacesAndNewlines)
        appConfig.servers[idx].xboxBroadcastAltAvatarPath = trimmedAvatar.isEmpty ? nil : trimmedAvatar
        configManager.config = appConfig
        configManager.save()
        let updatedServer = appConfig.servers[idx]
        _ = syncBroadcastConfig(for: updatedServer)
        logAppMessage("[Broadcast] Updated broadcast profile for \(appConfig.servers[idx].displayName).")
    }

    // MARK: - Auto-start preferences

    var xboxBroadcastAutoStartEnabled: Bool {
            get { configManager.config.xboxBroadcastAutoStartEnabled }
            set { configManager.setXboxBroadcastAutoStartEnabled(newValue) }
        }

        /// Per-server Xbox Broadcast enabled state — mirrors the Edit Server › Broadcast toggle.
        /// The sidebar auto-start toggle binds to this so both controls stay in sync.
        var selectedServerXboxBroadcastEnabled: Bool {
            get {
                guard let server = selectedServer,
                      let cfg = configServer(for: server) else { return false }
                return cfg.xboxBroadcastEnabled
            }
            set {
                guard let server = selectedServer,
                      let idx = configManager.config.servers.firstIndex(where: { $0.id == server.id }) else { return }
                configManager.config.servers[idx].xboxBroadcastEnabled = newValue
                configManager.save()
            }
        }

    var bedrockConnectAutoStartEnabled: Bool {
        get { configManager.config.bedrockConnectAutoStartEnabled }
        set { configManager.setBedrockConnectAutoStartEnabled(newValue) }
    }

    // MARK: - Manual sidebar controls

    func startXboxBroadcast() {
        guard !broadcastManager.isRunning else {
            logAppMessage("[Broadcast] Already running.")
            return
        }
        guard let jarPath = configManager.config.xboxBroadcastJarPath?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !jarPath.isEmpty else {
            logAppMessage("[Broadcast] JAR path not configured.")
            showError(title: "XboxBroadcast", message: "No JAR path configured. Download the helper in Edit Server → Broadcast.")
            return
        }
        guard let runningCfg = configManager.config.servers.first(where: { $0.id == lifecycle.runningServerId })
                                ?? configManager.config.servers.first else {
            showError(title: "XboxBroadcast", message: "No server config found. Open Edit Server → Broadcast to configure one first.")
            return
        }
        guard let configDir = syncBroadcastConfig(for: runningCfg) else { return }
        do {
            try broadcastManager.startBroadcast(javaPath: configManager.config.javaPath, jarPath: jarPath, workingDirectory: configDir)
            isXboxBroadcastRunning = true
            logAppMessage("[Broadcast] Manually started XboxBroadcast from sidebar.")
        } catch let error as XboxBroadcastProcessManager.BroadcastError {
            switch error {
            case .alreadyRunning: logAppMessage("[Broadcast] Already running.")
            case .failedToStart(let underlying):
                logAppMessage("[Broadcast] Failed to start: \(underlying.localizedDescription)")
                showError(title: "XboxBroadcast Failed", message: underlying.localizedDescription)
            }
        } catch {
            logAppMessage("[Broadcast] Failed to start: \(error.localizedDescription)")
            showError(title: "XboxBroadcast Failed", message: error.localizedDescription)
        }
    }

    func stopXboxBroadcast() {
        guard broadcastManager.isRunning else { return }
        broadcastManager.terminate()
        isXboxBroadcastRunning = false
        logAppMessage("[Broadcast] Manually stopped XboxBroadcast from sidebar.")
    }

    func stopBroadcastIfRunning() {
        guard broadcastManager.isRunning else { return }
        broadcastManager.terminate()
        isXboxBroadcastRunning = false
        logAppMessage("[Broadcast] Stopped Broadcaster.")
    }

    func stopBedrockConnectIfRunning() {
        guard bedrockConnectManager.isRunning else { return }
        bedrockConnectManager.terminate()
        isBedrockConnectRunning = false
        logAppMessage("[BedrockConnect] Stopped Bedrock Connect.")
    }

    func openBroadcastConfigFolder(for configServer: ConfigServer) {
        guard let dir = ensureBroadcastConfigDirectory(for: configServer) else { return }
        openInFinder(dir, description: "broadcast config folder for \(configServer.displayName)")
    }

    // MARK: - Auto-start after server starts

    // MARK: - Auto-start after server starts

    private var broadcastStartupDelaySeconds: Double { 30.0 }

    func startBroadcastIfNeeded(for configServer: ConfigServer) {
        if lifecycle.initiatingFirstRunServerId == configServer.id {
            logAppMessage("[Broadcast] Skipping Broadcaster start during Initiate for \(configServer.displayName).")
            return
        }
        guard configManager.config.xboxBroadcastAutoStartEnabled else {
            logAppMessage("[Broadcast] Auto-start is disabled — skipping automatic Broadcaster launch.")
            return
        }
        guard configServer.xboxBroadcastEnabled else { return }
        guard !broadcastManager.isRunning else {
            logAppMessage("[Broadcast] Already running.")
            return
        }
        guard activeBackend?.isRunning == true, isServerRunning, !lifecycle.isStopRequested, lifecycle.runningServerId == configServer.id else {
            logAppMessage("[Broadcast] Not starting – server is not running (or not the active running server).")
            return
        }

        let delay = broadcastStartupDelaySeconds
        logAppMessage("[Broadcast] Queued Broadcaster start in \(Int(delay))s for \(configServer.displayName).")
        let serverCopy = configServer
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self else { return }
            guard self.activeBackend?.isRunning == true,
                  self.isServerRunning,
                  !self.lifecycle.isStopRequested,
                  self.lifecycle.runningServerId == serverCopy.id,
                  self.lifecycle.initiatingFirstRunServerId != serverCopy.id else { return }
            self.startBroadcastNow(for: serverCopy)
        }
    }

    private func startBroadcastNow(for configServer: ConfigServer) {
        guard activeBackend?.isRunning == true,
              isServerRunning,
              !lifecycle.isStopRequested,
              lifecycle.runningServerId == configServer.id else {
            logAppMessage("[Broadcast] Not starting – server is not running (or not the active running server).")
            return
        }
        if lifecycle.initiatingFirstRunServerId == configServer.id {
            logAppMessage("[Broadcast] Skipping Broadcaster start during Initiate for \(configServer.displayName).")
            return
        }
        guard configServer.xboxBroadcastEnabled else { return }
        guard !broadcastManager.isRunning else {
            logAppMessage("[Broadcast] Already running.")
            return
        }
        guard let jarPath = configManager.config.xboxBroadcastJarPath?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !jarPath.isEmpty else {
            logAppMessage("[Broadcast] Not starting – MCXboxBroadcast JAR path not configured.")
            return
        }
        guard let configDir = syncBroadcastConfig(for: configServer) else { return }
        let javaPath = configManager.config.javaPath
        do {
            try broadcastManager.startBroadcast(javaPath: javaPath, jarPath: jarPath, workingDirectory: configDir)
            isXboxBroadcastRunning = true
            logAppMessage("[Broadcast] Starting Broadcaster for \(configServer.displayName).")
        } catch let error as XboxBroadcastProcessManager.BroadcastError {
            switch error {
            case .alreadyRunning: logAppMessage("[Broadcast] Already running.")
            case .failedToStart(let underlying):
                logAppMessage("[Broadcast] Failed to start Broadcaster: \(underlying.localizedDescription)")
                showError(title: "XboxBroadcast Failed", message: underlying.localizedDescription)
            }
        } catch {
            logAppMessage("[Broadcast] Failed to start Broadcaster: \(error.localizedDescription)")
            showError(title: "XboxBroadcast Failed", message: error.localizedDescription)
        }
    }

    func startBedrockConnectIfNeeded() {
        guard configManager.config.bedrockConnectAutoStartEnabled else {
            logAppMessage("[BedrockConnect] Auto-start is disabled — skipping automatic launch.")
            return
        }
        guard isBedrockConnectJarInstalled else {
            logAppMessage("[BedrockConnect] Not starting — BedrockConnect JAR not configured.")
            return
        }
        guard !bedrockConnectManager.isRunning else {
            logAppMessage("[BedrockConnect] Already running.")
            return
        }
        let delay = broadcastStartupDelaySeconds
        logAppMessage("[BedrockConnect] Queued auto-start in \(Int(delay))s.")
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, self.isServerRunning, !self.lifecycle.isStopRequested else { return }
            self.startBedrockConnect()
        }
    }
}

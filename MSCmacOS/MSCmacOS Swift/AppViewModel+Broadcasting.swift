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

        // When playit.gg is enabled and a Bedrock tunnel address is stored, use it so
        // Xbox Broadcast transfers friends to the correct external address.
        if server.playitEnabled,
           let playitAddr = configManager.config.playitBedrockAddress?
               .trimmingCharacters(in: .whitespacesAndNewlines),
           !playitAddr.isEmpty {
            // Strip port if present — host only
            return playitAddr.components(separatedBy: ":").first ?? playitAddr
        }

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

    /// The port the broadcast transfers joining players to. When playit is enabled this is the
    /// playit Bedrock *tunnel* port (e.g. 64009), not the local BDS port — matching the host
    /// returned by previewBroadcastHost. Falls back to the local port when playit is off.
    /// Used by both the broadcast start path and the Edit Server "Transfers to" preview.
    func broadcastPortForConfig(for server: ConfigServer) -> Int? {
        if let override = server.xboxBroadcastPortOverride { return override }
        // Use playit Bedrock tunnel port when active
        if server.playitEnabled,
           let playitAddr = configManager.config.playitBedrockAddress?
               .trimmingCharacters(in: .whitespacesAndNewlines),
           let portStr = playitAddr.components(separatedBy: ":").last,
           let port = Int(portStr) {
            return port
        }
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

    // MARK: - Reset Xbox sign-in

    /// Signs out of the current Xbox broadcast account by stopping the broadcaster
    /// and deleting its cached auth token (`cache/cache.json`). The next time the
    /// server starts, MCXboxBroadcast will prompt for a fresh device-code sign-in —
    /// used to switch to a different alt account. Leaves the Alt Account Profile
    /// notes (email/gamertag/photo) untouched so the user can update them after.
    func resetXboxBroadcastAuth(for server: ConfigServer) {
        // Stop any running broadcaster so the cache isn't held open.
        stopBroadcastIfRunning()
        stopBedrockBroadcastIfRunning()

        let dataDir: URL = server.isBedrock
            ? BedrockBroadcastManager.dataDirectoryURL(for: server)
            : broadcastRootDirectoryURL.appendingPathComponent(
                BroadcastConfigManager.folderName(for: server), isDirectory: true)

        let cacheDir = dataDir.appendingPathComponent("cache", isDirectory: true)
        let fm = FileManager.default
        var removed = false
        if fm.fileExists(atPath: cacheDir.path) {
            try? fm.removeItem(at: cacheDir)
            removed = true
        }

        // Drop the transient captured gamertag so stale info doesn't linger.
        initiationBroadcastGamertag = nil

        logAppMessage(removed
            ? "[Broadcast] Reset Xbox sign-in for \(server.displayName). You'll sign in again the next time this server starts."
            : "[Broadcast] No saved Xbox sign-in found for \(server.displayName) — nothing to reset.")
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

    func openBroadcastConfigFolder(for configServer: ConfigServer) {
        guard let dir = ensureBroadcastConfigDirectory(for: configServer) else { return }
        openInFinder(dir, description: "broadcast config folder for \(configServer.displayName)")
    }

    // MARK: - Bedrock broadcast

    func startBedrockBroadcast() {
        guard !bedrockBroadcastManager.isRunning else {
            logAppMessage("[BroadcastBDS] Already running.")
            return
        }
        guard let cfgServer = configManager.config.servers.first(where: { $0.id == lifecycle.runningServerId })
                              ?? selectedServer.flatMap({ configServer(for: $0) }) else {
            showError(title: "Xbox Broadcast", message: "No Bedrock server config found.")
            return
        }
        // Use broadcastPortForConfig (not effectiveBedrockPort) so that when playit is
        // enabled the transfer target uses the playit Bedrock *tunnel* port, matching the
        // playit host returned by previewBroadcastHost. Using the local port here sends
        // external clients to playit-host:local-port, which is a dead endpoint.
        let port = broadcastPortForConfig(for: cfgServer)
        let ip = previewBroadcastHost(for: cfgServer, mode: cfgServer.xboxBroadcastIPMode)
        let javaPath = configManager.config.javaPath
        guard let jarPath = configManager.config.xboxBroadcastJarPath,
              !jarPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logAppMessage("[BroadcastBDS] JAR not configured — download it in Edit Server → Broadcast.")
            showError(title: "Xbox Broadcast", message: "MCXboxBroadcast JAR not configured. Download it in Edit Server → Broadcast.")
            return
        }
        logAppMessage("[BroadcastBDS] Writing config: clients will be transferred to \(ip):\(port.map(String.init) ?? "19132") for \(cfgServer.displayName).")
        do {
            try bedrockBroadcastManager.start(for: cfgServer, ip: ip, port: port, javaPath: javaPath, jarPath: jarPath)
            isBedrockBroadcastRunning = true
            logAppMessage("[BroadcastBDS] Manually started MCXboxBroadcast.")
        } catch BedrockBroadcastManager.BroadcastError.alreadyRunning {
            logAppMessage("[BroadcastBDS] Already running.")
        } catch BedrockBroadcastManager.BroadcastError.failedToStart(let reason) {
            logAppMessage("[BroadcastBDS] Failed to start: \(reason)")
            showError(title: "Xbox Broadcast Failed", message: reason)
        } catch {
            logAppMessage("[BroadcastBDS] Failed to start: \(error.localizedDescription)")
            showError(title: "Xbox Broadcast Failed", message: error.localizedDescription)
        }
    }

    func stopBedrockBroadcast() {
        guard bedrockBroadcastManager.isRunning else { return }
        bedrockBroadcastManager.stop()
        isBedrockBroadcastRunning = false
        logAppMessage("[BroadcastBDS] Manually stopped MCXboxBroadcast.")
    }

    func stopBedrockBroadcastIfRunning() {
        guard bedrockBroadcastManager.isRunning else { return }
        bedrockBroadcastManager.stop()
        isBedrockBroadcastRunning = false
        logAppMessage("[BroadcastBDS] Stopped MCXboxBroadcast.")
    }

    /// Downloads (or updates) the MCXboxBroadcast JAR — same JAR used for Java servers.
    func downloadBedrockBroadcastJar() {
        downloadOrUpdateXboxBroadcastJar()
    }

    func startBedrockBroadcastIfNeeded(for configServer: ConfigServer) {
        if lifecycle.initiatingFirstRunServerId == configServer.id {
            logAppMessage("[BroadcastBDS] Skipping broadcast start during Initiate.")
            return
        }
        guard configManager.config.xboxBroadcastAutoStartEnabled else {
            logAppMessage("[BroadcastBDS] Auto-start is disabled — skipping.")
            return
        }
        guard configServer.xboxBroadcastEnabled else { return }
        guard !bedrockBroadcastManager.isRunning else {
            logAppMessage("[BroadcastBDS] Already running.")
            return
        }
        guard activeBackend?.isRunning == true, isServerRunning, !lifecycle.isStopRequested else {
            logAppMessage("[BroadcastBDS] Not starting — server is not running.")
            return
        }

        let delay = 15.0
        let serverCopy = configServer
        let javaPath = configManager.config.javaPath
        let jarPath = configManager.config.xboxBroadcastJarPath ?? ""
        logAppMessage("[BroadcastBDS] Queued broadcast start in \(Int(delay))s for \(configServer.displayName).")
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self else { return }
            guard self.activeBackend?.isRunning == true,
                  self.isServerRunning,
                  !self.lifecycle.isStopRequested,
                  self.lifecycle.runningServerId == serverCopy.id,
                  self.lifecycle.initiatingFirstRunServerId != serverCopy.id else { return }
            let port = self.broadcastPortForConfig(for: serverCopy)
            let ip = self.previewBroadcastHost(for: serverCopy, mode: serverCopy.xboxBroadcastIPMode)
            self.logAppMessage("[BroadcastBDS] Writing config: clients will be transferred to \(ip):\(port.map(String.init) ?? "19132") for \(serverCopy.displayName).")
            do {
                try self.bedrockBroadcastManager.start(for: serverCopy, ip: ip, port: port, javaPath: javaPath, jarPath: jarPath)
                await MainActor.run { self.isBedrockBroadcastRunning = true }
                self.logAppMessage("[BroadcastBDS] Started MCXboxBroadcast for \(serverCopy.displayName).")
            } catch BedrockBroadcastManager.BroadcastError.alreadyRunning {
                self.logAppMessage("[BroadcastBDS] Already running.")
            } catch BedrockBroadcastManager.BroadcastError.failedToStart(let reason) {
                self.logAppMessage("[BroadcastBDS] Failed to start: \(reason)")
            } catch {
                self.logAppMessage("[BroadcastBDS] Failed: \(error.localizedDescription)")
            }
        }
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

    // MARK: - Post-sign-in gamertag save offer

    /// After the broadcaster authenticates (gamertag parsed from its log), offer to
    /// save that gamertag to the running server's broadcast profile — so the user
    /// has a record of which alt/dummy account they used. Only the gamertag is
    /// available; email/password are entered on Microsoft's page and never seen here.
    func maybeOfferSaveBroadcastGamertag(_ gamertag: String) {
        // Don't interrupt first-time initiation — the completion sheet already
        // surfaces the gamertag, and a modal here would race the auto-stop.
        guard !lifecycle.isInitiationPass2 else { return }

        // Identify the server the running broadcaster belongs to.
        let serverId = lifecycle.runningServerId
            ?? selectedServer.flatMap { configServer(for: $0)?.id }
        guard let sid = serverId,
              let cfg = configManager.config.servers.first(where: { $0.id == sid }) else { return }

        // Skip if already saved (matching), already asking, or declined this session.
        let existing = cfg.xboxBroadcastAltGamertag?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard existing.caseInsensitiveCompare(gamertag) != .orderedSame else { return }
        guard pendingBroadcastGamertagSave == nil else { return }
        guard !broadcastGamertagSaveDeclinedServerIds.contains(sid) else { return }

        pendingBroadcastGamertagSave = BroadcastGamertagSavePrompt(serverId: sid, gamertag: gamertag)
    }

    /// Look up a config server by its id (used by the save sheet).
    func configServer(id: String) -> ConfigServer? {
        configManager.config.servers.first(where: { $0.id == id })
    }

    /// Persist the gamertag from a save prompt into the server's broadcast profile.
    func saveBroadcastGamertagFromPrompt(_ prompt: BroadcastGamertagSavePrompt) {
        if let idx = configManager.config.servers.firstIndex(where: { $0.id == prompt.serverId }) {
            configManager.config.servers[idx].xboxBroadcastAltGamertag = prompt.gamertag
            configManager.save()
            logAppMessage("[Broadcast] Saved gamertag \(prompt.gamertag) to \(configManager.config.servers[idx].displayName)'s broadcast profile.")
        }
        pendingBroadcastGamertagSave = nil
    }

}

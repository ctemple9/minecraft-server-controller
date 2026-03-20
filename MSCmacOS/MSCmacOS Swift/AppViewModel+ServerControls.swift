//
//  AppViewModel+ServerControls.swift
//  MinecraftServerController
//

import Foundation

extension AppViewModel {

    // MARK: - Start / Stop

    var startActionTitleForSelectedServer: String {
        guard let server = selectedServer,
              let cfg = configServer(for: server) else { return "Start" }
        return isFirstRun(for: cfg) ? "Initiate" : "Start"
    }

    var startButtonTitleForSelectedServer: String {
        guard let server = selectedServer,
              configServer(for: server) != nil else { return "Start" }
        return "Start"
    }

    private func isFirstRun(for server: ConfigServer) -> Bool {
        if server.hasEverStarted { return false }
        if hasFirstRunArtifactsOnDisk(serverDir: server.serverDir) { return false }
        return true
    }

    private func hasFirstRunArtifactsOnDisk(serverDir: String) -> Bool {
        let fm = FileManager.default
        let base = URL(fileURLWithPath: serverDir, isDirectory: true)
        let logsDir = base.appendingPathComponent("logs", isDirectory: true)
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: logsDir.path, isDirectory: &isDir), isDir.boolValue { return true }
        if fm.fileExists(atPath: logsDir.appendingPathComponent("latest.log").path) { return true }
        for worldName in ["world", "world_nether", "world_the_end"] {
            let worldURL = base.appendingPathComponent(worldName, isDirectory: true)
            var d: ObjCBool = false
            if fm.fileExists(atPath: worldURL.path, isDirectory: &d), d.boolValue { return true }
        }
        for dirName in ["cache", "libraries", "versions"] {
            let url = base.appendingPathComponent(dirName, isDirectory: true)
            var d: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &d), d.boolValue { return true }
        }
        let geyserCfg = GeyserConfigManager.configURL(for: serverDir)
        if fm.fileExists(atPath: geyserCfg.path) { return true }
        return false
    }

    func startServer() {
        guard let server = selectedServer else {
            logAppMessage("[App] No server selected.")
            return
        }

        let serverIsBedrock = configServer(for: server)?.isBedrock ?? false
        if !serverIsBedrock && eulaAccepted != true {
            logAppMessage("[App] Cannot start server until EULA is accepted.")
            return
        }

        if activeBackend?.isRunning == true {
            logAppMessage("[App] Server already running.")
            return
        }

        guard let cfgServer = configServer(for: server) else {
            logAppMessage("[App] No config entry for server.")
            return
        }

        let wasFirstRun = isFirstRun(for: cfgServer)

        if cfgServer.isBedrock {
            activeBackend = bedrockBackend
            checkDockerDaemonRunning()
        } else {
            activeBackend = javaBackend
        }

        let appCfg = configManager.config

        do {
            try activeBackend?.start(config: cfgServer, appConfig: appCfg)

            isServerRunning = true
            isMetricsPaused = false
            logAppMessage("[App] Starting REAL server: \(server.name)")
            refreshHealthCardsForSelectedServer()

            if !wasFirstRun {
                fireNotificationIfEnabled(event: .serverStarted,
                                          serverName: cfgServer.displayName,
                                          serverId: cfgServer.id)
            }

            onlinePlayers = []
            playerSessionHistory.removeAll()
            latestTps1m = nil
            latestTps5m = nil
            latestTps15m = nil
            tpsHistory1m.removeAll()
            playerCountHistory.removeAll()
            clearBedrockPerformanceMetrics()

            lifecycle.resetForNewRun(serverId: cfgServer.id)

            lifecycle.startMetricsTimer(interval: 5) { [weak self] in
                guard let self else { return }
                guard self.activeBackend?.isRunning == true else {
                    self.lifecycle.stopMetricsTimer()
                    return
                }
                guard !self.isMetricsPaused else { return }
                self.updateResourceUsageMetrics()
                guard self.lifecycle.serverReadyForAutoMetrics else { return }
                self.refreshPlayersAndTps()
            }

            // First-run / Initiate UX
            if wasFirstRun {
                markHasEverStarted(serverId: cfgServer.id)
                lifecycle.beginInitiateRun(serverId: cfgServer.id)

                let fm = FileManager.default
                let geyserCfgURL = GeyserConfigManager.configURL(for: cfgServer.serverDir)
                let geyserConfigExists = fm.fileExists(atPath: geyserCfgURL.path)
                let geyserInstalled = GeyserConfigManager().isGeyserInstalled(
                    serverPath: URL(fileURLWithPath: cfgServer.serverDir, isDirectory: true)
                )

                var message: String
                if cfgServer.isBedrock {
                    message = "Initiation complete \n\n"
                    message += "On first run, Bedrock generates its initial files and default settings. When the console shows \"Server started\", the app will automatically stop the server so you can safely review and adjust settings before real play.\n\n"
                    message += "Next steps:\n"
                    message += "• Open Server Settings and review/save your Bedrock settings.\n"
                    message += "• Check Bedrock-specific files like server.properties, allowlist.json, and permissions.json if you plan to customise them.\n"
                    message += "• Start the server again when you're ready.\n\n"
                    message += "If you use Bedrock Connect or Xbox Broadcast, confirm your host and Bedrock port after saving settings."

                    firstStartAlertTitle = "Bedrock First Start"
                } else {
                    message = "Initiation complete \n\n"
                    message += "On first run, Paper generates important config files (server.properties, eula.txt, plugin configs, etc.). When the console shows \"Done\", the app will automatically stop the server so you can safely edit settings.\n\n"
                    message += "Next steps:\n"
                    message += "• Open Server Settings and review/save your settings.\n"
                    if geyserInstalled && !geyserConfigExists {
                        message += "• Geyser is now installed. Please update your port settings and click save. If you already changed it earlier, save the settings again to apply them.\n"
                    } else if geyserInstalled {
                        message += "• If you use Geyser (Bedrock), your Bedrock port is managed in Server Settings. If you decide to add it later, you must save your port information after the first run\n"
                    }
                    message += "• Start the server again when you're ready.\n\n"
                    message += "If you use Xbox Broadcast, it stays synced with the Bedrock port where applicable."

                    firstStartAlertTitle = "First Start"
                }

                firstStartAlertMessage = message
            }

            if !wasFirstRun {
                startBroadcastIfNeeded(for: cfgServer)
                startBedrockConnectIfNeeded()
                if cfgServer.autoBackupEnabled {
                    startAutoBackupTimer(for: cfgServer)
                }
            } else {
                logAppMessage("[Broadcast] Skipping Broadcaster start during Initiate.")
            }

        } catch let error as ServerBackendError {
            switch error {
            case .alreadyRunning:
                logAppMessage("[App] Server already running.")
            case .failedToStart(let underlying):
                logAppMessage("[App] Failed to start server: \(underlying.localizedDescription)")
                showError(title: "Server Failed to Start", message: underlying.localizedDescription)
            }
            activeBackend = nil
        } catch {
            logAppMessage("[App] Failed to start server: \(error.localizedDescription)")
            showError(title: "Server Failed to Start", message: error.localizedDescription)
            activeBackend = nil
        }
    }

    func stopServer() {
        lifecycle.stopMetricsTimer()
        stopAutoBackupTimer()
        isMetricsPaused = false
        lifecycle.isStopRequested = true
        stopBroadcastIfRunning()
        stopBedrockConnectIfRunning()

        guard activeBackend?.isRunning == true else {
            logAppMessage("[App] Server is not running.")
            return
        }

        if let server = selectedServer,
           let cfgServer = configServer(for: server),
           cfgServer.autoBackupEnabled {
            logAppMessage("[Backup] Triggering stop-time auto backup for \(cfgServer.displayName).")
            createAutoBackupForServer(cfgServer)
        }

        if activeBackend?.stop() == true {
            logAppMessage("[App] Sent 'stop' to server.")
        } else {
            let msg = activeBackend?.lastCommandError ?? "Failed to send 'stop' to server."
            logAppMessage("[App] Failed to send 'stop': \(msg)")
            showError(title: "Stop Failed", message: msg)
        }

        refreshHealthCardsForSelectedServer()
    }

    func toggleMetricsMonitoring() {
        guard isServerRunning else { return }
        isMetricsPaused.toggle()
        if isMetricsPaused {
            logAppMessage("[App] Paused auto monitoring (TPS / players / CPU / RAM).")
        } else {
            logAppMessage("[App] Resumed auto monitoring (TPS / players / CPU / RAM).")
        }
    }

    private func markHasEverStarted(serverId: String) {
        guard let idx = configManager.config.servers.firstIndex(where: { $0.id == serverId }) else { return }
        if !configManager.config.servers[idx].hasEverStarted {
            configManager.config.servers[idx].hasEverStarted = true
            configManager.save()
        }
    }

    private func markHasShownFirstStartPopup(serverId: String) {
        guard let idx = configManager.config.servers.firstIndex(where: { $0.id == serverId }) else { return }
        if !configManager.config.servers[idx].hasShownFirstStartPopup {
            configManager.config.servers[idx].hasShownFirstStartPopup = true
            configManager.save()
        }
    }

    // MARK: - Commands

    func sendCommand() {
        let trimmed = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sendQuickCommand(trimmed)
        commandText = ""
    }

    func sendQuickCommand(_ cmd: String) {
        sendCommand(cmd, origin: .user)
    }

    private enum CommandOrigin {
        case user, auto
    }

    private func sendCommand(_ cmd: String, origin: CommandOrigin) {
        guard activeBackend?.isRunning == true else {
            logAppMessage("[App] Server is not running.")
            return
        }
        guard activeBackend?.sendCommand(cmd) == true else {
            let msg = activeBackend?.lastCommandError ?? "Failed to send command to server."
            logAppMessage("[App] Failed to send command: \(msg)")
            showError(title: "Command Failed", message: msg)
            return
        }
        guard let server = selectedServer else { return }
        switch origin {
        case .user:
            logAppMessage("[You → \(server.name)] \(cmd)")
        case .auto:
            console.markAutoCommand()
            logAppMessage("[Auto → \(server.name)] \(cmd)")
        }
    }

    func refreshPlayersAndTps() {
        guard activeBackend?.isRunning == true else { return }
        guard let server = selectedServer,
              let cfgServer = configServer(for: server) else { return }
        guard cfgServer.serverType == .java else { return }
        sendCommand("list", origin: .auto)
        sendCommand("tps", origin: .auto)
    }

    // MARK: - Quick commands

    func applyDifficulty(_ difficulty: ServerDifficulty) {
        guard activeBackend?.isRunning == true else { return }
        sendQuickCommand("difficulty \(difficulty.rawValue)")
    }

    func applyGamemode(_ gamemode: ServerGamemode) {
        guard activeBackend?.isRunning == true else { return }
        sendQuickCommand("defaultgamemode \(gamemode.rawValue)")
    }

    func setWhitelistEnabled(_ enabled: Bool) {
        guard activeBackend?.isRunning == true else { return }
        sendQuickCommand(enabled ? "whitelist on" : "whitelist off")
    }

    func runSaveAll() {
        guard activeBackend?.isRunning == true else { return }
        sendQuickCommand("save-all")
    }

    func runReload() {
        guard activeBackend?.isRunning == true else { return }
        sendQuickCommand("reload")
    }

    func setTimeOfDay(_ preset: TimeOfDayPreset) {
        guard activeBackend?.isRunning == true else { return }
        sendQuickCommand("time set \(preset.rawValue)")
    }

    func setWeather(_ preset: WeatherPreset) {
        guard activeBackend?.isRunning == true else { return }
        sendQuickCommand("weather \(preset.rawValue)")
    }

    func kickPlayer(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sendQuickCommand("kick \(trimmed)")
    }

    func opPlayer(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let server = selectedServer,
           let cfg = configServer(for: server),
           cfg.isBedrock {
            guard let xuid = bedrockXUID(forPlayerNamed: trimmed) else {
                showError(title: "Operator Error",
                          message: "MSC needs this player's XUID before it can edit permissions.json. Have them join once, or add them to the allowlist after they have joined.")
                return
            }
            do {
                try BedrockPropertiesManager.setPermission(xuid: xuid, level: .operator_, serverDir: cfg.serverDir)
                logAppMessage("[Permissions] Promoted \(trimmed) to operator in \(cfg.displayName).")
            } catch {
                logAppMessage("[Permissions] Failed to promote \(trimmed): \(error.localizedDescription)")
                showError(title: "Operator Error", message: error.localizedDescription)
            }
            return
        }
        sendQuickCommand("op \(trimmed)")
    }

    func deopPlayer(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let server = selectedServer,
           let cfg = configServer(for: server),
           cfg.isBedrock {
            guard let xuid = bedrockXUID(forPlayerNamed: trimmed) else {
                showError(title: "Operator Error",
                          message: "MSC could not find an XUID for this player, so it cannot remove the Bedrock operator entry.")
                return
            }
            do {
                try BedrockPropertiesManager.removePermission(xuid: xuid, serverDir: cfg.serverDir)
                logAppMessage("[Permissions] Removed operator permission for \(trimmed) in \(cfg.displayName).")
            } catch {
                logAppMessage("[Permissions] Failed to remove operator permission for \(trimmed): \(error.localizedDescription)")
                showError(title: "Operator Error", message: error.localizedDescription)
            }
            return
        }
        sendQuickCommand("deop \(trimmed)")
    }

    func setGamemode(_ gamemode: String, forPlayer name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sendQuickCommand("gamemode \(gamemode) \(trimmed)")
    }

    func messagePlayer(named name: String, message: String) {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }
        sendQuickCommand("tell \(name) \(trimmedMessage)")
    }

    // MARK: - Bedrock player management

    func bedrockXUID(forPlayerNamed name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let online = onlinePlayers.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }),
           let xuid = online.xuid, !xuid.isEmpty { return xuid }
        if let entry = bedrockAllowlist.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }),
           let xuid = entry.xuid, !xuid.isEmpty { return xuid }
        if let server = selectedServer,
           let cfg = configServer(for: server),
           cfg.isBedrock {
            let diskAllowlist = BedrockPropertiesManager.readAllowlist(serverDir: cfg.serverDir)
            if let entry = diskAllowlist.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }),
               let xuid = entry.xuid, !xuid.isEmpty { return xuid }
        }
        return nil
    }

    func isBedrockOperator(named name: String) -> Bool {
        guard let xuid = bedrockXUID(forPlayerNamed: name),
              let server = selectedServer,
              let cfg = configServer(for: server),
              cfg.isBedrock else { return false }
        return BedrockPropertiesManager
            .readPermissions(serverDir: cfg.serverDir)
            .contains { $0.xuid == xuid && $0.permission == .operator_ }
    }

    func loadBedrockAllowlistIfNeeded() {
        guard let server = selectedServer,
              let cfg = configServer(for: server),
              cfg.isBedrock else {
            bedrockAllowlist = []
            return
        }
        bedrockAllowlist = BedrockPropertiesManager.readAllowlist(serverDir: cfg.serverDir)
    }

    func addToBedrockAllowlist(gamertag: String) {
        guard let server = selectedServer,
              let cfg = configServer(for: server),
              cfg.isBedrock else { return }
        let trimmed = gamertag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try BedrockPropertiesManager.addToAllowlist(name: trimmed, xuid: bedrockXUID(forPlayerNamed: trimmed), serverDir: cfg.serverDir)
            bedrockAllowlist = BedrockPropertiesManager.readAllowlist(serverDir: cfg.serverDir)
            logAppMessage("[Allowlist] Added \(trimmed) to \(cfg.displayName).")
            if activeBackend?.isRunning == true { sendQuickCommand("allowlist reload") }
        } catch {
            logAppMessage("[Allowlist] Failed to add \(trimmed): \(error.localizedDescription)")
            showError(title: "Allowlist Error", message: error.localizedDescription)
        }
    }

    func removeFromBedrockAllowlist(gamertag: String) {
        guard let server = selectedServer,
              let cfg = configServer(for: server),
              cfg.isBedrock else { return }
        let trimmed = gamertag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try BedrockPropertiesManager.removeFromAllowlist(name: trimmed, serverDir: cfg.serverDir)
            bedrockAllowlist = BedrockPropertiesManager.readAllowlist(serverDir: cfg.serverDir)
            logAppMessage("[Allowlist] Removed \(trimmed) from \(cfg.displayName).")
            if activeBackend?.isRunning == true { sendQuickCommand("allowlist reload") }
        } catch {
            logAppMessage("[Allowlist] Failed to remove \(trimmed): \(error.localizedDescription)")
            showError(title: "Allowlist Error", message: error.localizedDescription)
        }
    }

    // MARK: - Quick commands model

    func quickCommandsModelForSelectedServer() -> (QuickCommandsModel, ConfigServer)? {
        guard let server = selectedServer,
              let cfg = configServer(for: server) else { return nil }
        let dict = ServerPropertiesManager.readProperties(serverDir: cfg.serverDir)
        let propsModel = ServerPropertiesModel(from: dict, fallbackMotd: cfg.displayName)
        let whitelistRaw = dict["white-list"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let whitelist = (whitelistRaw == "true")
        let model = QuickCommandsModel(difficulty: propsModel.difficulty, gamemode: propsModel.gamemode, whitelistEnabled: whitelist)
        return (model, cfg)
    }

    // MARK: - Server notes

    var selectedServerNotes: String {
        guard let server = selectedServer,
              let cfg = configServer(for: server) else { return "" }
        return cfg.notes
    }

    func saveSelectedServerNotes(_ notes: String) {
        guard let server = selectedServer,
              let idx = configManager.config.servers.firstIndex(where: { $0.id == server.id })
        else { return }
        configManager.config.servers[idx].notes = notes
        configManager.save()
    }

    // MARK: - Uptime tracking

    var serverUptime: TimeInterval? {
        guard let start = serverStartTime, isServerRunning else { return nil }
        return Date().timeIntervalSince(start)
    }

    func updateUptimeDisplay() {
        guard let uptime = serverUptime else {
            serverUptimeDisplay = nil
            return
        }
        let hours = Int(uptime) / 3600
        let minutes = Int(uptime) / 60 % 60
        if hours >= 48 {
            let days = hours / 24
            serverUptimeDisplay = "\(days)d \(hours % 24)h"
        } else if hours > 0 {
            serverUptimeDisplay = "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            serverUptimeDisplay = "\(minutes)m"
        } else {
            serverUptimeDisplay = "Just started"
        }
    }

    // MARK: - Auto backup timer

    func startAutoBackupTimer(for configServer: ConfigServer) {
        stopAutoBackupTimer()
        logAppMessage("[Backup] Auto backup timer started (every 30 min) for \(configServer.displayName).")
        let serverCopy = configServer
        autoBackupTimer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.activeBackend?.isRunning == true, self.isServerRunning else {
                    self.stopAutoBackupTimer()
                    return
                }
                self.logAppMessage("[Backup] Auto backup timer fired for \(serverCopy.displayName).")
                self.createAutoBackupForServer(serverCopy)
            }
        }
    }

    func stopAutoBackupTimer() {
        autoBackupTimer?.invalidate()
        autoBackupTimer = nil
    }

    func setAutoBackupEnabled(_ enabled: Bool, for serverId: String) {
        guard let idx = configManager.config.servers.firstIndex(where: { $0.id == serverId }) else { return }
        configManager.config.servers[idx].autoBackupEnabled = enabled
        configManager.save()
        logAppMessage("[Backup] Auto backup \(enabled ? "enabled" : "disabled") for \(configManager.config.servers[idx].displayName).")
        guard isServerRunning, lifecycle.runningServerId == serverId else { return }
        let cfgServer = configManager.config.servers[idx]
        if enabled {
            startAutoBackupTimer(for: cfgServer)
        } else {
            stopAutoBackupTimer()
        }
    }
}

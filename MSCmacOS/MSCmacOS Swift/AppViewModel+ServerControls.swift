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
        // Install-step flavors (NeoForge) pre-create libraries/ etc. at *creation*
        // time, so those can't be used as "already ran" signals — fall back to
        // logs/ and world/ only. Otherwise a fresh NeoForge server would skip the
        // first-run setup (auto-stop + settings sheet).
        let ignoreLibraryArtifacts = server.javaFlavor.provisioningKind == .installStep
        if hasFirstRunArtifactsOnDisk(serverDir: server.serverDir,
                                      ignoreLibraryArtifacts: ignoreLibraryArtifacts) { return false }
        return true
    }

    private func hasFirstRunArtifactsOnDisk(serverDir: String, ignoreLibraryArtifacts: Bool = false) -> Bool {
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
        if !ignoreLibraryArtifacts {
            for dirName in ["cache", "libraries", "versions"] {
                let url = base.appendingPathComponent(dirName, isDirectory: true)
                var d: ObjCBool = false
                if fm.fileExists(atPath: url.path, isDirectory: &d), d.boolValue { return true }
            }
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
            if configManager.config.useVMBedrockBackend {
                // Native VM appliance — no Docker dependency.
                activeBackend = vmBedrockBackend
            } else {
                activeBackend = bedrockBackend
                checkDockerDaemonRunning()
            }
        } else {
            activeBackend = javaBackend
        }

        let appCfg = configManager.config

        // Java-version preflight: warn clearly if the configured Java is too old for
        // this server's Minecraft version (the usual cause of a silent boot failure).
        // Non-blocking — we still attempt the start.
        if !cfgServer.isBedrock {
            if let warning = JavaRuntimeManager.compatibilityWarning(
                minecraftVersion: cfgServer.minecraftVersion,
                javaPath: appCfg.javaPath
            ) {
                javaCompatibilityWarning = warning
                logAppMessage("[App] ⚠️ Java compatibility: \(warning)")
            } else {
                javaCompatibilityWarning = nil
            }
        }

        do {
            try activeBackend?.start(config: cfgServer, appConfig: appCfg)

            isServerRunning = true
            isMetricsPaused = false
            // Mirror the Bedrock VM console to a rolling logs/latest.log on disk.
            if cfgServer.isBedrock { startBedrockLogFile(serverDir: cfgServer.serverDir) }
            logAppMessage("[App] Starting REAL server: \(server.name)")
            refreshHealthCardsForSelectedServer()
            startResourcePackHostIfNeeded(for: cfgServer)

            // Flow 2: if SVC is installed+enabled and port forwarding is used, ask once
            // whether the user has forwarded UDP 24454. "Yes" is remembered; "No" re-asks next start.
            if !cfgServer.playitEnabled,
               !cfgServer.svcPortForwardingConfirmed,
               VoiceChatConfigManager.isInstalled(serverDir: cfgServer.serverDir) {
                pendingSVCPortForwardingPrompt = SVCPortForwardingAlert(serverId: cfgServer.id)
            }

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
                self.sampleBedrockPlayerActivity()
                guard self.lifecycle.serverReadyForAutoMetrics else { return }
                self.refreshPlayersAndTps()
                self.refreshWorldTime()
                self.refreshFeaturedPlayerHealth()
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
                    message += "If you use Xbox Broadcast, confirm your host and Bedrock port after saving settings."

                    firstStartAlertTitle = "Bedrock First Start"
                } else {
                    let softwareName = cfgServer.javaFlavor.displayName
                    message = "Initiation complete \n\n"
                    message += "On first run, \(softwareName) generates important config files (server.properties, eula.txt, and more). When the console shows \"Done\", the app will automatically stop the server so you can safely edit settings.\n\n"
                    message += "Next steps:\n"
                    message += "• Open Server Settings and review/save your settings.\n"
                    if geyserInstalled && !geyserConfigExists {
                        message += "• Geyser is now installed. Please update your port settings and click save. If you already changed it earlier, save the settings again to apply them.\n"
                    } else if geyserInstalled {
                        message += "• If you use Geyser (Bedrock), your Bedrock port is managed in Server Settings. If you decide to add it later, you must save your port information after the first run\n"
                    }
                    if cfgServer.isModded {
                        message += "• Add your mods to the mods/ folder before starting for real. World-gen mods must be present on the first real start or they won't affect your world.\n"
                    }
                    message += "• Start the server again when you're ready.\n\n"
                    message += "If you use Xbox Broadcast, it stays synced with the Bedrock port where applicable."

                    firstStartAlertTitle = "First Start"
                }

                firstStartAlertMessage = message
            }

            if !wasFirstRun {
                if cfgServer.isBedrock {
                    startBedrockBroadcastIfNeeded(for: cfgServer)
                } else {
                    startBroadcastIfNeeded(for: cfgServer)
                }
                startPlayitIfNeeded(for: cfgServer)
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
        stopBedrockBroadcastIfRunning()
        stopPlayitIfRunning()
        resourcePackHostServer.stop()
        clearLiveWorldTime()

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
        case user, auto, silentAuto
    }

    private func sendCommand(_ cmd: String, origin: CommandOrigin) {
        guard activeBackend?.isRunning == true else {
            logAppMessage("[App] Server is not running.")
            return
        }
        // BDS console does not accept a leading slash — strip it automatically
        // so both hand-typed "/gamemode creative" and palette commands work correctly.
        let finalCmd = (selectedServerIsBedrock && cmd.hasPrefix("/"))
            ? String(cmd.dropFirst()) : cmd
        guard activeBackend?.sendCommand(finalCmd) == true else {
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
        case .silentAuto:
            break
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

    /// Records a player-count sample for a running Bedrock server so the Performance
    /// tab's "Player Activity" chart fills in over time. Bedrock has no auto `list`
    /// poll (its online list is derived from console log parsing), so without a
    /// periodic sample an idle server would show the "Collecting…" placeholder
    /// indefinitely instead of a flat baseline that rises when players join.
    func sampleBedrockPlayerActivity() {
        guard selectedServerIsBedrock else { return }
        appendPlayerCountHistory(onlinePlayers.count)
    }

    /// Polls the running Java server for the in-game day and time-of-day.
    /// Paper 1.21.4+ changed the response format to "Timeline minecraft:X is at Y tick(s)"
    /// and removed `time query daytime`. We now use:
    ///   - `time query gametime` → total ticks → divide by 24000 for day number
    ///   - `time query day`      → daytime ticks (0-23999) in newer Paper
    /// Both old ("The time is X") and new format responses are handled by `parseWorldTime`.
    /// Re-seeding the expectation list each cycle keeps it self-healing.
    func refreshWorldTime() {
        guard activeBackend?.isRunning == true else { return }
        guard let server = selectedServer,
              let cfgServer = configServer(for: server),
              cfgServer.serverType == .java else { return }
        pendingTimeQueryKinds = [.gametime, .daytime]
        sendCommand("time query gametime", origin: .silentAuto)
        sendCommand("time query day", origin: .silentAuto)
    }

    /// Polls the featured player's current health from the running Java server,
    /// so the hearts under the Overview character render update live. Only the one
    /// featured (and online) player is queried, keeping it to a single command.
    func refreshFeaturedPlayerHealth() {
        guard activeBackend?.isRunning == true else { return }
        guard let server = selectedServer,
              let cfg = configServer(for: server),
              cfg.serverType == .java else { return }
        guard let name = featuredPlayerName,
              onlinePlayers.contains(where: { $0.name == name }) else { return }
        sendCommand("data get entity \(name) Health", origin: .auto)
    }

    /// Clears live world-time state (used on stop / server switch) so a stale
    /// clock doesn't linger after the server is no longer running.
    func clearLiveWorldTime() {
        worldTimeOfDayTicks = nil
        worldDayNumber = nil
        worldTimeIsLive = false
        pendingTimeQueryKinds = []
        featuredPlayerHealth = nil
    }

    // MARK: - Quick commands

    func applyDifficulty(_ difficulty: ServerDifficulty) {
        guard activeBackend?.isRunning == true else { return }
        // Same command on both Java and BDS.
        sendQuickCommand("difficulty \(difficulty.rawValue)")
    }

    func applyGamemode(_ gamemode: ServerGamemode) {
        guard activeBackend?.isRunning == true else { return }
        // Both Java and BDS support defaultgamemode.
        sendQuickCommand("defaultgamemode \(gamemode.rawValue)")
    }

    func setWhitelistEnabled(_ enabled: Bool) {
        guard activeBackend?.isRunning == true else { return }
        if selectedServerIsBedrock {
            // BDS renamed the command from whitelist → allowlist.
            sendQuickCommand(enabled ? "allowlist on" : "allowlist off")
        } else {
            sendQuickCommand(enabled ? "whitelist on" : "whitelist off")
        }
    }

    func runSaveAll() {
        guard activeBackend?.isRunning == true else { return }
        if selectedServerIsBedrock {
            // BDS doesn't have save-all; save hold flushes to disk then
            // save resume re-enables auto-saves.
            sendQuickCommand("save hold")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.sendQuickCommand("save resume")
            }
        } else {
            sendQuickCommand("save-all")
        }
    }

    func runReload() {
        guard activeBackend?.isRunning == true else { return }
        // BDS has no reload command (no plugins); only send on Java.
        guard !selectedServerIsBedrock else { return }
        sendQuickCommand("reload")
    }

    func setTimeOfDay(_ preset: TimeOfDayPreset) {
        guard activeBackend?.isRunning == true else { return }
        // Same command on both Java and BDS.
        sendQuickCommand("time set \(preset.rawValue)")
    }

    func setWeather(_ preset: WeatherPreset) {
        guard activeBackend?.isRunning == true else { return }
        // Same command on both Java and BDS.
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

    /// Max-players for the selected server, read from properties. Used by the
    /// Overview Players strip header ("3 / 20 online"). Defaults to 20 if unknown.
    var serverMaxPlayersForOverview: Int {
        guard let server = selectedServer,
              let cfg = configServer(for: server) else { return 20 }
        if cfg.isBedrock {
            return BedrockPropertiesManager.readModel(serverDir: cfg.serverDir).maxPlayers
        }
        let dict = ServerPropertiesManager.readProperties(serverDir: cfg.serverDir)
        return ServerPropertiesModel(from: dict, fallbackMotd: cfg.displayName).maxPlayers
    }

    /// Teleports one online player to another. Same `tp` syntax works on Java and BDS.
    func teleportPlayer(named name: String, toPlayer target: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmedTarget.isEmpty else { return }
        sendQuickCommand("tp \(trimmed) \(trimmedTarget)")
    }

    /// Adds or removes a player from the server allowlist.
    /// Java uses the `whitelist` command; Bedrock edits allowlist.json (and reloads)
    /// through the existing allowlist helpers so the on-disk file stays in sync.
    func whitelistPlayer(named name: String, add: Bool) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if selectedServerIsBedrock {
            if add {
                addToBedrockAllowlist(gamertag: trimmed)
            } else {
                removeFromBedrockAllowlist(gamertag: trimmed)
            }
        } else {
            sendQuickCommand(add ? "whitelist add \(trimmed)" : "whitelist remove \(trimmed)")
        }
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
        let intervalMin = configServer.autoBackupIntervalMinutes
        let intervalDisplay: String
        if intervalMin >= 60 {
            let h = intervalMin / 60
            let m = intervalMin % 60
            intervalDisplay = m > 0 ? "\(h)h \(m)m" : "\(h)h"
        } else {
            intervalDisplay = "\(intervalMin)m"
        }
        logAppMessage("[Backup] Auto backup timer started (every \(intervalDisplay)) for \(configServer.displayName).")
        let serverCopy = configServer
        autoBackupTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(intervalMin) * 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.activeBackend?.isRunning == true, self.isServerRunning else {
                    self.stopAutoBackupTimer()
                    return
                }
                guard !self.onlinePlayers.isEmpty else {
                    self.logAppMessage("[Backup] Auto backup skipped — no players online for \(serverCopy.displayName).")
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

    func setAutoBackupInterval(_ minutes: Int, for serverId: String) {
        guard let idx = configManager.config.servers.firstIndex(where: { $0.id == serverId }) else { return }
        configManager.config.servers[idx].autoBackupIntervalMinutes = minutes
        configManager.save()
        logAppMessage("[Backup] Auto backup interval set to \(minutes) min for \(configManager.config.servers[idx].displayName).")
        guard isServerRunning, lifecycle.runningServerId == serverId,
              configManager.config.servers[idx].autoBackupEnabled else { return }
        startAutoBackupTimer(for: configManager.config.servers[idx])
    }

    func setAutoBackupMaxCount(_ count: Int, for serverId: String) {
        guard let idx = configManager.config.servers.firstIndex(where: { $0.id == serverId }) else { return }
        configManager.config.servers[idx].autoBackupMaxCount = count
        configManager.save()
        logAppMessage("[Backup] Auto backup max count set to \(count) for \(configManager.config.servers[idx].displayName).")
    }
}

// MARK: - First-Time Initiation Orchestration (two-pass)

extension AppViewModel {

    /// Snapshot of initiation lifecycle flags, captured in the termination handler
    /// BEFORE `resetAfterTermination()` wipes them.
    struct InitiationTerminationContext {
        var pass1JustEnded: Bool
        var pass1ServerId: String?
        var pass2JustEnded: Bool
        var pass2ServerId: String?
    }

    func captureInitiationTerminationContext() -> InitiationTerminationContext {
        InitiationTerminationContext(
            pass1JustEnded: lifecycle.initiatingFirstRunServerId != nil && lifecycle.hasIssuedAutoStopForInitiate,
            pass1ServerId: lifecycle.initiatingFirstRunServerId,
            pass2JustEnded: lifecycle.isInitiationPass2,
            pass2ServerId: lifecycle.initiationPass2ServerId
        )
    }

    /// Called at the very end of a server termination. Decides whether pass 1 was
    /// the config-generation run (→ launch pass 2 or show the sheet), or whether
    /// pass 2 (transport bring-up) just finished (→ show the completion sheet).
    func routeInitiationAfterTermination(_ ctx: InitiationTerminationContext) {
        if ctx.pass2JustEnded, let sid = ctx.pass2ServerId,
           let cfg = configManager.config.servers.first(where: { $0.id == sid }) {
            presentInitiationCompleteSheet(for: cfg)
            return
        }
        if ctx.pass1JustEnded, let sid = ctx.pass1ServerId,
           let cfg = configManager.config.servers.first(where: { $0.id == sid }) {
            if initiationNeedsPass2(for: cfg) {
                beginInitiationProgress(for: cfg)
                logAppMessage("[App] Initiation pass 1 complete. Bringing up connections in 5s…")
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                    self?.startInitiationPass2(for: cfg)
                }
            } else {
                presentInitiationCompleteSheet(for: cfg)
            }
        }
    }

    /// True when the server has a transport (playit or Xbox broadcast) worth
    /// bringing up on a second pass before showing connection info.
    func initiationNeedsPass2(for cfg: ConfigServer) -> Bool {
        let broadcastOn = configManager.config.xboxBroadcastAutoStartEnabled && cfg.xboxBroadcastEnabled
        return cfg.playitEnabled || broadcastOn
    }

    /// Show the non-modal progress overlay and arm per-transport waiting state.
    private func beginInitiationProgress(for cfg: ConfigServer) {
        let broadcastOn = configManager.config.xboxBroadcastAutoStartEnabled && cfg.xboxBroadcastEnabled
        initiationPlayitStatus = cfg.playitEnabled ? .waiting : .notApplicable
        initiationBroadcastStatus = broadcastOn ? .waiting : .notApplicable
        initiationBroadcastGamertag = nil
        isShowingInitiationProgress = true
    }

    /// Start the server again — this time bringing up playit + Xbox broadcast —
    /// and arm the pass-2 completion watchers + timeouts.
    func startInitiationPass2(for cfg: ConfigServer) {
        guard let sel = selectedServer, configServer(for: sel)?.id == cfg.id else {
            logAppMessage("[App] Initiation pass 2 skipped — server no longer selected.")
            isShowingInitiationProgress = false
            return
        }
        lifecycle.isInitiationPass2 = true
        lifecycle.initiationPass2ServerId = cfg.id
        lifecycle.hasIssuedAutoStopForPass2 = false
        lifecycle.pass2BroadcastTechTimerArmed = false
        logAppMessage("[App] Initiation pass 2 — starting server to bring up connections.")
        startServer()
        // playit: poll for addresses and only count toward a failure timeout once a
        // secret exists — i.e. after the user has finished signing in. We never
        // penalise the time spent in the sign-in sheet itself.
        if initiationPlayitStatus == .waiting {
            scheduleInitiationPlayitWatchdog(techElapsed: 0)
        }
        // Absolute backstop so a walked-away setup still ends instead of leaving
        // the server running forever.
        scheduleInitiationSafetyCap()
    }

    /// Polls playit tunnel addresses (~every 5s). While no secret exists the user
    /// is still signing in, so the failure clock is held at zero. Once a secret
    /// exists we're only waiting on the tunnel itself — allow ~75s for that.
    private func scheduleInitiationPlayitWatchdog(techElapsed: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self,
                  self.lifecycle.isInitiationPass2,
                  self.initiationPlayitStatus == .waiting else { return }
            if self.playitSecretKey != nil {
                self.fetchAndStorePlayitTunnelAddresses()
                let elapsed = techElapsed + 5
                if elapsed >= 75 {
                    self.initiationPlayitStatus = .failed
                    self.logAppMessage("[App] playit tunnel didn't come up in time — you can finish it later from Edit Server → Network.")
                    self.checkInitiationPass2Completion()
                    return
                }
                self.scheduleInitiationPlayitWatchdog(techElapsed: elapsed)
            } else {
                // Still waiting on the user to sign in — hold the clock.
                self.scheduleInitiationPlayitWatchdog(techElapsed: 0)
            }
        }
    }

    /// Called once the broadcaster authenticates (gamertag parsed). From there
    /// it's a technical wait to create the Xbox LIVE session — allow ~60s. Before
    /// authentication we wait indefinitely (the user may still be signing in).
    func armInitiationBroadcastTechTimeout() {
        guard lifecycle.isInitiationPass2,
              initiationBroadcastStatus == .waiting,
              !lifecycle.pass2BroadcastTechTimerArmed else { return }
        lifecycle.pass2BroadcastTechTimerArmed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            guard let self,
                  self.lifecycle.isInitiationPass2,
                  self.initiationBroadcastStatus == .waiting else { return }
            self.initiationBroadcastStatus = .failed
            self.logAppMessage("[App] Xbox broadcast didn't finish creating its session in time.")
            self.checkInitiationPass2Completion()
        }
    }

    /// Absolute backstop (~10 min). Dismisses any lingering sign-in prompts, marks
    /// still-waiting transports failed, and finishes so the server can't be left
    /// running indefinitely by a walked-away setup.
    private func scheduleInitiationSafetyCap() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 600) { [weak self] in
            guard let self,
                  self.lifecycle.isInitiationPass2,
                  !self.lifecycle.hasIssuedAutoStopForPass2 else { return }
            self.logAppMessage("[App] Initiation safety cap reached — finishing setup.")
            self.isShowingPlayitSecretSetup = false
            self.pendingBroadcastAuthPrompt = nil
            self.pendingBedrockTunnelMissing = nil
            if self.initiationPlayitStatus == .waiting { self.initiationPlayitStatus = .failed }
            if self.initiationBroadcastStatus == .waiting { self.initiationBroadcastStatus = .failed }
            self.checkInitiationPass2Completion()
        }
    }

    /// Mark playit confirmed if we're mid pass-2 (called when tunnel addresses land).
    /// Only confirms once EVERY configured tunnel has resolved an address — so a
    /// Java+Bedrock server doesn't finish (and show the completion sheet) with the
    /// Bedrock address still missing, which would fall back to the raw public IP.
    func markInitiationPlayitReadyIfNeeded() {
        guard lifecycle.isInitiationPass2, initiationPlayitStatus == .waiting else { return }
        guard let sel = selectedServer, let cfg = configServer(for: sel) else { return }
        let needJava = !cfg.isBedrock
        let needBedrock = bedrockPortForPlayit(for: cfg) != nil
        if needJava && configManager.config.playitJavaAddress == nil { return }
        if needBedrock && configManager.config.playitBedrockAddress == nil { return }
        initiationPlayitStatus = .ready
        logAppMessage("[App] Initiation: playit tunnel(s) confirmed.")
        checkInitiationPass2Completion()
    }

    /// Mark broadcast confirmed if we're mid pass-2 (Xbox LIVE session created).
    func markInitiationBroadcastReadyIfNeeded() {
        guard lifecycle.isInitiationPass2, initiationBroadcastStatus == .waiting else { return }
        initiationBroadcastStatus = .ready
        logAppMessage("[App] Initiation: Xbox broadcast confirmed.")
        checkInitiationPass2Completion()
    }

    /// User tapped Skip on the playit row.
    func skipInitiationPlayit() {
        guard initiationPlayitStatus == .waiting else { return }
        initiationPlayitStatus = .skipped
        logAppMessage("[App] Initiation: playit setup skipped by user.")
        checkInitiationPass2Completion()
    }

    /// User tapped Skip on the Xbox broadcast row — also dismisses any pending
    /// sign-in prompt and stops the broadcaster.
    func skipInitiationBroadcast() {
        guard initiationBroadcastStatus == .waiting else { return }
        initiationBroadcastStatus = .skipped
        pendingBroadcastAuthPrompt = nil
        stopBroadcastIfRunning()
        stopBedrockBroadcastIfRunning()
        logAppMessage("[App] Initiation: Xbox broadcast setup skipped by user.")
        checkInitiationPass2Completion()
    }

    /// If every awaited transport is resolved, auto-stop to finish initiation.
    func checkInitiationPass2Completion() {
        guard lifecycle.isInitiationPass2, !lifecycle.hasIssuedAutoStopForPass2 else { return }
        guard initiationPlayitStatus.isResolved, initiationBroadcastStatus.isResolved else { return }
        lifecycle.hasIssuedAutoStopForPass2 = true
        logAppMessage("[App] Initiation complete — connections ready. Stopping for the final time.")
        stopServer()
    }

    /// Hide the progress overlay and present the enriched completion sheet.
    private func presentInitiationCompleteSheet(for cfg: ConfigServer) {
        isShowingInitiationProgress = false
        if let idx = configManager.config.servers.firstIndex(where: { $0.id == cfg.id }),
           !configManager.config.servers[idx].hasShownFirstStartPopup {
            configManager.config.servers[idx].hasShownFirstStartPopup = true
            configManager.save()
        }
        // If broadcast authenticated during initiation (we captured a gamertag), stash
        // an offer to save it — surfaced once the completion sheet is dismissed, since
        // the save sheet is suppressed while initiation is running.
        if let tag = initiationBroadcastGamertag?.trimmingCharacters(in: .whitespacesAndNewlines),
           !tag.isEmpty {
            let existing = cfg.xboxBroadcastAltGamertag?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if existing.caseInsensitiveCompare(tag) != .orderedSame,
               !broadcastGamertagSaveDeclinedServerIds.contains(cfg.id) {
                pendingInitiationGamertagSave = BroadcastGamertagSavePrompt(serverId: cfg.id, gamertag: tag)
            }
        }
        showFirstStartAlert = true
    }

    /// Called when the first-start completion sheet is dismissed. If we stashed a
    /// gamertag-save offer during initiation, surface the save sheet now (unless
    /// another modal — e.g. Manage Servers — is up).
    func offerPendingInitiationGamertagSaveIfNeeded() {
        guard let pending = pendingInitiationGamertagSave else { return }
        pendingInitiationGamertagSave = nil
        // Don't stack over another modal (e.g. Manage Servers, opened via the
        // completion sheet's "Open Server Settings…"). contentViewSheetIsPresented
        // tracks those; the normal-start path will re-offer later anyway.
        guard !contentViewSheetIsPresented else { return }
        guard let cfg = configServer(id: pending.serverId) else { return }
        let existing = cfg.xboxBroadcastAltGamertag?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard existing.caseInsensitiveCompare(pending.gamertag) != .orderedSame else { return }
        guard !broadcastGamertagSaveDeclinedServerIds.contains(pending.serverId) else { return }
        pendingBroadcastGamertagSave = pending
    }
}

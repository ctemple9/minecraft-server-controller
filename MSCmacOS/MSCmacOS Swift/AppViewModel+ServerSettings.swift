//
//  AppViewModel+ServerSettings.swift
//  MinecraftServerController
//

import Foundation

extension AppViewModel {

    // MARK: - Initial setup

    func applyInitialSetup(serversRoot: String, javaPath: String) {
        let fm = FileManager.default
        var root = serversRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        if root.isEmpty { root = AppConfig.defaultConfig().serversRoot }
        root = (root as NSString).expandingTildeInPath
        try? fm.createDirectory(atPath: root, withIntermediateDirectories: true)

        var cfg = configManager.config
        cfg.serversRoot = root
        cfg.pluginTemplateDir = (root as NSString).appendingPathComponent("_plugin_templates")
        cfg.paperTemplateDir = (root as NSString).appendingPathComponent("_paper_templates")
        try? fm.createDirectory(atPath: cfg.pluginTemplateDir, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: cfg.paperTemplateDir, withIntermediateDirectories: true)

        let trimmedJava = javaPath.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.javaPath = trimmedJava.isEmpty ? "java" : trimmedJava
        cfg.initialSetupDone = true

        configManager.config = cfg
        configManager.save()
        reloadServersFromConfig()
        isShowingInitialSetup = false
        logAppMessage("[App] Initial setup complete.")
        shouldLaunchFirstRunEducationAfterInitialSetupDismiss = true
    }

    // MARK: - Welcome Guide helpers

    func handleInitialSetupDismissed() {
        guard shouldLaunchFirstRunEducationAfterInitialSetupDismiss else { return }
        shouldLaunchFirstRunEducationAfterInitialSetupDismiss = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            self.stageWelcomeGuideThenTourIfNeeded()
        }
    }

    func stageWelcomeGuideThenTourIfNeeded() {
        let shouldShowWelcomeGuide = !configManager.config.hasShownWelcomeGuide
        if shouldShowWelcomeGuide {
            shouldStartOnboardingAfterWelcomeGuide = true
            isShowingWelcomeGuide = true
            return
        }
        shouldStartOnboardingAfterWelcomeGuide = false
        OnboardingManager.shared.startIfNeeded()
    }

    func handleWelcomeGuideDismissed() {
        isShowingWelcomeGuide = false
        markWelcomeGuideShown()
        guard shouldStartOnboardingAfterWelcomeGuide else { return }
        shouldStartOnboardingAfterWelcomeGuide = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            OnboardingManager.shared.forceStart()
        }
    }

    func markWelcomeGuideShown() {
        if !configManager.config.hasShownWelcomeGuide {
            configManager.config.hasShownWelcomeGuide = true
            configManager.save()
            logAppMessage("[App] Welcome Guide marked as shown.")
        }
    }

    func showWelcomeGuideFromPreferences() {
        shouldStartOnboardingAfterWelcomeGuide = false
        isShowingWelcomeGuide = true
    }

    // MARK: - EULA

    func refreshEULAState() {
        guard let server = selectedServer else {
            eulaAccepted = nil
            return
        }
        eulaAccepted = EULAManager.readEULA(in: server.directory)
    }

    func acceptEULA() {
        guard let server = selectedServer else { return }
        do {
            try EULAManager.writeAcceptedEULA(in: server.directory)
            eulaAccepted = true
            logAppMessage("[App] EULA accepted for \(server.name).")
        } catch {
            logAppMessage("[App] Failed to write eula.txt: \(error.localizedDescription)")
        }
    }

    // MARK: - Server settings

    func loadServerSettings() {
        guard let server = selectedServer else {
            serverSettings = nil
            return
        }
        let props = ServerPropertiesManager.readProperties(serverDir: server.directory)
        let port = props["server-port"] ?? "25565"
        let motd = props["motd"] ?? "A Paper Server"
        let maxPlayers = props["max-players"] ?? "20"
        let onlineMode = (props["online-mode"] ?? "true").lowercased() == "true"
        let parsed = GeyserConfigManager.readConfig(serverDir: server.directory)
        let bedAddr = parsed?.address ?? ""
        let bedPortStr: String
        if let cfgServer = configServer(for: server) {
            let p = effectiveBedrockPort(for: cfgServer)
            bedPortStr = p.map(String.init) ?? ""
        } else {
            bedPortStr = parsed?.port.map(String.init) ?? ""
        }
        serverSettings = ServerSettingsData(
            port: port, motd: motd, maxPlayers: maxPlayers,
            onlineMode: onlineMode, bedrockAddress: bedAddr, bedrockPort: bedPortStr
        )
    }

    func saveServerSettings(_ data: ServerSettingsData) {
        guard let server = selectedServer else { return }
        var props = ServerPropertiesManager.readProperties(serverDir: server.directory)
        props["server-port"] = data.port
        props["motd"] = data.motd
        props["max-players"] = data.maxPlayers
        props["online-mode"] = data.onlineMode ? "true" : "false"
        do {
            try ServerPropertiesManager.writeProperties(props, to: server.directory)
            logAppMessage("[App] Updated server.properties for \(server.name).")
        } catch {
            logAppMessage("[App] Failed to save server.properties: \(error.localizedDescription)")
            showError(title: "Settings Save Failed", message: "Could not write server.properties: \(error.localizedDescription)")
        }
    }

    // MARK: - server.properties typed helpers

    func effectiveBedrockPort(for server: ConfigServer) -> Int? {
        if let p = server.bedrockPort { return p }
        if let geyser = GeyserConfigManager.readConfig(serverDir: server.serverDir),
           let p = geyser.port { return p }
        return nil
    }

    private func persistBedrockPort(_ port: Int?, for serverId: String) {
        guard let idx = configManager.config.servers.firstIndex(where: { $0.id == serverId }) else { return }
        configManager.config.servers[idx].bedrockPort = port
        configManager.save()
    }

    func loadServerPropertiesModel(for configServer: ConfigServer) -> ServerPropertiesModel {
        let props = ServerPropertiesManager.readProperties(serverDir: configServer.serverDir)
        var model = ServerPropertiesModel(from: props, fallbackMotd: configServer.displayName)
        model.bedrockPort = effectiveBedrockPort(for: configServer)
        return model
    }

    func saveServerPropertiesModel(_ model: ServerPropertiesModel, for configServer: ConfigServer) throws {
        var normalizedModel = model
        normalizedModel.onlineMode = true
        let existing = ServerPropertiesManager.readProperties(serverDir: configServer.serverDir)
        let merged = normalizedModel.mergedInto(existing)
        do {
            try ServerPropertiesManager.writeProperties(merged, to: configServer.serverDir)
            logAppMessage("[App] Updated server.properties for \(configServer.displayName).")
        } catch {
            logAppMessage("[App] Failed to save server.properties for \(configServer.displayName): \(error.localizedDescription)")
            throw error
        }
        persistBedrockPort(model.bedrockPort, for: configServer.id)
        if let port = model.bedrockPort {
            let cfgURL = GeyserConfigManager.configURL(for: configServer.serverDir)
            if FileManager.default.fileExists(atPath: cfgURL.path) {
                do {
                    let existingGeyser = GeyserConfigManager.readConfig(serverDir: configServer.serverDir)
                    let preservedAddress = existingGeyser?.address ?? ""
                    try GeyserConfigManager.writeConfig(
                        serverDir: configServer.serverDir,
                        config: GeyserConfig(address: preservedAddress, port: port)
                    )
                    logAppMessage("[Geyser] Synced bedrock.port for \(configServer.displayName) to \(port).")
                } catch {
                    logAppMessage("[Geyser] Failed to patch config.yml for \(configServer.displayName): \(error.localizedDescription)")
                }
            } else {
                logAppMessage("[Geyser] No config.yml found; skipping bedrock.port sync.")
            }
        } else {
            logAppMessage("[Geyser] Bedrock port not set; skipping Geyser bedrock.port sync.")
        }
        _ = syncBroadcastConfig(for: configServer)
        if let current = selectedServer, current.id == configServer.id {
            loadServerSettings()
            loadGeyserConfig()
        }
    }

    // MARK: - Geyser

    func loadGeyserConfig() {
        guard let server = selectedServer else { return }
        let serverURL = URL(fileURLWithPath: server.directory, isDirectory: true)
        hasGeyser = GeyserConfigManager().isGeyserInstalled(serverPath: serverURL)
        let parsed = GeyserConfigManager.readConfig(serverDir: server.directory)
        geyserAddress = parsed?.address ?? ""
        if let cfgServer = configServer(for: server) {
            let p = effectiveBedrockPort(for: cfgServer)
            geyserPort = p.map(String.init) ?? ""
        } else {
            geyserPort = parsed?.port.map(String.init) ?? ""
        }
    }

    func saveGeyserConfig() {
        guard let server = selectedServer else { return }
        let serverURL = URL(fileURLWithPath: server.directory, isDirectory: true)
        guard GeyserConfigManager().isGeyserInstalled(serverPath: serverURL) else {
            logAppMessage("[Geyser] Geyser plugin not detected (no JAR found).")
            return
        }
        let trimmed = geyserPort.trimmingCharacters(in: .whitespacesAndNewlines)
        let portInt: Int?
        if trimmed.isEmpty {
            portInt = nil
        } else {
            portInt = Int(trimmed)
        }
        if !trimmed.isEmpty && portInt == nil {
            logAppMessage("[Geyser] Invalid Bedrock port '\(geyserPort)'; not saving.")
            return
        }
        if let cfgServer = configServer(for: server) {
            persistBedrockPort(portInt, for: cfgServer.id)
            _ = syncBroadcastConfig(for: cfgServer)
        }
        let cfgURL = GeyserConfigManager.configURL(for: server.directory)
        if FileManager.default.fileExists(atPath: cfgURL.path) {
            let cfg = GeyserConfig(address: geyserAddress, port: portInt)
            do {
                try GeyserConfigManager.writeConfig(serverDir: server.directory, config: cfg)
                logAppMessage("[Geyser] Updated config.yml for \(server.name)")
            } catch {
                logAppMessage("[Geyser] Failed to write config.yml: \(error.localizedDescription)")
            }
        } else {
            logAppMessage("[Geyser] Saved desired Bedrock port. Start the server once to generate config.yml, then Save again to apply it.")
        }
    }

    // MARK: - DuckDNS

    func saveDuckDNSHostname() {
        let trimmed = duckdnsInput.trimmingCharacters(in: .whitespacesAndNewlines)
        configManager.setDuckDNS(trimmed.isEmpty ? nil : trimmed)
        let serversToSync = configManager.config.servers.filter { $0.xboxBroadcastEnabled || $0.xboxBroadcastConfigPath != nil }
        for server in serversToSync { _ = syncBroadcastConfig(for: server) }
        logAppMessage("[App] Updated DuckDNS hostname.")
    }

    // MARK: - Preferences

    func makePreferencesModel() -> PreferencesModel {
        let cfg = configManager.config
        return PreferencesModel(
            serversRoot: cfg.serversRoot,
            javaPath: cfg.javaPath,
            extraFlags: cfg.extraFlags,
            duckdnsHostname: cfg.duckdnsHostname ?? ""
        )
    }

    func applyPreferences(_ prefs: PreferencesModel) {
        var cfg = configManager.config
        let fm = FileManager.default
        var root = prefs.serversRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        if root.isEmpty { root = AppConfig.defaultConfig().serversRoot }
        root = (root as NSString).expandingTildeInPath
        if !root.isEmpty { try? fm.createDirectory(atPath: root, withIntermediateDirectories: true) }
        cfg.serversRoot = root
        let trimmedJava = prefs.javaPath.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.javaPath = trimmedJava.isEmpty ? "java" : trimmedJava
        cfg.extraFlags = prefs.extraFlags
        let oldDuck = cfg.duckdnsHostname
        let trimmedDuck = prefs.duckdnsHostname.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.duckdnsHostname = trimmedDuck.isEmpty ? nil : trimmedDuck
        duckdnsInput = trimmedDuck
        configManager.config = cfg
        configManager.save()
        if oldDuck != cfg.duckdnsHostname {
            let serversToSync = configManager.config.servers.filter { $0.xboxBroadcastEnabled || $0.xboxBroadcastConfigPath != nil }
            for server in serversToSync { _ = syncBroadcastConfig(for: server) }
        }
        logAppMessage("[App] Updated global preferences.")
    }

    func updatePreferences(javaPath: String, extraFlags: String, remoteAPIExposeOnLAN: Bool) {
        let previous = configManager.config
        var cfg = previous
        let trimmedJava = javaPath.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.javaPath = trimmedJava.isEmpty ? "java" : trimmedJava
        cfg.extraFlags = extraFlags.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.remoteAPIExposeOnLAN = remoteAPIExposeOnLAN
        configManager.config = cfg
        configManager.save()
        if previous.remoteAPIExposeOnLAN != cfg.remoteAPIExposeOnLAN {
            remoteAPIServer?.setListenOnAllInterfaces(cfg.remoteAPIExposeOnLAN)
        }
        logAppMessage("[App] Updated Preferences (Java path / extra flags / Remote API exposure).")
    }

    // MARK: - Connection info helpers

    var javaAddressForDisplay: String {
        if let ip = AppUtilities.localIPAddress() { return ip }
        return "Unknown address"
    }

    var javaPortForDisplay: String {
        let raw = serverSettings?.port.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? "25565" : raw
    }

    var bedrockAddressForDisplay: String? {
        guard hasGeyser else { return nil }
        let trimmed = geyserAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let anyAddressValues: Set<String> = ["0.0.0.0", "::", "0:0:0:0:0:0:0:0"]
        if trimmed.isEmpty || anyAddressValues.contains(trimmed) { return javaAddressForDisplay }
        return trimmed
    }

    var bedrockPortForDisplay: Int? {
        let trimmed = geyserPort.trimmingCharacters(in: .whitespacesAndNewlines)
        if let live = Int(trimmed), live > 0 { return live }
        guard hasGeyser else { return nil }
        guard let server = selectedServer,
              let cfgServer = configServer(for: server) else { return nil }
        if let desired = effectiveBedrockPort(for: cfgServer), desired > 0 { return desired }
        return nil
    }
}

//
//  AppViewModel+OutputHandling.swift
//  MinecraftServerController
//

import Foundation

extension AppViewModel {

    // MARK: - Server output handling

    func handleServerOutputLine(_ line: String) {
        let clean = AppUtilities.sanitized(line)
        let isBedrockServer = selectedServer.flatMap { configServer(for: $0) }?.isBedrock ?? false
        let didReachReadyState =
            clean.contains("Done (") ||
            (isBedrockServer && clean.localizedCaseInsensitiveContains("Server started"))

        if !lifecycle.serverReadyForAutoMetrics, didReachReadyState {
            lifecycle.serverReadyForAutoMetrics = true
            if !lifecycle.hasLoggedReadyOnce {
                lifecycle.hasLoggedReadyOnce = true
                logAppMessage("[App] Server is ready. Auto monitoring enabled.")
            }
            if let server = selectedServer, let cfg = configServer(for: server) {
                writeLastStartupResult(for: cfg, wasClean: true, fatalErrors: [], warnings: [])
                refreshHealthCardsForSelectedServer()
                scanPaperSoftFailures(for: cfg)
            }
        }

        console.appendRaw(line, source: .server)
        remoteAPIServer?.publishConsoleLine(source: "server", text: line)

        // Initiate (first run) auto-stop
        if let initiatingId = lifecycle.initiatingFirstRunServerId,
           !lifecycle.hasIssuedAutoStopForInitiate,
           didReachReadyState {
            lifecycle.hasIssuedAutoStopForInitiate = true

            let readySignalDescription: String
            if clean.contains("Done (") {
                readySignalDescription = "\"Done\""
            } else if isBedrockServer && clean.localizedCaseInsensitiveContains("Server started") {
                readySignalDescription = "\"Server started\""
            } else {
                readySignalDescription = "startup ready signal"
            }

            logAppMessage("[App] Initiation complete (detected \(readySignalDescription)). Auto-stopping so you can edit settings.")
            stopServer()
            if let idx = configManager.config.servers.firstIndex(where: { $0.id == initiatingId }) {
                if !configManager.config.servers[idx].hasShownFirstStartPopup {
                    configManager.config.servers[idx].hasShownFirstStartPopup = true
                    configManager.save()
                    showFirstStartAlert = true
                }
            }
        }

        parseTps(from: line)
        parseWorldTime(from: line)
        parseFeaturedHealth(from: line)
        parsePlayerList(from: line)
        parseBedrockVersion(from: line)
        parseBedrockPlayerEvent(from: line)
        parseJavaPlayerEvent(from: line)
    }

    // MARK: - Unexpected-stop diagnostics

    /// Called when a server process stops without a user request. For modded servers that
    /// never reached ready state, runs the crash analyzer off-main and, if it attributes
    /// problems to specific mods, presents the diagnostics sheet. Otherwise falls back to
    /// the generic "stopped unexpectedly" alert. Always refreshes the health cards.
    func diagnoseUnexpectedStop(reachedReadyState: Bool) {
        guard let server = selectedServer, let cfg = configServer(for: server) else {
            refreshHealthCardsForSelectedServer()
            return
        }

        // Recent server console output, used as a fallback when the log file isn't readable.
        let excerpt = console.entries
            .filter { $0.source == .server }
            .suffix(120)
            .map { $0.raw }
        let errorExcerpt = console.entries
            .filter { $0.source == .server && $0.level == .error }
            .suffix(5)
            .map { $0.raw }
        let mods = discoveredMods
        let isHardFail = !reachedReadyState
        let shouldAnalyze = isHardFail && cfg.isModded

        Task.detached { [weak self] in
            guard let self else { return }
            let problems: [StartupProblem] = shouldAnalyze
                ? StartupCrashAnalyzer.analyze(
                    serverDir: cfg.serverDir, flavor: cfg.javaFlavor,
                    consoleExcerpt: excerpt, installedMods: mods)
                : []

            await MainActor.run {
                if !problems.isEmpty {
                    let summaries = problems.map { "\($0.offenderName): \($0.requirement ?? $0.kind.title)" }
                    self.writeLastStartupResult(for: cfg, wasClean: false, fatalErrors: summaries, warnings: [], problems: problems)
                    self.startupProblems = problems
                    self.startupProblemsServerId = cfg.id
                    self.startupProblemsAreSoftFail = false
                    self.isShowingStartupProblems = true
                } else {
                    if isHardFail {
                        self.writeLastStartupResult(for: cfg, wasClean: false,
                            fatalErrors: ["Server stopped before reaching ready state."], warnings: [])
                    }
                    let detail = errorExcerpt.isEmpty
                        ? "The server process stopped unexpectedly with no error output in the log."
                        : errorExcerpt.joined(separator: "\n")
                    self.showError(title: "Server Stopped Unexpectedly", message: detail)
                }
                self.refreshHealthCardsForSelectedServer()
            }
        }
    }

    /// Reloads the persisted startup problems for the selected server and reopens the
    /// diagnostics sheet — used by the "Last startup" health card after the sheet has
    /// been dismissed. `wasClean` distinguishes a soft fail (started, add-ons failed)
    /// from a hard fail (couldn't start).
    func reopenStartupProblems() {
        guard let server = selectedServer, let cfg = configServer(for: server) else { return }
        let path = (cfg.serverDir as NSString).appendingPathComponent("last_startup_result.json")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let result = try? JSONDecoder().decode(LastStartupResult.self, from: data),
              let problems = result.problems, !problems.isEmpty else {
            logAppMessage("[Health] No structured startup problems recorded for this server.")
            return
        }
        startupProblems = problems
        startupProblemsServerId = cfg.id
        startupProblemsAreSoftFail = result.wasClean
        isShowingStartupProblems = true
    }

    /// On a *successful* Paper-family start, scans for plugins that failed to load and,
    /// if any, records them on the startup result so the health card can flag them. Runs
    /// off-main; never auto-opens a modal (the server is up and otherwise healthy).
    func scanPaperSoftFailures(for cfg: ConfigServer) {
        guard cfg.isJava, cfg.javaFlavor.addOnKind == .plugin else { return }
        let excerpt = console.entries.filter { $0.source == .server }.suffix(400).map { $0.raw }
        let plugins = discoveredPlugins

        Task.detached { [weak self] in
            guard let self else { return }
            let problems = StartupCrashAnalyzer.analyzePaperPlugins(
                serverDir: cfg.serverDir, consoleExcerpt: excerpt, installedPlugins: plugins)
            guard !problems.isEmpty else { return }
            await MainActor.run {
                let warnings = problems.map { "\($0.offenderName): \($0.requirement ?? $0.kind.title)" }
                // wasClean stays true — the server did start; these are non-fatal.
                self.writeLastStartupResult(for: cfg, wasClean: true, fatalErrors: [], warnings: warnings, problems: problems)
                self.refreshHealthCardsForSelectedServer()
                self.logAppMessage("[Health] \(problems.count) plugin issue(s) detected at startup — see the Last Startup card.")
            }
        }
    }

    // MARK: - Bedrock version parsing

    private func parseBedrockVersion(from line: String) {
        let clean = AppUtilities.sanitized(line)
        guard clean.contains("Starting Minecraft Bedrock server version") else { return }
        if let range = clean.range(of: "version ") {
            let after = String(clean[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let version = after.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
            if let version, !version.isEmpty {
                bedrockRunningVersion = version
            }
        }
    }

    // MARK: - Docker daemon check

    func checkDockerDaemonRunning() {
        Task.detached(priority: .userInitiated) { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/local/bin/docker")
            process.arguments = ["info"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            if !FileManager.default.fileExists(atPath: "/usr/local/bin/docker") {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/docker")
            }
            do {
                try process.run()
                let deadline = DispatchTime.now() + .seconds(3)
                DispatchQueue.global().asyncAfter(deadline: deadline) {
                    if process.isRunning { process.terminate() }
                }
                process.waitUntilExit()
                let running = process.terminationStatus == 0
                await MainActor.run { [weak self] in self?.dockerDaemonRunning = running }
            } catch {
                await MainActor.run { [weak self] in self?.dockerDaemonRunning = false }
            }
        }
    }

    // MARK: - Broadcast output handling

    func handleBroadcastOutputLine(_ line: String) {
        logAppMessage("[Broadcast] \(line)")
        if let prompt = Self.parseBroadcastAuthPrompt(from: line) {
            pendingBroadcastAuthPrompt = prompt
        }
    }

    private static func parseBroadcastAuthPrompt(from line: String) -> BroadcastAuthPrompt? {
        guard let urlRange = line.range(of: "https://www.microsoft.com/link") else { return nil }
        let afterURLStart = urlRange.lowerBound
        let substringFromURL = line[afterURLStart...]
        let urlToken = substringFromURL
            .split(whereSeparator: { $0.isWhitespace })
            .first
            .map(String.init) ?? "https://www.microsoft.com/link"
        guard let url = URL(string: urlToken) else { return nil }
        guard let codePrefixRange = line.range(of: " enter the code ") else { return nil }
        let codeStart = codePrefixRange.upperBound
        let codeSubstring = line[codeStart...]
        guard let rawCodeToken = codeSubstring
            .split(whereSeparator: { $0.isWhitespace })
            .first
            .map(String.init),
              !rawCodeToken.isEmpty else { return nil }
        let code = rawCodeToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return BroadcastAuthPrompt(linkURL: url, code: code)
    }

    // MARK: - TPS parsing

    private func parseTps(from line: String) {
        let clean = AppUtilities.sanitized(line)
        guard clean.contains("TPS from last 1m, 5m, 15m:") else { return }
        guard let colonIndex = clean.lastIndex(of: ":") else { return }
        let numbersPart = clean[clean.index(after: colonIndex)...]
            .trimmingCharacters(in: .whitespaces)
        let parts = numbersPart.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 3 else { return }
        guard let t1 = Double(parts[0]),
              let t5 = Double(parts[1]),
              let t15 = Double(parts[2]) else { return }
        latestTps1m = t1
        latestTps5m = t5
        latestTps15m = t15
        tpsHistory1m.append(t1)
        if tpsHistory1m.count > 30 { tpsHistory1m.removeFirst() }
    }

    // MARK: - World time parsing

    /// Parses responses to `time query gametime` and `time query day`.
    /// Handles both response formats:
    ///   - Legacy (pre-1.21.4):  "The time is X"
    ///   - New (1.21.4+ Paper):  "Timeline minecraft:X is at Y tick(s)"
    private func parseWorldTime(from line: String) {
        guard !pendingTimeQueryKinds.isEmpty else { return }
        let clean = AppUtilities.sanitized(line)

        let value: Int
        if let atRange = clean.range(of: " is at "),
           let tickRange = clean.range(of: " tick", range: atRange.upperBound..<clean.endIndex) {
            // New Paper format: "Timeline minecraft:day is at 35 tick(s)"
            let digits = String(clean[atRange.upperBound..<tickRange.lowerBound])
                .trimmingCharacters(in: .whitespaces)
            guard let v = Int(digits) else { return }
            value = v
        } else if let range = clean.range(of: "The time is ") {
            // Legacy format: "The time is 1234"
            let tail = clean[range.upperBound...]
            let digits = tail.prefix { $0.isNumber || $0 == "-" }
            guard let v = Int(digits) else { return }
            value = v
        } else {
            return
        }

        let kind = pendingTimeQueryKinds.removeFirst()
        switch kind {
        case .gametime:
            worldDayNumber = value / 24000
        case .daytime:
            worldTimeOfDayTicks = ((value % 24000) + 24000) % 24000
            worldTimeIsLive = true
        }
    }

    // MARK: - Featured player health parsing

    /// Parses the response to `/data get entity <name> Health`, e.g.
    /// "camkage has the following entity data: 19.5f", for the featured player.
    private func parseFeaturedHealth(from line: String) {
        guard let name = featuredPlayerName else { return }
        let clean = AppUtilities.sanitized(line)
        guard clean.contains("\(name) has the following entity data:"),
              let r = clean.range(of: "entity data:") else { return }
        let tail = clean[r.upperBound...].trimmingCharacters(in: .whitespaces)
        let digits = tail.prefix { $0.isNumber || $0 == "." || $0 == "-" }
        if let value = Double(digits) {
            featuredPlayerHealth = max(0, value)
        }
    }

    // MARK: - Player list parsing

    private func parsePlayerList(from line: String) {
        let clean = AppUtilities.sanitized(line)
        guard clean.lowercased().contains("players online") else { return }
        if let colonIndex = clean.lastIndex(of: ":") {
            let namesPart = clean[clean.index(after: colonIndex)...]
                .trimmingCharacters(in: .whitespaces)
            if namesPart.isEmpty {
                onlinePlayers = []
                appendPlayerCountHistory(0)
            } else {
                let names = namesPart
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .map { OnlinePlayer(name: $0, xuid: nil) }
                onlinePlayers = names
                let existingNames = Set(playerSessionHistory)
                for player in names where !existingNames.contains(player.name) {
                    playerSessionHistory.append(player.name)
                }
                appendPlayerCountHistory(names.count)
            }
        } else {
            onlinePlayers = []
            appendPlayerCountHistory(0)
        }
    }

    func appendPlayerCountHistory(_ count: Int) {
        playerCountHistory.append(count)
        if playerCountHistory.count > 30 { playerCountHistory.removeFirst() }
    }

    // MARK: - Bedrock player event parsing

    private func parseBedrockPlayerEvent(from line: String) {
        let clean = AppUtilities.sanitized(line)

        func extractIdentity(prefix: String) -> (name: String, xuid: String?)? {
            guard let range = clean.range(of: prefix) else { return nil }
            let after = String(clean[range.upperBound...])
            let gamertag = after
                .components(separatedBy: ",")
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !gamertag.isEmpty else { return nil }
            var xuid: String? = nil
            if let xuidRange = after.range(of: "xuid:") {
                let raw = String(after[xuidRange.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !raw.isEmpty { xuid = raw }
            }
            return (gamertag, xuid)
        }

        if clean.contains("Player connected:"),
           let identity = extractIdentity(prefix: "Player connected: ") {
            if let idx = onlinePlayers.firstIndex(where: {
                $0.name.caseInsensitiveCompare(identity.name) == .orderedSame
            }) {
                onlinePlayers[idx] = OnlinePlayer(name: identity.name, xuid: identity.xuid ?? onlinePlayers[idx].xuid)
            } else {
                onlinePlayers.append(OnlinePlayer(name: identity.name, xuid: identity.xuid))
            }
            if !playerSessionHistory.contains(where: { $0.caseInsensitiveCompare(identity.name) == .orderedSame }) {
                playerSessionHistory.append(identity.name)
            }
            if let xuid = identity.xuid, !xuid.isEmpty {
                backfillBedrockAllowlistXUIDIfNeeded(name: identity.name, xuid: xuid)
                // Persist the XUID→name mapping so profile cards show the right name
                // even after the server log is overwritten on next startup.
                if let serverDir = selectedServer.flatMap({ configServer(for: $0)?.serverDir }) {
                    BedrockNameCache.record(xuid: xuid, name: identity.name, serverDir: serverDir)
                }
            }
            appendPlayerCountHistory(onlinePlayers.count)
            recordSessionEvent(playerName: identity.name, eventType: .joined)
            if let server = selectedServer, let cfg = configServer(for: server) {
                fireNotificationIfEnabled(event: .playerJoined(playerName: identity.name),
                                          serverName: cfg.displayName, serverId: cfg.id)
            }
        } else if clean.contains("Player disconnected:"),
                  let identity = extractIdentity(prefix: "Player disconnected: ") {
            onlinePlayers.removeAll { $0.name.caseInsensitiveCompare(identity.name) == .orderedSame }
            appendPlayerCountHistory(onlinePlayers.count)
            recordSessionEvent(playerName: identity.name, eventType: .left)
            if let server = selectedServer, let cfg = configServer(for: server) {
                fireNotificationIfEnabled(event: .playerLeft(playerName: identity.name),
                                          serverName: cfg.displayName, serverId: cfg.id)
            }
        }
    }

    // MARK: - Java player event parsing

    private func parseJavaPlayerEvent(from line: String) {
        let clean = AppUtilities.sanitized(line)
        if let range = clean.range(of: " joined the game") {
            let before = String(clean[..<range.lowerBound])
            let name = before.split(whereSeparator: { $0.isWhitespace }).last.map(String.init) ?? ""
            guard !name.isEmpty else { return }
            recordSessionEvent(playerName: name, eventType: .joined)
            if let server = selectedServer, let cfg = configServer(for: server) {
                fireNotificationIfEnabled(event: .playerJoined(playerName: name),
                                          serverName: cfg.displayName, serverId: cfg.id)
            }
        } else if let range = clean.range(of: " left the game") {
            let before = String(clean[..<range.lowerBound])
            let name = before.split(whereSeparator: { $0.isWhitespace }).last.map(String.init) ?? ""
            guard !name.isEmpty else { return }
            recordSessionEvent(playerName: name, eventType: .left)
            if let server = selectedServer, let cfg = configServer(for: server) {
                fireNotificationIfEnabled(event: .playerLeft(playerName: name),
                                          serverName: cfg.displayName, serverId: cfg.id)
            }
        }
    }

    // MARK: - Allowlist XUID backfill

    private func backfillBedrockAllowlistXUIDIfNeeded(name: String, xuid: String) {
        guard let server = selectedServer,
              let cfg = configServer(for: server),
              cfg.isBedrock else { return }
        var list = BedrockPropertiesManager.readAllowlist(serverDir: cfg.serverDir)
        guard let idx = list.firstIndex(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame &&
            (($0.xuid ?? "").isEmpty)
        }) else { return }
        list[idx].xuid = xuid
        do {
            try BedrockPropertiesManager.writeAllowlist(list, serverDir: cfg.serverDir)
            bedrockAllowlist = list
            logAppMessage("[Allowlist] Recorded XUID for \(name).")
        } catch {
            logAppMessage("[Allowlist] Failed to record XUID for \(name): \(error.localizedDescription)")
        }
    }
}

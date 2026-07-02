//
//  AppViewModel+Playit.swift
//  MinecraftServerController
//
//  Native playit.gg tunnel manager.
//  Starts a shared playitd subprocess when a playit-enabled server starts;
//  stops it when the server stops.
//
//  playitd is a self-contained daemon (built from Rust source, signed, hosted on
//  MSC's GitHub releases). It reads the secret key from a chmod-600 file and
//  forwards tunnel traffic directly to 127.0.0.1:<port> — no socat, no Docker.
//  Port→tunnel mapping is managed on the playit.gg account (server-side).
//
//  Claim URL and tunnel addresses are parsed from the daemon's log stream.
//

import Foundation
import AppKit

extension AppViewModel {

    // MARK: - Paths & secret key

    /// Legacy Docker config dir — kept only for the one-time Keychain migration.
    private var playitConfigDir: URL {
        configManager.configURL
            .deletingLastPathComponent()
            .appendingPathComponent("playit-docker", isDirectory: true)
    }

    /// Legacy plain-text key file path — only used for one-time migration to Keychain.
    private var legacyPlayitSecretKeyURL: URL {
        playitConfigDir.appendingPathComponent("secret_key")
    }

    /// Reads the stored playit secret key from Keychain.
    /// Migrates from the old plain-text file on first access if the file exists.
    /// Returns nil if not yet configured.
    var playitSecretKey: String? {
        // One-time migration: if the legacy file exists, move it to Keychain and delete it.
        let fm = FileManager.default
        if fm.fileExists(atPath: legacyPlayitSecretKeyURL.path),
           let data = try? Data(contentsOf: legacyPlayitSecretKeyURL),
           let legacyKey = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !legacyKey.isEmpty {
            KeychainManager.shared.writePlayitSecretKey(legacyKey)
            try? fm.removeItem(at: legacyPlayitSecretKeyURL)
            logAppMessage("[Playit] Migrated secret key from file to Keychain.")
        }
        return KeychainManager.shared.readPlayitSecretKey()
    }

    /// Persists the secret key to the macOS Keychain.
    func savePlayitSecretKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if KeychainManager.shared.writePlayitSecretKey(trimmed) {
            logAppMessage("[Playit] Secret key saved to Keychain.")
        } else {
            logAppMessage("[Playit] Failed to save secret key to Keychain.")
        }
    }

    func removePlayitSecretKey() {
        KeychainManager.shared.writePlayitSecretKey(nil)
        // Also clean up legacy file if it somehow still exists.
        try? FileManager.default.removeItem(at: legacyPlayitSecretKeyURL)
    }

    // MARK: - Port resolution

    /// Java port for the given server (read from server.properties if possible).
    private func javaPortForPlayit(for server: ConfigServer) -> Int? {
        guard server.isJava else { return nil }
        let props = ServerPropertiesManager.readProperties(serverDir: server.serverDir)
        if let p = props["server-port"].flatMap(Int.init) { return p }
        return 25565
    }

    /// Bedrock / Geyser UDP port for the given server.
    private func bedrockPortForPlayit(for server: ConfigServer) -> Int? {
        if server.isBedrock {
            return server.bedrockPort ?? 19132
        }
        // Java + Geyser
        if server.bedrockEnabled || server.bedrockPort != nil {
            return server.bedrockPort ?? 19132
        }
        return nil
    }

    /// Voice Chat UDP port (24454) if enabled.
    private func voicePortForPlayit(for server: ConfigServer) -> Int? {
        server.playitVoiceChatEnabled ? 24454 : nil
    }

    // MARK: - Lifecycle (called from startServer / stopServer)

    func startPlayitIfNeeded(for server: ConfigServer) {
        guard server.playitEnabled else { return }

        let javaPort    = javaPortForPlayit(for: server)
        let bedrockPort = bedrockPortForPlayit(for: server)
        let voicePort   = voicePortForPlayit(for: server)

        // Secret key required — show setup sheet if not yet configured
        guard let secretKey = playitSecretKey else {
            logAppMessage("[Playit] No secret key configured — showing setup.")
            isShowingPlayitSecretSetup = true
            return
        }

        // Binary download and process launch happen on a background thread so the
        // Minecraft server starts immediately.
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            await MainActor.run {
                self.playitAgentManager.onOutputLine = { [weak self] line in
                    self?.handlePlayitContainerOutput(line)
                }
                self.playitAgentManager.onDidTerminate = { [weak self] in
                    DispatchQueue.main.async {
                        self?.isPlayitRunning = false
                        self?.playitTunnelAddress = nil
                        self?.logAppMessage("[Playit] Tunnel stopped.")
                    }
                }
            }

            do {
                // Ensure playitd binary is downloaded and cached.
                let binaryURL = try await PlayitBinaryManager.ensureBinary()

                // Write secret to a chmod-600 file for --secret-path.
                let secretFileURL = try PlayitBinaryManager.writeSecretFile(secretKey)

                try self.playitAgentManager.start(binaryURL: binaryURL, secretFilePath: secretFileURL)

                // Build a port summary for the log (mapping comes from the playit.gg account).
                var portSummary = [String]()
                if let p = javaPort    { portSummary.append("Java TCP \(p)") }
                if let p = bedrockPort { portSummary.append("Bedrock UDP \(p)") }
                if let p = voicePort   { portSummary.append("Voice UDP \(p)") }

                await MainActor.run {
                    self.isPlayitRunning = true
                    self.logAppMessage("[Playit] Tunnel started (\(portSummary.joined(separator: ", "))).")
                    // Fetch immediately if we already have stored addresses (refresh them)
                    // plus again after 5s for first-time setup when the daemon is still loading.
                    self.fetchAndStorePlayitTunnelAddresses()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        self.fetchAndStorePlayitTunnelAddresses()
                    }
                    // Ensure the voice tunnel exists (Scenario A: voice enabled on an existing
                    // agent) once the daemon is online, then keep voice_host in sync.
                    self.ensureVoiceTunnelIfNeeded(for: server)
                }
            } catch {
                await MainActor.run {
                    self.logAppMessage("[Playit] Failed to start: \(error.localizedDescription)")
                    self.showError(title: "playit.gg Failed", message: error.localizedDescription)
                }
            }
        }
    }

    func stopPlayitIfRunning() {
        guard isPlayitRunning || playitAgentManager.isRunning else { return }
        // Update state immediately on main thread so UI reflects stopped state.
        isPlayitRunning = false
        playitTunnelAddress = nil
        logAppMessage("[Playit] Stopping tunnel…")
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            self.playitAgentManager.terminate()
            await MainActor.run {
                self.logAppMessage("[Playit] Tunnel stopped.")
            }
        }
    }

    // MARK: - Daemon log parsing

    func handlePlayitContainerOutput(_ line: String) {
        logAppMessage("[Playit] \(line)")

        // The daemon logs its agent id on connect ("agent_id=<uuid>"). Persist it if we don't
        // have it yet (e.g. agent was claimed before we started saving it) — voice/extra tunnel
        // creation needs it. When newly learned, kick off any pending voice-tunnel setup.
        if configManager.config.playitAgentId == nil,
           let agentId = Self.parseAgentId(from: line) {
            configManager.config.playitAgentId = agentId
            configManager.save()
            logAppMessage("[Playit] Learned agent id \(agentId) from daemon.")
            if let server = selectedServer, let cfg = configServer(for: server) {
                ensureVoiceTunnelIfNeeded(for: cfg)
            }
        }

        // Claim URL — shown on first run before account is linked
        if let _ = Self.parsePlayitClaimURL(from: line) {
            // With the secret-key approach, claim URLs shouldn't appear.
            // Log it in case something unexpected happens.
            logAppMessage("[Playit] Unexpected claim URL in output — secret key may be invalid.")
            return
        }

        // "tunnel setup" precedes the address line
        if line.localizedCaseInsensitiveContains("tunnel setup") {
            playitExpectingAddressLine = true
            return
        }

        if let addr = Self.parsePlayitTunnelAddress(from: line, expectingAddress: playitExpectingAddressLine) {
            playitExpectingAddressLine = false
            DispatchQueue.main.async { [weak self] in
                // Only update if this is a new/different address
                if self?.playitTunnelAddress != addr {
                    self?.playitTunnelAddress = addr
                    self?.logAppMessage("[Playit] Java tunnel ready at \(addr)")
                }
            }
        } else if playitExpectingAddressLine {
            playitExpectingAddressLine = false
        }
    }

    // MARK: - Parsers

    /// Extracts the agent UUID from a daemon log line like "... agent_id=d36e57c0-8507-...".
    static func parseAgentId(from line: String) -> String? {
        guard let range = line.range(of: "agent_id=") else { return nil }
        let after = line[range.upperBound...]
        let token = after.prefix { $0.isHexDigit || $0 == "-" }
        let id = String(token)
        // A UUID is 36 chars (8-4-4-4-12). Guard against partial/garbage matches.
        return id.count == 36 ? id : nil
    }

    static func parsePlayitClaimURL(from line: String) -> String? {
        let patterns = ["playit.gg/claim/", "playit.gg/login/guest-account/", "playit.gg/mc/"]
        guard patterns.contains(where: { line.contains($0) }) else { return nil }
        let stripped = line.replacingOccurrences(of: "§.", with: "", options: .regularExpression)
        let tokens = stripped.components(separatedBy: .whitespaces)
        return tokens.first { tok in patterns.contains(where: { tok.contains($0) }) }
    }

    static func parsePlayitTunnelAddress(from line: String, expectingAddress: Bool = false) -> String? {
        let domainPatterns = ["joinmc.link", "auto.playit.gg", "ply.gg"]
        let tokens = line.components(separatedBy: .whitespaces)
        for token in tokens {
            let clean = token.trimmingCharacters(in: CharacterSet(charactersIn: "(),[]'\""))
            let hasDomain = domainPatterns.contains(where: { clean.contains($0) })
            if hasDomain {
                let parts = clean.split(separator: ":", maxSplits: 1)
                if parts.count == 2, Int(parts[1]) != nil { return clean }
                if !clean.isEmpty { return clean }
            }
            if expectingAddress {
                let parts = clean.split(separator: ":", maxSplits: 1)
                if parts.count == 2, Int(parts[1]) != nil, !parts[0].isEmpty { return clean }
            }
        }
        return nil
    }

    // MARK: - Tunnel address storage (global — one agent per app)

    var playitJavaAddress: String? { configManager.config.playitJavaAddress }
    var playitBedrockAddress: String? { configManager.config.playitBedrockAddress }

    func savePlayitTunnelAddresses(javaAddress: String?, bedrockAddress: String?) {
        if let j = javaAddress?.trimmingCharacters(in: .whitespacesAndNewlines), !j.isEmpty {
            configManager.config.playitJavaAddress = j
        } else if javaAddress != nil {
            configManager.config.playitJavaAddress = nil
        }
        if let b = bedrockAddress?.trimmingCharacters(in: .whitespacesAndNewlines), !b.isEmpty {
            configManager.config.playitBedrockAddress = b
        } else if bedrockAddress != nil {
            configManager.config.playitBedrockAddress = nil
        }
        configManager.save()
        if isXboxBroadcastRunning, let server = selectedServer, let cfg = configServer(for: server) {
            stopBroadcastIfRunning()
            startBroadcastIfNeeded(for: cfg)
        }
    }

    // MARK: - Auto-fetch tunnel addresses from playit.gg API

    /// Fetches tunnel addresses from the playit.gg API using the stored secret key,
    /// then stores them and refreshes Xbox Broadcast if addresses changed.
    func fetchAndStorePlayitTunnelAddresses() {
        guard let secret = playitSecretKey else { return }

        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            do {
                let (java, bedrock, voice) = try await Self.fetchPlayitTunnelAddresses(secretKey: secret)
                await MainActor.run {
                    var changed = false
                    if let j = java, j != self.configManager.config.playitJavaAddress {
                        self.configManager.config.playitJavaAddress = j
                        changed = true
                    }
                    if let b = bedrock, b != self.configManager.config.playitBedrockAddress {
                        self.configManager.config.playitBedrockAddress = b
                        changed = true
                    }
                    if let v = voice, v != self.configManager.config.playitVoiceAddress {
                        self.configManager.config.playitVoiceAddress = v
                        changed = true
                    }
                    if changed {
                        self.configManager.save()
                        self.logAppMessage("[Playit] Tunnel addresses updated — Java: \(java ?? "—"), Bedrock: \(bedrock ?? "—"), Voice: \(voice ?? "—")")
                        if self.isXboxBroadcastRunning,
                           let server = self.selectedServer,
                           let cfg = self.configServer(for: server) {
                            self.stopBroadcastIfRunning()
                            self.startBroadcastIfNeeded(for: cfg)
                        }
                    }
                    // Keep Simple Voice Chat's voice_host in sync with the current tunnel address.
                    if let v = voice,
                       let server = self.selectedServer,
                       let cfg = self.configServer(for: server),
                       cfg.playitVoiceChatEnabled {
                        self.applyVoiceChatHost(v, for: cfg)
                    }
                }
            } catch {
                await MainActor.run {
                    self.logAppMessage("[Playit] Could not fetch tunnel addresses: \(error.localizedDescription)")
                }
            }
        }
    }

    private static func fetchPlayitTunnelAddresses(secretKey: String) async throws -> (java: String?, bedrock: String?, voice: String?) {
        guard let url = URL(string: "https://api.playit.gg/tunnels/list") else { return (nil, nil, nil) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Agent-Key \(secretKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["agent_id": NSNull()])

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["status"] as? String == "success",
              let payload = json["data"] as? [String: Any],
              let tunnels = payload["tunnels"] as? [[String: Any]] else {
            return (nil, nil, nil)
        }

        var javaAddress: String? = nil
        var bedrockAddress: String? = nil
        var voiceAddress: String? = nil

        for tunnel in tunnels {
            guard let active = tunnel["active"] as? Bool, active else { continue }
            let tunnelType = tunnel["tunnel_type"] as? String ?? ""
            let name = tunnel["name"] as? String ?? ""
            guard let alloc = (tunnel["alloc"] as? [String: Any])?["data"] as? [String: Any] else { continue }
            let domain = alloc["assigned_domain"] as? String ?? ""
            let port = alloc["port_start"] as? Int ?? 0
            guard port > 0 else { continue }

            if tunnelType == "minecraft-java" {
                // Java: domain is fine — players type it into the server list
                guard !domain.isEmpty else { continue }
                javaAddress = "\(domain):\(port)"
            } else if tunnelType == "minecraft-bedrock" {
                // Bedrock: use static IP — Xbox Broadcast's RakNet transfer packet requires
                // a real IP address, not a domain name. Domain works for manual add though.
                let ip = (alloc["static_ip4"] as? String) ?? domain
                guard !ip.isEmpty else { continue }
                bedrockAddress = "\(ip):\(port)"
            } else if name == PlayitAPI.voiceTunnelName {
                // Voice: Simple Voice Chat's voice_host needs a reachable IP:port (custom UDP tunnel).
                let ip = (alloc["static_ip4"] as? String) ?? domain
                guard !ip.isEmpty else { continue }
                voiceAddress = "\(ip):\(port)"
            }
        }
        return (javaAddress, bedrockAddress, voiceAddress)
    }

    // MARK: - Post-key-setup retry

    /// Called immediately after the user saves a new secret key in PlayitSecretKeySheet.
    /// If a server is currently running with playit enabled, starts the tunnel now
    /// rather than requiring the user to restart the server.
    func retryPlayitAfterKeySetup() {
        guard isServerRunning,
              let server = selectedServer,
              let cfg = configServer(for: server),
              cfg.playitEnabled else { return }
        startPlayitIfNeeded(for: cfg)
    }

    /// Creates one tunnel, retrying while the agent is still coming online. The API reports
    /// `AgentVersionTooOld`/`AgentNotFound` until the daemon has connected and registered its
    /// version, so we wait that out (up to ~25s) before giving up.
    /// Creates one tunnel (skipping if one with that name already exists), retrying while the
    /// agent is still coming online. The API reports `AgentVersionTooOld`/`AgentNotFound` until
    /// the daemon has connected, so we wait that out (~25s). Requires a web session (creation is
    /// not allowed with the read-only agent secret).
    @MainActor
    private func createTunnelIfMissing(agentId: String, tunnelType: String?, portType: String,
                                       localPort: Int, name: String, sessionKey: String,
                                       secret: String, label: String) async {
        if await PlayitAPI.tunnelExists(named: name, secret: secret) {
            logAppMessage("[Playit] \(label) tunnel already exists — skipping.")
            return
        }
        for _ in 0..<16 {
            do {
                try await PlayitAPI.createTunnel(agentId: agentId, tunnelType: tunnelType,
                                                 portType: portType, localPort: localPort,
                                                 name: name, sessionKey: sessionKey)
                logAppMessage("[Playit] \(label) tunnel created (local \(portType.uppercased()) \(localPort)).")
                return
            } catch let e as PlayitAPI.APIError where e.message == "AgentVersionTooOld" || e.message == "AgentNotFound" {
                try? await Task.sleep(nanoseconds: 1_500_000_000)  // wait for the daemon to connect
            } catch let e as PlayitAPI.APIError {
                logAppMessage("[Playit] \(label) tunnel create failed: \(e.message)")
                return
            } catch {
                logAppMessage("[Playit] \(label) tunnel create error: \(error.localizedDescription)")
                return
            }
        }
        logAppMessage("[Playit] \(label) tunnel create timed out — agent didn't come online in time.")
    }

    // MARK: - Simple Voice Chat tunnel

    /// Writes `voice_host` into Simple Voice Chat's config so clients route voice through the tunnel.
    @MainActor
    func applyVoiceChatHost(_ host: String, for server: ConfigServer) {
        // Don't create a stray config for a plugin that isn't installed.
        guard VoiceChatConfigManager.isInstalled(serverDir: server.serverDir) else { return }
        if let url = VoiceChatConfigManager.applyVoiceHost(serverDir: server.serverDir,
                                                           voiceHost: host, localPort: 24454) {
            logAppMessage("[Playit] Simple Voice Chat host set to \(host) in \(url.lastPathComponent).")
        } else {
            logAppMessage("[Playit] Could not write voicechat-server.properties.")
        }
    }

    /// On server start / agent connect: if the voice tunnel already exists, sync `voice_host`
    /// from it. If it doesn't exist yet, we can't create it here (creation needs a web session,
    /// not the read-only agent secret) — the user creates it by signing in from the voice toggle.
    @MainActor
    func ensureVoiceTunnelIfNeeded(for server: ConfigServer) {
        guard server.playitVoiceChatEnabled,
              let secret = playitSecretKey,
              configManager.config.playitAgentId != nil,
              VoiceChatConfigManager.isInstalled(serverDir: server.serverDir) else { return }
        Task { @MainActor in
            if await PlayitAPI.tunnelExists(named: PlayitAPI.voiceTunnelName, secret: secret) {
                fetchAndStorePlayitTunnelAddresses()   // resolves + patches voice_host
            } else {
                logAppMessage("[Playit] Voice chat is on but no voice tunnel exists yet — sign in from Edit Server → Network to create it.")
            }
        }
    }

    // MARK: - Reset (for retesting / switching accounts)

    /// Clears all *local* playit state so the setup flow starts fresh: stops the tunnel,
    /// deletes the Keychain secret and on-disk secret file, and clears stored tunnel
    /// addresses. Does NOT delete the agent/tunnels on the playit.gg account — remove those
    /// from the playit.gg dashboard if you want a completely clean server-side slate.
    func resetPlayitSetup() {
        stopPlayitIfRunning()
        removePlayitSecretKey()
        try? FileManager.default.removeItem(at: PlayitBinaryManager.secretFileURL)
        configManager.config.playitJavaAddress = nil
        configManager.config.playitBedrockAddress = nil
        configManager.save()
        playitTunnelAddress = nil
        logAppMessage("[Playit] Local setup reset — secret key, secret file, and tunnel addresses cleared. (Agent/tunnels on playit.gg are untouched.)")
    }

    // MARK: - Persist settings

    func setPlayitEnabled(_ enabled: Bool, voiceChat: Bool? = nil, for serverId: String) {
        guard let idx = configManager.config.servers.firstIndex(where: { $0.id == serverId }) else { return }
        let wasVoiceEnabled = configManager.config.servers[idx].playitVoiceChatEnabled
        configManager.config.servers[idx].playitEnabled = enabled
        if let vc = voiceChat {
            configManager.config.servers[idx].playitVoiceChatEnabled = vc
        }
        configManager.save()
        logAppMessage("[Playit] Tunnel \(enabled ? "enabled" : "disabled") for server.")

        // Voice chat just turned on: create the tunnel now if the agent is already online,
        // otherwise it's created on next server start. Either way, SVC only reads voice_host at
        // startup, so tell the user a restart is needed if the server is currently running.
        let server = configManager.config.servers[idx]
        let voiceJustEnabled = (voiceChat == true) && !wasVoiceEnabled && enabled
        if voiceJustEnabled {
            if !VoiceChatConfigManager.isInstalled(serverDir: server.serverDir) {
                // Nothing to create until SVC is present; it'll be set up once installed.
                firstStartNotice = FirstStartNotice(
                    title: "Simple Voice Chat not installed",
                    message: "Install the Simple Voice Chat plugin/mod on this server first, then enable this again to set up the voice tunnel."
                )
            } else if playitSecretKey != nil, configManager.config.playitAgentId != nil {
                // Agent already exists. Creating the voice tunnel needs a web session (the agent
                // secret is read-only), so sign in — the sign-in flow reuses the agent and adds
                // just the voice tunnel. If it already exists, only sync voice_host.
                Task { @MainActor in
                    let secret = self.playitSecretKey ?? ""
                    if await PlayitAPI.tunnelExists(named: PlayitAPI.voiceTunnelName, secret: secret) {
                        self.fetchAndStorePlayitTunnelAddresses()  // already exists → just sync voice_host
                    } else {
                        self.logAppMessage("[Playit] Voice chat on — sign in to add the voice tunnel (reuses your existing agent).")
                        self.isShowingPlayitSecretSetup = true
                    }
                }
            }
            // No agent yet → the voice tunnel is created during first-time setup on server start.
        }
    }

    // MARK: - Native in-app setup (sign in → claim → secret key)

    /// Runs the entire playit setup natively against api.playit.gg — no browser, no webview.
    /// Signs the user in, generates + claims an agent, exchanges for the permanent secret key,
    /// saves it, and starts the tunnel. Returns `nil` on success, or a user-facing error string.
    ///
    /// CORS does not apply to native URLSession calls, which is why this works where the
    /// embedded WKWebView flow (blocked by api.playit.gg CORS) did not.
    @MainActor
    func setupPlayitViaSignin(email: String,
                              password: String,
                              progress: @escaping (String) -> Void) async -> String? {
        do {
            progress("Signing in…")
            let session = try await PlayitAPI.signin(email: email, password: password)

            // Reuse an existing agent (Scenario A — e.g. adding a voice tunnel later) or claim a
            // new one (Scenario B — first-time setup). Tunnel creation below needs this session
            // regardless: the stored agent secret is read-only and can't create tunnels.
            let agentId: String
            let secret: String
            if let existingSecret = playitSecretKey, let existingAgent = configManager.config.playitAgentId {
                agentId = existingAgent
                secret = existingSecret
                logAppMessage("[Playit] Signed in — reusing existing agent \(agentId).")
            } else {
                progress("Creating tunnel connection…")
                let code = PlayitAPI.generateClaimCode()
                let agentName = "MSC Agent"
                logAppMessage("[Playit] signin OK. claim code: \(code)")

                // Maintain "agent presence" by polling claim/setup continuously in the background
                // (a single setup call leaves the claim in WaitingForAgent). Then details (visit) →
                // accept, retried to absorb state-propagation timing.
                let pollingTask = Task.detached {
                    while !Task.isCancelled {
                        _ = try? await PlayitAPI.claimSetup(code: code)
                        try? await Task.sleep(nanoseconds: 300_000_000)
                    }
                }
                var acceptedAgentId: String?
                for attempt in 1...15 {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    var detailsOK = false
                    do {
                        _ = try await PlayitAPI.claimDetails(code: code, sessionKey: session)
                        detailsOK = true
                    } catch let e as PlayitAPI.APIError {
                        logAppMessage("[Playit] details #\(attempt): \(e.message)")
                    }
                    guard detailsOK else { continue }
                    do {
                        acceptedAgentId = try await PlayitAPI.claimAccept(code: code, name: agentName, sessionKey: session)
                        break
                    } catch let error as PlayitAPI.APIError {
                        logAppMessage("[Playit] accept #\(attempt): \(error.message)")
                    }
                }
                pollingTask.cancel()

                guard let claimedAgent = acceptedAgentId else {
                    return "Couldn't register the tunnel agent with playit.gg. Please try again."
                }

                progress("Finishing setup…")
                var claimedSecret: String?
                for _ in 0..<20 {
                    if let key = try await PlayitAPI.claimExchange(code: code) { claimedSecret = key; break }
                    _ = try? await PlayitAPI.claimSetup(code: code)  // keep the code alive
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                guard let claimedSecret else {
                    return "Timed out waiting for the tunnel to be set up. Please try again."
                }

                savePlayitSecretKey(claimedSecret)
                configManager.config.playitAgentId = claimedAgent
                configManager.save()
                logAppMessage("[Playit] Agent claimed and secret key saved natively (no browser).")
                agentId = claimedAgent
                secret = claimedSecret
            }

            // Ensure the daemon is running so tunnel creation sees an online agent (creation
            // returns AgentVersionTooOld until it connects).
            retryPlayitAfterKeySetup()

            progress("Creating tunnels…")
            var javaPort: Int? = 25565
            var bedrockPort: Int? = 19132
            var voicePort: Int?
            if let server = selectedServer, let cfg = configServer(for: server) {
                javaPort = javaPortForPlayit(for: cfg)
                bedrockPort = bedrockPortForPlayit(for: cfg)
                if VoiceChatConfigManager.isInstalled(serverDir: cfg.serverDir) {
                    voicePort = voicePortForPlayit(for: cfg)
                }
            }
            if let jp = javaPort {
                await createTunnelIfMissing(agentId: agentId, tunnelType: "minecraft-java",
                                            portType: "tcp", localPort: jp, name: "MSC Java",
                                            sessionKey: session, secret: secret, label: "Java")
            }
            if let bp = bedrockPort {
                await createTunnelIfMissing(agentId: agentId, tunnelType: "minecraft-bedrock",
                                            portType: "udp", localPort: bp, name: "MSC Bedrock",
                                            sessionKey: session, secret: secret, label: "Bedrock")
            }
            if let vp = voicePort {
                await createTunnelIfMissing(agentId: agentId, tunnelType: nil,
                                            portType: "udp", localPort: vp, name: PlayitAPI.voiceTunnelName,
                                            sessionKey: session, secret: secret, label: "Voice")
            }

            fetchAndStorePlayitTunnelAddresses()
            return nil
        } catch let error as PlayitAPI.APIError {
            switch error.message {
            case "IncorrectCredentials":
                return "Incorrect email or password."
            case "AccountBanned":
                return "This playit.gg account has been banned."
            case "TotpRequired", "totp_required":
                return "This account uses two-factor authentication, which isn't supported here yet. Use an account without 2FA."
            default:
                logAppMessage("[Playit] Native setup failed: \(error.message)")
                return "Setup failed: \(error.message)"
            }
        } catch {
            logAppMessage("[Playit] Native setup error: \(error.localizedDescription)")
            return "Setup failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Native playit.gg API client
//
// Thin async wrapper over the api.playit.gg endpoints used for agent setup.
// All calls are native URLSession POSTs (JSON in/out), so browser CORS rules
// never apply. Endpoint shapes verified against playit-cloud/playit-agent.

struct PlayitAPI {
    static let base = "https://api.playit.gg"

    /// Reported to playit as the agent software version. Must be a real, recent `playit <semver>`
    /// string or the API rejects tunnel creation with `AgentVersionTooOld`. Matches the bundled
    /// playitd binary version (see PlayitBinaryManager release tag).
    static let agentVersion = "playit 1.0.10"

    /// Name used for the Simple Voice Chat UDP tunnel, so we can find it again in /tunnels/list.
    static let voiceTunnelName = "MSC Voice"

    struct APIError: Error { let message: String }

    /// Generates a claim code the same way the official agent does: 5 random bytes, hex-encoded.
    static func generateClaimCode() -> String {
        (0..<5).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }

    /// POST JSON, returning the decoded top-level object. Optional Authorization header.
    private static func post(_ path: String,
                             body: [String: Any],
                             auth: String?) async throws -> [String: Any] {
        guard let url = URL(string: base + path) else { throw APIError(message: "Bad URL") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let auth { request.setValue(auth, forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError(message: "Unexpected response from playit.gg")
        }
        return json
    }

    /// Extracts the failure reason string from a `{status:fail/error, data:...}` envelope.
    private static func failureReason(_ json: [String: Any]) -> String {
        if let s = json["data"] as? String { return s }
        if let d = json["data"] as? [String: Any] {
            if let m = d["message"] as? String { return m }
            if let t = d["type"] as? String { return t }
            return String(describing: d)
        }
        return String(describing: json["data"] ?? json)
    }

    /// POST /login/signin → returns the web session key.
    static func signin(email: String, password: String) async throws -> String {
        let json = try await post("/login/signin",
                                  body: ["email": email, "password": password],
                                  auth: nil)
        if json["status"] as? String == "success",
           let data = json["data"] as? [String: Any],
           let key = data["session_key"] as? String {
            return key
        }
        throw APIError(message: failureReason(json))
    }

    /// POST /claim/setup (no auth) → registers/refreshes the claim code. Returns its status string.
    @discardableResult
    static func claimSetup(code: String) async throws -> String {
        let json = try await post("/claim/setup",
                                  body: ["code": code, "agent_type": "assignable", "version": agentVersion],
                                  auth: nil)
        return (json["data"] as? String) ?? "unknown"
    }

    /// POSTs a session-authenticated call. The `/login/signin` session key is returned in
    /// the response body (there is NO session cookie — verified live), and is sent as an
    /// Authorization header. The exact scheme isn't documented, so we try the known formats
    /// and use the first that gets past authentication (success OR a non-auth failure).
    /// Returns the parsed JSON of that response; throws only if every format fails auth.
    private static func postWithSession(_ path: String,
                                        body: [String: Any],
                                        sessionKey: String) async throws -> [String: Any] {
        let attempts: [(label: String, auth: String)] = [
            ("session", "session \(sessionKey)"),
            ("agent-key", "agent-key \(sessionKey)"),
            ("bearer", "Bearer \(sessionKey)"),
            ("raw", sessionKey),
        ]
        var lastReason = "AuthRequired"
        for attempt in attempts {
            let json = try await post(path, body: body, auth: attempt.auth)
            // An auth-type error means this format is wrong — try the next one.
            if let d = json["data"] as? [String: Any], d["type"] as? String == "auth" {
                lastReason = (d["message"] as? String) ?? "AuthRequired"
                continue
            }
            NSLog("[PlayitAPI] \(path) authenticated via: \(attempt.label)")
            return json
        }
        throw APIError(message: lastReason)
    }

    /// POST /claim/accept (session auth) → approves the agent. Returns agent id.
    @discardableResult
    static func claimAccept(code: String, name: String, sessionKey: String) async throws -> String {
        let json = try await postWithSession("/claim/accept",
                                             body: ["code": code, "name": name, "agent_type": "assignable"],
                                             sessionKey: sessionKey)
        if json["status"] as? String == "success",
           let data = json["data"] as? [String: Any],
           let agentId = data["agent_id"] as? String {
            return agentId
        }
        throw APIError(message: failureReason(json))
    }

    /// POST /claim/details (session auth) → the "visit" step. Loading the claim transitions
    /// it from WaitingForUserVisit → WaitingForUser so accept can find it. Returns status.
    @discardableResult
    static func claimDetails(code: String, sessionKey: String) async throws -> String {
        let json = try await postWithSession("/claim/details",
                                             body: ["code": code],
                                             sessionKey: sessionKey)
        if json["status"] as? String == "success" { return "ok" }
        throw APIError(message: failureReason(json))
    }

    /// Creates a tunnel on the agent. Requires a **web session** (the agent secret is read-only
    /// and the API rejects creation with `NotAllowedWithReadOnly`). Uses the free "global" region.
    /// Enums are internally tagged (type/data, type/details).
    /// Pass `tunnelType: nil` for a custom (non-Minecraft) tunnel, e.g. the UDP voice tunnel.
    @discardableResult
    static func createTunnel(agentId: String,
                             tunnelType: String?,
                             portType: String,
                             localPort: Int,
                             name: String,
                             sessionKey: String) async throws -> String {
        let path: String
        let body: [String: Any]
        if let tunnelType {
            // Known Minecraft tunnel — legacy /tunnels/create schema (verified for Java/Bedrock).
            path = "/tunnels/create"
            body = [
                "name": name,
                "tunnel_type": tunnelType,
                "port_type": portType,
                "port_count": 1,
                "enabled": true,
                "origin": [
                    "type": "agent",
                    "data": ["agent_id": agentId, "local_ip": "127.0.0.1", "local_port": localPort]
                ],
                "alloc": ["type": "region", "details": ["region": "global"]]
            ]
        } else {
            // Custom tunnel (voice) — current /v1/tunnels/create schema captured from the web.
            // software_description "simple voice chat" selects playit's free MC: Simple Voice Chat
            // preset (generic custom UDP is premium-only).
            path = "/v1/tunnels/create"
            body = [
                "name": name,
                "enabled": true,
                "protocol": [
                    "type": "raw-ports",
                    "details": ["port_type": portType, "port_count": 1, "software_description": "simple voice chat"]
                ],
                "endpoint": ["type": "region", "details": ["region": "global", "port": NSNull()]],
                "origin": [
                    "type": "agent",
                    "data": [
                        "agent_id": agentId,
                        "config": ["fields": [
                            ["name": "local_ip", "value": "127.0.0.1"],
                            ["name": "local_port", "value": String(localPort)]
                        ]]
                    ]
                ]
            ]
        }

        let json = try await postWithSession(path, body: body, sessionKey: sessionKey)
        if json["status"] as? String == "success",
           let data = json["data"] as? [String: Any],
           let id = data["id"] as? String {
            return id
        }
        throw APIError(message: failureReason(json))
    }

    /// POST /tunnels/list (agent-key auth) → true if a tunnel with the given name already exists.
    /// Used to avoid creating duplicate voice tunnels on every server start.
    static func tunnelExists(named name: String, secret: String) async -> Bool {
        let json = try? await post("/tunnels/list", body: ["agent_id": NSNull()], auth: "agent-key \(secret)")
        guard let json,
              json["status"] as? String == "success",
              let data = json["data"] as? [String: Any],
              let tunnels = data["tunnels"] as? [[String: Any]] else { return false }
        return tunnels.contains { ($0["name"] as? String) == name }
    }

    /// POST /claim/exchange (no auth) → returns the permanent secret key once accepted, else nil.
    static func claimExchange(code: String) async throws -> String? {
        let json = try await post("/claim/exchange", body: ["code": code], auth: nil)
        if json["status"] as? String == "success",
           let data = json["data"] as? [String: Any],
           let key = data["secret_key"] as? String {
            return key
        }
        return nil
    }
}

// MARK: - Simple Voice Chat config patcher
//
// Surgically sets voice_host / bind_address / port in voicechat-server.properties so SVC
// clients connect through the playit UDP tunnel. Mirrors BroadcastConfigManager's approach:
// patch the keys we own, preserve everything else.

struct VoiceChatConfigManager {

    /// Whether the Simple Voice Chat plugin/mod is installed, by scanning for its jar in
    /// `plugins/` (Paper/Spigot) or `mods/` (Fabric/Forge/NeoForge). We check the jar rather than
    /// the `voicechat/` config folder because MSC itself may create that folder when patching.
    static func isInstalled(serverDir: String) -> Bool {
        let root = URL(fileURLWithPath: serverDir, isDirectory: true)
        let fm = FileManager.default
        for sub in ["plugins", "mods"] {
            let dir = root.appendingPathComponent(sub).path
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            if items.contains(where: {
                let n = $0.lowercased()
                return n.hasSuffix(".jar") && (n.contains("voicechat") || n.contains("voice-chat"))
            }) {
                return true
            }
        }
        return false
    }

    /// Locates voicechat-server.properties under the server directory. Paper/Spigot keep it in
    /// `plugins/voicechat/`, Fabric/Forge/NeoForge in `config/voicechat/`. Returns the existing
    /// file, or (when `createIfMissing`) a path in the loader-appropriate folder.
    static func propertiesURL(serverDir: String, createIfMissing: Bool) -> URL? {
        let root = URL(fileURLWithPath: serverDir, isDirectory: true)
        let pluginsPath = root.appendingPathComponent("plugins/voicechat/voicechat-server.properties")
        let configPath  = root.appendingPathComponent("config/voicechat/voicechat-server.properties")
        let fm = FileManager.default

        if fm.fileExists(atPath: pluginsPath.path) { return pluginsPath }
        if fm.fileExists(atPath: configPath.path) { return configPath }
        guard createIfMissing else { return nil }

        // No file yet — pick the folder that matches the server layout.
        let hasPlugins = fm.fileExists(atPath: root.appendingPathComponent("plugins").path)
        let hasMods    = fm.fileExists(atPath: root.appendingPathComponent("mods").path)
        return (hasPlugins && !hasMods) ? pluginsPath : configPath
    }

    /// Sets `voice_host`, `bind_address=*`, and `port` in the properties file, preserving all
    /// other lines. Creates the file (and parent dir) if it doesn't exist yet. Returns the URL
    /// written, or nil on failure.
    @discardableResult
    static func applyVoiceHost(serverDir: String, voiceHost: String, localPort: Int) -> URL? {
        guard let url = propertiesURL(serverDir: serverDir, createIfMissing: true) else { return nil }
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let desired: [String: String] = [
            "voice_host": voiceHost,
            "bind_address": "*",
            "port": String(localPort),
        ]

        var lines = existing.isEmpty ? [] : existing.components(separatedBy: .newlines)
        for (key, value) in desired {
            let newLine = "\(key)=\(value)"
            if let idx = lines.firstIndex(where: {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("\(key)=")
            }) {
                lines[idx] = newLine
            } else {
                lines.append(newLine)
            }
        }
        let out = lines.joined(separator: "\n")
        do {
            try out.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}

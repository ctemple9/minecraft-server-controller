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
                let (java, bedrock) = try await Self.fetchPlayitTunnelAddresses(secretKey: secret)
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
                    if changed {
                        self.configManager.save()
                        self.logAppMessage("[Playit] Tunnel addresses updated — Java: \(java ?? "—"), Bedrock: \(bedrock ?? "—")")
                        if self.isXboxBroadcastRunning,
                           let server = self.selectedServer,
                           let cfg = self.configServer(for: server) {
                            self.stopBroadcastIfRunning()
                            self.startBroadcastIfNeeded(for: cfg)
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.logAppMessage("[Playit] Could not fetch tunnel addresses: \(error.localizedDescription)")
                }
            }
        }
    }

    private static func fetchPlayitTunnelAddresses(secretKey: String) async throws -> (java: String?, bedrock: String?) {
        guard let url = URL(string: "https://api.playit.gg/tunnels/list") else { return (nil, nil) }
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
            return (nil, nil)
        }

        var javaAddress: String? = nil
        var bedrockAddress: String? = nil

        for tunnel in tunnels {
            guard let active = tunnel["active"] as? Bool, active else { continue }
            let tunnelType = tunnel["tunnel_type"] as? String ?? ""
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
            }
        }
        return (javaAddress, bedrockAddress)
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

    // MARK: - Persist settings

    func setPlayitEnabled(_ enabled: Bool, voiceChat: Bool? = nil, for serverId: String) {
        guard let idx = configManager.config.servers.firstIndex(where: { $0.id == serverId }) else { return }
        configManager.config.servers[idx].playitEnabled = enabled
        if let vc = voiceChat {
            configManager.config.servers[idx].playitVoiceChatEnabled = vc
        }
        configManager.save()
        logAppMessage("[Playit] Tunnel \(enabled ? "enabled" : "disabled") for server.")
    }
}

//
//  AppViewModel+APIWiring.swift
//  MSCmacOS
//
//  M1 (flowstate): Decomposition of AppViewModel.init's Remote API provider wiring.
//
//  The additive Remote API providers used to be assigned in TWO places inside
//  AppViewModel.init — once on the reused `shared` server and once on the freshly
//  constructed `api` server — and the two blocks had to be kept byte-for-byte in sync
//  by discipline alone (the "two-place invariant", flowstate §1.5). This umbrella method
//  assigns every additive provider onto a single `server` parameter, so BOTH branches
//  call the same code. The invariant is now enforced by the compiler, not by convention.
//
//  Core providers (tokenProvider … logger) remain built as locals in init because they
//  are passed as constructor / updateProviders arguments, which differ between the two
//  branches (reuse vs. construct). Only the *additive* providers live here.
//
//  Each domain is a `wire<Domain>Providers(into:)` helper in its own file; this file holds
//  the umbrella that calls them all. Behavior is identical to the previous inline wiring —
//  this is pure structural extraction.
//

import Foundation

extension AppViewModel {

    /// Assigns every additive Remote API provider onto `server`. Called from BOTH wiring
    /// branches in `init` (the reused `shared` server and the fresh `api` server).
    /// `isoFmt` is threaded through for the providers that format timestamps.
    func wireProviders(into server: RemoteAPIServer, isoFmt: ISO8601DateFormatter) {
        wireInfraProviders(into: server)
    }

    // MARK: - Infra (watchdog, connectivity, playit, DuckDNS, Geyser)

    /// Watchdog control, connectivity snapshot, playit.gg agent control, and the
    /// DuckDNS / Geyser configuration providers. All operate on main-actor state via the
    /// `await MainActor.run` bridging pattern (A3-standardized already).
    func wireInfraProviders(into server: RemoteAPIServer) {
        server.watchdogStatusProvider  = { [weak self] in self?.watchdogEnabled ?? false }
        server.enableWatchdogProvider  = { [weak self] in self?.enableWatchdogSync() }
        server.disableWatchdogProvider = { [weak self] in self?.disableWatchdogSync() }

        server.connectivityProvider = { [weak self] in
            await self?.connectivitySnapshot()
                ?? RemoteAPIServer.ConnectivityResponseDTO(serverType: "java", status: "unknown", severity: "gray", headline: "Connectivity unavailable", note: "not_available")
        }

        server.playitStatusProvider = { [weak self] in
            await MainActor.run { [weak self] in
                guard let self else { return RemoteAPIServer.PlayitStatusResponseDTO(serverName: "", serverType: "java", playitEnabled: false, isRunning: false, hasSecretKey: false, note: "no_server") }
                let cfg = self.selectedServer.flatMap { self.configServer(for: $0) }
                return RemoteAPIServer.PlayitStatusResponseDTO(
                    serverName: cfg?.displayName ?? "",
                    serverType: cfg?.isBedrock == true ? "bedrock" : "java",
                    playitEnabled: cfg?.playitEnabled ?? false,
                    isRunning: self.isPlayitRunning,
                    hasSecretKey: self.playitSecretKey != nil,
                    javaAddress: self.configManager.config.playitJavaAddress,
                    bedrockAddress: self.configManager.config.playitBedrockAddress,
                    voiceAddress: self.configManager.config.playitVoiceAddress,
                    voiceChatEnabled: cfg?.playitVoiceChatEnabled ?? false,
                    note: cfg == nil ? "no_server" : nil
                )
            }
        }
        server.startPlayitProvider = { [weak self] in
            await MainActor.run { [weak self] in
                guard let self else { return RemoteAPIServer.PlayitActionResultDTO(result: "no_server") }
                guard let server = self.selectedServer, let cfg = self.configServer(for: server) else {
                    return RemoteAPIServer.PlayitActionResultDTO(result: "no_server")
                }
                guard cfg.playitEnabled else { return RemoteAPIServer.PlayitActionResultDTO(result: "not_enabled") }
                guard self.playitSecretKey != nil else { return RemoteAPIServer.PlayitActionResultDTO(result: "no_secret_key") }
                guard !self.isPlayitRunning else { return RemoteAPIServer.PlayitActionResultDTO(result: "already_running") }
                self.startPlayitIfNeeded(for: cfg)
                return RemoteAPIServer.PlayitActionResultDTO(result: "started")
            }
        }
        server.stopPlayitProvider = { [weak self] in
            await MainActor.run { [weak self] in
                guard let self else { return RemoteAPIServer.PlayitActionResultDTO(result: "no_server") }
                guard self.isPlayitRunning || self.playitAgentManager.isRunning else {
                    return RemoteAPIServer.PlayitActionResultDTO(result: "not_running")
                }
                self.stopPlayitIfRunning()
                return RemoteAPIServer.PlayitActionResultDTO(result: "stopped")
            }
        }
        // DuckDNS (P13)
        server.duckdnsStatusProvider = { [weak self] in
            await MainActor.run { [weak self] in
                guard let self else { return RemoteAPIServer.DuckDNSStatusResponseDTO() }
                return RemoteAPIServer.DuckDNSStatusResponseDTO(hostname: self.configManager.config.duckdnsHostname)
            }
        }
        server.updateDuckDNSProvider = { [weak self] hostname in
            await MainActor.run { [weak self] in
                guard let self else { return RemoteAPIServer.DuckDNSUpdateResultDTO(success: false, message: "no_server") }
                self.duckdnsInput = hostname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                self.saveDuckDNSHostname()
                return RemoteAPIServer.DuckDNSUpdateResultDTO(success: true, hostname: self.configManager.config.duckdnsHostname)
            }
        }
        // Geyser config (P13)
        server.geyserConfigProvider = { [weak self] in
            await MainActor.run { [weak self] in
                guard let self else { return RemoteAPIServer.GeyserConfigResponseDTO(note: "no_server") }
                guard let server = self.selectedServer else {
                    return RemoteAPIServer.GeyserConfigResponseDTO(note: "no_server")
                }
                let serverURL = URL(fileURLWithPath: server.directory, isDirectory: true)
                let isInstalled = GeyserConfigManager().isGeyserInstalled(serverPath: serverURL)
                let config = GeyserConfigManager.readConfig(serverDir: server.directory)
                let cfgFileExists = FileManager.default.fileExists(atPath: GeyserConfigManager.configURL(for: server.directory).path)
                let cfg = self.configServer(for: server)
                return RemoteAPIServer.GeyserConfigResponseDTO(
                    serverName: cfg?.displayName ?? server.name,
                    serverType: cfg?.isBedrock == true ? "bedrock" : "java",
                    isGeyserInstalled: isInstalled,
                    address: config?.address,
                    port: config?.port,
                    configFileExists: cfgFileExists
                )
            }
        }
        server.updateGeyserConfigProvider = { [weak self] address, port in
            await MainActor.run { [weak self] in
                guard let self else { return RemoteAPIServer.GeyserConfigUpdateResultDTO(success: false, message: "no_server") }
                guard let server = self.selectedServer else {
                    return RemoteAPIServer.GeyserConfigUpdateResultDTO(success: false, message: "no_server")
                }
                let serverURL = URL(fileURLWithPath: server.directory, isDirectory: true)
                guard GeyserConfigManager().isGeyserInstalled(serverPath: serverURL) else {
                    return RemoteAPIServer.GeyserConfigUpdateResultDTO(success: false, message: "not_installed")
                }
                self.loadGeyserConfig()
                if let addr = address?.trimmingCharacters(in: .whitespacesAndNewlines), !addr.isEmpty {
                    self.geyserAddress = addr
                }
                if let p = port { self.geyserPort = String(p) }
                self.saveGeyserConfig()
                let updated = GeyserConfigManager.readConfig(serverDir: server.directory)
                return RemoteAPIServer.GeyserConfigUpdateResultDTO(
                    success: true,
                    message: "updated",
                    address: updated?.address,
                    port: updated?.port
                )
            }
        }
    }
}

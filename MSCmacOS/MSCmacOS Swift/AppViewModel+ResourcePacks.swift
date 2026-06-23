// AppViewModel+ResourcePacks.swift
// MinecraftServerController
//
//
// AppViewModel extension for loading, installing, removing, and activating
// resource packs for the selected server.
//
// Delivery paths (see ResourcePackManager / ResourcePackHostServer):
//   • Java players      → resource-packs/<zip> hosted over HTTP; URL written to server.properties.
//   • Bedrock players   → Geyser packs/ folder (.mcpack), served in-band by Geyser. Covers XboxBroadcast joiners.
//   • Standalone BDS    → resource_packs/ + valid_known_packs.json (unchanged).

import Foundation
import UniformTypeIdentifiers
import AppKit   // NSOpenPanel

extension AppViewModel {

    // MARK: - Load

    /// Reload the resource pack list(s) for the currently selected server.
    func loadResourcePacksForSelectedServer() {
        guard let server = selectedServer,
              let cfg = configServer(for: server) else {
            installedResourcePacks = []
            geyserResourcePacks = []
            isGeyserAvailable = false
            return
        }

        isLoadingResourcePacks = true
        let serverDir = cfg.serverDir
        let isJava = cfg.isJava

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let packs = isJava
                ? ResourcePackManager.listJavaPacks(serverDir: serverDir)
                : ResourcePackManager.listBedrockPacks(serverDir: serverDir)

            // Geyser packs only apply to Java servers running Geyser.
            let geyserAvailable = isJava && ResourcePackManager.isGeyserInstalled(serverDir: serverDir)
            let geyserPacks = geyserAvailable
                ? ResourcePackManager.listGeyserPacks(serverDir: serverDir)
                : []

            DispatchQueue.main.async {
                self.installedResourcePacks = packs
                self.geyserResourcePacks = geyserPacks
                self.isGeyserAvailable = geyserAvailable
                self.isLoadingResourcePacks = false

                // Keep the host server in sync with whatever pack is marked active.
                if isJava, let active = packs.first(where: { $0.isActive }) {
                    self.ensureResourcePackHostRunning(activePack: active, cfg: cfg)
                }
            }
        }
    }

    // MARK: - Install (file picker)

    func presentResourcePackPicker() {
        guard let server = selectedServer,
              let cfg = configServer(for: server) else { return }

        let panel = NSOpenPanel()
        panel.title = cfg.isJava ? "Add Resource Pack (.zip)" : "Add Resource Pack (.mcpack / .zip)"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = cfg.isJava
            ? [UTType.zip]
            : [UTType(filenameExtension: "mcpack") ?? .data, .zip]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        installResourcePack(from: url, for: cfg)
    }

    /// Picker for adding a Bedrock pack to Geyser (Java servers with Geyser installed).
    func presentGeyserPackPicker() {
        guard let server = selectedServer,
              let cfg = configServer(for: server), cfg.isJava else { return }

        let panel = NSOpenPanel()
        panel.title = "Add Bedrock Pack for Geyser (.mcpack / .zip)"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType(filenameExtension: "mcpack") ?? .data, .zip]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        installGeyserPack(from: url, for: cfg)
    }

    // MARK: - Install (drag-and-drop or programmatic)

    func installResourcePack(from sourceURL: URL, for cfg: ConfigServer) {
        isLoadingResourcePacks = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                if cfg.isJava {
                    let ext = sourceURL.pathExtension.lowercased()
                    guard ext == "zip" else {
                        DispatchQueue.main.async {
                            self.isLoadingResourcePacks = false
                            self.showError(title: "Unsupported File", message: "Java resource packs must be .zip files.")
                        }
                        return
                    }
                    _ = try ResourcePackManager.installJavaPack(from: sourceURL, serverDir: cfg.serverDir)
                    DispatchQueue.main.async {
                        self.logAppMessage("[ResourcePacks] Installed Java pack: \(sourceURL.lastPathComponent) for \(cfg.displayName).")
                        self.loadResourcePacksForSelectedServer()
                    }
                } else {
                    _ = try ResourcePackManager.installBedrockPack(from: sourceURL, serverDir: cfg.serverDir)
                    DispatchQueue.main.async {
                        self.logAppMessage("[ResourcePacks] Installed Bedrock pack: \(sourceURL.lastPathComponent) for \(cfg.displayName).")
                        self.loadResourcePacksForSelectedServer()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoadingResourcePacks = false
                    self.logAppMessage("[ResourcePacks] Failed to install pack: \(error.localizedDescription)")
                    self.showError(title: "Pack Install Failed", message: error.localizedDescription)
                }
            }
        }
    }

    func installGeyserPack(from sourceURL: URL, for cfg: ConfigServer) {
        isLoadingResourcePacks = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                _ = try ResourcePackManager.installGeyserPack(from: sourceURL, serverDir: cfg.serverDir)
                DispatchQueue.main.async {
                    self.logAppMessage("[ResourcePacks] Added Geyser (Bedrock) pack: \(sourceURL.lastPathComponent) for \(cfg.displayName). Restart the server for Geyser to load it.")
                    self.loadResourcePacksForSelectedServer()
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoadingResourcePacks = false
                    self.showError(title: "Pack Install Failed", message: error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Remove

    func removeResourcePack(_ pack: InstalledResourcePack) {
        guard let server = selectedServer,
              let cfg = configServer(for: server) else { return }
        do {
            try ResourcePackManager.removePack(pack, serverDir: cfg.serverDir, isJava: cfg.isJava)
            logAppMessage("[ResourcePacks] Removed pack \(pack.fileName) from \(cfg.displayName).")
            // If we just removed the active Java pack, no pack is hosted anymore.
            if cfg.isJava && pack.isActive { resourcePackHostServer.stop() }
            loadResourcePacksForSelectedServer()
        } catch {
            logAppMessage("[ResourcePacks] Failed to remove pack \(pack.fileName): \(error.localizedDescription)")
            showError(title: "Pack Remove Failed", message: error.localizedDescription)
        }
    }

    func removeGeyserPack(_ pack: InstalledResourcePack) {
        guard let server = selectedServer,
              let cfg = configServer(for: server) else { return }
        do {
            try ResourcePackManager.removeGeyserPack(pack, serverDir: cfg.serverDir)
            logAppMessage("[ResourcePacks] Removed Geyser pack \(pack.fileName) from \(cfg.displayName).")
            loadResourcePacksForSelectedServer()
        } catch {
            showError(title: "Pack Remove Failed", message: error.localizedDescription)
        }
    }

    // MARK: - Java: activate / toggle a hosted pack

    /// Toggle a Java pack on/off. Turning one on makes it the single active server pack
    /// (Java's server.properties holds one), starts the HTTP host, and writes URL + SHA1.
    func setJavaPackActive(_ pack: InstalledResourcePack, active: Bool) {
        guard let server = selectedServer,
              let cfg = configServer(for: server), cfg.isJava else { return }
        let serverDir = cfg.serverDir

        if !active {
            do {
                try ResourcePackManager.setJavaActivePack(url: nil, sha1: nil, require: false, serverDir: serverDir)
                resourcePackHostServer.stop()
                logAppMessage("[ResourcePacks] Disabled Java resource pack for \(cfg.displayName).")
                loadResourcePacksForSelectedServer()
            } catch {
                showError(title: "Settings Save Failed", message: error.localizedDescription)
            }
            return
        }

        guard let host = resourcePackHostAddress(), !host.isEmpty else {
            showError(
                title: "No Address to Host From",
                message: "Set a DuckDNS hostname (or wait for your public IP to be detected) before enabling a Java resource pack. Clients need a reachable address to download it from."
            )
            return
        }

        isLoadingResourcePacks = true
        let port = cfg.resourcePackHostPort
        let fileName = pack.fileName
        let fileURL = pack.fileURL

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let sha1 = ResourcePackManager.sha1Hex(of: fileURL)
            let encoded = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName
            let url = "http://\(host):\(port)/\(encoded)"

            DispatchQueue.main.async {
                let dir = ResourcePackManager.javaPacksDirectory(serverDir: serverDir)
                let started = self.resourcePackHostServer.start(directory: dir, port: UInt16(port))
                do {
                    try ResourcePackManager.setJavaActivePack(url: url, sha1: sha1, require: true, serverDir: serverDir)
                    self.logAppMessage("[ResourcePacks] Hosting \(fileName) at \(url)\(started ? "" : " — WARNING: host server failed to start"). Players apply it on next join.")
                    self.loadResourcePacksForSelectedServer()
                } catch {
                    self.isLoadingResourcePacks = false
                    self.showError(title: "Settings Save Failed", message: error.localizedDescription)
                }
            }
        }
    }

    /// Backwards-compatible entry point used by the older ResourcePacksView.
    /// Pass nil to clear the active pack.
    func setJavaActivePack(_ pack: InstalledResourcePack?) {
        if let pack {
            setJavaPackActive(pack, active: true)
        } else if let active = installedResourcePacks.first(where: { $0.isActive }) {
            setJavaPackActive(active, active: false)
        } else {
            // Nothing active — just make sure properties are clean.
            guard let server = selectedServer, let cfg = configServer(for: server), cfg.isJava else { return }
            try? ResourcePackManager.setJavaActivePack(url: nil, sha1: nil, require: false, serverDir: cfg.serverDir)
            resourcePackHostServer.stop()
            loadResourcePacksForSelectedServer()
        }
    }

    // MARK: - Geyser: enable / disable

    func setGeyserPackEnabled(_ pack: InstalledResourcePack, enabled: Bool) {
        guard let server = selectedServer,
              let cfg = configServer(for: server) else { return }
        do {
            try ResourcePackManager.setGeyserPackEnabled(pack, enabled: enabled, serverDir: cfg.serverDir)
            logAppMessage("[ResourcePacks] \(enabled ? "Enabled" : "Disabled") Geyser pack \(pack.fileName). Restart the server for Geyser to apply the change.")
            loadResourcePacksForSelectedServer()
        } catch {
            showError(title: "Pack Update Failed", message: error.localizedDescription)
        }
    }

    // MARK: - Hosting helpers

    /// The public-facing address Java clients use to download the pack: DuckDNS if set, else public IP.
    func resourcePackHostAddress() -> String? {
        let duck = duckdnsInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !duck.isEmpty { return duck }
        return cachedPublicIPAddress
    }

    /// Ensure the host server is serving the packs folder on the configured port.
    private func ensureResourcePackHostRunning(activePack: InstalledResourcePack, cfg: ConfigServer) {
        let dir = ResourcePackManager.javaPacksDirectory(serverDir: cfg.serverDir)
        if !resourcePackHostServer.isRunning || resourcePackHostServer.boundPort != UInt16(cfg.resourcePackHostPort) {
            resourcePackHostServer.start(directory: dir, port: UInt16(cfg.resourcePackHostPort))
        }
    }

    /// Called when a server starts: if a Java pack is active, host it so joining clients can fetch it.
    func startResourcePackHostIfNeeded(for cfg: ConfigServer) {
        guard cfg.isJava else { return }
        let packs = ResourcePackManager.listJavaPacks(serverDir: cfg.serverDir)
        guard let active = packs.first(where: { $0.isActive }) else { return }
        ensureResourcePackHostRunning(activePack: active, cfg: cfg)
    }
}

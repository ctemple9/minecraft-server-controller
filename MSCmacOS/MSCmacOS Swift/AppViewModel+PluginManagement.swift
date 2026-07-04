//
//  AppViewModel+PluginManagement.swift
//  MinecraftServerController
//
//  Plugin enable/disable, source URL management, and generic plugin downloads.
//

import Foundation
import AppKit
import UniformTypeIdentifiers

extension AppViewModel {

    // MARK: - Modrinth add-on install (M5)

    /// Installs the latest compatible version of a Modrinth add-on into the given
    /// server's add-on folder (`plugins/` or `mods/`). Returns the result so the
    /// browser can show success/failure.
    @discardableResult
    func installModrinthAddon(_ hit: ModrinthSearchHit, into cfg: ConfigServer) async -> (ok: Bool, message: String) {
        guard let addOn = cfg.javaFlavor.addOnKind else {
            return (false, "\(cfg.displayName) doesn't support add-ons.")
        }
        let loaders = cfg.javaFlavor.modrinthLoaderFacets
        do {
            let versions = try await ModrinthAPI.projectVersions(
                idOrSlug: hit.slug, loaders: loaders, gameVersion: cfg.minecraftVersion)
            guard let best = versions.first, let file = best.primaryFile else {
                let v = cfg.minecraftVersion ?? "this version"
                return (false, "No \(addOn.displayName.lowercased()) version of \(hit.title) for \(v).")
            }
            let folder = URL(fileURLWithPath: cfg.serverDir).appendingPathComponent(addOn.folderName, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let dest = folder.appendingPathComponent(file.filename)
            try await ModrinthAPI.downloadVersionFile(best, to: dest)
            logAppMessage("[Modrinth] Installed \(hit.title) \(best.versionNumber) → \(addOn.folderName)/\(file.filename)")
            await installRequiredDependencies(of: best, into: cfg)
            if addOn == .plugin { refreshDiscoveredPlugins() } else { refreshDiscoveredMods() }
            invalidateAddonPlan()
            return (true, "Added \(hit.title) \(best.versionNumber)")
        } catch {
            logAppMessage("[Modrinth] Failed to install \(hit.title): \(error.localizedDescription)")
            return (false, error.localizedDescription)
        }
    }

    /// Installs a specific Modrinth version (chosen from the detail page) into the
    /// server's add-on folder. Used for "install this exact version".
    @discardableResult
    func installModrinthVersion(_ version: ModrinthVersionInfo, title: String, into cfg: ConfigServer) async -> (ok: Bool, message: String) {
        guard let addOn = cfg.javaFlavor.addOnKind else {
            return (false, "\(cfg.displayName) doesn't support add-ons.")
        }
        guard let file = version.primaryFile else {
            return (false, "That version of \(title) has no downloadable file.")
        }
        do {
            let folder = URL(fileURLWithPath: cfg.serverDir).appendingPathComponent(addOn.folderName, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let dest = folder.appendingPathComponent(file.filename)
            try await ModrinthAPI.downloadVersionFile(version, to: dest)
            logAppMessage("[Modrinth] Installed \(title) \(version.versionNumber) → \(addOn.folderName)/\(file.filename)")
            await installRequiredDependencies(of: version, into: cfg)
            if addOn == .plugin { refreshDiscoveredPlugins() } else { refreshDiscoveredMods() }
            invalidateAddonPlan()
            return (true, "Added \(title) \(version.versionNumber)")
        } catch {
            logAppMessage("[Modrinth] Failed to install \(title) \(version.versionNumber): \(error.localizedDescription)")
            return (false, error.localizedDescription)
        }
    }

    // MARK: - Add plugin from file picker

    /// Opens an NSOpenPanel filtered to .jar files and copies the chosen JAR into
    /// the selected server's plugins folder, then refreshes the plugin list.
    func addPluginFromFilePicker() {
        guard let cfg = selectedServerConfig else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.init(filenameExtension: "jar")!]
        panel.prompt = "Add Plugin"
        panel.message = "Choose a plugin JAR to add to this server."

        guard panel.runModal() == .OK, let srcURL = panel.url else { return }

        let serverDirURL = URL(fileURLWithPath: cfg.serverDir, isDirectory: true)
        let pluginsDir   = serverDirURL.appendingPathComponent("plugins", isDirectory: true)
        let destURL      = pluginsDir.appendingPathComponent(srcURL.lastPathComponent)

        do {
            let fm = FileManager.default
            try fm.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
            if fm.fileExists(atPath: destURL.path) {
                try fm.removeItem(at: destURL)
            }
            try fm.copyItem(at: srcURL, to: destURL)
            logAppMessage("[Plugins] Added \(srcURL.lastPathComponent) to plugins folder.")
            refreshDiscoveredPlugins()
            invalidateAddonPlan()
        } catch {
            logAppMessage("[Plugins] Failed to add plugin: \(error.localizedDescription)")
        }
    }

    // MARK: - Enable / Disable

    /// Toggles a plugin between enabled (.jar) and disabled (.jar.disabled) by renaming on disk.
    func togglePlugin(jarStem: String) {
        guard let cfg = selectedServerConfig else { return }
        guard let entry = discoveredPlugins.first(where: { $0.jarStem == jarStem }) else { return }

        let serverDirURL = URL(fileURLWithPath: cfg.serverDir, isDirectory: true)
        let pluginsDir   = serverDirURL.appendingPathComponent("plugins", isDirectory: true)
        let currentURL   = pluginsDir.appendingPathComponent(entry.filename)

        let newFilename: String
        if entry.isEnabled {
            newFilename = entry.filename + ".disabled"
        } else {
            // Strip the trailing .disabled
            newFilename = String(entry.filename.dropLast(".disabled".count))
        }

        let newURL = pluginsDir.appendingPathComponent(newFilename)

        do {
            try FileManager.default.moveItem(at: currentURL, to: newURL)
            logAppMessage("[Plugins] \(entry.isEnabled ? "Disabled" : "Enabled") \(entry.displayName).")
            // SVC just disabled → clear saved SVC prompt prefs so they re-evaluate
            if entry.isEnabled && isSVCJar(entry.filename) {
                clearSVCPromptPrefs(for: cfg.id)
            }
            refreshDiscoveredPlugins()
            checkSVCTunnelMismatch()
        } catch {
            logAppMessage("[Plugins] Failed to toggle \(entry.displayName): \(error.localizedDescription)")
        }
    }

    /// Permanently deletes a plugin JAR from the plugins/ folder.
    func removePlugin(jarStem: String) {
        guard let cfg = selectedServerConfig else { return }
        guard let entry = discoveredPlugins.first(where: { $0.jarStem == jarStem }) else { return }

        let pluginsDir = URL(fileURLWithPath: cfg.serverDir, isDirectory: true)
            .appendingPathComponent("plugins", isDirectory: true)
        let url = pluginsDir.appendingPathComponent(entry.filename)

        do {
            try FileManager.default.removeItem(at: url)
            logAppMessage("[Plugins] Removed \(entry.displayName).")
            if isSVCJar(entry.filename) {
                clearSVCPromptPrefs(for: cfg.id)
            }
            refreshDiscoveredPlugins()
            invalidateAddonPlan()
            checkSVCTunnelMismatch()
        } catch {
            logAppMessage("[Plugins] Failed to remove \(entry.displayName): \(error.localizedDescription)")
        }
    }

    private func isSVCJar(_ filename: String) -> Bool {
        let n = filename.lowercased()
        return n.contains("voicechat") || n.contains("voice-chat")
    }

    // MARK: - SVC alert actions (called from ContentView alert handlers)

    /// Disables the SVC plugin for the given server (Flow 1 "Disable Voice Chat" action).
    /// Performs the rename directly so it works regardless of which server is currently selected.
    func disableSVCPlugin(for serverId: String) {
        guard let cfg = configManager.config.servers.first(where: { $0.id == serverId }) else { return }
        let pluginsDir = URL(fileURLWithPath: cfg.serverDir, isDirectory: true)
            .appendingPathComponent("plugins", isDirectory: true)
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: pluginsDir.path) else { return }
        guard let svcFilename = items.first(where: {
            let n = $0.lowercased()
            return n.hasSuffix(".jar") && isSVCJar(n)
        }) else { return }
        let src = pluginsDir.appendingPathComponent(svcFilename)
        let dst = pluginsDir.appendingPathComponent(svcFilename + ".disabled")
        do {
            try FileManager.default.moveItem(at: src, to: dst)
            logAppMessage("[Plugins] Disabled Simple Voice Chat (SVC tunnel mismatch resolution).")
            clearSVCPromptPrefs(for: serverId)
            refreshDiscoveredPlugins()
        } catch {
            logAppMessage("[Plugins] Failed to disable SVC: \(error.localizedDescription)")
        }
        pendingSVCTunnelMismatch = nil
    }

    /// Stores "don't ask again" for the Flow 1 mismatch on the given server.
    func dismissSVCTunnelMismatch(for serverId: String) {
        guard let idx = configManager.config.servers.firstIndex(where: { $0.id == serverId }) else { return }
        configManager.config.servers[idx].svcTunnelPromptDismissed = true
        configManager.save()
        pendingSVCTunnelMismatch = nil
    }

    /// Stores the user's "Yes" answer for the Flow 2 port forwarding prompt.
    func confirmSVCPortForwarding(for serverId: String) {
        guard let idx = configManager.config.servers.firstIndex(where: { $0.id == serverId }) else { return }
        configManager.config.servers[idx].svcPortForwardingConfirmed = true
        configManager.save()
    }

    // MARK: - Source URL management

    /// Saves a source config for a plugin (creates or replaces).
    func setPluginSource(jarStem: String, url: String, type: PluginSourceType) {
        guard let server = selectedServer,
              let idx = configManager.config.servers.firstIndex(where: { $0.id == server.id })
        else { return }

        var sources = configManager.config.servers[idx].pluginSources ?? [:]
        // Remove any old prefix-matching entry to avoid duplicate keys after version updates
        sources = sources.filter { key, _ in
            let kl = key.lowercased(); let sl = jarStem.lowercased()
            return !(sl.hasPrefix(kl) || kl.hasPrefix(sl))
        }
        sources[jarStem] = PluginSourceConfig(url: url, type: type)
        configManager.config.servers[idx].pluginSources = sources
        configManager.save()

        logAppMessage("[Plugins] Source set for \(jarStem): \(type.displayName) — \(url)")
        refreshDiscoveredPlugins()
    }

    /// Removes the source config for a plugin.
    func removePluginSource(jarStem: String) {
        guard let server = selectedServer,
              let idx = configManager.config.servers.firstIndex(where: { $0.id == server.id })
        else { return }

        var sources = configManager.config.servers[idx].pluginSources ?? [:]
        sources.removeValue(forKey: jarStem)
        // Also remove any prefix-matching entries
        sources = sources.filter { key, _ in
            let kl = key.lowercased(); let sl = jarStem.lowercased()
            return !(sl.hasPrefix(kl) || kl.hasPrefix(sl))
        }
        configManager.config.servers[idx].pluginSources = sources.isEmpty ? nil : sources
        configManager.save()

        logAppMessage("[Plugins] Source removed for \(jarStem).")
        refreshDiscoveredPlugins()
    }

    // MARK: - One-step check + download (used from JARs tab in Edit Server)

    /// Fetches the download URL (if needed) and then downloads the plugin.
    /// For direct-URL sources this skips the network check and downloads immediately.
    func downloadPluginWithSourceCheck(entry: PluginEntry) {
        guard let source = entry.sourceConfig else { return }
        guard !downloadingPlugins.contains(entry.jarStem) else { return }

        if source.type == .direct {
            guard let url = URL(string: source.url) else {
                logAppMessage("[Plugins] Invalid download URL for \(entry.displayName).")
                return
            }
            var e = entry
            e.onlineDownloadURL = url
            e.onlineVersion = "(direct)"
            downloadLatestForPlugin(entry: e)
        } else {
            downloadingPlugins.insert(entry.jarStem)
            let mcVersion = componentsSnapshot.paper.local?.split(separator: " ").first.map(String.init) ?? "1.21"
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let (version, url) = try await self.fetchOnlineVersion(for: source, mcVersion: mcVersion)
                    self.discoveredPlugins = self.discoveredPlugins.map { e in
                        guard e.jarStem == entry.jarStem else { return e }
                        var updated = e
                        updated.onlineVersion = version
                        updated.onlineDownloadURL = url
                        return updated
                    }
                    self.downloadingPlugins.remove(entry.jarStem)
                    if let fresh = self.discoveredPlugins.first(where: { $0.jarStem == entry.jarStem }) {
                        self.downloadLatestForPlugin(entry: fresh)
                    }
                } catch {
                    self.downloadingPlugins.remove(entry.jarStem)
                    self.logAppMessage("[Plugins] Check for update failed (\(entry.displayName)): \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Download latest for a user-sourced plugin

    /// Downloads the latest version of a user-sourced plugin from its `onlineDownloadURL`.
    /// Replaces the old JAR with the same display name prefix and updates the source key.
    func downloadLatestForPlugin(entry: PluginEntry) {
        guard let downloadURL = entry.onlineDownloadURL else {
            logAppMessage("[Plugins] No download URL for \(entry.displayName). Run Check Online first.")
            return
        }
        guard let cfg = selectedServerConfig else { return }
        guard !downloadingPlugins.contains(entry.jarStem) else { return }

        downloadingPlugins.insert(entry.jarStem)

        Task.detached { [weak self] in
            guard let self else { return }

            let serverDirURL = URL(fileURLWithPath: cfg.serverDir, isDirectory: true)
            let pluginsDir   = serverDirURL.appendingPathComponent("plugins", isDirectory: true)

            await MainActor.run {
                self.logAppMessage("[Plugins] Downloading \(entry.displayName)…")
            }

            // Download to temp file
            let tempURL = pluginsDir.appendingPathComponent("\(entry.jarStem)-downloading.jar")
            do {
                let (location, response) = try await URLSession.shared.download(from: downloadURL)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    throw NSError(domain: "PluginDownload", code: code,
                                  userInfo: [NSLocalizedDescriptionKey: "Server returned HTTP \(code)."])
                }

                let fm = FileManager.default
                try fm.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
                if fm.fileExists(atPath: tempURL.path) { try fm.removeItem(at: tempURL) }
                try fm.moveItem(at: location, to: tempURL)

                // Derive final filename from the download URL's last path component
                let finalName = downloadURL.lastPathComponent.hasSuffix(".jar")
                    ? downloadURL.lastPathComponent
                    : "\(entry.displayName)-\(entry.onlineVersion ?? "latest").jar"
                let finalURL  = pluginsDir.appendingPathComponent(finalName)

                // Remove any existing JAR(s) with the same display name prefix
                let prefix = entry.displayName.lowercased()
                if let existing = try? fm.contentsOfDirectory(at: pluginsDir, includingPropertiesForKeys: nil) {
                    for old in existing where old.lastPathComponent.lowercased().hasPrefix(prefix)
                        && (old.pathExtension == "jar"
                            || old.lastPathComponent.hasSuffix(".jar.disabled")) {
                        try? fm.removeItem(at: old)
                    }
                }

                if fm.fileExists(atPath: finalURL.path) { try fm.removeItem(at: finalURL) }
                try fm.moveItem(at: tempURL, to: finalURL)

                // Update source key if the filename stem changed
                let newStem = finalURL.deletingPathExtension().lastPathComponent
                await MainActor.run {
                    if newStem != entry.jarStem, let source = entry.sourceConfig {
                        self.setPluginSource(jarStem: newStem, url: source.url, type: source.type)
                        // Remove the old key
                        if let server = self.selectedServer,
                           let idx = self.configManager.config.servers.firstIndex(where: { $0.id == server.id }) {
                            self.configManager.config.servers[idx].pluginSources?.removeValue(forKey: entry.jarStem)
                            self.configManager.save()
                        }
                    }
                    self.downloadingPlugins.remove(entry.jarStem)
                    self.logAppMessage("[Plugins] Downloaded \(entry.displayName) \(entry.onlineVersion ?? "").")
                    self.refreshDiscoveredPlugins()
                    self.invalidateAddonPlan()
                }
            } catch {
                await MainActor.run {
                    self.downloadingPlugins.remove(entry.jarStem)
                    self.logAppMessage("[Plugins] Download failed for \(entry.displayName): \(error.localizedDescription)")
                }
            }
        }
    }
}

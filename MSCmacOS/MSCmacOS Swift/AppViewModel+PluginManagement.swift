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
            refreshDiscoveredPlugins()
        } catch {
            logAppMessage("[Plugins] Failed to toggle \(entry.displayName): \(error.localizedDescription)")
        }
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

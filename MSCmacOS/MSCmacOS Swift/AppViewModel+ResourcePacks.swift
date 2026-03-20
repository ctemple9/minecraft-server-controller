// AppViewModel+ResourcePacks.swift
// MinecraftServerController
//
//
// AppViewModel extension for loading, installing, and removing resource packs
// for the selected server.

import Foundation
import UniformTypeIdentifiers
import AppKit   // NSOpenPanel

extension AppViewModel {

    // MARK: - Load

    /// Reload the resource pack list for the currently selected server.
    func loadResourcePacksForSelectedServer() {
        guard let server = selectedServer,
              let cfg = configServer(for: server) else {
            installedResourcePacks = []
            return
        }

        isLoadingResourcePacks = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let packs: [InstalledResourcePack]
            if cfg.isJava {
                packs = ResourcePackManager.listJavaPacks(serverDir: cfg.serverDir)
            } else {
                packs = ResourcePackManager.listBedrockPacks(serverDir: cfg.serverDir)
            }

            DispatchQueue.main.async {
                self.installedResourcePacks = packs
                self.isLoadingResourcePacks = false
            }
        }
    }

    // MARK: - Install (file picker)

    /// Open a system file picker for the selected server type and install the chosen pack.
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

    // MARK: - Install (drag-and-drop or programmatic)

    /// Install a resource pack file into the selected server's packs directory.
    /// Called both by the file picker and by drag-and-drop.
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
                            self.showError(
                                title: "Unsupported File",
                                message: "Java resource packs must be .zip files."
                            )
                        }
                        return
                    }
                    _ = try ResourcePackManager.installJavaPack(
                        from: sourceURL,
                        serverDir: cfg.serverDir
                    )
                    DispatchQueue.main.async {
                        self.logAppMessage("[ResourcePacks] Installed Java pack: \(sourceURL.lastPathComponent) for \(cfg.displayName).")
                        self.loadResourcePacksForSelectedServer()
                    }
                } else {
                    _ = try ResourcePackManager.installBedrockPack(
                        from: sourceURL,
                        serverDir: cfg.serverDir
                    )
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

    // MARK: - Remove

    /// Remove an installed resource pack from disk.
    func removeResourcePack(_ pack: InstalledResourcePack) {
        guard let server = selectedServer,
              let cfg = configServer(for: server) else { return }

        do {
            try ResourcePackManager.removePack(pack, serverDir: cfg.serverDir, isJava: cfg.isJava)
            logAppMessage("[ResourcePacks] Removed pack \(pack.fileName) from \(cfg.displayName).")
            loadResourcePacksForSelectedServer()
        } catch {
            logAppMessage("[ResourcePacks] Failed to remove pack \(pack.fileName): \(error.localizedDescription)")
            showError(title: "Pack Remove Failed", message: error.localizedDescription)
        }
    }

    // MARK: - Java: set active pack

    /// Write the resource-pack entry in server.properties for a Java server.
    /// Pass nil to clear.
    func setJavaActivePack(_ pack: InstalledResourcePack?) {
        guard let server = selectedServer,
              let cfg = configServer(for: server),
              cfg.isJava else { return }

        do {
            try ResourcePackManager.setJavaActivePack(pack, serverDir: cfg.serverDir)
            if let pack = pack {
                logAppMessage("[ResourcePacks] Set active Java resource pack to \(pack.fileName) for \(cfg.displayName).")
            } else {
                logAppMessage("[ResourcePacks] Cleared active Java resource pack for \(cfg.displayName).")
            }
            loadResourcePacksForSelectedServer()
        } catch {
            logAppMessage("[ResourcePacks] Failed to update server.properties: \(error.localizedDescription)")
            showError(title: "Settings Save Failed", message: error.localizedDescription)
        }
    }
}

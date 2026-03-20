//
//  AppViewModel+FinderTools.swift
//  MinecraftServerController
//

import AppKit

extension AppViewModel {

    // MARK: - Finder helpers

    func openSelectedServerFolder() {
        guard let server = selectedServer else {
            logAppMessage("[App] Unable to open server folder – no server selected.")
            return
        }
        let url = URL(fileURLWithPath: server.directory, isDirectory: true)
        openInFinder(url, description: "server folder for \(server.name)")
    }

    func openSelectedPluginsFolder() {
        guard let server = selectedServer else {
            logAppMessage("[App] Unable to open plugins folder – no server selected.")
            return
        }
        let fm = FileManager.default
        let serverDir = URL(fileURLWithPath: server.directory, isDirectory: true)
        let pluginsDir = serverDir.appendingPathComponent("plugins", isDirectory: true)
        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: pluginsDir.path, isDirectory: &isDir) {
            do {
                try fm.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
                logAppMessage("[App] Created plugins folder for \(server.name).")
            } catch {
                logAppMessage("[App] Unable to create plugins folder for \(server.name): \(error.localizedDescription)")
                return
            }
        }
        openInFinder(pluginsDir, description: "plugins folder for \(server.name)")
    }

    func openSelectedLogsFolder() {
        guard let server = selectedServer else {
            logAppMessage("[App] Unable to open logs folder – no server selected.")
            return
        }
        let fm = FileManager.default
        let serverDir = URL(fileURLWithPath: server.directory, isDirectory: true)
        let logsDir = serverDir.appendingPathComponent("logs", isDirectory: true)
        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: logsDir.path, isDirectory: &isDir) {
            do {
                try fm.createDirectory(at: logsDir, withIntermediateDirectories: true)
                logAppMessage("[App] Created logs folder for \(server.name) at \(logsDir.path).")
            } catch {
                logAppMessage("[App] Unable to create logs folder for \(server.name): \(error.localizedDescription)")
                return
            }
        }
        openInFinder(logsDir, description: "logs folder for \(server.name)")
    }

    func revealBackupInFinder(_ item: BackupItem) {
        let url = item.url
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            logAppMessage("[App] Revealed backup in Finder: \(item.displayName)")
        } else {
            logAppMessage("[App] Unable to reveal backup – file does not exist: \(url.path)")
        }
    }

    func openPluginTemplatesFolder() {
        let fm = FileManager.default
        let dirURL = configManager.pluginTemplateDirURL
        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: dirURL.path, isDirectory: &isDir) {
            do {
                try fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
                logAppMessage("[App] Created plugin templates folder at \(dirURL.path).")
            } catch {
                logAppMessage("[App] Unable to create plugin templates folder: \(error.localizedDescription)")
                return
            }
        }
        openInFinder(dirURL, description: "plugin templates folder")
    }

    func openPaperTemplatesFolder() {
        let fm = FileManager.default
        let cfg = configManager.config
        let path = cfg.paperTemplateDir
        guard !path.isEmpty else {
            logAppMessage("[App] Unable to open Paper templates folder – path not configured.")
            return
        }
        let dirURL = URL(fileURLWithPath: path, isDirectory: true)
        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: dirURL.path, isDirectory: &isDir) {
            do {
                try fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
                logAppMessage("[App] Created Paper templates folder at \(dirURL.path).")
            } catch {
                logAppMessage("[App] Unable to create Paper templates folder: \(error.localizedDescription)")
                return
            }
        }
        openInFinder(dirURL, description: "Paper templates folder")
    }

    func openAppSupportFolder() {
        let dirURL = configManager.configURL.deletingLastPathComponent()
        openInFinder(dirURL, description: "App Support folder")
    }

    func openInFinder(_ url: URL, description: String) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            logAppMessage("[App] Unable to open \(description) – path does not exist: \(url.path)")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

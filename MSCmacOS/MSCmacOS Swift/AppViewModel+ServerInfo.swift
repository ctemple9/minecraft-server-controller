//
//  AppViewModel+ServerInfo.swift
//  MinecraftServerController
//

import Foundation

extension AppViewModel {

    // MARK: - Cross-play status

    enum CrossPlayStatus {
        case none
        case geyserOnly
        case floodgateOnly
        case both

        var label: String {
            switch self {
            case .none:          return "Off"
            case .geyserOnly:    return "Geyser only"
            case .floodgateOnly: return "Floodgate only"
            case .both:          return "Geyser + Floodgate"
            }
        }
    }

    // MARK: - Effective Paper JAR

    /// Returns the effective Paper jar URL for a given ConfigServer, if it exists on disk.
    /// - Uses `paperJarPath` if non-empty, otherwise `serverDir/paper.jar`.
    func effectivePaperJarURL(for configServer: ConfigServer) -> URL? {
        let fm = FileManager.default

        // 1. Try explicit paperJarPath from config
        let trimmed = configServer.paperJarPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let explicitURL = URL(fileURLWithPath: trimmed)
            if fm.fileExists(atPath: explicitURL.path) {
                return explicitURL
            }
        }

        // 2. Fall back to paper.jar inside the server directory
        let serverDirURL = URL(fileURLWithPath: configServer.serverDir, isDirectory: true)
        let defaultJarURL = serverDirURL.appendingPathComponent("paper.jar")
        if fm.fileExists(atPath: defaultJarURL.path) {
            return defaultJarURL
        }

        // 3. Nothing found
        return nil
    }

    /// User-friendly display name for the Paper jar used by this server.
    func paperJarDisplayName(for configServer: ConfigServer) -> String {
        if let url = effectivePaperJarURL(for: configServer) {
            return url.lastPathComponent
        } else {
            return "No Paper jar found"
        }
    }

    // MARK: - Geyser / Floodgate detection

    /// Returns whether this server has Geyser / Floodgate JARs in its plugins folder.
    func crossPlayStatus(for configServer: ConfigServer) -> CrossPlayStatus {
        let fm = FileManager.default
        let serverDirURL = URL(fileURLWithPath: configServer.serverDir, isDirectory: true)
        let pluginsDirURL = serverDirURL.appendingPathComponent("plugins", isDirectory: true)

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: pluginsDirURL.path, isDirectory: &isDir), isDir.boolValue else {
            return .none
        }

        do {
            let contents = try fm.contentsOfDirectory(
                at: pluginsDirURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )

            var hasGeyser = false
            var hasFloodgate = false

            for url in contents where url.pathExtension.lowercased() == "jar" {
                let name = url.lastPathComponent.lowercased()
                if name.contains("geyser") {
                    hasGeyser = true
                }
                if name.contains("floodgate") {
                    hasFloodgate = true
                }
            }

            switch (hasGeyser, hasFloodgate) {
            case (false, false): return .none
            case (true,  false): return .geyserOnly
            case (false, true):  return .floodgateOnly
            case (true,  true):  return .both
            }

        } catch {
            logAppMessage("[App] Failed to inspect plugins for cross-play status: \(error.localizedDescription)")
            return .none
        }
    }
}


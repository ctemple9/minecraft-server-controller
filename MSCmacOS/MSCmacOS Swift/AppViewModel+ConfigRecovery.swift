//
//  AppViewModel+ConfigRecovery.swift
//  MinecraftServerController
//
//  Two recovery paths for a wiped or corrupt server list:
//  1. restoreServersFromBackup — decodes a .corrupt-* backup JSON and merges
//     its servers into the current config (skipping any already present).
//  2. rescanAndImportServers — walks the configured servers root on disk,
//     detects server folders not in the config, and imports them.
//

import Foundation

extension AppViewModel {

    // MARK: - Corrupt-backup discovery

    /// Returns all `.corrupt-*` backup files in the app support directory, newest first.
    func findCorruptBackups() -> [URL] {
        let dir = configManager.appDirectoryURL
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return contents
            .filter { $0.lastPathComponent.hasPrefix("server_config_swift.json.corrupt-") }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                return a > b
            }
    }

    /// Quickly reads the server count from a backup file without fully decoding it.
    func serverCountInBackup(at url: URL) -> Int? {
        guard let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = raw["servers"] as? [[String: Any]]
        else { return nil }
        return servers.count
    }

    // MARK: - Restore from backup

    struct BackupRestoreResult {
        var restored: Int
        var skipped: Int
        var error: String?
    }

    /// Decodes a corrupt backup and merges its servers into the live config.
    /// Servers already present (matched by `serverDir` path or `id`) are skipped.
    @discardableResult
    func restoreServersFromBackup(at url: URL) -> BackupRestoreResult {
        guard let data = try? Data(contentsOf: url) else {
            return BackupRestoreResult(restored: 0, skipped: 0,
                                       error: "Could not read backup file.")
        }
        let decoded: AppConfig
        do {
            decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            return BackupRestoreResult(restored: 0, skipped: 0,
                                       error: "Backup could not be decoded: \(error.localizedDescription)")
        }

        let existingPaths = Set(configManager.config.servers.map {
            URL(fileURLWithPath: $0.serverDir).standardized.path
        })
        let existingIDs = Set(configManager.config.servers.map { $0.id })

        var restored = 0
        var skipped  = 0
        for server in decoded.servers {
            let normalised = URL(fileURLWithPath: server.serverDir).standardized.path
            if existingPaths.contains(normalised) || existingIDs.contains(server.id) {
                skipped += 1
                continue
            }
            configManager.config.servers.append(server)
            restored += 1
        }

        if restored > 0 {
            configManager.save()
            reloadServersFromConfig()
            logAppMessage("[Recovery] Restored \(restored) server(s) from backup.")
        }
        return BackupRestoreResult(restored: restored, skipped: skipped, error: nil)
    }

    // MARK: - Rescan server root

    struct RescanResult {
        var added:   Int
        var skipped: Int
    }

    /// Walks the configured servers root (and its `java/` and `bedrock/` subdirs),
    /// detects any server folders not already in the config, and adds them.
    @discardableResult
    func rescanAndImportServers() -> RescanResult {
        let fm   = FileManager.default
        let root = configManager.serversRootURL

        let existingPaths = Set(configManager.config.servers.map {
            URL(fileURLWithPath: $0.serverDir).standardized.path
        })

        // Search the root itself plus the typed subdirectories MSC creates.
        var searchDirs: [URL] = [root]
        for sub in ["java", "bedrock"] {
            let url = root.appendingPathComponent(sub, isDirectory: true)
            if fm.fileExists(atPath: url.path) { searchDirs.append(url) }
        }

        // Collect candidates: one level of subdirectories not already registered.
        var candidates: [URL] = []
        var seen = Set<String>()
        for dir in searchDirs {
            guard let contents = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for item in contents {
                guard (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                else { continue }
                let std = item.standardized.path
                guard !existingPaths.contains(std), seen.insert(std).inserted
                else { continue }
                candidates.append(item.standardized)
            }
        }

        var added   = 0
        var skipped = 0

        for dir in candidates {
            guard let contents = try? fm.contentsOfDirectory(atPath: dir.path) else {
                skipped += 1; continue
            }
            let hasJar     = contents.contains { $0.lowercased().hasSuffix(".jar") }
            let hasBedrock = contents.contains { $0 == "bedrock_server" || $0 == "bedrock_server.exe" }
            guard hasJar || hasBedrock else { skipped += 1; continue }

            let serverType: ServerType = (hasBedrock && !hasJar) ? .bedrock : .java

            let rawName     = dir.lastPathComponent
            let displayName = rawName.replacingOccurrences(of: "_", with: " ")

            var cfg = ConfigServer(
                id: UUID().uuidString,
                displayName: displayName,
                serverDir: dir.path,
                paperJarPath: "",
                minRamGB: 2,
                maxRamGB: 4,
                notes: ""
            )
            cfg.serverType     = serverType
            cfg.hasEverStarted = true

            if serverType == .java {
                let detected       = AppViewModel.detectJavaFlavor(in: dir)
                cfg.javaFlavor     = detected.flavor
                cfg.paperJarPath   = detected.primaryJarPath ?? ""
                cfg.minecraftVersion = detected.mcVersion
                cfg.loaderVersion  = detected.loaderVersion
            }

            configManager.config.servers.append(cfg)
            added += 1
        }

        if added > 0 {
            configManager.save()
            reloadServersFromConfig()
            logAppMessage("[Recovery] Rescan added \(added) server(s) from \(root.path).")
        }
        return RescanResult(added: added, skipped: skipped)
    }
}

//
//  AppViewModel+Backups.swift
//  MinecraftServerController
//

import Foundation

// MARK: - Backup filename constants
//
// Automatic and manual backups encode their origin in the filename so the label
// survives app restarts without a separate metadata file.
// Pattern: <levelName>_auto_<timestamp>.zip  or  <levelName>_manual_<timestamp>.zip
//
// The pruning logic ONLY removes files matching one of these two tokens, so any
// zip files placed in the backup folder by other tools are never touched.

private let autoBackupToken   = "_auto_"
private let manualBackupToken = "_manual_"
private let maxAutoBackupCount = 12

extension AppViewModel {

    // MARK: - Backup list

    func loadBackupsForSelectedServer() {
        guard let server = selectedServer else {
            backupItems = []
            backupsFolderSizeDisplay = nil
            return
        }

        let backupsDir = configManager.backupsDirectoryURL(forServerDirectory: server.directory)
        let fm = FileManager.default

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: backupsDir.path, isDirectory: &isDir), isDir.boolValue else {
            backupItems = []
            backupsFolderSizeDisplay = nil
            logAppMessage("[Backup] No backups directory yet for \(server.name).")
            return
        }

        let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]

        let contents: [URL]
        do {
            contents = try fm.contentsOfDirectory(
                at: backupsDir,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles]
            )
        } catch {
            backupItems = []
            backupsFolderSizeDisplay = nil
            logAppMessage("[Backup] Failed to list backups: \(error.localizedDescription)")
            showError(title: "Backups Unavailable", message: "Could not read the backups folder for \(server.name): \(error.localizedDescription)")
            return
        }

        var items: [BackupItem] = []

        for url in contents where url.pathExtension.lowercased() == "zip" {
            let values = try? url.resourceValues(forKeys: resourceKeys)
            let mdate = values?.contentModificationDate
            let size = values?.fileSize.map(Int64.init)

            let displayName = makeDisplayName(for: url, fallbackDate: mdate)

            // Start with the filename-derived trigger reason for backwards compat,
            // then override from the sidecar if present.
            let filenameTrigger: String = url.lastPathComponent.contains(autoBackupToken) ? "auto" : "manual"

            var item = BackupItem(
                url: url,
                displayName: displayName,
                fileSize: size,
                modificationDate: mdate,
                triggerReason: filenameTrigger
            )

            // Attempt to read sidecar. Non-fatal — missing or corrupt sidecar leaves
            // item.slotId = nil and triggerReason at its filename-derived default.
            if let meta = readBackupMeta(forBackupURL: url) {
                item.serverId = meta.serverId
                item.serverDisplayName = meta.serverDisplayName
                item.slotId = meta.slotId
                item.slotName = meta.slotName
                item.triggerReason = meta.triggerReason
            }

            items.append(item)
        }

        items.sort {
            ($0.modificationDate ?? .distantPast) >
            ($1.modificationDate ?? .distantPast)
        }

        backupItems = items

        // Compute backup folder size on a background thread to avoid blocking the main thread.
        let dirURL = backupsDir
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self else { return }
            let bytes = AppUtilities.directorySizeInBytes(at: dirURL)
            let formatted = AppUtilities.formatBytes(bytes)
            DispatchQueue.main.async {
                self.backupsFolderSizeDisplay = formatted
            }
        }
    }

    // MARK: - Create backup (selected server — called from UI buttons)

    /// Creates a backup zip for the currently selected server.
    /// Pass `isAutomatic: true` when called by the auto-backup timer or stop-time trigger.
    func createBackupForSelectedServer(isAutomatic: Bool = false) {
        guard let server = selectedServer else {
            logAppMessage("[Backup] No active server selected; cannot back up.")
            return
        }
        guard let cfgServer = self.configServer(for: server) else {
            logAppMessage("[Backup] Could not find config entry for server \(server.name).")
            return
        }
        createAutoBackupForServer(cfgServer, isAutomatic: isAutomatic)
    }

    // MARK: - Create backup (by ConfigServer — called by timer and stop-time path)

    /// Internal entry point used by the auto-backup timer and the stop-time backup.
    /// Using ConfigServer directly avoids a dependency on `selectedServer`.
    func createAutoBackupForServer(_ cfgServer: ConfigServer, isAutomatic: Bool = true) {
        Task {
            _ = await createBackup(for: cfgServer, isAutomatic: isAutomatic)
        }
    }

    private func activeWorldSlotMetadata(for configServer: ConfigServer) -> (id: String, name: String, seed: String?)? {
        guard let slot = WorldSlotManager.activeSlot(forServerDir: configServer.serverDir) else { return nil }
        return (slot.id, slot.name, slot.worldSeed)
    }

    private func effectiveBackupAssociation(
        for configServer: ConfigServer,
        explicitSlotId: String?,
        explicitSlotName: String?
    ) -> (slotId: String?, slotName: String?, worldSeed: String?) {
        if let explicitSlotId, !explicitSlotId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let trimmedName = explicitSlotName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedSeed = WorldSlotManager.loadSlots(forServerDir: configServer.serverDir)
                .first(where: { $0.id == explicitSlotId })?
                .worldSeed?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (
                explicitSlotId,
                trimmedName?.isEmpty == false ? trimmedName : nil,
                trimmedSeed?.isEmpty == false ? trimmedSeed : nil
            )
        }

        if let active = activeWorldSlotMetadata(for: configServer) {
            return (active.id, active.name, active.seed)
        }

        return (nil, nil, nil)
    }

    // MARK: - Slot-aware backup creation (primary implementation)

    /// Creates a backup ZIP for the given server, optionally associating it with a world slot.
    /// Returns `true` on success. This is the authoritative implementation — all other
    /// backup-creation paths funnel through here.
    ///
    /// - Parameters:
    ///   - configServer: The server whose world folders should be backed up.
    ///   - isAutomatic: `true` for timer/stop-triggered backups; encodes `_auto_` in the filename.
    ///   - slotId: Optional UUID string of the WorldSlot being backed up.
    ///   - slotName: Optional display-name snapshot for the slot (for display after deletion).
    ///   - triggerReason: Override for the sidecar's triggerReason field. Defaults to
    ///     "auto" / "manual" derived from `isAutomatic` when nil.
    @discardableResult
    func createBackup(
        for configServer: ConfigServer,
        isAutomatic: Bool,
        slotId: String? = nil,
        slotName: String? = nil,
        triggerReason: String? = nil
    ) async -> Bool {
        let association = effectiveBackupAssociation(
            for: configServer,
            explicitSlotId: slotId,
            explicitSlotName: slotName
        )

        let serverDirURL = URL(fileURLWithPath: configServer.serverDir, isDirectory: true)
        let propsURL = serverDirURL.appendingPathComponent("server.properties")
        let props = readProperties(at: propsURL)

        let javaLevelName = (props["level-name"]?
            .trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 } ?? "world"

        let fm = FileManager.default
        let worldNames = WorldSlotManager.worldFolderNames(for: configServer)
        let archiveBaseName = configServer.serverType == .bedrock ? "worlds" : javaLevelName

        guard !worldNames.isEmpty else {
            let tried = configServer.serverType == .bedrock
                ? "worlds"
                : [javaLevelName, "\(javaLevelName)_nether", "\(javaLevelName)_the_end"].joined(separator: ", ")
            await MainActor.run { logAppMessage("[Backup] No world folders found. Tried: \(tried)") }
            return false
        }

        let backupsDir = configManager.backupsDirectoryURL(forServerDirectory: configServer.serverDir)
        do {
            try fm.createDirectory(at: backupsDir, withIntermediateDirectories: true)
        } catch {
            await MainActor.run { logAppMessage("[Backup] Failed to create backups directory: \(error.localizedDescription)") }
            return false
        }

        if isAutomatic {
            await MainActor.run { pruneAutoBackupsIfNeeded(in: backupsDir) }
        }

        let tsFormatter = DateFormatter()
        tsFormatter.dateFormat = "yyyyMMdd-HHmmss"
        tsFormatter.locale = Locale(identifier: "en_US_POSIX")
        let ts = tsFormatter.string(from: Date())

        let token = isAutomatic ? autoBackupToken : manualBackupToken
        let zipURL = backupsDir.appendingPathComponent("\(archiveBaseName)\(token)\(ts).zip")

        let joined = worldNames.joined(separator: ", ")
        let kind = isAutomatic ? "auto" : "manual"
        await MainActor.run { logAppMessage("[Backup] Starting \(kind) backup of \(joined) to:\n\(zipURL.path)") }

        do {
            let status: Int32 = try await Task.detached(priority: .userInitiated) { () -> Int32 in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                process.currentDirectoryURL = serverDirURL
                process.arguments = ["-r", zipURL.path] + worldNames
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus
            }.value

            await MainActor.run {
                if status == 0 {
                    // Write sidecar immediately after a successful zip.
                    let reason = triggerReason ?? (isAutomatic ? "auto" : "manual")
                    let meta = BackupMeta(
                        serverId: configServer.id,
                        serverDisplayName: configServer.displayName,
                        slotId: association.slotId,
                        slotName: association.slotName,
                        worldSeed: association.worldSeed,
                        triggerReason: reason
                    )
                    writeBackupMeta(meta, forBackupURL: zipURL)

                    logAppMessage("[Backup] Completed (\(kind)): \(zipURL.lastPathComponent)")
                    loadBackupsForSelectedServer()
                } else {
                    logAppMessage("[Backup] zip failed with status \(status)")
                    if !isAutomatic {
                        showError(
                            title: "Backup Failed",
                            message: "The zip process exited with an error (status \(status)). Check the console for details."
                        )
                    }
                }
            }

            return status == 0
        } catch {
            await MainActor.run {
                logAppMessage("[Backup] Failed to start zip: \(error.localizedDescription)")
                if !isAutomatic {
                    showError(title: "Backup Failed", message: "Could not launch zip: \(error.localizedDescription)")
                }
            }
            return false
        }
    }

    // MARK: - Sidecar read / write helpers

    /// Reads the sidecar .meta.json for the given backup ZIP URL.
    /// Returns nil silently if the file is missing or cannot be decoded — never throws.
    func readBackupMeta(forBackupURL url: URL) -> BackupMeta? {
        let metaURL = sidecarURL(for: url)
        let fm = FileManager.default

        guard fm.fileExists(atPath: metaURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: metaURL)
            return try JSONDecoder().decode(BackupMeta.self, from: data)
        } catch {
            logAppMessage("[Backup] Warning: could not read sidecar for \(url.lastPathComponent): \(error.localizedDescription). Treating it as a legacy/unmatched backup.")
            return nil
        }
    }

    /// Writes a BackupMeta sidecar alongside the given backup ZIP.
    /// Failures are logged but never surfaced as errors — the backup ZIP itself is the
    /// important artifact; the sidecar is supplementary.
    func writeBackupMeta(_ meta: BackupMeta, forBackupURL url: URL) {
        let metaURL = sidecarURL(for: url)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(meta)
            try data.write(to: metaURL, options: .atomic)
        } catch {
            logAppMessage("[Backup] Warning: could not write sidecar for \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// Returns the sidecar URL for a backup ZIP: replaces the .zip extension with .meta.json.
    private func sidecarURL(for backupURL: URL) -> URL {
        backupURL.deletingPathExtension().appendingPathExtension("meta.json")
    }

    /// Public entry point for the Backups tab "Prune Old Backups" button.
    /// Resolves the backups directory for the currently selected server and
    /// delegates to pruneAutoBackupsIfNeeded(in:).
    func pruneAutoBackupsForSelectedServer() {
        guard let server = selectedServer else {
            logAppMessage("[Backup] Prune: no server selected.")
            return
        }
        let backupsDir = configManager.backupsDirectoryURL(forServerDirectory: server.directory)
        pruneAutoBackupsIfNeeded(in: backupsDir)
        loadBackupsForSelectedServer()
        logAppMessage("[Backup] Manual prune complete for \"\(server.name)\".")
    }

    /// Deletes the oldest automatic backups from `backupsDir` until the count of
    /// app-managed backups is at most `maxAutoBackupCount - 1`.
    /// Also removes orphaned .meta.json sidecars when their paired ZIP is deleted.
    private func pruneAutoBackupsIfNeeded(in backupsDir: URL) {
        let fm = FileManager.default
        let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey]

        let contents: [URL]
        do {
            contents = try fm.contentsOfDirectory(
                at: backupsDir,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles]
            )
        } catch {
            logAppMessage("[Backup] Pruning: failed to list directory: \(error.localizedDescription)")
            return
        }

        let managedFiles = contents.filter { url in
            let name = url.lastPathComponent
            return url.pathExtension.lowercased() == "zip"
                && (name.contains(autoBackupToken) || name.contains(manualBackupToken))
        }

        guard managedFiles.count >= maxAutoBackupCount else { return }

        var dated: [(date: Date, url: URL)] = []
        for url in managedFiles {
            let values = try? url.resourceValues(forKeys: resourceKeys)
            guard let date = values?.contentModificationDate else {
                logAppMessage("[Backup] Pruning: skipping \(url.lastPathComponent) — modification date unreadable.")
                continue
            }
            dated.append((date, url))
        }

        dated.sort { $0.date < $1.date }

        let deleteCount = managedFiles.count - (maxAutoBackupCount - 1)
        let toDelete = dated.prefix(deleteCount)

        for (_, url) in toDelete {
            do {
                try fm.removeItem(at: url)
                logAppMessage("[Backup] Pruned oldest backup: \(url.lastPathComponent)")

                // Remove paired sidecar if it exists.
                let metaURL = sidecarURL(for: url)
                if fm.fileExists(atPath: metaURL.path) {
                    try? fm.removeItem(at: metaURL)
                }
            } catch {
                logAppMessage("[Backup] Pruning: failed to delete \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Restore backup

    func restoreBackup(_ backup: BackupItem) {
        guard let server = selectedServer else {
            logAppMessage("[Backup] No active server selected; cannot restore.")
            return
        }
        guard let cfgServer = self.configServer(for: server) else {
            logAppMessage("[Backup] Could not find config entry for server \(server.name).")
            return
        }

        guard cfgServer.serverType == .java else {
            logAppMessage("[Backup] Live-world restore is currently supported for Java servers only. Bedrock slot backups remain available inside World Slots.")
            showError(
                title: "Restore Not Available",
                message: "Live-world backup restore is currently available for Java servers only. Bedrock world-slot backups are still available in the Worlds tab."
            )
            return
        }

        let targetIsRunning = isServerRunning && configManager.config.activeServerId == cfgServer.id
        guard !targetIsRunning else {
            logAppMessage("[Backup] Refusing to restore while the target server is running. Stop the server first.")
            showError(title: "Restore Blocked", message: "Stop \"\(cfgServer.displayName)\" before restoring a backup.")
            return
        }

        if let backupSlotId = backup.slotId,
           let activeSlotId = WorldSlotManager.resolvedActiveSlotID(forServerDir: cfgServer.serverDir),
           backupSlotId != activeSlotId {
            logAppMessage("[Backup] Refusing to restore backup \"\(backup.filename)\" because it belongs to slot ID \(backupSlotId), not the active slot \(activeSlotId).")
            showError(
                title: "Restore Blocked",
                message: "This backup belongs to a different world slot. Activate that slot first, or restore it from the slot-specific Worlds tab."
            )
            return
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: backup.url.path) else {
            logAppMessage("[Backup] Restore source is missing: \(backup.url.path)")
            showError(title: "Restore Failed", message: "The selected backup file could not be found on disk.")
            loadBackupsForSelectedServer()
            return
        }

        let serverDirURL = URL(fileURLWithPath: cfgServer.serverDir, isDirectory: true)
        let propsURL = serverDirURL.appendingPathComponent("server.properties")
        let props = readProperties(at: propsURL)

        let levelName = (props["level-name"]?
            .trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 } ?? "world"

        Task {
            let safetyBackupCreated = await createBackup(
                for: cfgServer,
                isAutomatic: false,
                triggerReason: "pre-restore"
            )

            guard safetyBackupCreated else {
                await MainActor.run {
                    self.logAppMessage("[Backup] Restore aborted because a safety backup could not be created for \(cfgServer.displayName).")
                    self.showError(
                        title: "Restore Aborted",
                        message: "A safety backup of the current world could not be created, so no files were changed."
                    )
                }
                return
            }

            let archiveValid = await validateZipArchive(backup.url, logPrefix: "[Backup]")
            guard archiveValid else {
                await MainActor.run {
                    self.showError(
                        title: "Restore Failed",
                        message: "The selected backup ZIP could not be opened. Your current world was not changed."
                    )
                }
                return
            }

            await MainActor.run {
                self.removeWorldFolders(in: serverDirURL, levelName: levelName, logPrefix: "[Backup]")
                self.logAppMessage("[Backup] Restoring from backup: \(backup.url.path)")
            }

            let status: Int32 = await Task.detached(priority: .userInitiated) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                process.arguments = ["-o", backup.url.path, "-d", serverDirURL.path]

                do {
                    try process.run()
                    process.waitUntilExit()
                    return process.terminationStatus
                } catch {
                    return -1
                }
            }.value

            await MainActor.run {
                if status == 0 {
                    self.logAppMessage("[Backup] Restore complete from \(backup.url.path)")
                    self.loadBackupsForSelectedServer()
                } else {
                    self.logAppMessage("[Backup] unzip failed with status \(status)")
                    self.showError(
                        title: "Restore Failed",
                        message: "The backup ZIP could not be extracted. A safety backup of the previous world was created before the restore."
                    )
                }
            }
        }
    }

    // MARK: - Delete backup

    /// Deletes a single backup file from disk (and its sidecar if present) then refreshes the list.
    func deleteBackup(_ backup: BackupItem) {
        let fm = FileManager.default
        do {
            try fm.removeItem(at: backup.url)
            logAppMessage("[Backup] Deleted backup: \(backup.filename)")

            // Remove paired sidecar silently.
            let metaURL = sidecarURL(for: backup.url)
            if fm.fileExists(atPath: metaURL.path) {
                try? fm.removeItem(at: metaURL)
            }

            loadBackupsForSelectedServer()
        } catch {
            logAppMessage("[Backup] Failed to delete backup \(backup.filename): \(error.localizedDescription)")
            showError(title: "Delete Failed", message: "Could not delete \(backup.filename): \(error.localizedDescription)")
        }
    }

    // MARK: - Duplicate backup into new server

    func duplicateBackupToNewServer(from backup: BackupItem, newDisplayName: String) {
        let trimmedName = newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            logAppMessage("[Backup] New server name is empty; aborting duplicate.")
            return
        }

        guard let server = selectedServer else {
            logAppMessage("[Backup] No active server selected; cannot duplicate backup.")
            return
        }
        guard let cfgServer = self.configServer(for: server) else {
            logAppMessage("[Backup] Could not find config entry for server \(server.name).")
            return
        }

        let serversRootURL = configManager.serversRootURL
        let folderName = trimmedName.replacingOccurrences(of: " ", with: "_").lowercased()
        let newDirURL = serversRootURL.appendingPathComponent(folderName, isDirectory: true)

        let fm = FileManager.default
        if fm.fileExists(atPath: newDirURL.path) {
            logAppMessage("[Backup] Folder already exists: \(newDirURL.path)")
            return
        }

        let templateDirURL = URL(fileURLWithPath: cfgServer.serverDir, isDirectory: true)

        let srcJarURL: URL
        let jarPathTrimmed = cfgServer.paperJarPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !jarPathTrimmed.isEmpty {
            srcJarURL = URL(fileURLWithPath: jarPathTrimmed)
        } else {
            srcJarURL = templateDirURL.appendingPathComponent("paper.jar")
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let fm = FileManager.default

            do {
                try fm.createDirectory(at: newDirURL, withIntermediateDirectories: true)

                let dstJarURL = newDirURL.appendingPathComponent("paper.jar")
                if fm.fileExists(atPath: srcJarURL.path) {
                    try fm.copyItem(at: srcJarURL, to: dstJarURL)
                } else {
                    Task { @MainActor in
                        self.logAppMessage("[Backup] Could not find paper.jar in template server.")
                    }
                    return
                }

                let srcPluginsURL = templateDirURL.appendingPathComponent("plugins", isDirectory: true)
                if fm.fileExists(atPath: srcPluginsURL.path) {
                    let dstPluginsURL = newDirURL.appendingPathComponent("plugins", isDirectory: true)
                    try fm.copyItem(at: srcPluginsURL, to: dstPluginsURL)
                }

                let srcPropsURL = templateDirURL.appendingPathComponent("server.properties")
                let dstPropsURL = newDirURL.appendingPathComponent("server.properties")
                if fm.fileExists(atPath: srcPropsURL.path) {
                    try fm.copyItem(at: srcPropsURL, to: dstPropsURL)
                }

                let eulaURL = newDirURL.appendingPathComponent("eula.txt")
                try "eula=false\n".write(to: eulaURL, atomically: true, encoding: .utf8)

                let unzip = Process()
                unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                unzip.arguments = ["-o", backup.url.path, "-d", newDirURL.path]
                try unzip.run()
                unzip.waitUntilExit()

                if unzip.terminationStatus != 0 {
                    Task { @MainActor in
                        self.logAppMessage("[Backup] unzip failed when creating new server from backup (status \(unzip.terminationStatus)).")
                    }
                    return
                }

                Task { @MainActor in
                    let newId = "server_\(self.configManager.config.servers.count + 1)"
                    let newConfig = ConfigServer(
                        id: newId,
                        displayName: trimmedName,
                        serverDir: newDirURL.path,
                        paperJarPath: dstJarURL.path,
                        minRamGB: cfgServer.minRam,
                        maxRamGB: cfgServer.maxRam,
                        notes: cfgServer.notes
                    )

                    self.upsertServer(newConfig)
                    self.setActiveServer(withId: newId)
                    self.logAppMessage("[Backup] Created new server '\(trimmedName)' at \(newDirURL.path) from backup \(backup.filename)")
                }

            } catch {
                Task { @MainActor in
                    self.logAppMessage("[Backup] Failed to duplicate backup into new server: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Async backup helper for Replace World

    /// Async backup helper used by `replaceWorld(...)`.
    /// Creates a backup ZIP of the current world's folders for the given `ConfigServer`.
    /// Pre-replace backups use triggerReason "pre-replace" in the sidecar;
    /// they intentionally have no `_auto_` or `_manual_` token so they are not pruned.
    func backupWorld(for configServer: ConfigServer) async -> Bool {
        let serverDirURL = URL(fileURLWithPath: configServer.serverDir, isDirectory: true)
        let propsURL = serverDirURL.appendingPathComponent("server.properties")
        let props = readProperties(at: propsURL)

        let javaLevelName = (props["level-name"]?
            .trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 } ?? "world"

        let fm = FileManager.default
        let worldNames = WorldSlotManager.worldFolderNames(for: configServer)
        let archiveBaseName = configServer.serverType == .bedrock ? "worlds" : javaLevelName

        guard !worldNames.isEmpty else {
            let tried = configServer.serverType == .bedrock
                ? "worlds"
                : [javaLevelName, "\(javaLevelName)_nether", "\(javaLevelName)_the_end"].joined(separator: ", ")
            logAppMessage("[Backup] (Replace World) No world folders found. Tried: \(tried)")
            return false
        }

        let backupsDir = configManager.backupsDirectoryURL(forServerDirectory: configServer.serverDir)
        do {
            try fm.createDirectory(at: backupsDir, withIntermediateDirectories: true)
        } catch {
            logAppMessage("[Backup] (Replace World) Failed to create backups directory: \(error.localizedDescription)")
            return false
        }

        let tsFormatter = DateFormatter()
        tsFormatter.dateFormat = "yyyyMMdd-HHmmss"
        tsFormatter.locale = Locale(identifier: "en_US_POSIX")
        let ts = tsFormatter.string(from: Date())

        // Intentionally no _auto_ / _manual_ token — this is a replace-world safety backup.
        let zipURL = backupsDir.appendingPathComponent("\(archiveBaseName)-\(ts).zip")

        let joined = worldNames.joined(separator: ", ")
        logAppMessage("[Backup] (Replace World) Starting backup of \(joined) to:\n\(zipURL.path)")

        do {
            let status: Int32 = try await Task.detached(priority: .userInitiated) { () -> Int32 in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                process.currentDirectoryURL = serverDirURL
                process.arguments = ["-r", zipURL.path] + worldNames
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus
            }.value

            if status == 0 {
                // Write sidecar with pre-replace reason.
                let association = activeWorldSlotMetadata(for: configServer)
                let meta = BackupMeta(
                    serverId: configServer.id,
                    serverDisplayName: configServer.displayName,
                    slotId: association?.id,
                    slotName: association?.name,
                    triggerReason: "pre-replace"
                )
                writeBackupMeta(meta, forBackupURL: zipURL)
                logAppMessage("[Backup] (Replace World) Completed: \(zipURL.path)")
                return true
            } else {
                logAppMessage("[Backup] (Replace World) zip failed with status \(status)")
                return false
            }
        } catch {
            logAppMessage("[Backup] (Replace World) Failed to start zip: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - World folder removal helper (shared with Restore + Replace World)

    /// Removes world folders for a given `levelName` in a server directory.
    func removeWorldFolders(in serverDirURL: URL, levelName: String, logPrefix: String) {
        let fm = FileManager.default
        let names = [levelName, "\(levelName)_nether", "\(levelName)_the_end"]

        var removedAny = false

        for name in names {
            let path = serverDirURL.appendingPathComponent(name, isDirectory: true)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: path.path, isDirectory: &isDir), isDir.boolValue {
                do {
                    try fm.removeItem(at: path)
                    removedAny = true
                } catch {
                    logAppMessage("\(logPrefix) Failed to remove existing \(name): \(error.localizedDescription)")
                }
            }
        }

        if removedAny {
            logAppMessage("\(logPrefix) Removed existing world folders for '\(levelName)'.")
        }
    }

    // MARK: - Private helpers

    /// Builds a human-readable display name for a backup URL.
    private func makeDisplayName(for url: URL, fallbackDate: Date?) -> String {
        let base = url.deletingPathExtension().lastPathComponent

        let dateParser = DateFormatter()
        dateParser.locale = Locale(identifier: "en_US_POSIX")

        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        // New format: levelName_auto_YYYYMMDD-HHmmss or levelName_manual_YYYYMMDD-HHmmss
        for token in [autoBackupToken, manualBackupToken] {
            if let range = base.range(of: token) {
                let tsString = String(base[range.upperBound...])
                dateParser.dateFormat = "yyyyMMdd-HHmmss"
                if let date = dateParser.date(from: tsString) {
                    return displayFormatter.string(from: date)
                }
            }
        }

        // Legacy format: worldname-YYYYMMDD-HHmmss
        if let dashRange = base.range(of: "-", options: .backwards) {
            let prefix = String(base[..<dashRange.lowerBound])
            let tsString = String(base[dashRange.upperBound...])
            dateParser.dateFormat = "yyyyMMdd-HHmmss"
            if let date = dateParser.date(from: tsString) {
                return "\(prefix) — \(displayFormatter.string(from: date))"
            }
        }

        return base
    }

    private func readProperties(at url: URL) -> [String: String] {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return [:]
        }

        var result: [String: String] = [:]

        for line in contents.split(whereSeparator: \.isNewline) {
            let raw = String(line)
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            guard let eqIndex = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<eqIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: eqIndex)...]).trimmingCharacters(in: .whitespaces)
            result[key] = value
        }

        return result
    }
}


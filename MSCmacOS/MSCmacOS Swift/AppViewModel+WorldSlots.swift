// AppViewModel+WorldSlots.swift
// MinecraftServerController
//
//
// This extension owns:
//   - @Published worldSlots: [WorldSlot]       — the slot list shown in UI
//   - @Published isWorldSlotsLoading: Bool      — progress indicator
//   - loadWorldSlotsForSelectedServer()         — reload from disk
//   - saveCurrentWorldAsSlot(name:)             — create new slot
//   - activateWorldSlot(_:)                     — swap active world
//   - renameWorldSlot(_:newName:)               — rename metadata only
//   - deleteWorldSlot(_:)                       — remove slot directory
//   - duplicateWorldSlot(_:newName:)            — copy slot to new named slot
//   - copyWorldSlot(_:into:)                    — overwrite existing slot with another's world data
//   - exportWorldSlot(_:to:)                    — copy slot zip to user-chosen URL
//
// All methods guard against server-is-running where world data is touched.

import Foundation
import Combine

// MARK: - Published state

// Add these @Published vars to AppViewModel directly (they cannot live in an extension).
// To integrate: add the following two lines to AppViewModel's @Published block:
//
//   @Published var worldSlots: [WorldSlot] = []
//   @Published var isWorldSlotsLoading: Bool = false
//
// The extension below references them as normal self properties.

extension AppViewModel {

    // MARK: - Load

    /// Reloads the slot list for the currently selected server.
    /// Safe to call any time; is a no-op if no server is selected.
    func loadWorldSlotsForSelectedServer() {
        guard let server = selectedServer,
              let cfgServer = configServer(for: server) else {
            worldSlots = []
            return
        }

        worldSlots = WorldSlotManager.loadSlots(forServerDir: cfgServer.serverDir)
    }

    // MARK: - Active slot resolution

    private func defaultPersistentSlotName(for cfgServer: ConfigServer) -> String {
        if cfgServer.isBedrock {
            let levelName = BedrockPropertiesManager.readModel(serverDir: cfgServer.serverDir).levelName
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return levelName.isEmpty ? "World 1" : levelName
        }

        let props = ServerPropertiesManager.readProperties(serverDir: cfgServer.serverDir)
        let raw = props["level-name"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? "World 1" : raw.prefix(1).uppercased() + raw.dropFirst()
    }

    private func ensureActiveWorldSlotExists(for cfgServer: ConfigServer) async -> WorldSlot? {
        if let active = WorldSlotManager.activeSlot(forServerDir: cfgServer.serverDir) {
            do {
                try WorldSlotManager.setActiveSlotID(active.id, forServerDir: cfgServer.serverDir)
            } catch {
                logAppMessage("[WorldSlots] Warning: could not persist active slot identity: \(error.localizedDescription)")
            }
            return active
        }

        let existing = WorldSlotManager.loadSlots(forServerDir: cfgServer.serverDir)
        if let fallback = existing.max(by: { $0.createdAt < $1.createdAt }) {
            do {
                try WorldSlotManager.setActiveSlotID(fallback.id, forServerDir: cfgServer.serverDir)
            } catch {
                logAppMessage("[WorldSlots] Warning: could not persist active slot identity: \(error.localizedDescription)")
            }
            return fallback
        }

        let created = await WorldSlotManager.createSlot(
            name: defaultPersistentSlotName(for: cfgServer),
            for: cfgServer,
            logLine: { [weak self] msg in
                Task { @MainActor in self?.logAppMessage(msg) }
            }
        )

        guard var created else { return nil }

        created.lastPlayedAt = Date()
        do {
            try WorldSlotManager.saveMetadata(created, serverDir: cfgServer.serverDir)
            try WorldSlotManager.setActiveSlotID(created.id, forServerDir: cfgServer.serverDir)
        } catch {
            logAppMessage("[WorldSlots] Failed to finalize initial persistent slot: \(error.localizedDescription)")
        }
        return created
    }

    // MARK: - Save current world into active slot

    /// Saves the current live world back into the currently active persistent slot.
    /// If this server predates the persistent-slot model and has no slots yet, a one-time
    /// initial slot is created from the current world and marked active.
    func saveCurrentWorldToActiveSlot() {
        guard let server = selectedServer,
              let cfgServer = configServer(for: server) else {
            logAppMessage("[WorldSlots] No server selected.")
            return
        }

        isWorldSlotsLoading = true

        Task {
            guard let activeSlot = await ensureActiveWorldSlotExists(for: cfgServer) else {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isWorldSlotsLoading = false
                    self.showError(
                        title: "Save Failed",
                        message: "No active world slot could be resolved for this server. Create or activate a slot first."
                    )
                }
                return
            }

            let updated = await WorldSlotManager.updateSlotFromCurrentWorld(
                activeSlot,
                for: cfgServer,
                logLine: { [weak self] msg in
                    Task { @MainActor in self?.logAppMessage(msg) }
                }
            )

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isWorldSlotsLoading = false
                if updated != nil {
                    self.loadWorldSlotsForSelectedServer()
                    self.loadBackupsForSelectedServer()
                } else {
                    self.showError(
                        title: "Save Failed",
                        message: "Could not save the current world into the active slot. Check the console for details."
                    )
                }
            }
        }
    }

    // MARK: - Create a new fresh world slot

    func createNewWorldSlot(name: String, seed: String?) {
        guard let server = selectedServer,
              let cfgServer = configServer(for: server) else {
            logAppMessage("[WorldSlots] No server selected.")
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            logAppMessage("[WorldSlots] Slot name is empty.")
            return
        }

        isWorldSlotsLoading = true

        Task {
            let slot = await WorldSlotManager.createFreshWorldSlot(
                name: trimmedName,
                seed: seed,
                for: cfgServer,
                logLine: { [weak self] msg in
                    Task { @MainActor in self?.logAppMessage(msg) }
                }
            )

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isWorldSlotsLoading = false
                if slot != nil {
                    self.loadWorldSlotsForSelectedServer()
                } else {
                    self.showError(
                        title: "Create World Failed",
                        message: "Could not create the new world slot. Check the console for details."
                    )
                }
            }
        }
    }

    /// Backwards-compatible wrapper retained for older call sites.
    /// The corrected behavior saves the live world back into the active slot instead of
    /// creating a brand-new snapshot slot. The passed name is ignored intentionally.
    func saveCurrentWorldAsSlot(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            logAppMessage("[WorldSlots] Ignoring legacy slot name \"\(trimmed)\". Save Current World now updates the active persistent slot instead of creating a new slot.")
        }
        saveCurrentWorldToActiveSlot()
    }

    // MARK: - Activate a slot

    /// Swaps the active world for the selected server to the given slot.
    /// Refuses to operate if the server is currently running.
    /// Always creates a backup of the current world before swapping.
    func activateWorldSlot(_ slot: WorldSlot) {
        guard let server = selectedServer,
              let cfgServer = configServer(for: server) else {
            logAppMessage("[WorldSlots] No server selected.")
            return
        }

        // Safety: refuse if this server is the active running one.
        if isServerRunning, configManager.config.activeServerId == cfgServer.id {
            showError(
                title: "Server Is Running",
                message: "Stop \"\(cfgServer.displayName)\" before switching worlds."
            )
            return
        }

        isWorldSlotsLoading = true

        Task {
            let success = await WorldSlotManager.activateSlot(
                slot,
                for: cfgServer,
                backupCurrent: true,
                logLine: { [weak self] msg in
                    Task { @MainActor in self?.logAppMessage(msg) }
                },
                backupWorld: { [weak self] cfg -> Bool in
                    guard let self else { return false }
                    return await self.backupWorld(for: cfg)
                }
            )

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isWorldSlotsLoading = false
                if success {
                    self.loadWorldSlotsForSelectedServer()
                    self.loadBackupsForSelectedServer()
                    self.refreshWorldSize()
                } else {
                    self.showError(
                        title: "Activation Failed",
                        message: "Could not activate slot \"\(slot.name)\". The original world was backed up. Check the console for details."
                    )
                }
            }
        }
    }

    // MARK: - Rename a slot (metadata only)

    func renameWorldSlot(_ slot: WorldSlot, newName: String) {
        guard let server = selectedServer,
              let cfgServer = configServer(for: server) else { return }

        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            _ = try WorldSlotManager.renameSlot(slot, newName: trimmed, serverDir: cfgServer.serverDir)
            logAppMessage("[WorldSlots] Renamed slot to \"\(trimmed)\".")
            loadWorldSlotsForSelectedServer()
        } catch {
            logAppMessage("[WorldSlots] Failed to rename slot: \(error.localizedDescription)")
            showError(title: "Rename Failed", message: error.localizedDescription)
        }
    }

    // MARK: - Delete a slot

    func deleteWorldSlot(_ slot: WorldSlot) {
        guard let server = selectedServer,
              let cfgServer = configServer(for: server) else { return }

        let activeSlotId = WorldSlotManager.resolvedActiveSlotID(forServerDir: cfgServer.serverDir)
        guard activeSlotId != slot.id else {
            logAppMessage("[WorldSlots] Refusing to delete active slot \"\(slot.name)\".")
            showError(
                title: "Delete Blocked",
                message: "Activate a different world slot before deleting \"\(slot.name)\". The active persistent world identity cannot be removed in place."
            )
            return
        }

        do {
            try WorldSlotManager.deleteSlot(slot, serverDir: cfgServer.serverDir)
            logAppMessage("[WorldSlots] Deleted slot \"\(slot.name)\".")
            loadWorldSlotsForSelectedServer()
        } catch {
            logAppMessage("[WorldSlots] Failed to delete slot: \(error.localizedDescription)")
            showError(title: "Delete Failed", message: error.localizedDescription)
        }
    }

    // MARK: - Duplicate a slot (P5)

    /// Copies the source slot's world data into a new slot with a fresh UUID and the given name.
    /// The source slot is untouched. The caller does not need to confirm — this is non-destructive.
    func duplicateWorldSlot(_ slot: WorldSlot, newName: String) {
        guard let server = selectedServer,
              let cfgServer = configServer(for: server) else {
            logAppMessage("[WorldSlots] No server selected.")
            return
        }

        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            logAppMessage("[WorldSlots] Duplicate slot name is empty.")
            return
        }

        isWorldSlotsLoading = true

        Task {
            let newSlot = await WorldSlotManager.duplicateSlot(
                slot,
                newName: trimmed,
                for: cfgServer,
                logLine: { [weak self] msg in
                    Task { @MainActor in self?.logAppMessage(msg) }
                }
            )

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isWorldSlotsLoading = false
                if newSlot != nil {
                    self.loadWorldSlotsForSelectedServer()
                } else {
                    self.showError(
                        title: "Duplicate Failed",
                        message: "Could not duplicate slot \"\(slot.name)\". Check the console for details."
                    )
                }
            }
        }
    }

    // MARK: - Copy slot into existing slot (P5)

    /// Overwrites the destination slot's world data with the source slot's world data.
    /// ⚠️ Destructive. The caller (UI) must confirm with the user before calling this.
    func copyWorldSlot(_ source: WorldSlot, into destination: WorldSlot) {
        guard let server = selectedServer,
              let cfgServer = configServer(for: server) else {
            logAppMessage("[WorldSlots] No server selected.")
            return
        }

        isWorldSlotsLoading = true

        Task {
            let success = await WorldSlotManager.copySlotIntoExisting(
                source,
                into: destination,
                for: cfgServer,
                logLine: { [weak self] msg in
                    Task { @MainActor in self?.logAppMessage(msg) }
                }
            )

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isWorldSlotsLoading = false
                if success {
                    self.loadWorldSlotsForSelectedServer()
                } else {
                    self.showError(
                        title: "Replace Failed",
                        message: "Could not replace slot \"\(destination.name)\" with data from \"\(source.name)\". Check the console for details."
                    )
                }
            }
        }
    }

    // MARK: - Restore a slot from one of its associated backups

    /// Restores a slot-associated backup back into that same slot's saved world.zip.
    /// This does not touch the currently live world folders.
    func restoreSlotBackup(_ backup: BackupItem, into slot: WorldSlot) {
        guard let server = selectedServer,
              let cfgServer = configServer(for: server) else {
            logAppMessage("[WorldSlots] No server selected.")
            return
        }

        guard backup.slotId == slot.id else {
            logAppMessage("[WorldSlots] Refusing to restore backup \"\(backup.filename)\" into slot \"\(slot.name)\" because it belongs to a different slot.")
            showError(
                title: "Wrong Slot",
                message: "This backup belongs to a different world slot and cannot be restored into \"\(slot.name)\"."
            )
            return
        }

        if isServerRunning, configManager.config.activeServerId == cfgServer.id {
            showError(
                title: "Server Is Running",
                message: "Stop \"\(cfgServer.displayName)\" before restoring a slot backup."
            )
            return
        }

        isWorldSlotsLoading = true

        Task {
            let fm = FileManager.default
            let slotDir = WorldSlotManager.slotDirectory(slot: slot, serverDir: cfgServer.serverDir)
            let destZip = WorldSlotManager.zipURL(forSlot: slot, serverDir: cfgServer.serverDir)

            let restoreFailureMessage: String? = await Task.detached(priority: .userInitiated) { () -> String? in
                let tempZip = slotDir.appendingPathComponent("world.restore.tmp.zip")

                do {
                    guard fm.fileExists(atPath: backup.url.path) else {
                        return "The selected backup file no longer exists on disk."
                    }

                    try fm.createDirectory(at: slotDir, withIntermediateDirectories: true)

                    if fm.fileExists(atPath: tempZip.path) {
                        try fm.removeItem(at: tempZip)
                    }

                    try fm.copyItem(at: backup.url, to: tempZip)

                    if fm.fileExists(atPath: destZip.path) {
                        try fm.removeItem(at: destZip)
                    }

                    try fm.moveItem(at: tempZip, to: destZip)
                    return nil
                } catch {
                    if fm.fileExists(atPath: tempZip.path) {
                        try? fm.removeItem(at: tempZip)
                    }
                    return error.localizedDescription
                }
            }.value

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isWorldSlotsLoading = false

                if let message = restoreFailureMessage {
                    self.logAppMessage("[WorldSlots] Failed to restore backup \"\(backup.filename)\" into slot \"\(slot.name)\": \(message)")
                    self.showError(
                        title: "Restore Failed",
                        message: "Could not restore this backup into \"\(slot.name)\": \(message)"
                    )
                } else {
                    self.logAppMessage("[WorldSlots] Restored backup \"\(backup.filename)\" into slot \"\(slot.name)\".")
                    self.loadWorldSlotsForSelectedServer()
                    self.loadBackupsForSelectedServer()
                }
            }
        }
    }

    /// Imports a legacy/unmatched backup ZIP as a brand-new world slot.
    /// The original backup remains untouched in the backups folder.
    func importLegacyBackupAsNewSlot(_ backup: BackupItem) {
        guard let server = selectedServer,
              let cfgServer = configServer(for: server) else {
            logAppMessage("[WorldSlots] No server selected.")
            return
        }

        let proposedName: String = {
            if let slotName = backup.slotName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !slotName.isEmpty {
                return slotName
            }

            let trimmedDisplayName = backup.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedDisplayName.isEmpty {
                return "Imported \(trimmedDisplayName)"
            }

            return "Imported Backup"
        }()

        Task {
            let archiveValid = await validateZipArchive(backup.url, logPrefix: "[WorldSlots]")
            guard archiveValid else {
                await MainActor.run {
                    self.showError(
                        title: "Import Failed",
                        message: "The selected backup ZIP could not be opened, so no world slot was created."
                    )
                }
                return
            }

            let success = await importZIPAsSlot(zipURL: backup.url, name: proposedName)

            await MainActor.run { [weak self] in
                guard let self else { return }

                if success {
                    self.logAppMessage("[WorldSlots] Imported legacy backup \"\(backup.filename)\" as new slot \"\(proposedName)\" for \(cfgServer.displayName).")
                } else {
                    self.logAppMessage("[WorldSlots] Failed to import legacy backup \"\(backup.filename)\" as a new slot for \(cfgServer.displayName).")
                    self.showError(
                        title: "Import Failed",
                        message: "Could not create a new world slot from this backup. Check the console for details."
                    )
                }
            }
        }
    }

    // MARK: - Export a slot's ZIP (P5)

    /// Copies the slot's world.zip to the supplied destinationURL.
    /// NSSavePanel must be shown by the UI before calling this — this method only does the file copy.
    func exportWorldSlot(_ slot: WorldSlot, to destinationURL: URL) {
        guard let server = selectedServer,
              let cfgServer = configServer(for: server) else {
            logAppMessage("[WorldSlots] No server selected.")
            return
        }

        isWorldSlotsLoading = true

        Task {
            let success = await WorldSlotManager.exportSlotZIP(
                slot,
                from: cfgServer.serverDir,
                to: destinationURL,
                logLine: { [weak self] msg in
                    Task { @MainActor in self?.logAppMessage(msg) }
                }
            )

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isWorldSlotsLoading = false
                if !success {
                    self.showError(
                        title: "Export Failed",
                        message: "Could not export slot \"\(slot.name)\". Check the console for details."
                    )
                }
                // No loadWorldSlotsForSelectedServer() needed — export doesn't change slot state.
            }
        }
    }

    // MARK: - Import external ZIP as new slot (P6)

    /// Unzips an external world ZIP into a new named slot directory.
    /// The zip must contain world folder(s) at its root (same layout produced by createSlot).
    /// Returns true on success. The NSSavePanel / NSOpenPanel is the UI's responsibility.
    func importZIPAsSlot(zipURL: URL, name: String) async -> Bool {
        guard let server = selectedServer,
              let cfgServer = configServer(for: server) else {
            logAppMessage("[WorldSlots] importZIPAsSlot: no server selected.")
            return false
        }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            logAppMessage("[WorldSlots] importZIPAsSlot: name is empty.")
            return false
        }

        await MainActor.run { isWorldSlotsLoading = true }

        let slotId = UUID().uuidString
        let now = Date()
        var slot = WorldSlot(id: slotId, name: trimmed, createdAt: now, lastPlayedAt: nil)

        let slotsDir = WorldSlotManager.slotsDirectory(forServerDir: cfgServer.serverDir)
        let slotDir = slotsDir.appendingPathComponent(slotId, isDirectory: true)
        let destZip = slotDir.appendingPathComponent("world.zip")

        let fm = FileManager.default
        let logLine: (String) -> Void = { [weak self] msg in
            Task { @MainActor in self?.logAppMessage(msg) }
        }

        // Create the slot directory.
        do {
            try fm.createDirectory(at: slotDir, withIntermediateDirectories: true)
        } catch {
            logLine("[WorldSlots] importZIPAsSlot: could not create slot dir: \(error.localizedDescription)")
            await MainActor.run { isWorldSlotsLoading = false }
            return false
        }

        // Copy the external ZIP into the slot directory as world.zip.
        let copyOk: Bool = await Task.detached(priority: .userInitiated) {
            do {
                if fm.fileExists(atPath: destZip.path) {
                    try fm.removeItem(at: destZip)
                }
                try fm.copyItem(at: zipURL, to: destZip)
                return true
            } catch {
                return false
            }
        }.value

        guard copyOk else {
            logLine("[WorldSlots] importZIPAsSlot: failed to copy ZIP.")
            try? fm.removeItem(at: slotDir)
            await MainActor.run { isWorldSlotsLoading = false }
            return false
        }

        // Populate zip size.
        if let attrs = try? fm.attributesOfItem(atPath: destZip.path),
           let size = attrs[.size] as? Int64 {
            slot.zipSizeBytes = size
        }

        // Write metadata.
        do {
            try WorldSlotManager.saveMetadata(slot, serverDir: cfgServer.serverDir)
        } catch {
            logLine("[WorldSlots] importZIPAsSlot: could not write metadata: \(error.localizedDescription)")
            try? fm.removeItem(at: slotDir)
            await MainActor.run { isWorldSlotsLoading = false }
            return false
        }

        logLine("[WorldSlots] Imported \"\(trimmed)\" from \(zipURL.lastPathComponent).")

        await MainActor.run { [weak self] in
            self?.isWorldSlotsLoading = false
            self?.loadWorldSlotsForSelectedServer()
        }
        return true
    }

    // MARK: - Auto-create initial slot on first stop

    /// Called automatically after the server's first stop (Java or Bedrock).
    /// Creates a persistent slot from the current world if no slots exist yet,
    /// then marks it as the explicit active slot. Safe to call on every stop.
    func createInitialWorldSlotIfNeeded(for cfgServer: ConfigServer) {
        let existing = WorldSlotManager.loadSlots(forServerDir: cfgServer.serverDir)
        guard existing.isEmpty else { return }

        let worldFolders = WorldSlotManager.worldFolderNames(for: cfgServer)
        guard !worldFolders.isEmpty else { return }

        let slotName = defaultPersistentSlotName(for: cfgServer)
        logAppMessage("[WorldSlots] Auto-creating initial world slot \"\(slotName)\".")

        Task {
            let slot = await WorldSlotManager.createSlot(
                name: slotName,
                for: cfgServer,
                logLine: { [weak self] msg in
                    Task { @MainActor in self?.logAppMessage(msg) }
                }
            )

            await MainActor.run { [weak self] in
                guard let self, var created = slot else { return }
                created.lastPlayedAt = Date()
                do {
                    try WorldSlotManager.saveMetadata(created, serverDir: cfgServer.serverDir)
                    try WorldSlotManager.setActiveSlotID(created.id, forServerDir: cfgServer.serverDir)
                    self.logAppMessage("[WorldSlots] Initial world slot \"\(slotName)\" created and set as active.")
                } catch {
                    self.logAppMessage("[WorldSlots] Failed to finalize initial slot: \(error.localizedDescription)")
                }
                self.loadWorldSlotsForSelectedServer()
            }
        }
    }

    // MARK: - Active slot helpers

    func activeWorldSlot(for server: Server) -> WorldSlot? {
        guard let cfgServer = configServer(for: server) else { return nil }
        return WorldSlotManager.activeSlot(forServerDir: cfgServer.serverDir)
    }

    /// Returns the name of the explicit active persistent world slot for the given server.
    func activeWorldSlotName(for server: Server) -> String? {
        activeWorldSlot(for: server)?.name
    }

    /// Returns the id of the explicit active persistent world slot for the given server dir.
    func activeWorldSlotId(forServerDir serverDir: String) -> String? {
        WorldSlotManager.resolvedActiveSlotID(forServerDir: serverDir)
    }
}

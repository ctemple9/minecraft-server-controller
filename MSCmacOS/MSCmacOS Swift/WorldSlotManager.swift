// WorldSlotManager.swift
// MinecraftServerController
//
//
// Provides Realms-style named world snapshots for both Java and Bedrock servers.
//
// Directory layout (per server):
//   {serverDir}/world_slots/
//       {slotId}/
//           world.zip          — zipped world folder(s)
//           slot.json          — WorldSlot metadata
//           thumbnail.png      — optional screenshot (future)
//
// Java world folders: level-name, level-name_nether, level-name_the_end
//   (resolved from server.properties["level-name"])
// Bedrock world folders: worlds/
//   (fixed location inside the BDS /data volume, always "worlds")
//
// The server MUST be stopped before any slot operation that touches world data.
// WorldSlotManager enforces nothing here — the caller (AppViewModel) is responsible.

import Foundation

// MARK: - WorldSlot model

struct WorldSlot: Identifiable, Codable, Hashable {
    var id: String          // UUID string
    var name: String        // user-facing display name
    var createdAt: Date
    var lastPlayedAt: Date? // nil until the slot has been activated at least once
    var thumbnailFileName: String? // relative to slot directory; future use

    /// Canonical level-name identity for this slot.
    /// Java: folder prefix for overworld/nether/end.
    /// Bedrock: value written to server.properties["level-name"].
    /// Nil for legacy imported slots until inferred or resaved.
    var worldLevelName: String? = nil

    /// Optional seed associated with this world slot.
    /// Freshly generated slots store the requested seed up front. Imported worlds may
    /// also carry a best-effort recovered seed when MSC can safely discover it.
    /// The stored value is only reapplied when generating a fresh world for this slot.
    var worldSeed: String? = nil

    // Not stored in JSON — computed on load from zip file size.
    var zipSizeBytes: Int64? = nil

    // MARK: Codable

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt       = "created_at"
        case lastPlayedAt    = "last_played_at"
        case thumbnailFileName = "thumbnail_file_name"
        case worldLevelName  = "world_level_name"
        case worldSeed       = "world_seed"
        // zipSizeBytes is intentionally excluded — it's computed from disk.
    }
}

// MARK: - WorldSlotManager

/// Handles all file system operations for world slots.
/// All methods that do significant I/O (zip/unzip) are async and run on a background thread.
/// Methods that only read metadata are synchronous.
enum WorldSlotManager {

    // MARK: - Directory helpers

    /// Returns the world_slots directory for a given server directory, creating it if needed.
    static func slotsDirectory(forServerDir serverDir: String) -> URL {
        URL(fileURLWithPath: serverDir, isDirectory: true)
            .appendingPathComponent("world_slots", isDirectory: true)
    }

    static func slotDirectory(slot: WorldSlot, serverDir: String) -> URL {
        slotsDirectory(forServerDir: serverDir)
            .appendingPathComponent(slot.id, isDirectory: true)
    }

    static func zipURL(forSlot slot: WorldSlot, serverDir: String) -> URL {
        slotDirectory(slot: slot, serverDir: serverDir)
            .appendingPathComponent("world.zip")
    }

    static func metadataURL(forSlot slot: WorldSlot, serverDir: String) -> URL {
        slotDirectory(slot: slot, serverDir: serverDir)
            .appendingPathComponent("slot.json")
    }

    static func activeSlotIDURL(forServerDir serverDir: String) -> URL {
        slotsDirectory(forServerDir: serverDir)
            .appendingPathComponent("active_slot_id.txt")
    }

    static func loadExplicitActiveSlotID(forServerDir serverDir: String) -> String? {
        let url = activeSlotIDURL(forServerDir: serverDir)
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func setActiveSlotID(_ slotID: String?, forServerDir serverDir: String) throws {
        let fm = FileManager.default
        let slotsDir = slotsDirectory(forServerDir: serverDir)
        try fm.createDirectory(at: slotsDir, withIntermediateDirectories: true)

        let url = activeSlotIDURL(forServerDir: serverDir)
        guard let slotID else {
            if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
            }
            return
        }

        try (slotID + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    static func resolvedActiveSlotID(forServerDir serverDir: String) -> String? {
        let slots = loadSlots(forServerDir: serverDir)
        guard !slots.isEmpty else { return nil }

        if let explicit = loadExplicitActiveSlotID(forServerDir: serverDir),
           slots.contains(where: { $0.id == explicit }) {
            return explicit
        }

        if let legacy = slots
            .filter({ $0.lastPlayedAt != nil })
            .max(by: { ($0.lastPlayedAt ?? .distantPast) < ($1.lastPlayedAt ?? .distantPast) })?.id {
            return legacy
        }

        return slots.max(by: { $0.createdAt < $1.createdAt })?.id
    }

    static func activeSlot(forServerDir serverDir: String) -> WorldSlot? {
        let slots = loadSlots(forServerDir: serverDir)
        guard let activeID = resolvedActiveSlotID(forServerDir: serverDir) else { return nil }
        return slots.first(where: { $0.id == activeID })
    }

    // MARK: - World folder resolution

    static func currentLevelName(for configServer: ConfigServer) -> String {
        switch configServer.serverType {
        case .bedrock:
            let raw = BedrockPropertiesManager.readModel(serverDir: configServer.serverDir).levelName
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return raw.isEmpty ? "Bedrock level" : raw
        case .java:
            let props = ServerPropertiesManager.readProperties(serverDir: configServer.serverDir)
            return (props["level-name"]?
                .trimmingCharacters(in: .whitespacesAndNewlines))
                .flatMap { $0.isEmpty ? nil : $0 } ?? "world"
        }
    }

    static func sanitizedWorldLevelName(_ raw: String, fallback: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }

        let invalid = CharacterSet(charactersIn: "/\\:\n\r\t")
        let components = trimmed.components(separatedBy: invalid)
        let collapsed = components
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))

        return collapsed.isEmpty ? fallback : collapsed
    }

    static func inferJavaLevelName(fromSlotZIP zipURL: URL) -> String? {
        let output: String? = try? {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-Z", "-1", zipURL.path]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        }()

        guard let output else { return nil }

        let roots = Set(output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                let first = trimmed.split(separator: "/", maxSplits: 1).first.map(String.init) ?? trimmed
                guard !first.isEmpty, first != "__MACOSX" else { return nil }
                return first
            })

        guard !roots.isEmpty else { return nil }

        let plain = roots.filter { !$0.hasSuffix("_nether") && !$0.hasSuffix("_the_end") }.sorted()
        if let best = plain.first { return best }
        if let suffixed = roots.sorted().first {
            if suffixed.hasSuffix("_nether") { return String(suffixed.dropLast("_nether".count)) }
            if suffixed.hasSuffix("_the_end") { return String(suffixed.dropLast("_the_end".count)) }
        }
        return nil
    }

    static func inferredWorldLevelName(for slot: WorldSlot, serverDir: String, serverType: ServerType) -> String? {
        if let stored = slot.worldLevelName?.trimmingCharacters(in: .whitespacesAndNewlines), !stored.isEmpty {
            return stored
        }

        switch serverType {
        case .bedrock:
            return nil
        case .java:
            return inferJavaLevelName(fromSlotZIP: zipURL(forSlot: slot, serverDir: serverDir))
        }
    }

    /// Returns the list of world folder *names* (relative to serverDir) for a given ConfigServer.
    ///
    /// Java: reads level-name from server.properties, returns [level, level_nether, level_the_end]
    ///       (only folders that actually exist on disk are included).
    /// Bedrock: always returns ["worlds"] if that directory exists.
    static func worldFolderNames(for configServer: ConfigServer) -> [String] {
        let serverDirURL = URL(fileURLWithPath: configServer.serverDir, isDirectory: true)
        let fm = FileManager.default

        switch configServer.serverType {
        case .bedrock:
            let worldsURL = serverDirURL.appendingPathComponent("worlds", isDirectory: true)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: worldsURL.path, isDirectory: &isDir), isDir.boolValue {
                return ["worlds"]
            }
            return []

        case .java:
            let props = ServerPropertiesManager.readProperties(serverDir: configServer.serverDir)
            let levelName = (props["level-name"]?
                .trimmingCharacters(in: .whitespacesAndNewlines))
                .flatMap { $0.isEmpty ? nil : $0 } ?? "world"

            let candidates = [levelName, "\(levelName)_nether", "\(levelName)_the_end"]
            return candidates.filter { name in
                let url = serverDirURL.appendingPathComponent(name, isDirectory: true)
                var isDir: ObjCBool = false
                return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
            }
        }
    }

    // MARK: - Load all slots

    /// Reads all slot metadata from disk, sorted newest-first by createdAt.
    /// Also populates zipSizeBytes from the zip file on disk (cheap stat, not slow).
    static func loadSlots(forServerDir serverDir: String) -> [WorldSlot] {
        let slotsDir = slotsDirectory(forServerDir: serverDir)
        let fm = FileManager.default

        guard fm.fileExists(atPath: slotsDir.path) else { return [] }

        let entries: [URL]
        do {
            entries = try fm.contentsOfDirectory(
                at: slotsDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }

        var slots: [WorldSlot] = []

        for entry in entries {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            let metaURL = entry.appendingPathComponent("slot.json")
            guard let data = try? Data(contentsOf: metaURL) else { continue }

            var slot: WorldSlot
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                slot = try decoder.decode(WorldSlot.self, from: data)
            } catch {
                continue
            }

            // Populate zip size without blocking (just a stat).
            let zipPath = entry.appendingPathComponent("world.zip")
            if let attrs = try? fm.attributesOfItem(atPath: zipPath.path),
               let size = attrs[.size] as? Int64 {
                slot.zipSizeBytes = size
            }

            slots.append(slot)
        }

        // Newest first.
        return slots.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Save metadata

    static func saveMetadata(_ slot: WorldSlot, serverDir: String) throws {
        let fm = FileManager.default
        let dir = slotDirectory(slot: slot, serverDir: serverDir)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(slot)
        try data.write(to: metadataURL(forSlot: slot, serverDir: serverDir), options: .atomic)
    }

    // MARK: - Create a new slot from current world

    /// Zips the current world folder(s) into a new named slot.
    /// Returns the new WorldSlot on success, nil on failure.
    /// - Parameters:
    ///   - name: Display name for the slot.
    ///   - configServer: The server whose world we're saving.
    ///   - logLine: Called for progress/error messages.
    static func createSlot(
        name: String,
        for configServer: ConfigServer,
        worldSeed: String? = nil,
        logLine: @escaping (String) -> Void
    ) async -> WorldSlot? {
        let serverDirURL = URL(fileURLWithPath: configServer.serverDir, isDirectory: true)
        let worldFolders = worldFolderNames(for: configServer)

        guard !worldFolders.isEmpty else {
            logLine("[WorldSlots] No world folders found for \(configServer.displayName) — nothing to save.")
            return nil
        }

        let slotId = UUID().uuidString
        let now = Date()
        let trimmedSeed = worldSeed?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSeed = (trimmedSeed?.isEmpty == false) ? trimmedSeed : nil

        var slot = WorldSlot(
            id: slotId,
            name: name,
            createdAt: now,
            lastPlayedAt: nil,
            worldLevelName: currentLevelName(for: configServer),
            worldSeed: normalizedSeed
        )

        let slotsDir = slotsDirectory(forServerDir: configServer.serverDir)
        let slotDir = slotsDir.appendingPathComponent(slotId, isDirectory: true)
        let zipPath = slotDir.appendingPathComponent("world.zip")

        let fm = FileManager.default
        do {
            try fm.createDirectory(at: slotDir, withIntermediateDirectories: true)
        } catch {
            logLine("[WorldSlots] Failed to create slot directory: \(error.localizedDescription)")
            return nil
        }

        logLine("[WorldSlots] Saving slot \"\(name)\" — zipping \(worldFolders.joined(separator: ", "))...")

        let status: Int32 = await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.currentDirectoryURL = serverDirURL
            process.arguments = ["-r", zipPath.path] + worldFolders
            do {
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus
            } catch {
                return -1
            }
        }.value

        guard status == 0 else {
            logLine("[WorldSlots] zip failed (status \(status)) for slot \"\(name)\".")
            try? fm.removeItem(at: slotDir)
            return nil
        }

        if let attrs = try? fm.attributesOfItem(atPath: zipPath.path),
           let size = attrs[.size] as? Int64 {
            slot.zipSizeBytes = size
        }

        do {
            try saveMetadata(slot, serverDir: configServer.serverDir)
        } catch {
            logLine("[WorldSlots] Failed to write slot metadata: \(error.localizedDescription)")
            try? fm.removeItem(at: slotDir)
            return nil
        }

        logLine("[WorldSlots] Slot \"\(name)\" saved (\(formatBytes(slot.zipSizeBytes ?? 0))).")
        return slot
    }

    static func updateSlotFromCurrentWorld(
        _ slot: WorldSlot,
        for configServer: ConfigServer,
        logLine: @escaping (String) -> Void
    ) async -> WorldSlot? {
        let serverDirURL = URL(fileURLWithPath: configServer.serverDir, isDirectory: true)
        let worldFolders = worldFolderNames(for: configServer)

        guard !worldFolders.isEmpty else {
            logLine("[WorldSlots] No world folders found for \(configServer.displayName) — nothing to save into active slot \"\(slot.name)\".")
            return nil
        }

        let fm = FileManager.default
        let slotDir = slotDirectory(slot: slot, serverDir: configServer.serverDir)
        let zipPath = zipURL(forSlot: slot, serverDir: configServer.serverDir)
        let tempZip = slotDir.appendingPathComponent("world.update.tmp.zip")

        do {
            try fm.createDirectory(at: slotDir, withIntermediateDirectories: true)
            if fm.fileExists(atPath: tempZip.path) {
                try fm.removeItem(at: tempZip)
            }
        } catch {
            logLine("[WorldSlots] Failed to prepare slot directory for \"\(slot.name)\": \(error.localizedDescription)")
            return nil
        }

        logLine("[WorldSlots] Updating active slot \"\(slot.name)\" from current world data...")

        let status: Int32 = await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.currentDirectoryURL = serverDirURL
            process.arguments = ["-r", tempZip.path] + worldFolders
            do {
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus
            } catch {
                return -1
            }
        }.value

        guard status == 0 else {
            logLine("[WorldSlots] zip failed (status \(status)) while updating slot \"\(slot.name)\".")
            try? fm.removeItem(at: tempZip)
            return nil
        }

        do {
            if fm.fileExists(atPath: zipPath.path) {
                try fm.removeItem(at: zipPath)
            }
            try fm.moveItem(at: tempZip, to: zipPath)
        } catch {
            logLine("[WorldSlots] Failed to replace world archive for slot \"\(slot.name)\": \(error.localizedDescription)")
            try? fm.removeItem(at: tempZip)
            return nil
        }

        var updated = slot
        updated.worldLevelName = currentLevelName(for: configServer)
        if let attrs = try? fm.attributesOfItem(atPath: zipPath.path),
           let size = attrs[.size] as? Int64 {
            updated.zipSizeBytes = size
        }

        do {
            try saveMetadata(updated, serverDir: configServer.serverDir)
        } catch {
            logLine("[WorldSlots] Failed to write updated metadata for slot \"\(slot.name)\": \(error.localizedDescription)")
            return nil
        }

        logLine("[WorldSlots] Active slot \"\(slot.name)\" updated (\(formatBytes(updated.zipSizeBytes ?? 0))).")
        return updated
    }

    static func createFreshWorldSlot(
        name: String,
        seed: String?,
        for configServer: ConfigServer,
        logLine: @escaping (String) -> Void
    ) async -> WorldSlot? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            logLine("[WorldSlots] Fresh world slot name is empty.")
            return nil
        }

        let fallbackLevelName = configServer.serverType == .bedrock ? "Bedrock level" : "world"
        let levelName = sanitizedWorldLevelName(trimmedName, fallback: fallbackLevelName)
        let trimmedSeed = seed?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSeed = (trimmedSeed?.isEmpty == false) ? trimmedSeed : nil

        let slotId = UUID().uuidString
        let now = Date()
        let slot = WorldSlot(
            id: slotId,
            name: trimmedName,
            createdAt: now,
            lastPlayedAt: nil,
            worldLevelName: levelName,
            worldSeed: normalizedSeed
        )

        let slotDir = slotDirectory(slot: slot, serverDir: configServer.serverDir)
        do {
            try FileManager.default.createDirectory(at: slotDir, withIntermediateDirectories: true)
            try saveMetadata(slot, serverDir: configServer.serverDir)
        } catch {
            logLine("[WorldSlots] Failed to create fresh world slot \"\(trimmedName)\": \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: slotDir)
            return nil
        }

        if let normalizedSeed {
            logLine("[WorldSlots] Created fresh world slot \"\(trimmedName)\" with seed \"\(normalizedSeed)\". The world will generate when the slot is first activated.")
        } else {
            logLine("[WorldSlots] Created fresh world slot \"\(trimmedName)\". The world will generate when the slot is first activated.")
        }
        return slot
    }

    private static func applyWorldIdentity(
        levelName: String,
        seed: String?,
        applySeed: Bool,
        for configServer: ConfigServer,
        logLine: @escaping (String) -> Void
    ) -> Bool {
        switch configServer.serverType {
        case .java:
            var props = ServerPropertiesManager.readProperties(serverDir: configServer.serverDir)
            props["level-name"] = levelName
            if applySeed {
                if let seed, !seed.isEmpty {
                    props["level-seed"] = seed
                } else {
                    props.removeValue(forKey: "level-seed")
                }
            }
            do {
                try ServerPropertiesManager.writeProperties(props, to: configServer.serverDir)
                return true
            } catch {
                logLine("[WorldSlots] Failed to update server.properties for \(configServer.displayName): \(error.localizedDescription)")
                return false
            }

        case .bedrock:
            var props = BedrockPropertiesManager.readRawProperties(serverDir: configServer.serverDir)
            props["level-name"] = levelName
            if applySeed {
                if let seed, !seed.isEmpty {
                    props["level-seed"] = seed
                } else {
                    props.removeValue(forKey: "level-seed")
                }
            }
            do {
                try BedrockPropertiesManager.writeRawProperties(props, serverDir: configServer.serverDir)
                return true
            } catch {
                logLine("[WorldSlots] Failed to update Bedrock server.properties for \(configServer.displayName): \(error.localizedDescription)")
                return false
            }
        }
    }

    // MARK: - Activate a slot

    /// Activates a saved slot by:
    ///   1. Auto-backing up the current world (safety net).
    ///   2. Removing current world folder(s).
    ///   3. Unzipping the slot's world.zip into serverDir.
    ///   4. Updating slot.lastPlayedAt.
    ///
    /// The server must already be stopped. Caller is responsible for that check.
    ///
    /// - Returns: true on success, false on any failure.
    static func activateSlot(
        _ slot: WorldSlot,
        for configServer: ConfigServer,
        backupCurrent: Bool,
        logLine: @escaping (String) -> Void,
        backupWorld: (ConfigServer) async -> Bool
    ) async -> Bool {
        let serverDirURL = URL(fileURLWithPath: configServer.serverDir, isDirectory: true)
        let fm = FileManager.default
        let zipPath = zipURL(forSlot: slot, serverDir: configServer.serverDir)
        let currentFolders = worldFolderNames(for: configServer)

        let storedLevelName = inferredWorldLevelName(for: slot, serverDir: configServer.serverDir, serverType: configServer.serverType)
        let freshLevelName = slot.worldLevelName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasArchivedZip = fm.fileExists(atPath: zipPath.path)
        let willGenerateFresh = !hasArchivedZip && (freshLevelName?.isEmpty == false)

        guard hasArchivedZip || willGenerateFresh else {
            logLine("[WorldSlots] Slot \"\(slot.name)\" has no saved world archive and no fresh-world generation metadata.")
            return false
        }

        if backupCurrent, !currentFolders.isEmpty {
            logLine("[WorldSlots] Backing up current world before activating slot \"\(slot.name)\"...")
            let ok = await backupWorld(configServer)
            if !ok {
                logLine("[WorldSlots] Pre-activation backup failed; aborting activation so the current world stays untouched.")
                return false
            }
        } else if currentFolders.isEmpty {
            logLine("[WorldSlots] No current world folders found; skipping pre-activation backup.")
        }

        let removeOk: Bool = await Task.detached(priority: .userInitiated) {
            do {
                for name in currentFolders {
                    let url = serverDirURL.appendingPathComponent(name, isDirectory: true)
                    if fm.fileExists(atPath: url.path) {
                        try fm.removeItem(at: url)
                    }
                }
                return true
            } catch {
                return false
            }
        }.value

        guard removeOk else {
            logLine("[WorldSlots] Failed to remove current world folders for \(configServer.displayName).")
            return false
        }

        var updated = slot
        updated.lastPlayedAt = Date()

        if hasArchivedZip {
            if let storedLevelName, !storedLevelName.isEmpty {
                guard applyWorldIdentity(levelName: storedLevelName, seed: nil, applySeed: false, for: configServer, logLine: logLine) else {
                    return false
                }
                updated.worldLevelName = storedLevelName
            }

            logLine("[WorldSlots] Activating slot \"\(slot.name)\" — extracting world...")
            let unzipStatus: Int32 = await Task.detached(priority: .userInitiated) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                process.arguments = ["-o", zipPath.path, "-d", serverDirURL.path]
                do {
                    try process.run()
                    process.waitUntilExit()
                    return process.terminationStatus
                } catch {
                    return -1
                }
            }.value

            guard unzipStatus == 0 else {
                logLine("[WorldSlots] unzip failed (status \(unzipStatus)) for slot \"\(slot.name)\".")
                return false
            }
        } else {
            let levelName = sanitizedWorldLevelName(freshLevelName ?? slot.name, fallback: currentLevelName(for: configServer))
            guard applyWorldIdentity(levelName: levelName, seed: slot.worldSeed, applySeed: true, for: configServer, logLine: logLine) else {
                return false
            }
            updated.worldLevelName = levelName
            logLine("[WorldSlots] Fresh world slot \"\(slot.name)\" activated. A new world will generate for level-name \"\(levelName)\" the next time the server starts.")
        }

        do {
            try saveMetadata(updated, serverDir: configServer.serverDir)
        } catch {
            logLine("[WorldSlots] Warning: could not update slot metadata: \(error.localizedDescription)")
        }

        do {
            try setActiveSlotID(updated.id, forServerDir: configServer.serverDir)
        } catch {
            logLine("[WorldSlots] Warning: could not persist active slot identity: \(error.localizedDescription)")
        }

        logLine("[WorldSlots] Slot \"\(slot.name)\" is now active.")
        return true
    }

    // MARK: - Rename a slot (metadata only)

    static func renameSlot(_ slot: WorldSlot, newName: String, serverDir: String) throws -> WorldSlot {
        var updated = slot
        updated.name = newName
        try saveMetadata(updated, serverDir: serverDir)
        return updated
    }

    // MARK: - Delete a slot

    static func deleteSlot(_ slot: WorldSlot, serverDir: String) throws {
        let dir = slotDirectory(slot: slot, serverDir: serverDir)
        try FileManager.default.removeItem(at: dir)
    }

    // MARK: - Duplicate a slot to a new named slot (P5)

    /// Copies the source slot's world.zip into a brand-new slot directory with a fresh UUID.
    /// The source slot is left completely untouched.
    /// - Returns: The newly created WorldSlot on success, nil on failure.
    static func duplicateSlot(
        _ slot: WorldSlot,
        newName: String,
        for configServer: ConfigServer,
        logLine: @escaping (String) -> Void
    ) async -> WorldSlot? {
        let fm = FileManager.default

        let sourceZip = zipURL(forSlot: slot, serverDir: configServer.serverDir)
        guard fm.fileExists(atPath: sourceZip.path) else {
            logLine("[WorldSlots] Duplicate: source zip not found for slot \"\(slot.name)\".")
            return nil
        }

        // New slot gets a brand-new UUID — never reuse the source id.
        let newId = UUID().uuidString
        let now = Date()
        var newSlot = WorldSlot(id: newId, name: newName, createdAt: now, lastPlayedAt: nil, worldLevelName: slot.worldLevelName, worldSeed: slot.worldSeed)

        let slotsDir = slotsDirectory(forServerDir: configServer.serverDir)
        let newSlotDir = slotsDir.appendingPathComponent(newId, isDirectory: true)
        let destZip = newSlotDir.appendingPathComponent("world.zip")

        do {
            try fm.createDirectory(at: newSlotDir, withIntermediateDirectories: true)
        } catch {
            logLine("[WorldSlots] Duplicate: failed to create slot directory: \(error.localizedDescription)")
            return nil
        }

        logLine("[WorldSlots] Duplicating slot \"\(slot.name)\" → \"\(newName)\"...")

        let copyOk: Bool = await Task.detached(priority: .userInitiated) {
            do {
                try fm.copyItem(at: sourceZip, to: destZip)
                return true
            } catch {
                return false
            }
        }.value

        guard copyOk else {
            logLine("[WorldSlots] Duplicate: file copy failed.")
            try? fm.removeItem(at: newSlotDir)
            return nil
        }

        // Populate zip size.
        if let attrs = try? fm.attributesOfItem(atPath: destZip.path),
           let size = attrs[.size] as? Int64 {
            newSlot.zipSizeBytes = size
        }

        do {
            try saveMetadata(newSlot, serverDir: configServer.serverDir)
        } catch {
            logLine("[WorldSlots] Duplicate: failed to write metadata: \(error.localizedDescription)")
            try? fm.removeItem(at: newSlotDir)
            return nil
        }

        logLine("[WorldSlots] Duplicate complete: \"\(newName)\" (\(formatBytes(newSlot.zipSizeBytes ?? 0))).")
        return newSlot
    }

    // MARK: - Copy slot into existing slot (P5)

    /// Overwrites the destination slot's world.zip with the source slot's world.zip.
    /// The destination slot's id and name are preserved; only world data and createdAt are updated.
    ///
    /// ⚠️ This is destructive. The caller must confirm with the user before invoking this.
    ///
    /// - Returns: true on success, false on failure.
    static func copySlotIntoExisting(
        _ source: WorldSlot,
        into destination: WorldSlot,
        for configServer: ConfigServer,
        logLine: @escaping (String) -> Void
    ) async -> Bool {
        let fm = FileManager.default

        let sourceZip = zipURL(forSlot: source, serverDir: configServer.serverDir)
        let destZip = zipURL(forSlot: destination, serverDir: configServer.serverDir)

        guard fm.fileExists(atPath: sourceZip.path) else {
            logLine("[WorldSlots] CopyInto: source zip not found for slot \"\(source.name)\".")
            return false
        }

        // Ensure destination slot directory exists (it should, but be safe).
        let destSlotDir = slotDirectory(slot: destination, serverDir: configServer.serverDir)
        do {
            try fm.createDirectory(at: destSlotDir, withIntermediateDirectories: true)
        } catch {
            logLine("[WorldSlots] CopyInto: could not ensure destination directory: \(error.localizedDescription)")
            return false
        }

        logLine("[WorldSlots] Replacing slot \"\(destination.name)\" with data from \"\(source.name)\"...")

        let copyFailureMessage: String? = await Task.detached(priority: .userInitiated) { () -> String? in
            let tempZip = destSlotDir.appendingPathComponent("world.replace.tmp.zip")

            do {
                if fm.fileExists(atPath: tempZip.path) {
                    try fm.removeItem(at: tempZip)
                }

                try fm.copyItem(at: sourceZip, to: tempZip)

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

        if let message = copyFailureMessage {
            logLine("[WorldSlots] CopyInto: file copy failed: \(message)")
            return false
        }

        // Update metadata: preserve id and name, refresh createdAt to signal new content.
        var updated = destination
        updated.createdAt = Date()
        updated.worldLevelName = source.worldLevelName
        updated.worldSeed = source.worldSeed
        if let attrs = try? fm.attributesOfItem(atPath: destZip.path),
           let size = attrs[.size] as? Int64 {
            updated.zipSizeBytes = size
        }

        do {
            try saveMetadata(updated, serverDir: configServer.serverDir)
        } catch {
            // Non-fatal — world data is already in place.
            logLine("[WorldSlots] CopyInto: warning — could not update metadata: \(error.localizedDescription)")
        }

        logLine("[WorldSlots] Slot \"\(destination.name)\" replaced with data from \"\(source.name)\".")
        return true
    }

    // MARK: - Export a slot's ZIP to a destination URL (P5)

    /// Copies the slot's world.zip to the caller-supplied destinationURL.
    /// Opening NSSavePanel is the UI's responsibility — this method only performs the copy.
    /// - Returns: true on success, false on failure.
    static func exportSlotZIP(
        _ slot: WorldSlot,
        from serverDir: String,
        to destinationURL: URL,
        logLine: @escaping (String) -> Void
    ) async -> Bool {
        let fm = FileManager.default
        let sourceZip = zipURL(forSlot: slot, serverDir: serverDir)

        guard fm.fileExists(atPath: sourceZip.path) else {
            logLine("[WorldSlots] Export: zip not found for slot \"\(slot.name)\".")
            return false
        }

        logLine("[WorldSlots] Exporting slot \"\(slot.name)\" → \(destinationURL.path)...")

        let copyOk: Bool = await Task.detached(priority: .userInitiated) {
            do {
                // If a file already exists at the destination, remove it first so copyItem succeeds.
                if fm.fileExists(atPath: destinationURL.path) {
                    try fm.removeItem(at: destinationURL)
                }
                try fm.copyItem(at: sourceZip, to: destinationURL)
                return true
            } catch {
                return false
            }
        }.value

        if copyOk {
            logLine("[WorldSlots] Export complete: \(destinationURL.lastPathComponent)")
        } else {
            logLine("[WorldSlots] Export failed for slot \"\(slot.name)\".")
        }

        return copyOk
    }

    // MARK: - Create a slot from an external ZIP (P6)

    /// Imports an external ZIP file as a new named world slot.
    /// The ZIP is copied verbatim into the slot directory — no re-zipping is performed.
    /// This is the backing implementation for "Import ZIP as New Slot" in the Edit Server
    /// World tab. The ZIP should contain world folder(s) at its root (same structure the
    /// app produces when it exports a slot), but no structural validation is enforced here —
    /// if the ZIP is malformed the slot will be stored but activation will fail.
    ///
    /// - Returns: The newly created WorldSlot on success, nil on failure.
    static func createSlotFromZIP(
        zipURL: URL,
        name: String,
        for configServer: ConfigServer,
        logLine: @escaping (String) -> Void
    ) async -> WorldSlot? {
        let fm = FileManager.default

        guard fm.fileExists(atPath: zipURL.path) else {
            logLine("[WorldSlots] createSlotFromZIP: ZIP not found at \(zipURL.path)")
            return nil
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            logLine("[WorldSlots] createSlotFromZIP: name is empty — aborting.")
            return nil
        }

        let slotId  = UUID().uuidString
        let now     = Date()
        var slot    = WorldSlot(id: slotId, name: trimmedName, createdAt: now, lastPlayedAt: nil, worldLevelName: nil, worldSeed: nil)

        let slotsDir = slotsDirectory(forServerDir: configServer.serverDir)
        let slotDir  = slotsDir.appendingPathComponent(slotId, isDirectory: true)
        let destZip  = slotDir.appendingPathComponent("world.zip")

        do {
            try fm.createDirectory(at: slotDir, withIntermediateDirectories: true)
        } catch {
            logLine("[WorldSlots] createSlotFromZIP: could not create slot directory: \(error.localizedDescription)")
            return nil
        }

        logLine("[WorldSlots] Importing \"\(zipURL.lastPathComponent)\" as slot \"\(trimmedName)\"...")

        let copyOk: Bool = await Task.detached(priority: .userInitiated) {
            do {
                try fm.copyItem(at: zipURL, to: destZip)
                return true
            } catch {
                return false
            }
        }.value

        guard copyOk else {
            logLine("[WorldSlots] createSlotFromZIP: file copy failed.")
            try? fm.removeItem(at: slotDir)
            return nil
        }

        // Populate zip size from the copied file.
        if let attrs = try? fm.attributesOfItem(atPath: destZip.path),
           let size = attrs[.size] as? Int64 {
            slot.zipSizeBytes = size
        }

        if configServer.serverType == .java {
            slot.worldLevelName = inferJavaLevelName(fromSlotZIP: destZip)
        } else {
            slot.worldLevelName = currentLevelName(for: configServer)
        }
        slot.worldSeed = importedWorldMetadata(fromZIP: zipURL, serverType: configServer.serverType).seed

        do {
            try saveMetadata(slot, serverDir: configServer.serverDir)
        } catch {
            logLine("[WorldSlots] createSlotFromZIP: failed to write metadata: \(error.localizedDescription)")
            try? fm.removeItem(at: slotDir)
            return nil
        }

        logLine("[WorldSlots] Import complete: slot \"\(trimmedName)\" (\(formatBytes(slot.zipSizeBytes ?? 0))).")
        return slot
    }

    private enum NBTEndianness {
        case big
        case little
    }

    private enum NBTTag: UInt8 {
        case end = 0
        case byte = 1
        case short = 2
        case int = 3
        case long = 4
        case float = 5
        case double = 6
        case byteArray = 7
        case string = 8
        case list = 9
        case compound = 10
        case intArray = 11
        case longArray = 12
    }

    private enum NBTValue {
        case byte(Int8)
        case short(Int16)
        case int(Int32)
        case long(Int64)
        case float(Float)
        case double(Double)
        case string(String)
        case byteArray(Data)
        case list([NBTValue])
        case compound([String: NBTValue])
        case intArray([Int32])
        case longArray([Int64])
    }

    struct ImportedWorldMetadata {
        var seed: String? = nil
        var difficulty: String? = nil
        var gamemode: String? = nil
    }

    private struct NBTReader {
        let data: Data
        let endianness: NBTEndianness
        var offset: Int = 0

        mutating func readRootCompound() throws -> NBTValue {
            guard let type = NBTTag(rawValue: try readUInt8()), type == .compound else {
                throw NSError(domain: "WorldSlotManager.NBT", code: 1)
            }
            _ = try readString()
            return try readPayload(type: .compound)
        }

        mutating func readPayload(type: NBTTag) throws -> NBTValue {
            switch type {
            case .end:
                return .compound([:])
            case .byte:
                return .byte(Int8(bitPattern: try readUInt8()))
            case .short:
                return .short(try readInt16())
            case .int:
                return .int(try readInt32())
            case .long:
                return .long(try readInt64())
            case .float:
                return .float(Float(bitPattern: UInt32(bitPattern: try readInt32())))
            case .double:
                return .double(Double(bitPattern: UInt64(bitPattern: try readInt64())))
            case .byteArray:
                let count = Int(try readInt32())
                return .byteArray(try readData(count: count))
            case .string:
                return .string(try readString())
            case .list:
                guard let elementType = NBTTag(rawValue: try readUInt8()) else {
                    throw NSError(domain: "WorldSlotManager.NBT", code: 2)
                }
                let count = Int(try readInt32())
                var values: [NBTValue] = []
                values.reserveCapacity(max(0, count))
                for _ in 0..<max(0, count) {
                    values.append(try readPayload(type: elementType))
                }
                return .list(values)
            case .compound:
                var dict: [String: NBTValue] = [:]
                while true {
                    let rawType = try readUInt8()
                    guard rawType != NBTTag.end.rawValue else { break }
                    guard let nestedType = NBTTag(rawValue: rawType) else {
                        throw NSError(domain: "WorldSlotManager.NBT", code: 3)
                    }
                    let name = try readString()
                    dict[name] = try readPayload(type: nestedType)
                }
                return .compound(dict)
            case .intArray:
                let count = Int(try readInt32())
                var values: [Int32] = []
                values.reserveCapacity(max(0, count))
                for _ in 0..<max(0, count) {
                    values.append(try readInt32())
                }
                return .intArray(values)
            case .longArray:
                let count = Int(try readInt32())
                var values: [Int64] = []
                values.reserveCapacity(max(0, count))
                for _ in 0..<max(0, count) {
                    values.append(try readInt64())
                }
                return .longArray(values)
            }
        }

        mutating func readUInt8() throws -> UInt8 {
            guard offset < data.count else {
                throw NSError(domain: "WorldSlotManager.NBT", code: 4)
            }
            let value = data[offset]
            offset += 1
            return value
        }

        mutating func readInt16() throws -> Int16 {
            let raw = try readUnsignedInteger(byteCount: 2)
            return Int16(bitPattern: UInt16(raw))
        }

        mutating func readInt32() throws -> Int32 {
            let raw = try readUnsignedInteger(byteCount: 4)
            return Int32(bitPattern: UInt32(raw))
        }

        mutating func readInt64() throws -> Int64 {
            let raw = try readUnsignedInteger(byteCount: 8)
            return Int64(bitPattern: UInt64(raw))
        }

        mutating func readUnsignedInteger(byteCount: Int) throws -> UInt64 {
            let chunk = try readData(count: byteCount)
            return chunk.withUnsafeBytes { rawBuffer in
                let bytes = rawBuffer.bindMemory(to: UInt8.self)
                switch endianness {
                case .big:
                    return bytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
                case .little:
                    return bytes.enumerated().reduce(UInt64(0)) { partial, element in
                        partial | (UInt64(element.element) << (UInt64(element.offset) * 8))
                    }
                }
            }
        }

        mutating func readData(count: Int) throws -> Data {
            guard count >= 0, offset + count <= data.count else {
                throw NSError(domain: "WorldSlotManager.NBT", code: 5)
            }
            let range = offset..<(offset + count)
            offset += count
            return data.subdata(in: range)
        }

        mutating func readString() throws -> String {
            let length = Int(try readInt16())
            let stringData = try readData(count: max(0, length))
            return String(data: stringData, encoding: .utf8) ?? ""
        }
    }

    static func importedWorldMetadata(fromZIP zipURL: URL, serverType: ServerType) -> ImportedWorldMetadata {
        var metadata = readAdjacentBackupMetadata(forZIP: zipURL) ?? ImportedWorldMetadata()
        guard let levelDatPath = firstLevelDatPath(inZIP: zipURL) else { return metadata }
        guard let rawLevelDat = unzipMemberData(zipURL: zipURL, memberPath: levelDatPath) else { return metadata }
        let parsed = importedWorldMetadata(fromLevelDatData: rawLevelDat, serverType: serverType)
        metadata.seed = metadata.seed ?? parsed.seed
        metadata.difficulty = metadata.difficulty ?? parsed.difficulty
        metadata.gamemode = metadata.gamemode ?? parsed.gamemode
        return metadata
    }

    static func importedWorldMetadata(fromFolder folderURL: URL, serverType: ServerType) -> ImportedWorldMetadata {
        let levelDatURL = folderURL.appendingPathComponent("level.dat")
        guard let rawLevelDat = try? Data(contentsOf: levelDatURL) else { return ImportedWorldMetadata() }
        return importedWorldMetadata(fromLevelDatData: rawLevelDat, serverType: serverType)
    }

    static func importedWorldSeed(fromFolder folderURL: URL, serverType: ServerType) -> String? {
        importedWorldMetadata(fromFolder: folderURL, serverType: serverType).seed
    }

    private static func importedWorldMetadata(fromLevelDatData rawLevelDat: Data, serverType: ServerType) -> ImportedWorldMetadata {
        let root: NBTValue?
        switch serverType {
        case .java:
            guard let nbtData = gunzipData(rawLevelDat) else { return ImportedWorldMetadata() }
            root = parseNBTRoot(data: nbtData, endianness: .big)
        case .bedrock:
            let nbtPayload: Data
            if rawLevelDat.count > 8, rawLevelDat[8] == NBTTag.compound.rawValue {
                nbtPayload = rawLevelDat.subdata(in: 8..<rawLevelDat.count)
            } else {
                nbtPayload = rawLevelDat
            }
            root = parseNBTRoot(data: nbtPayload, endianness: .little)
        }

        guard let root else { return ImportedWorldMetadata() }
        return ImportedWorldMetadata(
            seed: extractSeedString(fromNBT: root, preferJavaPaths: serverType == .java),
            difficulty: extractDifficultyString(fromNBT: root),
            gamemode: extractGamemodeString(fromNBT: root)
        )
    }

    private static func readAdjacentBackupMetadata(forZIP zipURL: URL) -> ImportedWorldMetadata? {
        let sidecarURL = zipURL.deletingPathExtension().appendingPathExtension("meta.json")
        guard let data = try? Data(contentsOf: sidecarURL),
              let meta = try? JSONDecoder().decode(BackupMeta.self, from: data) else {
            return nil
        }

        let trimmedSeed = meta.worldSeed?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ImportedWorldMetadata(
            seed: trimmedSeed?.isEmpty == false ? trimmedSeed : nil,
            difficulty: nil,
            gamemode: nil
        )
    }

    private static func firstLevelDatPath(inZIP zipURL: URL) -> String? {
        guard let listingData = runProcess(executablePath: "/usr/bin/unzip", arguments: ["-Z", "-1", zipURL.path]),
              let listing = String(data: listingData, encoding: .utf8) else {
            return nil
        }

        let paths = listing
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("__MACOSX/") }

        return paths.first(where: { $0 == "level.dat" || $0.hasSuffix("/level.dat") })
    }

    private static func unzipMemberData(zipURL: URL, memberPath: String) -> Data? {
        runProcess(executablePath: "/usr/bin/unzip", arguments: ["-p", zipURL.path, memberPath])
    }

    private static func gunzipData(_ compressedData: Data) -> Data? {
        let fm = FileManager.default
        let tempURL = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("gz")
        do {
            try compressedData.write(to: tempURL, options: .atomic)
            defer { try? fm.removeItem(at: tempURL) }
            return runProcess(executablePath: "/usr/bin/gunzip", arguments: ["-c", tempURL.path])
        } catch {
            try? fm.removeItem(at: tempURL)
            return nil
        }
    }

    private static func runProcess(executablePath: String, arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return out.fileHandleForReading.readDataToEndOfFile()
        } catch {
            return nil
        }
    }

    private static func parseNBTRoot(data: Data, endianness: NBTEndianness) -> NBTValue? {
        var reader = NBTReader(data: data, endianness: endianness)
        return try? reader.readRootCompound()
    }

    private static func extractSeedString(fromNBT root: NBTValue, preferJavaPaths: Bool) -> String? {
        if preferJavaPaths {
            if let value = nbtInteger(atPath: ["Data", "WorldGenSettings", "seed"], in: root) { return String(value) }
            if let value = nbtInteger(atPath: ["Data", "RandomSeed"], in: root) { return String(value) }
        }

        if let value = nbtInteger(atPath: ["RandomSeed"], in: root) { return String(value) }
        if let value = nbtInteger(atPath: ["WorldGenSettings", "seed"], in: root) { return String(value) }
        if let value = findInteger(named: "RandomSeed", in: root) { return String(value) }
        if let value = findInteger(named: "seed", in: root) { return String(value) }
        return nil
    }

    private static func extractDifficultyString(fromNBT root: NBTValue) -> String? {
        let candidates: [Int64?] = [
            nbtInteger(atPath: ["Data", "Difficulty"], in: root),
            nbtInteger(atPath: ["Difficulty"], in: root),
            findInteger(named: "Difficulty", in: root)
        ]

        guard let raw = candidates.compactMap({ $0 }).first else { return nil }
        switch raw {
        case 0: return "peaceful"
        case 1: return "easy"
        case 2: return "normal"
        case 3: return "hard"
        default: return nil
        }
    }

    private static func extractGamemodeString(fromNBT root: NBTValue) -> String? {
        let candidates: [Int64?] = [
            nbtInteger(atPath: ["Data", "GameType"], in: root),
            nbtInteger(atPath: ["GameType"], in: root),
            findInteger(named: "GameType", in: root)
        ]

        guard let raw = candidates.compactMap({ $0 }).first else { return nil }
        switch raw {
        case 0: return "survival"
        case 1: return "creative"
        case 2: return "adventure"
        case 3: return "spectator"
        default: return nil
        }
    }

    private static func nbtInteger(atPath path: [String], in value: NBTValue) -> Int64? {
        guard !path.isEmpty else {
            switch value {
            case .long(let number):
                return number
            case .int(let number):
                return Int64(number)
            case .short(let number):
                return Int64(number)
            case .byte(let number):
                return Int64(number)
            default:
                return nil
            }
        }

        guard case .compound(let dict) = value, let next = dict[path[0]] else { return nil }
        return nbtInteger(atPath: Array(path.dropFirst()), in: next)
    }

    private static func findInteger(named key: String, in value: NBTValue) -> Int64? {
        switch value {
        case .compound(let dict):
            if let direct = dict[key], let matched = nbtInteger(atPath: [], in: direct) {
                return matched
            }
            for nested in dict.values {
                if let matched = findInteger(named: key, in: nested) {
                    return matched
                }
            }
            return nil
        case .list(let values):
            for nested in values {
                if let matched = findInteger(named: key, in: nested) {
                    return matched
                }
            }
            return nil
        default:
            return nil
        }
    }

    // MARK: - Byte formatting helper

    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}


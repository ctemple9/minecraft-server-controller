//
//  AppViewModel+PlayerProfiles.swift
//  MinecraftServerController
//
//  Player profile loading, async UUID resolution, and data management actions
//  for the Java Edition Player Profiles feature.
//

import AppKit
import Combine
import Foundation

/// Runs heavy synchronous work on a background GCD queue and awaits the result.
/// `Task.detached` bodies can run on the main thread when scheduled very early in
/// launch (before the cooperative pool is serving jobs), which froze the splash while
/// the Bedrock LevelDB was parsed. GCD's global queues always run off-main, so this
/// guarantees the parse never blocks the UI regardless of when it's kicked off.
fileprivate func runOffMainThread<T>(_ work: @escaping () -> T) async -> T {
    await withCheckedContinuation { (cont: CheckedContinuation<T, Never>) in
        DispatchQueue.global(qos: .userInitiated).async {
            cont.resume(returning: work())
        }
    }
}

extension AppViewModel {

    // MARK: - Level name helper

    private func currentLevelName(for cfg: ConfigServer) -> String {
        let props = ServerPropertiesManager.readProperties(serverDir: cfg.serverDir)
        return props["level-name"] ?? "world"
    }

    /// Friendly name of the world the player data is read from: the active world slot's
    /// display name when available, otherwise the raw level-name.
    private func activeWorldDisplayName(for cfg: ConfigServer) -> String {
        if let active = WorldSlotManager.activeSlot(forServerDir: cfg.serverDir) {
            return active.name
        }
        return currentLevelName(for: cfg)
    }

    private func selectedConfigServerForProfiles() -> ConfigServer? {
        guard let server = selectedServer else { return nil }
        return configServer(for: server)
    }

    // MARK: - Load / refresh

    /// Called on server switch and the Players tab refresh button.
    func loadPlayerProfilesForSelectedServer() {
        guard let cfg = selectedConfigServerForProfiles() else {
            playerProfiles = []
            isLoadingProfiles = false
            activePlayerDataWorldName = nil
            return
        }
        activePlayerDataWorldName = activeWorldDisplayName(for: cfg)
        if cfg.isJava {
            loadPlayerProfiles(for: cfg)
        } else {
            loadBedrockPlayerProfiles(for: cfg)
        }
    }

    /// Re-scan Bedrock profiles in response to a live console join/leave, passing the
    /// event's gamertag so console-first auto-naming can bind it to the player's
    /// anonymous `server_<uuid>` record. On a first-ever join the record may not be on
    /// disk yet (no bind); the leave event fires after BDS saves, so it reliably binds.
    func refreshBedrockProfilesAfterPlayerEvent(nameHint: String) {
        guard let cfg = selectedConfigServerForProfiles(), cfg.isBedrock else { return }
        loadBedrockPlayerProfiles(for: cfg, nameHint: nameHint)
    }

    /// Full scan + async UUID resolution for a given Java server.
    func loadPlayerProfiles(for cfg: ConfigServer) {
        isLoadingProfiles = true
        let serverDir = cfg.serverDir
        let levelName = currentLevelName(for: cfg)
        let onlineNames = Set(onlinePlayers.map { $0.name })

        Task.detached(priority: .userInitiated) {
            // 1. Scan playerdata/ directory for .dat files (off-main, even at launch)
            var profiles = await runOffMainThread {
                PlayerDataManager.scanProfiles(serverDir: serverDir, levelName: levelName)
            }

            guard !profiles.isEmpty else {
                await MainActor.run {
                    self.playerProfiles = []
                    self.isLoadingProfiles = false
                }
                return
            }

            // 2. Apply usercache.json (instant, no network)
            let usercache = PlayerDataManager.readUsercache(serverDir: serverDir)
            let ops = PlayerDataManager.readOps(serverDir: serverDir)

            for i in profiles.indices {
                profiles[i].username = usercache[profiles[i].uuid]
                profiles[i].isOp = ops.contains(profiles[i].uuid)
                if let name = profiles[i].username {
                    profiles[i].isOnline = onlineNames.contains(name)
                }
            }

            // Load hidden UUIDs so isProfileHidden() works immediately.
            let hiddenJava = JavaHiddenProfiles.load(serverDir: serverDir)
            let hiddenBedrock = BedrockHiddenProfiles.load(serverDir: serverDir)
            await MainActor.run {
                self.hiddenJavaUUIDs = hiddenJava
                self.hiddenBedrockXUIDs = hiddenBedrock
                self.playerProfiles = profiles
                self.isLoadingProfiles = false
            }

            // 3. Resolve remaining UUIDs via Mojang API
            let unresolved = profiles.filter { $0.username == nil }.map { $0.uuid }
            if !unresolved.isEmpty {
                await self.resolveUUIDs(unresolved, onlineNames: onlineNames, ops: ops)
            }
        }
    }

    // MARK: - Bedrock profile loading

    /// Scans the Bedrock LevelDB, applies online/op state, then resolves XUIDs → gamertags.
    ///
    /// `nameHint` is the gamertag of the player involved in the console event that
    /// triggered this refresh (a join or leave). It lets the console-first naming
    /// step bind a departing player (no longer in `onlinePlayers`) to their freshly
    /// saved `server_<uuid>` record.
    func loadBedrockPlayerProfiles(for cfg: ConfigServer, nameHint: String? = nil) {
        isLoadingProfiles = true
        let serverDir = cfg.serverDir
        let levelName = currentLevelName(for: cfg)
        let onlineXUIDs = Set(onlinePlayers.compactMap { $0.xuid })
        let onlineNames = Set(onlinePlayers.map { $0.name.lowercased() })
        // Gamertags known from the live console this session — the "console-first"
        // source for naming anonymous broadcast/transfer joins. Includes the
        // currently-online players plus the departing player (nameHint), if any.
        var liveNames = onlinePlayers.map { $0.name }
        if let nameHint { liveNames.append(nameHint) }

        Task.detached(priority: .userInitiated) {
            // 1. Scan LevelDB (NBT is parsed here — stats + inventory pre-populated).
            //    Forced off-main so the heavy parse never blocks the UI/splash at launch.
            var profiles = await runOffMainThread {
                BedrockPlayerDataManager.scanProfiles(serverDir: serverDir, levelName: levelName)
            }

            guard !profiles.isEmpty else {
                await MainActor.run {
                    self.playerProfiles = []
                    self.isLoadingProfiles = false
                }
                return
            }

            // 2. Load hidden players (Bedrock XUIDs + Java UUIDs) so the card
            //    views can filter them out.
            let hidden = BedrockHiddenProfiles.load(serverDir: serverDir)
            let hiddenJava = JavaHiddenProfiles.load(serverDir: serverDir)
            await MainActor.run {
                self.hiddenBedrockXUIDs = hidden
                self.hiddenJavaUUIDs = hiddenJava
            }

            // 3. Apply the local name cache — fills in names that were seen during
            //    previous sessions (persisted across server log rollovers), and names
            //    that were manually assigned via "Identify Player".
            //    Also overwrites "Unknown Player" so manual assignments and auto-resolved
            //    server_* entries (Realm/Floodgate) are applied on load.
            let nameCache = BedrockNameCache.load(serverDir: serverDir)
            for i in profiles.indices {
                guard let xuid = profiles[i].xuid else { continue }
                let isUnresolved = profiles[i].username == nil || profiles[i].username == "Unknown Player"
                guard isUnresolved else { continue }
                if let cachedName = nameCache[xuid] {
                    profiles[i].username = cachedName
                }
            }

            // 3b. Console-first auto-naming. Broadcast/transfer joins are stored on
            //     disk as anonymous `server_<uuid>` records that share NO identifier
            //     with the console identity (the numeric XUID, pfid, and gamertag never
            //     appear on disk), so they can't be matched to a live player by id.
            //     Correlate by liveness instead: if exactly one unresolved `server_`
            //     profile exists and exactly one live gamertag is unaccounted for, they
            //     must be the same person — bind the name and cache it against the stable
            //     `server_<uuid>` key so it sticks for every future session. Ambiguous
            //     cases (multiple unknowns at once) are left for manual "Identify Player".
            let unresolvedServer = profiles.indices.filter { i in
                guard let x = profiles[i].xuid, x.hasPrefix("server_"), !hidden.contains(x) else { return false }
                return profiles[i].username == nil || profiles[i].username == "Unknown Player"
            }
            let knownNames = Set(profiles.compactMap { $0.username?.lowercased() })
            let pendingNames = Set(liveNames.map { $0.lowercased() }).subtracting(knownNames)
            if unresolvedServer.count == 1, pendingNames.count == 1,
               let lower = pendingNames.first,
               let name = liveNames.first(where: { $0.lowercased() == lower }) {
                let i = unresolvedServer[0]
                profiles[i].username = name
                if let serverKey = profiles[i].xuid {
                    BedrockNameCache.record(xuid: serverKey, name: name, serverDir: serverDir)
                }
            }

            // 4. Mark online players — by XUID (numeric Xbox) or, for `server_` profiles
            //    named via the console/cache, by matching the live gamertag.
            for i in profiles.indices {
                let byXUID = profiles[i].xuid.map { onlineXUIDs.contains($0) } ?? false
                let byName = profiles[i].username.map { onlineNames.contains($0.lowercased()) } ?? false
                profiles[i].isOnline = byXUID || byName
            }

            await MainActor.run {
                self.playerProfiles = profiles
                self.isLoadingProfiles = false
            }

            // 4. Batch-resolve remaining XUIDs → gamertags (and Floodgate UUIDs) via GeyserMC.
            //    Only attempt resolution for purely-numeric XUIDs (real Xbox Live IDs).
            //    UUID-format and server_* entries cannot be resolved this way.
            //    Successfully resolved names are written back into the local cache.
            let unresolved = profiles.filter {
                guard let x = $0.xuid else { return false }
                return $0.username == nil && x.allSatisfy({ $0.isNumber })
            }
            if !unresolved.isEmpty {
                await self.resolveBedrockXUIDs(unresolved, serverDir: serverDir)
            }

            // 5. Resolve Floodgate UUIDs for all Bedrock profiles that have a name but
            //    no floodgateUUID yet. This includes server_* (Realm/Floodgate) entries
            //    AND numeric-XUID profiles whose gamertag was restored from cache —
            //    those skip step 4 (username already set) so their floodgateUUID would
            //    otherwise stay nil every session after the first, causing the wrong skin.
            let needsFloodgate = profiles.filter {
                guard let x = $0.xuid else { return false }
                let hasName = $0.username != nil && $0.username != "Unknown Player"
                let isResolvable = x.allSatisfy({ $0.isNumber }) || x.hasPrefix("server_")
                return hasName && isResolvable
            }
            if !needsFloodgate.isEmpty {
                await self.resolveServerProfileFloodgateUUIDs(needsFloodgate)
            }
        }
    }

    private func resolveServerProfileFloodgateUUIDs(_ profiles: [PlayerProfile]) async {
        await withTaskGroup(of: (String, UUID?).self) { group in
            for profile in profiles {
                guard let gamertag = profile.username else { continue }
                let profileId = profile.id
                group.addTask {
                    (profileId, await BedrockPlayerDataManager.resolveFloodgateUUID(gamertag: gamertag))
                }
            }
            for await (profileId, floodgateUUID) in group {
                guard let uuid = floodgateUUID else { continue }
                await MainActor.run {
                    if let i = self.playerProfiles.firstIndex(where: { $0.id == profileId }) {
                        self.playerProfiles[i].floodgateUUID = uuid
                    }
                }
            }
        }
    }

    private func resolveBedrockXUIDs(_ profiles: [PlayerProfile], serverDir: String) async {
        let batchSize = 5
        for batchStart in stride(from: 0, to: profiles.count, by: batchSize) {
            let batch = Array(profiles[batchStart..<min(batchStart + batchSize, profiles.count)])

            await withTaskGroup(of: (String, String?, UUID?).self) { group in
                for profile in batch {
                    guard let xuid = profile.xuid else { continue }
                    group.addTask {
                        let gamertag = await BedrockPlayerDataManager.xuidToGamertag(xuid: xuid)
                        var floodgateUUID: UUID? = nil
                        if let tag = gamertag {
                            floodgateUUID = await BedrockPlayerDataManager.resolveFloodgateUUID(gamertag: tag)
                        }
                        return (xuid, gamertag, floodgateUUID)
                    }
                }

                for await (xuid, gamertag, floodgateUUID) in group {
                    // Cache the resolved name so it survives log rollovers
                    if let tag = gamertag {
                        BedrockNameCache.record(xuid: xuid, name: tag, serverDir: serverDir)
                    }
                    await MainActor.run {
                        if let i = self.playerProfiles.firstIndex(where: { $0.xuid == xuid }) {
                            if let tag = gamertag { self.playerProfiles[i].username = tag }
                            if let uuid = floodgateUUID { self.playerProfiles[i].floodgateUUID = uuid }
                        }
                    }
                }
            }

            if batchStart + batchSize < profiles.count {
                try? await Task.sleep(nanoseconds: 250_000_000) // 250ms between batches
            }
        }
    }

    // MARK: - Bedrock hide / unhide

    func hideBedrockPlayer(profile: PlayerProfile) {
        guard let xuid = profile.xuid,
              let cfg = selectedConfigServerForProfiles() else { return }
        BedrockHiddenProfiles.hide(xuid: xuid, serverDir: cfg.serverDir)
        hiddenBedrockXUIDs.insert(xuid)
    }

    func unhideBedrockPlayer(profile: PlayerProfile) {
        guard let xuid = profile.xuid,
              let cfg = selectedConfigServerForProfiles() else { return }
        BedrockHiddenProfiles.unhide(xuid: xuid, serverDir: cfg.serverDir)
        hiddenBedrockXUIDs.remove(xuid)
    }

    // MARK: - Java hide / unhide

    func hideJavaPlayer(profile: PlayerProfile) {
        guard !profile.isBedrockPlayer,
              let cfg = selectedConfigServerForProfiles() else { return }
        let uuid = profile.uuid.uuidString
        JavaHiddenProfiles.hide(uuid: uuid, serverDir: cfg.serverDir)
        hiddenJavaUUIDs.insert(uuid)
    }

    func unhideJavaPlayer(profile: PlayerProfile) {
        guard let cfg = selectedConfigServerForProfiles() else { return }
        let uuid = profile.uuid.uuidString
        JavaHiddenProfiles.unhide(uuid: uuid, serverDir: cfg.serverDir)
        hiddenJavaUUIDs.remove(uuid)
    }

    // MARK: - Unified hide helpers (Java + Bedrock)

    /// True when a profile is hidden by either the Bedrock (XUID) or Java (UUID) list.
    func isProfileHidden(_ profile: PlayerProfile) -> Bool {
        if let xuid = profile.xuid { return hiddenBedrockXUIDs.contains(xuid) }
        return hiddenJavaUUIDs.contains(profile.uuid.uuidString)
    }

    /// Hides a profile using the correct list for its edition.
    func hideProfile(_ profile: PlayerProfile) {
        if profile.isBedrockPlayer { hideBedrockPlayer(profile: profile) }
        else { hideJavaPlayer(profile: profile) }
    }

    /// Unhides a profile using the correct list for its edition.
    func unhideProfile(_ profile: PlayerProfile) {
        if profile.isBedrockPlayer { unhideBedrockPlayer(profile: profile) }
        else { unhideJavaPlayer(profile: profile) }
    }

    // MARK: - Bedrock manual identification

    /// Assigns a gamertag to an unresolved Bedrock profile (e.g. a Realm player whose
    /// name was never logged). Persists to bedrock_names.json so the assignment survives
    /// restarts and is overwritten automatically if the player connects and the correct
    /// name comes in via the console log.
    func identifyBedrockPlayer(profile: PlayerProfile, gamertag: String) {
        let trimmed = gamertag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let xuid = profile.xuid,
              let cfg = selectedConfigServerForProfiles() else { return }

        BedrockNameCache.record(xuid: xuid, name: trimmed, serverDir: cfg.serverDir)

        if let i = playerProfiles.firstIndex(where: { $0.id == profile.id }) {
            playerProfiles[i].username = trimmed
        }

        Task {
            if let floodgateUUID = await BedrockPlayerDataManager.resolveFloodgateUUID(gamertag: trimmed) {
                await MainActor.run {
                    if let i = self.playerProfiles.firstIndex(where: { $0.id == profile.id }) {
                        self.playerProfiles[i].floodgateUUID = floodgateUUID
                    }
                }
            }
        }
    }

    // MARK: - NBT loading (Java only; Bedrock stats are pre-populated during scan)

    /// Loads NBT stats + inventory for a single profile into the published array.
    func loadProfileNBT(uuid: UUID) {
        guard let idx = playerProfiles.firstIndex(where: { $0.uuid == uuid }) else { return }
        let path = playerProfiles[idx].datFilePath

        Task.detached(priority: .userInitiated) {
            let (stats, inventory) = await runOffMainThread { PlayerNBTReader.readAll(from: path) }
            await MainActor.run {
                if let i = self.playerProfiles.firstIndex(where: { $0.uuid == uuid }) {
                    self.playerProfiles[i].stats = stats
                    self.playerProfiles[i].inventory = inventory
                }
            }
        }
    }

    // MARK: - UUID resolution via Mojang API

    private func resolveUUIDs(_ uuids: [UUID], onlineNames: Set<String>, ops: Set<UUID>) async {
        let batchSize = 5
        for batchStart in stride(from: 0, to: uuids.count, by: batchSize) {
            let batch = Array(uuids[batchStart..<min(batchStart + batchSize, uuids.count)])

            await withTaskGroup(of: (UUID, String?).self) { group in
                for uuid in batch {
                    group.addTask { (uuid, await self.mojangName(for: uuid)) }
                }
                for await (uuid, name) in group {
                    if let n = name {
                        await MainActor.run {
                            if let i = self.playerProfiles.firstIndex(where: { $0.uuid == uuid }) {
                                self.playerProfiles[i].username = n
                                self.playerProfiles[i].isOnline = onlineNames.contains(n)
                            }
                        }
                    }
                }
            }

            // Respect Mojang rate limits between batches
            if batchStart + batchSize < uuids.count {
                try? await Task.sleep(nanoseconds: 250_000_000) // 250ms
            }
        }
    }

    private func mojangName(for uuid: UUID) async -> String? {
        let raw = uuid.uuidString.replacingOccurrences(of: "-", with: "")
        guard let url = URL(string: "https://sessionserver.mojang.com/session/minecraft/profile/\(raw)") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.setValue("MinecraftServerController/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200 else { return nil }

        struct Profile: Decodable { let name: String }
        return (try? JSONDecoder().decode(Profile.self, from: data))?.name
    }

    // MARK: - Computed helpers

    /// The offline-mode UUID for a player whose username is known.
    func offlineUUID(for profile: PlayerProfile) -> UUID? {
        guard let name = profile.username, !name.isEmpty else { return nil }
        return PlayerDataManager.offlineUUID(for: name)
    }

    private func playerDataDirForSelected() throws -> String {
        guard let cfg = selectedConfigServerForProfiles() else { throw ProfileError.noServer }
        return PlayerDataManager.playerDataDir(serverDir: cfg.serverDir, levelName: currentLevelName(for: cfg))
    }

    // MARK: - Actions

    /// Copies this player's .dat to their offline-mode UUID.
    /// The key action when switching online mode → offline mode.
    func migratePlayerToOfflineUUID(profile: PlayerProfile) throws {
        guard let name = profile.username, !name.isEmpty else { throw ProfileError.usernameUnknown }
        let dir = try playerDataDirForSelected()
        let target = PlayerDataManager.offlineUUID(for: name)
        try PlayerDataManager.copyPlayerData(from: profile.uuid, to: target, in: dir)
        logAppMessage("[Players] Migrated \(name) → offline UUID \(target.uuidString.lowercased()).")
        if let cfg = selectedConfigServerForProfiles() { loadPlayerProfiles(for: cfg) }
    }

    /// Copies this player's .dat to an arbitrary target UUID.
    func migratePlayerToUUID(profile: PlayerProfile, targetUUID: UUID) throws {
        let dir = try playerDataDirForSelected()
        try PlayerDataManager.copyPlayerData(from: profile.uuid, to: targetUUID, in: dir)
        logAppMessage("[Players] Copied \(profile.displayName) → UUID \(targetUUID.uuidString.lowercased()).")
        if let cfg = selectedConfigServerForProfiles() { loadPlayerProfiles(for: cfg) }
    }

    /// Copies one player's .dat onto another player's UUID (overwrites).
    func copyPlayerData(from sourceUUID: UUID, to destUUID: UUID) throws {
        let dir = try playerDataDirForSelected()
        try PlayerDataManager.copyPlayerData(from: sourceUUID, to: destUUID, in: dir)
        let srcName = playerProfiles.first(where: { $0.uuid == sourceUUID })?.displayName ?? "?"
        let dstName = playerProfiles.first(where: { $0.uuid == destUUID })?.displayName ?? "?"
        logAppMessage("[Players] Copied \(srcName) data → \(dstName).")
        if let cfg = selectedConfigServerForProfiles() { loadPlayerProfiles(for: cfg) }
    }

    /// Deletes a player's .dat file permanently.
    func deletePlayerData(uuid: UUID) throws {
        let dir = try playerDataDirForSelected()
        try PlayerDataManager.deletePlayerData(uuid: uuid, in: dir)
        logAppMessage("[Players] Deleted player data \(uuid.uuidString.lowercased()).")
        playerProfiles.removeAll { $0.uuid == uuid }
    }

    /// Duplicates a player's .dat under a new random UUID.
    func duplicatePlayerData(uuid: UUID) throws {
        let dir = try playerDataDirForSelected()
        let newUUID = try PlayerDataManager.duplicatePlayerData(uuid: uuid, in: dir)
        logAppMessage("[Players] Duplicated player data → \(newUUID.uuidString.lowercased()).")
        if let cfg = selectedConfigServerForProfiles() { loadPlayerProfiles(for: cfg) }
    }

    // MARK: - Player skin overrides

    func playerAppearance(for profile: PlayerProfile) -> (identifier: String, skinURL: URL?) {
        guard let cfg = selectedConfigServerForProfiles() else {
            return (profile.imageIdentifier, nil)
        }
        return PlayerSkinStore.resolveAppearance(for: profile, serverDir: cfg.serverDir)
    }

    func setPlayerLookupOverride(_ identifier: String?, for profile: PlayerProfile) {
        guard let cfg = selectedConfigServerForProfiles() else { return }
        var overrides = PlayerSkinStore.loadOverrides(serverDir: cfg.serverDir)
        var override = overrides[profile.id] ?? PlayerSkinOverride()
        let trimmed = identifier?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        override.lookupIdentifier = trimmed
        overrides[profile.id] = override
        PlayerSkinStore.saveOverrides(overrides, serverDir: cfg.serverDir)
        objectWillChange.send()
    }

    func uploadPlayerSkin(_ image: NSImage, for profile: PlayerProfile) {
        guard let cfg = selectedConfigServerForProfiles() else { return }
        do {
            let filename = try PlayerSkinStore.saveSkin(image, profileID: profile.id, serverDir: cfg.serverDir)
            var overrides = PlayerSkinStore.loadOverrides(serverDir: cfg.serverDir)
            var override = overrides[profile.id] ?? PlayerSkinOverride()
            override.skinFileName = filename
            overrides[profile.id] = override
            PlayerSkinStore.saveOverrides(overrides, serverDir: cfg.serverDir)
            objectWillChange.send()
        } catch {
            logAppMessage("[PlayerSkins] Failed to save skin for \(profile.displayName): \(error.localizedDescription)")
        }
    }

    func clearPlayerSkinOverride(for profile: PlayerProfile) {
        guard let cfg = selectedConfigServerForProfiles() else { return }
        PlayerSkinStore.clearOverride(profileID: profile.id, serverDir: cfg.serverDir)
        objectWillChange.send()
    }

    // MARK: - Error type

    enum ProfileError: LocalizedError {
        case noServer
        case usernameUnknown

        var errorDescription: String? {
            switch self {
            case .noServer:
                return "No Java server is selected."
            case .usernameUnknown:
                return "Cannot migrate: this player's username is not yet resolved. Wait a moment and try again."
            }
        }
    }
}

// MARK: - String helper

private extension String {
    var nilIfEmpty: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}

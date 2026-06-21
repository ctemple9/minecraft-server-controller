//
//  AppViewModel+PlayerProfiles.swift
//  MinecraftServerController
//
//  Player profile loading, async UUID resolution, and data management actions
//  for the Java Edition Player Profiles feature.
//

import Foundation

extension AppViewModel {

    // MARK: - Level name helper

    private func currentLevelName(for cfg: ConfigServer) -> String {
        let props = ServerPropertiesManager.readProperties(serverDir: cfg.serverDir)
        return props["level-name"] ?? "world"
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
            return
        }
        if cfg.isJava {
            loadPlayerProfiles(for: cfg)
        } else {
            loadBedrockPlayerProfiles(for: cfg)
        }
    }

    /// Full scan + async UUID resolution for a given Java server.
    func loadPlayerProfiles(for cfg: ConfigServer) {
        isLoadingProfiles = true
        let serverDir = cfg.serverDir
        let levelName = currentLevelName(for: cfg)
        let onlineNames = Set(onlinePlayers.map { $0.name })

        Task.detached(priority: .userInitiated) {
            // 1. Scan playerdata/ directory for .dat files
            var profiles = PlayerDataManager.scanProfiles(serverDir: serverDir, levelName: levelName)

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

            await MainActor.run {
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
    func loadBedrockPlayerProfiles(for cfg: ConfigServer) {
        isLoadingProfiles = true
        let serverDir = cfg.serverDir
        let levelName = currentLevelName(for: cfg)
        let onlineXUIDs = Set(onlinePlayers.compactMap { $0.xuid })

        Task.detached(priority: .userInitiated) {
            // 1. Scan LevelDB (NBT is parsed here — stats + inventory pre-populated)
            var profiles = BedrockPlayerDataManager.scanProfiles(serverDir: serverDir, levelName: levelName)

            guard !profiles.isEmpty else {
                await MainActor.run {
                    self.playerProfiles = []
                    self.isLoadingProfiles = false
                }
                return
            }

            // 2. Load hidden XUIDs so the card view can filter them out.
            let hidden = BedrockHiddenProfiles.load(serverDir: serverDir)
            await MainActor.run { self.hiddenBedrockXUIDs = hidden }

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

            // 4. Mark online players
            for i in profiles.indices {
                if let xuid = profiles[i].xuid {
                    profiles[i].isOnline = onlineXUIDs.contains(xuid)
                }
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

            // 5. Resolve Floodgate UUIDs for server_* profiles that already have a name
            //    (from cache or manual identification). Without this, their imageIdentifier
            //    falls back to the Realm UUID which mc-heads.net can't render.
            let namedServerProfiles = profiles.filter {
                guard let x = $0.xuid else { return false }
                let hasName = $0.username != nil && $0.username != "Unknown Player"
                return x.hasPrefix("server_") && hasName
            }
            if !namedServerProfiles.isEmpty {
                await self.resolveServerProfileFloodgateUUIDs(namedServerProfiles)
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
            let (stats, inventory) = PlayerNBTReader.readAll(from: path)
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

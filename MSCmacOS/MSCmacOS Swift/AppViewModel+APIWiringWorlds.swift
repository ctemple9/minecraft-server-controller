//
//  AppViewModel+APIWiringWorlds.swift
//  MSCmacOS
//
//  M1 (flowstate) slice 2: player-profile and world-slot Remote API providers.
//  Extracted verbatim from AppViewModel.init's two wiring branches (which were
//  byte-identical). Assigned onto a single `server` param via wireProviders(into:isoFmt:).
//

import Foundation

extension AppViewModel {

    /// Player profiles (with NBT stat hydration) and world-slot management: list, activate,
    /// create, rename, replace, and repair. `isoFmt` formats profile/slot timestamps.
    func wirePlayerAndWorldProviders(into server: RemoteAPIServer, isoFmt: ISO8601DateFormatter) {
        // MARK: World management verbs (P9): create / rename / replace / repair.
        // Shared builder (pure, disk-backed) so every mutation can echo fresh slot state,
        // mirroring buildResourcePacksResponse. `repairing` is supplied by the caller since
        // it reflects @MainActor state (isRepairingWorld).
        let buildWorldSlotsResponse: (_ serverDir: String, _ serverRunning: Bool, _ repairing: Bool) -> RemoteAPIServer.WorldSlotsResponseDTO = { serverDir, running, repairing in
            let slots = WorldSlotManager.loadSlots(forServerDir: serverDir)
            let activeId = WorldSlotManager.resolvedActiveSlotID(forServerDir: serverDir)
            let dtos = slots.map { RemoteAPIServer.WorldSlotDTO(id: $0.id, name: $0.name, isActive: $0.id == activeId,
                                                                createdAt: isoFmt.string(from: $0.createdAt),
                                                                zipSizeBytes: $0.zipSizeBytes, worldSeed: $0.worldSeed) }
            return RemoteAPIServer.WorldSlotsResponseDTO(slots: dtos, activeSlotId: activeId, serverRunning: running, isRepairing: repairing)
        }

        server.playerProfilesProvider = { [weak self, isoFmt] in
            guard let self else { return RemoteAPIServer.PlayerProfilesResponseDTO(profiles: [], isLoadingStats: false) }
            let (profiles, hiddenJava, hiddenBedrock, selectedCfg) = Thread.isMainThread
                ? (self.playerProfiles, self.hiddenJavaUUIDs, self.hiddenBedrockXUIDs, self.selectedServer.flatMap { self.configServer(for: $0) })
                : DispatchQueue.main.sync { (self.playerProfiles, self.hiddenJavaUUIDs, self.hiddenBedrockXUIDs, self.selectedServer.flatMap { self.configServer(for: $0) }) }
            let dtos = profiles.map { p -> RemoteAPIServer.PlayerProfileDTO in
                let statsDTO = p.stats.map { s in
                    RemoteAPIServer.PlayerStatsDTO(
                        health: s.health, maxHealth: s.maxHealth, foodLevel: s.foodLevel,
                        xpLevel: s.xpLevel, xpTotal: s.xpTotal, gameMode: s.gameMode,
                        gameModeDisplay: s.gameModeDisplay, posX: s.posX, posY: s.posY,
                        posZ: s.posZ, dimensionDisplay: s.dimensionDisplay, score: s.score
                    )
                }
            let inventoryDTOs = p.inventory.map { item in
                    RemoteAPIServer.InventoryItemDTO(
                        slot: item.slot, itemID: item.itemID, iconName: item.iconName,
                        count: item.count, displayName: item.displayName,
                        enchantments: item.enchantments.map {
                            RemoteAPIServer.ItemEnchantmentDTO(id: $0.id, level: $0.level, displayName: $0.displayName)
                        },
                        damage: item.damage
                    )
                }
                let override = selectedCfg.flatMap { PlayerSkinStore.currentOverride(profileID: p.id, serverDir: $0.serverDir) }
                let isHidden = p.xuid.map { hiddenBedrock.contains($0) } ?? hiddenJava.contains(p.uuid.uuidString)
                return RemoteAPIServer.PlayerProfileDTO(
                    id: p.id, username: p.username, imageIdentifier: p.imageIdentifier,
                    isOnline: p.isOnline, isOp: p.isOp,
                    lastSeen: isoFmt.string(from: p.lastModified),
                    isBedrockPlayer: p.isBedrockPlayer,
                    isHidden: isHidden,
                    skinOverrideIdentifier: override?.lookupIdentifier,
                    hasSkinFileOverride: override?.skinFileName != nil,
                    stats: statsDTO,
                    inventory: inventoryDTOs
                )
            }
            // Trigger NBT loading for Java profiles that don't have stats yet.
            let needsNBT = profiles.filter { $0.stats == nil && !$0.isBedrockPlayer }
            if !needsNBT.isEmpty {
                DispatchQueue.main.async { needsNBT.forEach { self.loadProfileNBT(uuid: $0.uuid) } }
            }
            return RemoteAPIServer.PlayerProfilesResponseDTO(profiles: dtos, isLoadingStats: !needsNBT.isEmpty)
        }
        server.worldSlotsProvider = { [weak self, isoFmt] in
            guard let self else { return RemoteAPIServer.WorldSlotsResponseDTO(slots: [], activeSlotId: nil, serverRunning: false) }
            let (slots, running, selectedServer, repairing) = Thread.isMainThread
                ? (self.worldSlots, self.isServerRunning, self.selectedServer, self.isRepairingWorld)
                : DispatchQueue.main.sync { (self.worldSlots, self.isServerRunning, self.selectedServer, self.isRepairingWorld) }
            let activeId = selectedServer.flatMap { self.activeWorldSlotId(forServerDir: $0.directory) }
            let dtos = slots.map { RemoteAPIServer.WorldSlotDTO(id: $0.id, name: $0.name, isActive: $0.id == activeId,
                                                                createdAt: isoFmt.string(from: $0.createdAt),
                                                                zipSizeBytes: $0.zipSizeBytes, worldSeed: $0.worldSeed) }
            return RemoteAPIServer.WorldSlotsResponseDTO(slots: dtos, activeSlotId: activeId, serverRunning: running, isRepairing: repairing)
        }
        server.activateWorldSlotProvider = { [weak self] slotId in
            guard let self else { return false }
            let (slots, running) = Thread.isMainThread
                ? (self.worldSlots, self.isServerRunning)
                : DispatchQueue.main.sync { (self.worldSlots, self.isServerRunning) }
            guard !running, let slot = slots.first(where: { $0.id == slotId }) else { return false }
            Task { @MainActor [weak self] in await self?.activateWorldSlot(slot) }
            return true
        }

        server.createWorldSlotProvider = { [weak self] name, seed in
            guard let self else { return RemoteAPIServer.WorldMutationResultDTO(success: false, message: "not_available") }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return RemoteAPIServer.WorldMutationResultDTO(success: false, message: "name_required") }
            let ctx = await MainActor.run { () -> (ConfigServer, Bool)? in
                guard let server = self.selectedServer, let cfg = self.configServer(for: server) else { return nil }
                return (cfg, self.isServerRunning)
            }
            guard let (cfg, running) = ctx else { return RemoteAPIServer.WorldMutationResultDTO(success: false, message: "no_active_server") }
            let slot = await WorldSlotManager.createFreshWorldSlot(name: trimmed, seed: seed, for: cfg,
                logLine: { [weak self] msg in Task { @MainActor in self?.logAppMessage(msg) } })
            guard slot != nil else { return RemoteAPIServer.WorldMutationResultDTO(success: false, message: "create_failed") }
            let repairing = await MainActor.run { () -> Bool in self.loadWorldSlotsForSelectedServer(); return self.isRepairingWorld }
            return RemoteAPIServer.WorldMutationResultDTO(success: true, message: "ok",
                updated: buildWorldSlotsResponse(cfg.serverDir, running, repairing))
        }

        // POST /worlds/rename — metadata-only rename of a saved slot. Non-destructive.
        server.renameWorldSlotProvider = { [weak self] slotId, name in
            guard let self else { return RemoteAPIServer.WorldMutationResultDTO(success: false, message: "not_available") }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return RemoteAPIServer.WorldMutationResultDTO(success: false, message: "name_required") }
            let ctx = await MainActor.run { () -> (String, Bool)? in
                guard let server = self.selectedServer, let cfg = self.configServer(for: server) else { return nil }
                return (cfg.serverDir, self.isServerRunning)
            }
            guard let (serverDir, running) = ctx else { return RemoteAPIServer.WorldMutationResultDTO(success: false, message: "no_active_server") }
            let slots = WorldSlotManager.loadSlots(forServerDir: serverDir)
            guard let slot = slots.first(where: { $0.id == slotId }) else {
                return RemoteAPIServer.WorldMutationResultDTO(success: false, message: "slot_not_found")
            }
            do { _ = try WorldSlotManager.renameSlot(slot, newName: trimmed, serverDir: serverDir) }
            catch { return RemoteAPIServer.WorldMutationResultDTO(success: false, message: error.localizedDescription) }
            let repairing = await MainActor.run { () -> Bool in
                self.loadWorldSlotsForSelectedServer()
                self.logAppMessage("[WorldSlots] Remote: renamed slot to \"\(trimmed)\".")
                return self.isRepairingWorld
            }
            return RemoteAPIServer.WorldMutationResultDTO(success: true, message: "ok",
                updated: buildWorldSlotsResponse(serverDir, running, repairing))
        }

        // POST /worlds/replace — overwrite a slot's saved world with another saved slot's world.
        // (The Remote API caps bodies at 64 KB, so raw world upload is impossible; this exposes
        // ReplaceWorldView's "from an existing world" capability, the achievable subset.)
        // Destructive to the destination slot only; the source slot is untouched.
        server.replaceWorldSlotProvider = { [weak self] destId, sourceId in
            guard let self else { return RemoteAPIServer.WorldMutationResultDTO(success: false, message: "not_available") }
            guard destId != sourceId else { return RemoteAPIServer.WorldMutationResultDTO(success: false, message: "same_slot") }
            let ctx = await MainActor.run { () -> (ConfigServer, Bool)? in
                guard let server = self.selectedServer, let cfg = self.configServer(for: server) else { return nil }
                return (cfg, self.isServerRunning)
            }
            guard let (cfg, running) = ctx else { return RemoteAPIServer.WorldMutationResultDTO(success: false, message: "no_active_server") }
            let slots = WorldSlotManager.loadSlots(forServerDir: cfg.serverDir)
            guard let dest = slots.first(where: { $0.id == destId }) else {
                return RemoteAPIServer.WorldMutationResultDTO(success: false, message: "slot_not_found")
            }
            guard let source = slots.first(where: { $0.id == sourceId }) else {
                return RemoteAPIServer.WorldMutationResultDTO(success: false, message: "source_not_found")
            }
            let ok = await WorldSlotManager.copySlotIntoExisting(source, into: dest, for: cfg,
                logLine: { [weak self] msg in Task { @MainActor in self?.logAppMessage(msg) } })
            guard ok else { return RemoteAPIServer.WorldMutationResultDTO(success: false, message: "replace_failed") }
            let repairing = await MainActor.run { () -> Bool in self.loadWorldSlotsForSelectedServer(); return self.isRepairingWorld }
            return RemoteAPIServer.WorldMutationResultDTO(success: true, message: "ok",
                updated: buildWorldSlotsResponse(cfg.serverDir, running, repairing))
        }

        // POST /worlds/repair — Bedrock level.dat repair on the active world. Long-running
        // (starts + stops the server), so it is launched detached and reports "repair_started";
        // iOS polls GET /worlds until isRepairing flips back to false.
        server.repairWorldSlotProvider = { [weak self] slotId in
            guard let self else { return RemoteAPIServer.WorldMutationResultDTO(success: false, message: "not_available") }
            let ctx = await MainActor.run { () -> (String, Bool, Bool, String?, Bool)? in
                guard let server = self.selectedServer, let cfg = self.configServer(for: server) else { return nil }
                return (cfg.serverDir, cfg.isBedrock, self.isServerRunning,
                        self.activeWorldSlotId(forServerDir: cfg.serverDir), self.isRepairingWorld)
            }
            guard let (serverDir, isBedrock, running, activeId, alreadyRepairing) = ctx else {
                return RemoteAPIServer.WorldMutationResultDTO(success: false, message: "no_active_server")
            }
            guard isBedrock else { return RemoteAPIServer.WorldMutationResultDTO(success: false, message: "bedrock_only") }
            guard !running else { return RemoteAPIServer.WorldMutationResultDTO(success: false, message: "server_running") }
            guard let activeId, activeId == slotId else {
                return RemoteAPIServer.WorldMutationResultDTO(success: false, message: "not_active_slot")
            }
            guard !alreadyRepairing else { return RemoteAPIServer.WorldMutationResultDTO(success: false, message: "repair_in_progress") }
            await MainActor.run {
                self.logAppMessage("[WorldRepair] Remote: starting world repair (server will restart briefly).")
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    _ = await self.repairWorldLevelDat(logLine: { [weak self] msg in self?.logAppMessage(msg) })
                    self.loadWorldSlotsForSelectedServer()
                }
            }
            // Report repairing=true immediately even though the detached Task may not have set the flag yet.
            return RemoteAPIServer.WorldMutationResultDTO(success: true, message: "repair_started",
                updated: buildWorldSlotsResponse(serverDir, running, true))
        }

        // MARK: Diagnostics providers (P10) — health cards + startup-problem repair.
        // These expose the Mac's own diagnostic engine (refreshHealthCards / StartupCrashAnalyzer
        // results / the sheet's repair methods) rather than reimplementing any of it.
    }
}

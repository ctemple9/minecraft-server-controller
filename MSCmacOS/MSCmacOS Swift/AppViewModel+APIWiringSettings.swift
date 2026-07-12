//
//  AppViewModel+APIWiringSettings.swift
//  MSCmacOS
//
//  M1 (flowstate) slice 6: resource-pack, server-settings/backup-config, and user-token
//  Remote API providers. Extracted verbatim from AppViewModel.init (local-let +
//  by-reference assignment). buildResourcePacksResponse stays a local helper captured by
//  the pack providers.
//

import Foundation

extension AppViewModel {

    /// Resource-pack management (list/activate/set-URL/toggle-Geyser/remove), server
    /// settings + backup configuration, and shared-token user management.
    func wirePackSettingsUserProviders(into server: RemoteAPIServer) {
        // GET /resourcepacks — list installed packs + Geyser packs for the active server.
        // Helper: build the response DTO from disk (pure, no self needed).
        let buildResourcePacksResponse: (_ serverDir: String, _ isJava: Bool) -> RemoteAPIServer.ResourcePacksResponseDTO = { serverDir, isJava in
            let packs = isJava
                ? ResourcePackManager.listJavaPacks(serverDir: serverDir)
                : ResourcePackManager.listBedrockPacks(serverDir: serverDir)
            let isGeyserAvail = isJava && ResourcePackManager.isGeyserInstalled(serverDir: serverDir)
            let geyserPacks = isGeyserAvail ? ResourcePackManager.listGeyserPacks(serverDir: serverDir) : []
            let props = isJava ? ServerPropertiesManager.readProperties(serverDir: serverDir) : [:]
            let activeUrl = props["resource-pack"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let requirePack = (props["require-resource-pack"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "") == "true"
            func dto(_ p: InstalledResourcePack, kind: String) -> RemoteAPIServer.ResourcePackItemDTO {
                RemoteAPIServer.ResourcePackItemDTO(
                    id: p.id, name: p.name, fileName: p.fileName,
                    fileSizeDisplay: p.fileSizeDisplay,
                    packKind: kind, isActive: p.isActive, typeLabel: p.typeLabel
                )
            }
            return RemoteAPIServer.ResourcePacksResponseDTO(
                serverType: isJava ? "java" : "bedrock",
                isJava: isJava,
                packs: packs.map { dto($0, kind: isJava ? "java" : "bedrock") },
                geyserPacks: geyserPacks.map { dto($0, kind: "geyser") },
                isGeyserAvailable: isGeyserAvail,
                activePackUrl: activeUrl.flatMap { $0.isEmpty ? nil : $0 },
                requirePack: requirePack
            )
        }

        let resourcePacksProvider: () async -> RemoteAPIServer.ResourcePacksResponseDTO = { [weak self] in
            guard let self else { return RemoteAPIServer.ResourcePacksResponseDTO(serverType: "java", note: "not_available") }
            let result = await MainActor.run { () -> (String, Bool)? in
                guard let server = self.selectedServer, let cfg = self.configServer(for: server) else { return nil }
                return (cfg.serverDir, cfg.isJava)
            }
            guard let (serverDir, isJava) = result else {
                return RemoteAPIServer.ResourcePacksResponseDTO(serverType: "java", note: "no_active_server")
            }
            return buildResourcePacksResponse(serverDir, isJava)
        }

        // POST /resourcepacks/activate — set or clear the active Java pack (local file hosted by Mac).
        let activateResourcePackProvider: (String?, Bool) async -> RemoteAPIServer.ResourcePackMutationResultDTO = { [weak self] packId, require in
            guard let self else { return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: "not_available") }
            let state = await MainActor.run { () -> (String, String?, Int, Bool)? in
                guard let server = self.selectedServer, let cfg = self.configServer(for: server), cfg.isJava else { return nil }
                return (cfg.serverDir, self.resourcePackHostAddress(), cfg.resourcePackHostPort, true)
            }
            guard let (serverDir, hostAddr, port, _) = state else {
                return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: "java_only")
            }
            if let packId {
                let packs = ResourcePackManager.listJavaPacks(serverDir: serverDir)
                guard let pack = packs.first(where: { $0.id == packId }) else {
                    return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: "pack_not_found")
                }
                guard let host = hostAddr, !host.isEmpty else {
                    return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: "no_host_address")
                }
                let sha1 = ResourcePackManager.sha1Hex(of: pack.fileURL)
                let encoded = pack.fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pack.fileName
                let url = "http://\(host):\(port)/\(encoded)"
                await MainActor.run {
                    let dir = ResourcePackManager.javaPacksDirectory(serverDir: serverDir)
                    self.resourcePackHostServer.start(directory: dir, port: UInt16(port))
                }
                do {
                    try ResourcePackManager.setJavaActivePack(url: url, sha1: sha1, require: require, serverDir: serverDir)
                    await MainActor.run { self.logAppMessage("[ResourcePacks] Remote: activated \(pack.fileName).") }
                } catch {
                    return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: error.localizedDescription)
                }
            } else {
                do {
                    try ResourcePackManager.setJavaActivePack(url: nil, sha1: nil, require: false, serverDir: serverDir)
                    await MainActor.run { self.resourcePackHostServer.stop() }
                } catch {
                    return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: error.localizedDescription)
                }
            }
            await MainActor.run { self.loadResourcePacksForSelectedServer() }
            return RemoteAPIServer.ResourcePackMutationResultDTO(success: true, message: "ok",
                updated: buildResourcePacksResponse(serverDir, true))
        }

        // POST /resourcepacks/seturl — write a custom URL directly to server.properties (iOS "add by URL").
        let setResourcePackURLProvider: (String, String?, Bool) async -> RemoteAPIServer.ResourcePackMutationResultDTO = { [weak self] url, sha1, require in
            guard let self else { return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: "not_available") }
            let state = await MainActor.run { () -> String? in
                guard let server = self.selectedServer, let cfg = self.configServer(for: server), cfg.isJava else { return nil }
                return cfg.serverDir
            }
            guard let serverDir = state else {
                return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: "java_only")
            }
            do {
                try ResourcePackManager.setJavaActivePack(url: url, sha1: sha1, require: require, serverDir: serverDir)
                await MainActor.run { self.logAppMessage("[ResourcePacks] Remote: set custom URL \(url).") }
            } catch {
                return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: error.localizedDescription)
            }
            await MainActor.run { self.loadResourcePacksForSelectedServer() }
            return RemoteAPIServer.ResourcePackMutationResultDTO(success: true, message: "ok",
                updated: buildResourcePacksResponse(serverDir, true))
        }

        // POST /resourcepacks/toggle — enable or disable a Geyser pack.
        let toggleGeyserPackProvider: (String, Bool) async -> RemoteAPIServer.ResourcePackMutationResultDTO = { [weak self] packId, enabled in
            guard let self else { return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: "not_available") }
            let state = await MainActor.run { () -> (String, Bool)? in
                guard let server = self.selectedServer, let cfg = self.configServer(for: server) else { return nil }
                return (cfg.serverDir, cfg.isJava)
            }
            guard let (serverDir, isJava) = state else {
                return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: "no_active_server")
            }
            let geyserPacks = ResourcePackManager.listGeyserPacks(serverDir: serverDir)
            guard let pack = geyserPacks.first(where: { $0.id == packId }) else {
                return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: "pack_not_found")
            }
            do {
                try ResourcePackManager.setGeyserPackEnabled(pack, enabled: enabled, serverDir: serverDir)
                await MainActor.run { self.logAppMessage("[ResourcePacks] Remote: \(enabled ? "enabled" : "disabled") Geyser pack \(pack.fileName).") }
            } catch {
                return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: error.localizedDescription)
            }
            await MainActor.run { self.loadResourcePacksForSelectedServer() }
            return RemoteAPIServer.ResourcePackMutationResultDTO(success: true, message: "ok",
                updated: buildResourcePacksResponse(serverDir, isJava))
        }

        // POST /resourcepacks/remove — delete a pack from disk.
        let removeResourcePackProvider: (String, String) async -> RemoteAPIServer.ResourcePackMutationResultDTO = { [weak self] packId, packKind in
            guard let self else { return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: "not_available") }
            let state = await MainActor.run { () -> (String, Bool)? in
                guard let server = self.selectedServer, let cfg = self.configServer(for: server) else { return nil }
                return (cfg.serverDir, cfg.isJava)
            }
            guard let (serverDir, isJava) = state else {
                return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: "no_active_server")
            }
            switch packKind {
            case "geyser":
                let packs = ResourcePackManager.listGeyserPacks(serverDir: serverDir)
                guard let pack = packs.first(where: { $0.id == packId }) else {
                    return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: "pack_not_found")
                }
                do { try ResourcePackManager.removeGeyserPack(pack, serverDir: serverDir) }
                catch { return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: error.localizedDescription) }
            case "java":
                let packs = ResourcePackManager.listJavaPacks(serverDir: serverDir)
                guard let pack = packs.first(where: { $0.id == packId }) else {
                    return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: "pack_not_found")
                }
                do {
                    let wasActive = pack.isActive
                    try ResourcePackManager.removePack(pack, serverDir: serverDir, isJava: true)
                    if wasActive { await MainActor.run { self.resourcePackHostServer.stop() } }
                } catch { return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: error.localizedDescription) }
            case "bedrock":
                let packs = ResourcePackManager.listBedrockPacks(serverDir: serverDir)
                guard let pack = packs.first(where: { $0.id == packId }) else {
                    return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: "pack_not_found")
                }
                do { try ResourcePackManager.removePack(pack, serverDir: serverDir, isJava: false) }
                catch { return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: error.localizedDescription) }
            default:
                return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: "invalid_kind")
            }
            await MainActor.run { self.loadResourcePacksForSelectedServer() }
            return RemoteAPIServer.ResourcePackMutationResultDTO(success: true, message: "ok",
                updated: buildResourcePacksResponse(serverDir, isJava))
        }

        // GET /settings — typed server.properties schema for the active server.
        let settingsProvider: () -> RemoteAPIServer.SettingsResponseDTO = { [weak self] in
            guard let self else {
                return RemoteAPIServer.SettingsResponseDTO(serverType: "java", serverName: "", serverRunning: false, editable: false, sections: [], note: "not_available")
            }
            let work: () -> RemoteAPIServer.SettingsResponseDTO = {
                let cfg = self.configManager.config
                guard let server = cfg.servers.first(where: { $0.id == cfg.activeServerId }) else {
                    return RemoteAPIServer.SettingsResponseDTO(serverType: "java", serverName: "", serverRunning: false, editable: false, sections: [], note: "no_active_server")
                }
                if server.isBedrock {
                    let model = self.bedrockPropertiesModel(for: server)
                    return RemoteAPIServer.SettingsResponseDTO(
                        serverType: server.serverType.rawValue,
                        serverName: server.displayName,
                        serverRunning: self.isServerRunning,
                        editable: true,
                        sections: ServerSettingsSchema.bedrockSections(from: model)
                    )
                }
                let model = self.loadServerPropertiesModel(for: server)
                return RemoteAPIServer.SettingsResponseDTO(
                    serverType: server.serverType.rawValue,
                    serverName: server.displayName,
                    serverRunning: self.isServerRunning,
                    editable: true,
                    sections: ServerSettingsSchema.javaSections(from: model)
                )
            }
            if Thread.isMainThread { return work() }
            return DispatchQueue.main.sync { work() }
        }

        // POST /settings — apply a sparse change set to the active Java server.
        let updateSettingsProvider: ([String: String]) -> RemoteAPIServer.SettingsUpdateResultDTO = { [weak self] changes in
            guard let self else {
                return RemoteAPIServer.SettingsUpdateResultDTO(success: false, message: "not_available", restartRequired: false, appliedKeys: [])
            }
            let work: () -> RemoteAPIServer.SettingsUpdateResultDTO = {
                let cfg = self.configManager.config
                guard let server = cfg.servers.first(where: { $0.id == cfg.activeServerId }) else {
                    return RemoteAPIServer.SettingsUpdateResultDTO(success: false, message: "no_active_server", restartRequired: false, appliedKeys: [])
                }
                if server.isBedrock {
                    var model = self.bedrockPropertiesModel(for: server)
                    let (applied, rejected) = ServerSettingsSchema.applyBedrock(changes: changes, onto: &model)
                    let rejectedOut = rejected.isEmpty ? nil : rejected
                    guard !applied.isEmpty else {
                        let sections = ServerSettingsSchema.bedrockSections(from: self.bedrockPropertiesModel(for: server))
                        return RemoteAPIServer.SettingsUpdateResultDTO(success: false, message: "no_valid_changes", restartRequired: self.isServerRunning, appliedKeys: [], rejected: rejectedOut, sections: sections)
                    }
                    do {
                        try self.saveBedrockPropertiesModel(model, for: server)
                        let sections = ServerSettingsSchema.bedrockSections(from: self.bedrockPropertiesModel(for: server))
                        let msg = rejected.isEmpty ? "saved" : "saved_with_rejections"
                        self.logAppMessage("[Settings] (remote) Applied \(applied.count) change(s) to \(server.displayName)\(rejected.isEmpty ? "" : "; \(rejected.count) rejected").")
                        return RemoteAPIServer.SettingsUpdateResultDTO(success: true, message: msg, restartRequired: self.isServerRunning, appliedKeys: applied, rejected: rejectedOut, sections: sections)
                    } catch {
                        return RemoteAPIServer.SettingsUpdateResultDTO(success: false, message: error.localizedDescription, restartRequired: self.isServerRunning, appliedKeys: [], rejected: rejectedOut)
                    }
                }
                var model = self.loadServerPropertiesModel(for: server)
                let (applied, rejected) = ServerSettingsSchema.applyJava(changes: changes, onto: &model)
                let rejectedOut = rejected.isEmpty ? nil : rejected
                guard !applied.isEmpty else {
                    // Nothing valid changed — report but don't touch the file.
                    let sections = ServerSettingsSchema.javaSections(from: self.loadServerPropertiesModel(for: server))
                    return RemoteAPIServer.SettingsUpdateResultDTO(success: false, message: "no_valid_changes", restartRequired: self.isServerRunning, appliedKeys: [], rejected: rejectedOut, sections: sections)
                }
                do {
                    try self.saveServerPropertiesModel(model, for: server)
                    // Re-read from disk so the echoed schema reflects clamped/merged ground truth.
                    let sections = ServerSettingsSchema.javaSections(from: self.loadServerPropertiesModel(for: server))
                    let msg = rejected.isEmpty ? "saved" : "saved_with_rejections"
                    self.logAppMessage("[Settings] (remote) Applied \(applied.count) change(s) to \(server.displayName)\(rejected.isEmpty ? "" : "; \(rejected.count) rejected").")
                    return RemoteAPIServer.SettingsUpdateResultDTO(success: true, message: msg, restartRequired: self.isServerRunning, appliedKeys: applied, rejected: rejectedOut, sections: sections)
                } catch {
                    return RemoteAPIServer.SettingsUpdateResultDTO(success: false, message: error.localizedDescription, restartRequired: self.isServerRunning, appliedKeys: [], rejected: rejectedOut)
                }
            }
            if Thread.isMainThread { return work() }
            return DispatchQueue.main.sync { work() }
        }

        // GET /backups/config — current schedule + retention for the active server.
        let backupConfigProvider: () -> RemoteAPIServer.BackupConfigResponseDTO = { [weak self] in
            guard let self else {
                return RemoteAPIServer.BackupConfigResponseDTO(serverName: "", autoBackupEnabled: false, autoBackupIntervalMinutes: 30, autoBackupMaxCount: 12, note: "not_available")
            }
            let work: () -> RemoteAPIServer.BackupConfigResponseDTO = {
                let cfg = self.configManager.config
                guard let server = cfg.servers.first(where: { $0.id == cfg.activeServerId }) else {
                    return RemoteAPIServer.BackupConfigResponseDTO(serverName: "", autoBackupEnabled: false, autoBackupIntervalMinutes: 30, autoBackupMaxCount: 12, note: "no_active_server")
                }
                return RemoteAPIServer.BackupConfigResponseDTO(
                    serverName: server.displayName,
                    autoBackupEnabled: server.autoBackupEnabled,
                    autoBackupIntervalMinutes: server.autoBackupIntervalMinutes,
                    autoBackupMaxCount: server.autoBackupMaxCount
                )
            }
            if Thread.isMainThread { return work() }
            return DispatchQueue.main.sync { work() }
        }

        // POST /backups/config — apply sparse backup schedule changes to the active server.
        let updateBackupConfigProvider: (_ enabled: Bool?, _ intervalMinutes: Int?, _ maxCount: Int?) -> RemoteAPIServer.BackupConfigUpdateResultDTO = { [weak self] enabled, intervalMinutes, maxCount in
            guard let self else {
                return RemoteAPIServer.BackupConfigUpdateResultDTO(success: false, message: "not_available")
            }
            let work: () -> RemoteAPIServer.BackupConfigUpdateResultDTO = {
                let cfg = self.configManager.config
                guard let server = cfg.servers.first(where: { $0.id == cfg.activeServerId }) else {
                    return RemoteAPIServer.BackupConfigUpdateResultDTO(success: false, message: "no_active_server")
                }
                if let enabled { self.setAutoBackupEnabled(enabled, for: server.id) }
                if let intervalMinutes {
                    let clamped = [15, 30, 45, 60, 120, 240, 360].contains(intervalMinutes) ? intervalMinutes : 30
                    self.setAutoBackupInterval(clamped, for: server.id)
                }
                if let maxCount { self.setAutoBackupMaxCount(Swift.max(3, Swift.min(50, maxCount)), for: server.id) }
                let fresh = self.configManager.config.servers.first(where: { $0.id == server.id })
                let echoDTO = RemoteAPIServer.BackupConfigResponseDTO(
                    serverName: server.displayName,
                    autoBackupEnabled: fresh?.autoBackupEnabled ?? server.autoBackupEnabled,
                    autoBackupIntervalMinutes: fresh?.autoBackupIntervalMinutes ?? server.autoBackupIntervalMinutes,
                    autoBackupMaxCount: fresh?.autoBackupMaxCount ?? server.autoBackupMaxCount
                )
                self.logAppMessage("[Backup] (remote) Config updated for \(server.displayName).")
                return RemoteAPIServer.BackupConfigUpdateResultDTO(success: true, message: "saved", config: echoDTO)
            }
            if Thread.isMainThread { return work() }
            return DispatchQueue.main.sync { work() }
        }

        let listUsersProvider: () async -> RemoteAPIServer.UserListResponseDTO = { [weak self] in
            guard let self else { return RemoteAPIServer.UserListResponseDTO(users: []) }
            let entries = self.configManager.config.remoteAPISharedAccess
            let dtos = entries.map { e in
                RemoteAPIServer.UserSummaryDTO(
                    id: e.id, label: e.label, role: e.role,
                    permissions: e.permissions,
                    createdAtISO8601: e.createdAtISO8601,
                    expiresAtISO8601: e.expiresAtISO8601,
                    isExpired: e.isExpired
                )
            }
            return RemoteAPIServer.UserListResponseDTO(users: dtos)
        }

        let createUserProvider: (_ label: String, _ role: String, _ permissions: [String]?, _ expiresInDays: Int?) async -> RemoteAPIServer.UserCreateResultDTO = { [weak self] label, role, permissions, expiresInDays in
            guard let self else { return RemoteAPIServer.UserCreateResultDTO(success: false, message: "not_available") }
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return RemoteAPIServer.UserCreateResultDTO(success: false, message: "label_empty") }
            let rawToken = UUID().uuidString + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            let entry = RemoteAPISharedAccessEntry.make(
                label: trimmed, token: rawToken, role: role,
                permissions: permissions, expiresInDays: expiresInDays
            )
            await MainActor.run {
                self.configManager.config.remoteAPISharedAccess.append(entry)
                self.configManager.save()
            }
            let dto = RemoteAPIServer.UserSummaryDTO(
                id: entry.id, label: entry.label, role: entry.role,
                permissions: entry.permissions,
                createdAtISO8601: entry.createdAtISO8601,
                expiresAtISO8601: entry.expiresAtISO8601,
                isExpired: false
            )
            return RemoteAPIServer.UserCreateResultDTO(success: true, message: "created", user: dto, token: rawToken)
        }

        let revokeUserProvider: (_ userId: String) async -> RemoteAPIServer.UserRevokeResultDTO = { [weak self] userId in
            guard let self else { return RemoteAPIServer.UserRevokeResultDTO(success: false, message: "not_available") }
            let found = await MainActor.run { () -> Bool in
                let before = self.configManager.config.remoteAPISharedAccess.count
                self.configManager.config.remoteAPISharedAccess.removeAll { $0.id == userId }
                if self.configManager.config.remoteAPISharedAccess.count < before {
                    self.configManager.save()
                    return true
                }
                return false
            }
            return found
                ? RemoteAPIServer.UserRevokeResultDTO(success: true, message: "revoked")
                : RemoteAPIServer.UserRevokeResultDTO(success: false, message: "not_found")
        }

        let updateUserProvider: (_ userId: String, _ label: String?, _ role: String?, _ permissions: [String]?, _ expiresInDays: Int?) async -> RemoteAPIServer.UserUpdateResultDTO = { [weak self] userId, label, role, permissions, expiresInDays in
            guard let self else { return RemoteAPIServer.UserUpdateResultDTO(success: false, message: "not_available") }
            if let l = label, l.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return RemoteAPIServer.UserUpdateResultDTO(success: false, message: "label_empty")
            }
            let result: RemoteAPIServer.UserUpdateResultDTO = await MainActor.run {
                guard let idx = self.configManager.config.remoteAPISharedAccess.firstIndex(where: { $0.id == userId }) else {
                    return RemoteAPIServer.UserUpdateResultDTO(success: false, message: "not_found")
                }
                var e = self.configManager.config.remoteAPISharedAccess[idx]
                if let l = label { e.label = l.trimmingCharacters(in: .whitespacesAndNewlines) }
                if let r = role { e.role = r }
                if let p = permissions { e.permissions = p }
                if let days = expiresInDays {
                    if days < 0 {
                        e.expiresAtISO8601 = nil
                    } else {
                        let fmt = ISO8601DateFormatter()
                        e.expiresAtISO8601 = Calendar.current.date(byAdding: .day, value: days, to: Date()).map { fmt.string(from: $0) }
                    }
                }
                self.configManager.config.remoteAPISharedAccess[idx] = e
                self.configManager.save()
                let dto = RemoteAPIServer.UserSummaryDTO(
                    id: e.id, label: e.label, role: e.role,
                    permissions: e.permissions,
                    createdAtISO8601: e.createdAtISO8601,
                    expiresAtISO8601: e.expiresAtISO8601,
                    isExpired: e.isExpired
                )
                return RemoteAPIServer.UserUpdateResultDTO(success: true, message: "updated", user: dto)
            }
            return result
        }
        server.resourcePacksProvider = resourcePacksProvider
        server.activateResourcePackProvider = activateResourcePackProvider
        server.setResourcePackURLProvider = setResourcePackURLProvider
        server.toggleGeyserPackProvider = toggleGeyserPackProvider
        server.removeResourcePackProvider = removeResourcePackProvider
        server.settingsProvider = settingsProvider
        server.updateSettingsProvider = updateSettingsProvider
        server.backupConfigProvider = backupConfigProvider
        server.updateBackupConfigProvider = updateBackupConfigProvider
        server.listUsersProvider = listUsersProvider
        server.createUserProvider = createUserProvider
        server.revokeUserProvider = revokeUserProvider
        server.updateUserProvider = updateUserProvider
    }
}

//
//  AppViewModel+APIWiringAddons.swift
//  MSCmacOS
//
//  M1 (flowstate) slice 5: allowlist-mutation, add-on (install/update/remove/catalog),
//  and version-management Remote API providers. Extracted verbatim from
//  AppViewModel.init (local-let + by-reference assignment).
//

import Foundation

extension AppViewModel {

    /// Bedrock allowlist mutation, add-on management (list/update/remove/catalog search/
    /// install), and server version listing/change.
    func wireAllowlistAddonVersionProviders(into server: RemoteAPIServer) {
        // POST /allowlist — add/remove an entry on the active Bedrock server.
        // Reuses BedrockPropertiesManager (the same logic the Mac UI calls) and
        // returns the freshly-read list so iOS updates in one round-trip.
        let mutateAllowlistProvider: (String, String) -> RemoteAPIServer.AllowlistMutationResultDTO = { [weak self] action, name in
            guard let self else {
                return RemoteAPIServer.AllowlistMutationResultDTO(success: false, message: "not_available", serverType: "java", entries: [])
            }
            let work: () -> RemoteAPIServer.AllowlistMutationResultDTO = {
                let cfg = self.configManager.config
                guard let server = cfg.servers.first(where: { $0.id == cfg.activeServerId }) else {
                    return RemoteAPIServer.AllowlistMutationResultDTO(success: false, message: "no_active_server", serverType: "java", entries: [])
                }
                guard server.isBedrock else {
                    return RemoteAPIServer.AllowlistMutationResultDTO(success: false, message: "not_bedrock", serverType: server.serverType.rawValue, entries: [])
                }
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                do {
                    if action == "add" {
                        try BedrockPropertiesManager.addToAllowlist(name: trimmed, xuid: self.bedrockXUID(forPlayerNamed: trimmed), serverDir: server.serverDir)
                        self.logAppMessage("[Allowlist] (remote) Added \(trimmed) to \(server.displayName).")
                    } else {
                        try BedrockPropertiesManager.removeFromAllowlist(name: trimmed, serverDir: server.serverDir)
                        self.logAppMessage("[Allowlist] (remote) Removed \(trimmed) from \(server.displayName).")
                    }
                    let entries = BedrockPropertiesManager.readAllowlist(serverDir: server.serverDir)
                    // Keep the published list (which GET /allowlist reads) in sync when
                    // this active server is also the one selected in the Mac UI, and
                    // hot-reload a running server so the change takes effect live.
                    if let sel = self.selectedServer, self.configServer(for: sel)?.id == server.id {
                        self.bedrockAllowlist = entries
                    }
                    if self.activeBackend?.isRunning == true { self.sendQuickCommand("allowlist reload") }
                    let dtoEntries = entries.map {
                        RemoteAPIServer.AllowlistEntryDTO(name: $0.name, xuid: $0.xuid, ignoresPlayerLimit: $0.ignoresPlayerLimit)
                    }
                    return RemoteAPIServer.AllowlistMutationResultDTO(
                        success: true,
                        message: action == "add" ? "added" : "removed",
                        serverType: server.serverType.rawValue,
                        entries: dtoEntries
                    )
                } catch {
                    self.logAppMessage("[Allowlist] (remote) Failed to \(action) \(trimmed): \(error.localizedDescription)")
                    return RemoteAPIServer.AllowlistMutationResultDTO(success: false, message: error.localizedDescription, serverType: server.serverType.rawValue, entries: [])
                }
            }
            if Thread.isMainThread { return work() }
            return DispatchQueue.main.sync { work() }
        }

        // GET /addons — returns the current add-on update plan, triggering a resolve if stale.
        let addonsProvider: () async -> RemoteAPIServer.AddonsResponseDTO = { [weak self] in
            guard let self else {
                return RemoteAPIServer.AddonsResponseDTO(addons: [], isResolving: false, serverSupportsAddons: false)
            }
            return await MainActor.run {
                let cfg = self.configManager.config
                guard let activeServer = cfg.servers.first(where: { $0.id == cfg.activeServerId }) else {
                    return RemoteAPIServer.AddonsResponseDTO(addons: [], isResolving: false, serverSupportsAddons: false)
                }
                let supportsAddons = activeServer.javaFlavor.addOnKind != nil
                if supportsAddons { self.resolveAddonUpdates(for: activeServer) }
                let dtos = self.addonUpdatePlan.map { item in
                    RemoteAPIServer.AddonItemDTO(
                        jarStem: item.jarStem,
                        displayName: item.displayName,
                        isEnabled: item.isEnabled,
                        projectId: item.projectId,
                        currentVersion: item.currentVersion,
                        availableVersion: item.availableVersion,
                        bucket: item.bucket.remoteAPIString,
                        iconURL: item.iconURL
                    )
                }
                return RemoteAPIServer.AddonsResponseDTO(
                    addons: dtos,
                    isResolving: self.isResolvingAddonUpdates,
                    serverSupportsAddons: supportsAddons
                )
            }
        }

        // POST /components/update with jarStem/updateAll — fire-and-forget via AppViewModel+AddonUpdates.
        let updateAddonProvider: (String?, Bool) -> RemoteAPIServer.AddonUpdateResultDTO = { [weak self] jarStem, updateAll in
            guard let self else {
                return RemoteAPIServer.AddonUpdateResultDTO(result: "not_available", jarStem: nil, count: 0)
            }
            let work: () -> RemoteAPIServer.AddonUpdateResultDTO = {
                let cfg = self.configManager.config
                guard let activeServer = cfg.servers.first(where: { $0.id == cfg.activeServerId }),
                      activeServer.javaFlavor.addOnKind != nil else {
                    return RemoteAPIServer.AddonUpdateResultDTO(result: "not_supported", jarStem: nil, count: 0)
                }
                if updateAll {
                    let items = self.addonUpdatePlan.filter { $0.bucket == .updateAvailable && $0.availableVersionId != nil }
                    guard !items.isEmpty else {
                        return RemoteAPIServer.AddonUpdateResultDTO(result: "no_updates_available", jarStem: nil, count: 0)
                    }
                    self.updateAddons(items, for: activeServer)
                    return RemoteAPIServer.AddonUpdateResultDTO(result: "update_started", jarStem: nil, count: items.count)
                } else if let stem = jarStem, !stem.isEmpty {
                    guard let item = self.addonUpdatePlan.first(where: { $0.jarStem == stem }) else {
                        return RemoteAPIServer.AddonUpdateResultDTO(result: "not_found", jarStem: stem, count: 0)
                    }
                    guard item.bucket == .updateAvailable else {
                        return RemoteAPIServer.AddonUpdateResultDTO(result: "no_updates_available", jarStem: stem, count: 0)
                    }
                    self.updateAddon(item, for: activeServer)
                    return RemoteAPIServer.AddonUpdateResultDTO(result: "update_started", jarStem: stem, count: 1)
                }
                return RemoteAPIServer.AddonUpdateResultDTO(result: "invalid_request", jarStem: nil, count: 0)
            }
            if Thread.isMainThread { return work() }
            return DispatchQueue.main.sync { work() }
        }

        // POST /components/remove — deletes the add-on file from the active server's add-on folder.
        let removeAddonProvider: (String) -> RemoteAPIServer.AddonRemoveResultDTO = { [weak self] jarStem in
            guard let self else {
                return RemoteAPIServer.AddonRemoveResultDTO(success: false, message: "not_available", jarStem: jarStem)
            }
            let work: () -> RemoteAPIServer.AddonRemoveResultDTO = {
                let cfg = self.configManager.config
                guard let activeServer = cfg.servers.first(where: { $0.id == cfg.activeServerId }),
                      let addOnKind = activeServer.javaFlavor.addOnKind else {
                    return RemoteAPIServer.AddonRemoveResultDTO(success: false, message: "not_supported", jarStem: jarStem)
                }
                let folder = URL(fileURLWithPath: activeServer.serverDir, isDirectory: true)
                    .appendingPathComponent(addOnKind.folderName, isDirectory: true)
                let fm = FileManager.default
                let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
                guard let targetURL = files.first(where: { url in
                    let name = url.lastPathComponent
                    let isDisabled = name.lowercased().hasSuffix(".jar.disabled")
                    let stem = isDisabled ? String(name.dropLast(".jar.disabled".count))
                                          : url.deletingPathExtension().lastPathComponent
                    return stem == jarStem
                }) else {
                    return RemoteAPIServer.AddonRemoveResultDTO(success: false, message: "not_found", jarStem: jarStem)
                }
                do {
                    try fm.removeItem(at: targetURL)
                    DispatchQueue.main.async { [weak self] in
                        if addOnKind == .mod { self?.refreshDiscoveredMods() } else { self?.refreshDiscoveredPlugins() }
                        self?.invalidateAddonPlan()
                        self?.logAppMessage("[Add-ons] (remote) Removed \(jarStem).")
                    }
                    return RemoteAPIServer.AddonRemoveResultDTO(success: true, message: "removed", jarStem: jarStem)
                } catch {
                    return RemoteAPIServer.AddonRemoveResultDTO(success: false, message: error.localizedDescription, jarStem: jarStem)
                }
            }
            if Thread.isMainThread { return work() }
            return DispatchQueue.main.sync { work() }
        }

        // GET /catalog/search — proxies ModrinthAPI.search for the active server's loader + version.
        let catalogSearchProvider: (String, Int) async -> RemoteAPIServer.CatalogSearchResponseDTO = { [weak self] query, offset in
            guard let self else {
                return RemoteAPIServer.CatalogSearchResponseDTO(supportsAddons: false, note: "not_available")
            }
            // Resolve the active server's add-on context on the main actor.
            let context: (loaders: [String], gameVersion: String?, projectType: String, addonKind: String, loaderName: String)? = await MainActor.run {
                let cfg = self.configManager.config
                guard let server = cfg.servers.first(where: { $0.id == cfg.activeServerId }) else { return nil }
                guard let addOn = server.javaFlavor.addOnKind else { return nil }
                return (server.javaFlavor.modrinthLoaderFacets,
                        server.minecraftVersion,
                        server.javaFlavor.modrinthProjectType,
                        addOn == .plugin ? "plugin" : "mod",
                        server.javaFlavor.displayName)
            }
            guard let ctx = context else {
                // Distinguish "no active server" from "server doesn't support add-ons".
                let hasActive = await MainActor.run { self.configManager.config.activeServerId != nil && self.configManager.config.servers.contains(where: { $0.id == self.configManager.config.activeServerId }) }
                return RemoteAPIServer.CatalogSearchResponseDTO(supportsAddons: false, note: hasActive ? "not_supported" : "no_active_server")
            }
            do {
                let result = try await ModrinthAPI.search(
                    query: query,
                    loaders: ctx.loaders,
                    gameVersion: ctx.gameVersion,
                    projectType: ctx.projectType,
                    limit: 30,
                    offset: offset)
                // Down-rank client-only add-ons (they do nothing on a server), mirroring the Mac browser.
                let sorted = result.hits.sorted { !$0.isClientOnly && $1.isClientOnly }
                let items = sorted.map { hit in
                    RemoteAPIServer.CatalogItemDTO(
                        projectId: hit.projectId, slug: hit.slug, title: hit.title,
                        description: hit.description, author: hit.author, downloads: hit.downloads,
                        iconURL: hit.iconUrl, isClientOnly: hit.isClientOnly, projectType: hit.projectType)
                }
                return RemoteAPIServer.CatalogSearchResponseDTO(
                    supportsAddons: true, addonKind: ctx.addonKind, loaderName: ctx.loaderName,
                    gameVersion: ctx.gameVersion, results: items)
            } catch {
                return RemoteAPIServer.CatalogSearchResponseDTO(
                    supportsAddons: true, addonKind: ctx.addonKind, loaderName: ctx.loaderName,
                    gameVersion: ctx.gameVersion, results: [], note: "search_failed: \(error.localizedDescription)")
            }
        }

        // POST /components/install — installs the latest compatible version via the Mac's exact install path.
        let installAddonProvider: (String, String, String) async -> RemoteAPIServer.CatalogInstallResultDTO = { [weak self] projectId, slug, title in
            guard let self else {
                return RemoteAPIServer.CatalogInstallResultDTO(success: false, message: "not_available", projectId: projectId)
            }
            // Resolve the active server on the main actor.
            let cfg: ConfigServer? = await MainActor.run {
                let c = self.configManager.config
                return c.servers.first(where: { $0.id == c.activeServerId })
            }
            guard let server = cfg else {
                return RemoteAPIServer.CatalogInstallResultDTO(success: false, message: "no_active_server", projectId: projectId)
            }
            guard server.javaFlavor.addOnKind != nil else {
                return RemoteAPIServer.CatalogInstallResultDTO(success: false, message: "not_supported", projectId: projectId)
            }
            // Build a minimal hit — installModrinthAddon only reads `slug` (to fetch versions)
            // and `title` (for its log/message); the other fields are cosmetic.
            let hit = ModrinthSearchHit(
                projectId: projectId, slug: slug, title: title.isEmpty ? slug : title,
                description: "", author: "", downloads: 0, iconUrl: nil,
                clientSide: "optional", serverSide: "required",
                projectType: server.javaFlavor.modrinthProjectType)
            let result = await self.installModrinthAddon(hit, into: server)
            return RemoteAPIServer.CatalogInstallResultDTO(success: result.ok, message: result.message, projectId: projectId)
        }

        // GET /versions — available server JAR / Bedrock versions for the active server.
        let versionsProvider: () async -> RemoteAPIServer.VersionsResponseDTO = { [weak self] in
            guard let self else {
                return RemoteAPIServer.VersionsResponseDTO(supportsVersions: false, note: "not_available")
            }
            // Resolve active server on main actor.
            typealias VersionCtx = (isBedrock: Bool, flavor: JavaServerFlavor?, displayName: String, currentVersion: String?)
            let ctx: VersionCtx? = await MainActor.run {
                let cfg = self.configManager.config
                guard let server = cfg.servers.first(where: { $0.id == cfg.activeServerId }) else { return nil }
                return (server.isBedrock,
                        server.isBedrock ? nil : server.javaFlavor,
                        server.displayName,
                        server.isBedrock ? (server.bedrockVersion ?? "LATEST") : server.minecraftVersion)
            }
            guard let ctx else {
                return RemoteAPIServer.VersionsResponseDTO(supportsVersions: false, note: "no_active_server")
            }
            if ctx.isBedrock {
                let versions = await BedrockVersionFetcher.fetchVersions()
                let entries = versions.map { v in
                    RemoteAPIServer.VersionEntryDTO(id: v.version, displayLabel: v.displayName,
                                                    mcVersion: v.version, loaderVersion: nil,
                                                    buildLabel: nil, isStable: true, isLatest: v.isLatest)
                }
                return RemoteAPIServer.VersionsResponseDTO(supportsVersions: true, flavorName: "Bedrock",
                                                           currentVersion: ctx.currentVersion, isBedrock: true,
                                                           versions: entries)
            }
            guard let flavor = ctx.flavor else {
                return RemoteAPIServer.VersionsResponseDTO(supportsVersions: false, note: "not_supported")
            }
            do {
                let rawEntries = try await ServerJarProvider.listVersions(for: flavor)
                if rawEntries.isEmpty {
                    // Pufferfish / Spigot / Quilt: can only download latest.
                    let latestEntry = RemoteAPIServer.VersionEntryDTO(
                        id: "__latest__", displayLabel: "Latest (recommended)",
                        mcVersion: "", loaderVersion: nil, buildLabel: nil, isStable: true, isLatest: true)
                    return RemoteAPIServer.VersionsResponseDTO(supportsVersions: true, flavorName: flavor.displayName,
                                                               currentVersion: ctx.currentVersion, isBedrock: false,
                                                               versions: [latestEntry], note: "latest_only")
                }
                let entries = rawEntries.map { e in
                    RemoteAPIServer.VersionEntryDTO(id: e.id, displayLabel: e.displayLabel,
                                                    mcVersion: e.mcVersion, loaderVersion: e.loaderVersion,
                                                    buildLabel: e.buildLabel, isStable: e.isStable, isLatest: e.isLatest)
                }
                return RemoteAPIServer.VersionsResponseDTO(supportsVersions: true, flavorName: flavor.displayName,
                                                           currentVersion: ctx.currentVersion, isBedrock: false,
                                                           versions: entries)
            } catch {
                return RemoteAPIServer.VersionsResponseDTO(supportsVersions: true, flavorName: flavor.displayName,
                                                           currentVersion: ctx.currentVersion, isBedrock: false,
                                                           versions: [], note: "fetch_failed: \(error.localizedDescription)")
            }
        }

        // POST /components/version — download / install the chosen JAR version.
        // Java: authoritative-async (awaits the real result). Bedrock: fire-and-forget pin + download.
        let changeVersionProvider: (String, String?) async -> RemoteAPIServer.VersionChangeResultDTO = { [weak self] versionId, loaderVersion in
            guard let self else {
                return RemoteAPIServer.VersionChangeResultDTO(success: false, message: "not_available", requiresRestart: false)
            }
            typealias ChangeCtx = (isBedrock: Bool, flavor: JavaServerFlavor?, cfg: ConfigServer, isRunning: Bool, isDownloading: Bool)
            let ctx: ChangeCtx? = await MainActor.run {
                let appCfg = self.configManager.config
                guard let server = appCfg.servers.first(where: { $0.id == appCfg.activeServerId }) else { return nil }
                return (server.isBedrock, server.isBedrock ? nil : server.javaFlavor, server,
                        self.isServerRunning, self.isDownloadingJar)
            }
            guard let ctx else {
                return RemoteAPIServer.VersionChangeResultDTO(success: false, message: "no_active_server", requiresRestart: false)
            }
            if ctx.isRunning {
                return RemoteAPIServer.VersionChangeResultDTO(success: false, message: "server_running", requiresRestart: false)
            }
            if ctx.isDownloading {
                return RemoteAPIServer.VersionChangeResultDTO(success: false, message: "download_in_progress", requiresRestart: false)
            }

            let cfg = ctx.cfg

            // BEDROCK: pin the version then trigger the VM download (fire-and-forget — same as Mac UI).
            if ctx.isBedrock {
                let pinned = versionId.trimmingCharacters(in: .whitespacesAndNewlines)

                // Downgrade guard: check and backup BEFORE pinning, so we can return
                // backup_failed synchronously. updateBedrockVMFiles is called with
                // skipDowngradeCheck: true to avoid a redundant second backup.
                if pinned.uppercased() != "LATEST" {
                    let serverDir = URL(fileURLWithPath: cfg.serverDir, isDirectory: true)
                    let installed = BedrockProvisioner.installedVersion(serverDir: serverDir)
                    if MCVersionComparator.isDowngrade(from: installed, to: pinned) {
                        let ok = await self.createBackup(for: cfg, isAutomatic: true, triggerReason: "pre-downgrade")
                        if !ok {
                            return RemoteAPIServer.VersionChangeResultDTO(
                                success: false, message: "backup_failed", requiresRestart: false)
                        }
                    }
                }

                await MainActor.run {
                    self.setBedrockVersion(pinned)
                    self.updateBedrockVMFiles(cfg: cfg, skipDowngradeCheck: true)
                }
                let label = (pinned.uppercased() == "LATEST") ? "latest" : pinned
                return RemoteAPIServer.VersionChangeResultDTO(
                    success: true,
                    message: "Bedrock \(label) — download started. Restart the server to apply.",
                    requiresRestart: true)
            }

            // JAVA: authoritative-async — calls the same underlying async installers.
            guard let flavor = ctx.flavor else {
                return RemoteAPIServer.VersionChangeResultDTO(success: false, message: "not_supported", requiresRestart: false)
            }

            // Downgrade guard: extract the target MC version from versionId and compare
            // to the currently pinned version. NeoForge/Forge versionIds are "MC—Loader"
            // (em-dash); all other flavors use the MC version directly as versionId.
            let targetMCForCheck: String?
            switch flavor {
            case .neoforge, .forge:
                let mc = versionId.components(separatedBy: "\u{2014}").first ?? ""
                targetMCForCheck = (mc.isEmpty || mc == "__latest__") ? nil : mc
            default:
                targetMCForCheck = (versionId.isEmpty || versionId == "__latest__") ? nil : versionId
            }
            if let t = targetMCForCheck, MCVersionComparator.isDowngrade(from: cfg.minecraftVersion, to: t) {
                let ok = await self.createBackup(for: cfg, isAutomatic: true, triggerReason: "pre-downgrade")
                if !ok {
                    return RemoteAPIServer.VersionChangeResultDTO(
                        success: false, message: "backup_failed", requiresRestart: false)
                }
            }

            await MainActor.run { self.isDownloadingJar = true }

            let serverDir = URL(fileURLWithPath: cfg.serverDir, isDirectory: true)
            let trimmed = cfg.paperJarPath.trimmingCharacters(in: .whitespacesAndNewlines)
            let destURL = trimmed.isEmpty
                ? serverDir.appendingPathComponent("paper.jar")
                : URL(fileURLWithPath: trimmed)

            do {
                try FileManager.default.createDirectory(
                    at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            } catch {
                await MainActor.run { self.isDownloadingJar = false }
                return RemoteAPIServer.VersionChangeResultDTO(success: false,
                    message: "Could not create directory: \(error.localizedDescription)", requiresRestart: false)
            }

            do {
                let result: ServerJarDownloadResult

                switch flavor {
                case .neoforge:
                    let javaPath = await MainActor.run { self.configManager.config.javaPath }
                    let info: NeoForgeInstaller.InstallResult
                    if let nfv = loaderVersion, !nfv.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        info = try await NeoForgeInstaller.install(
                            specificVersion: nfv.trimmingCharacters(in: .whitespacesAndNewlines),
                            into: serverDir, javaPath: javaPath,
                            onLog: { line in Task { @MainActor in self.logAppMessage("[NeoForge] \(line)") } })
                    } else {
                        info = try await NeoForgeInstaller.install(
                            into: serverDir, javaPath: javaPath,
                            onLog: { line in Task { @MainActor in self.logAppMessage("[NeoForge] \(line)") } })
                    }
                    await MainActor.run {
                        if let idx = self.configManager.config.servers.firstIndex(where: { $0.id == cfg.id }) {
                            self.configManager.config.servers[idx].minecraftVersion = info.minecraftVersion
                            self.configManager.config.servers[idx].loaderVersion = info.neoForgeVersion
                            self.configManager.config.servers[idx].serverBuild = info.neoForgeVersion
                            self.configManager.save()
                        }
                        self.recordLoaderVersion(flavor: .neoforge, mc: info.minecraftVersion, loader: info.neoForgeVersion)
                    }
                    result = ServerJarDownloadResult(version: info.minecraftVersion, build: info.neoForgeVersion,
                                                     loaderVersion: info.neoForgeVersion)

                case .forge:
                    let javaPath = await MainActor.run { self.configManager.config.javaPath }
                    // id format is "MC—ForgeVersion" with an em-dash separator.
                    let parts = versionId.components(separatedBy: "—")
                    let mcVer = parts.first ?? versionId
                    let info: ForgeInstaller.InstallResult
                    if let fv = loaderVersion, !fv.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       !mcVer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, versionId != "__latest__" {
                        info = try await ForgeInstaller.install(
                            mcVersion: mcVer.trimmingCharacters(in: .whitespacesAndNewlines),
                            forgeVersion: fv.trimmingCharacters(in: .whitespacesAndNewlines),
                            into: serverDir, javaPath: javaPath,
                            onLog: { line in Task { @MainActor in self.logAppMessage("[Forge] \(line)") } })
                    } else {
                        info = try await ForgeInstaller.install(
                            into: serverDir, javaPath: javaPath,
                            onLog: { line in Task { @MainActor in self.logAppMessage("[Forge] \(line)") } })
                    }
                    await MainActor.run {
                        if let idx = self.configManager.config.servers.firstIndex(where: { $0.id == cfg.id }) {
                            self.configManager.config.servers[idx].minecraftVersion = info.minecraftVersion
                            self.configManager.config.servers[idx].loaderVersion = info.forgeVersion
                            self.configManager.config.servers[idx].serverBuild = info.forgeVersion
                            self.configManager.save()
                        }
                        self.recordLoaderVersion(flavor: .forge, mc: info.minecraftVersion, loader: info.forgeVersion)
                    }
                    result = ServerJarDownloadResult(version: info.minecraftVersion, build: info.forgeVersion,
                                                     loaderVersion: info.forgeVersion)

                case .fabric:
                    let downloadResult: ServerJarDownloadResult
                    if versionId == "__latest__" || versionId.isEmpty {
                        downloadResult = try await ServerJarProvider.downloadLatest(flavor: .fabric, to: destURL)
                    } else {
                        let entry = ServerVersionEntry(id: versionId, displayLabel: versionId,
                                                       mcVersion: versionId, loaderVersion: nil)
                        downloadResult = try await ServerJarProvider.downloadVersion(entry, flavor: .fabric, to: destURL)
                    }
                    await MainActor.run {
                        if let idx = self.configManager.config.servers.firstIndex(where: { $0.id == cfg.id }) {
                            self.configManager.config.servers[idx].minecraftVersion = downloadResult.version
                            self.configManager.config.servers[idx].loaderVersion = downloadResult.loaderVersion
                            self.configManager.save()
                        }
                    }
                    result = downloadResult

                default:
                    // Paper, Purpur, Vanilla (and any other downloadable flavor).
                    let downloadResult: ServerJarDownloadResult
                    if versionId == "__latest__" || versionId.isEmpty {
                        downloadResult = try await ServerJarProvider.downloadLatest(flavor: flavor, to: destURL)
                    } else {
                        let entry = ServerVersionEntry(id: versionId, displayLabel: versionId,
                                                       mcVersion: versionId, loaderVersion: nil)
                        downloadResult = try await ServerJarProvider.downloadVersion(entry, flavor: flavor, to: destURL)
                    }
                    if flavor == .paper, let buildInt = Int(downloadResult.build) {
                        await MainActor.run {
                            PaperVersionSidecarManager.write(mcVersion: downloadResult.version,
                                                             build: buildInt, toServerDirectory: serverDir)
                        }
                    }
                    await MainActor.run {
                        if let idx = self.configManager.config.servers.firstIndex(where: { $0.id == cfg.id }) {
                            self.configManager.config.servers[idx].minecraftVersion = downloadResult.version
                            self.configManager.save()
                        }
                    }
                    result = downloadResult
                }

                await MainActor.run {
                    self.logAppMessage("[\(flavor.displayName)] (remote) Applied \(result.version) (build \(result.build)).")
                    self.isDownloadingJar = false
                    self.refreshComponentsSnapshotLocalAndTemplate(clearOnline: false)
                }
                let loaderSuffix = result.loaderVersion.map { " (loader \($0))" } ?? ""
                return RemoteAPIServer.VersionChangeResultDTO(
                    success: true,
                    message: "Applied \(result.version)\(loaderSuffix) — restart the server to apply.",
                    requiresRestart: true)

            } catch {
                await MainActor.run {
                    self.logAppMessage("[\(flavor.displayName)] (remote) Version change failed: \(error.localizedDescription)")
                    self.isDownloadingJar = false
                }
                return RemoteAPIServer.VersionChangeResultDTO(success: false,
                    message: error.localizedDescription, requiresRestart: false)
            }
        }
        server.mutateAllowlistProvider = mutateAllowlistProvider
        server.addonsProvider = addonsProvider
        server.updateAddonProvider = updateAddonProvider
        server.removeAddonProvider = removeAddonProvider
        server.catalogSearchProvider = catalogSearchProvider
        server.installAddonProvider = installAddonProvider
        server.versionsProvider = versionsProvider
        server.changeVersionProvider = changeVersionProvider
    }
}

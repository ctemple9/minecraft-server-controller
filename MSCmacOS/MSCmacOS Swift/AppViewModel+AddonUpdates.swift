//
//  AppViewModel+AddonUpdates.swift
//  MinecraftServerController
//
//  Bridges the pure AddonUpdateResolver to the UI: resolves the update plan,
//  persists hash-detected links so associations self-heal, updates one or many
//  add-ons (dependency-aware), and lets the user manually link an unlinked file
//  to a Modrinth project. Works uniformly for plugin and mod servers.
//

import Foundation

extension AppViewModel {

    // MARK: - Resolve

    /// Builds the update plan for the given server's add-on folder and merges any
    /// hash-detected links into the persisted config.
    ///
    /// Resolve-once-with-cache: when the plan is already current for this server and
    /// `force` is false, this is a no-op — so calling it on every Components-tab appear
    /// is cheap. Pass `force: true` after a mutation or from an explicit Refresh.
    func resolveAddonUpdates(for cfg: ConfigServer, force: Bool = false) {
        guard cfg.javaFlavor.addOnKind != nil else {
            addonUpdatePlan = []
            addonPlanServerId = cfg.id
            return
        }
        if !force && addonPlanServerId == cfg.id { return }   // cached and current
        guard !isResolvingAddonUpdates else { return }
        if addonPlanServerId != cfg.id { addonUpdatePlan = [] } // drop another server's stale plan
        isResolvingAddonUpdates = true
        addonUpdateError = nil

        Task { [weak self] in
            guard let self else { return }
            let result = await AddonUpdateResolver.resolve(for: cfg)
            await MainActor.run {
                self.addonUpdatePlan = result.items
                self.addonPlanServerId = cfg.id
                self.mergeDiscoveredLinks(result.discoveredLinks, into: cfg.id)
                self.isResolvingAddonUpdates = false
            }
        }
    }

    /// Invalidates the cached plan so the next resolve recomputes. Call after any change
    /// to the installed file set (install/remove/replace).
    func invalidateAddonPlan() {
        addonPlanServerId = nil
    }

    /// Merges resolver-discovered links into the server's persisted addonLinks, only
    /// overwriting weaker/auto provenance (never clobbers a user's manual link's title).
    private func mergeDiscoveredLinks(_ links: [String: AddonLink], into serverId: String) {
        guard !links.isEmpty,
              let idx = configManager.config.servers.firstIndex(where: { $0.id == serverId }) else { return }
        var existing = configManager.config.servers[idx].addonLinks ?? [:]
        for (projectId, discovered) in links {
            if let prior = existing[projectId], prior.provenance == .userLinked {
                // Preserve the user's choice but refresh the installed-file bookkeeping.
                // Also refresh clientSide/serverSide from Modrinth (source of truth).
                var merged = prior
                merged.installedVersionId = discovered.installedVersionId
                merged.installedFileName = discovered.installedFileName
                merged.installedHash = discovered.installedHash
                merged.clientSide = discovered.clientSide ?? prior.clientSide
                merged.serverSide = discovered.serverSide ?? prior.serverSide
                existing[projectId] = merged
            } else {
                existing[projectId] = discovered
            }
        }
        configManager.config.servers[idx].addonLinks = existing
        configManager.save()
    }

    // MARK: - Update one

    /// Updates a single add-on to its latest compatible build, then refreshes + re-resolves.
    func updateAddon(_ item: AddonUpdateItem, for cfg: ConfigServer) {
        Task { [weak self] in
            guard let self else { return }
            await self.applyAddonUpdate(item, for: cfg)
            await MainActor.run {
                self.refreshDiscoveredAddons(for: cfg)
                self.resolveAddonUpdates(for: cfg, force: true)
            }
        }
    }

    // MARK: - Update many

    /// Updates a selected set of add-ons sequentially (dependency-aware), with a single
    /// refresh + re-resolve at the end. Skips items with no available update.
    func updateAddons(_ items: [AddonUpdateItem], for cfg: ConfigServer) {
        let updatable = items.filter { $0.bucket == .updateAvailable && $0.availableVersionId != nil }
        guard !updatable.isEmpty else { return }

        Task { [weak self] in
            guard let self else { return }
            var ok = 0
            for item in updatable {
                if await self.applyAddonUpdate(item, for: cfg) { ok += 1 }
            }
            await MainActor.run {
                self.logAppMessage("[Add-ons] Updated \(ok) of \(updatable.count) selected.")
                self.refreshDiscoveredAddons(for: cfg)
                self.resolveAddonUpdates(for: cfg, force: true)
            }
        }
    }

    // MARK: - Manual link

    /// Associates an unlinked installed file with a Modrinth project the user picked,
    /// then re-resolves so its update status appears.
    func manuallyLinkAddon(_ item: AddonUpdateItem, to hit: ModrinthSearchHit, for cfg: ConfigServer) {
        guard let idx = configManager.config.servers.firstIndex(where: { $0.id == cfg.id }) else { return }
        var links = configManager.config.servers[idx].addonLinks ?? [:]
        links[hit.projectId] = AddonLink(
            projectId: hit.projectId,
            slug: hit.slug,
            title: hit.title,
            provider: "modrinth",
            provenance: .userLinked,
            installedVersionId: nil,
            installedFileName: item.fileName,
            installedHash: nil,
            iconURL: hit.iconUrl,
            clientSide: hit.clientSide == "unknown" ? nil : hit.clientSide,
            serverSide: hit.serverSide == "unknown" ? nil : hit.serverSide
        )
        configManager.config.servers[idx].addonLinks = links
        configManager.save()
        logAppMessage("[Add-ons] Linked \(item.displayName) → \(hit.title) on Modrinth.")
        resolveAddonUpdates(for: cfg, force: true)
    }

    // MARK: - Core apply

    /// Downloads the item's target version, replaces the on-disk jar (preserving its
    /// enabled/disabled state), updates the persisted link, and pulls required deps.
    /// Returns true on success. Runs off the main actor for the network/file work.
    @discardableResult
    private func applyAddonUpdate(_ item: AddonUpdateItem, for cfg: ConfigServer) async -> Bool {
        guard let addOn = cfg.javaFlavor.addOnKind,
              let projectId = item.projectId,
              let versionId = item.availableVersionId else { return false }

        await MainActor.run { _ = self.updatingAddonStems.insert(item.jarStem) }
        defer { Task { @MainActor in self.updatingAddonStems.remove(item.jarStem) } }

        do {
            let version = try await ModrinthAPI.version(id: versionId)
            guard let file = version.primaryFile else {
                await MainActor.run { self.logAppMessage("[Add-ons] \(item.displayName): update has no downloadable file.") }
                return false
            }

            let folder = URL(fileURLWithPath: cfg.serverDir, isDirectory: true)
                .appendingPathComponent(addOn.folderName, isDirectory: true)
            let fm = FileManager.default
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)

            // Preserve disabled state by mirroring the suffix onto the new filename.
            let newName = item.isEnabled ? file.filename : file.filename + ".disabled"
            let dest = folder.appendingPathComponent(newName)

            try await ModrinthAPI.downloadVersionFile(version, to: dest)

            // Remove the previous jar if the filename changed (the common case on update).
            if item.fileName != newName {
                try? fm.removeItem(at: folder.appendingPathComponent(item.fileName))
            }

            let newHash = ModrinthAPI.sha512Hex(of: dest)

            await MainActor.run {
                if let idx = self.configManager.config.servers.firstIndex(where: { $0.id == cfg.id }) {
                    var links = self.configManager.config.servers[idx].addonLinks ?? [:]
                    var link = links[projectId] ?? AddonLink(
                        projectId: projectId,
                        slug: item.slug ?? projectId,
                        title: item.displayName,
                        provenance: .hashDetected
                    )
                    link.installedVersionId = version.id
                    link.installedFileName = newName
                    link.installedHash = newHash
                    links[projectId] = link
                    self.configManager.config.servers[idx].addonLinks = links
                    self.configManager.save()
                }
                self.logAppMessage("[Add-ons] Updated \(item.displayName) → \(version.versionNumber).")
            }

            // Pull any newly-required dependencies for the updated build.
            await installRequiredDependencies(of: version, into: cfg)
            return true
        } catch {
            await MainActor.run {
                self.logAppMessage("[Add-ons] Failed to update \(item.displayName): \(error.localizedDescription)")
            }
            return false
        }
    }

    /// Refreshes whichever discovered list applies to this server's add-on kind.
    private func refreshDiscoveredAddons(for cfg: ConfigServer) {
        if cfg.javaFlavor.addOnKind == .mod { refreshDiscoveredMods() }
        else { refreshDiscoveredPlugins() }
    }

    // MARK: - Startup-crash repairs

    /// Repairs an "incompatible version" startup problem by replacing the offender with
    /// the latest build compatible with the server's loader + Minecraft version. Resolves
    /// the project from the persisted link or by hashing the file, removes the old jar,
    /// and pulls any newly-required dependencies. Removes the problem on success.
    func repairIncompatibleAddon(_ problem: StartupProblem, for cfg: ConfigServer) {
        guard let addOn = cfg.javaFlavor.addOnKind,
              let currentFileName = problem.installedFile,
              !repairingProblemIds.contains(problem.id) else { return }
        repairingProblemIds.insert(problem.id)

        Task { [weak self] in
            guard let self else { return }
            let folder = URL(fileURLWithPath: cfg.serverDir, isDirectory: true)
                .appendingPathComponent(addOn.folderName, isDirectory: true)
            let currentURL = folder.appendingPathComponent(currentFileName)

            // Identify the Modrinth project: persisted link first, then a hash lookup.
            var projectId = cfg.addonLinks?.values.first { $0.installedFileName == currentFileName }?.projectId
            if projectId == nil, let hash = ModrinthAPI.sha512Hex(of: currentURL),
               let v = try? await ModrinthAPI.versionFromHash(hash) {
                projectId = v.projectId
            }
            guard let projectId else {
                await self.finishRepair(problem, ok: false, log: "[Repair] Couldn't identify \(problem.offenderName) on Modrinth.")
                return
            }

            let loaders = cfg.javaFlavor.modrinthLoaderFacets
            do {
                let versions = try await ModrinthAPI.projectVersions(
                    idOrSlug: projectId, loaders: loaders, gameVersion: cfg.minecraftVersion)
                guard let best = versions.first, let file = best.primaryFile else {
                    let mc = cfg.minecraftVersion ?? "this version"
                    await self.finishRepair(problem, ok: false,
                        log: "[Repair] No \(problem.offenderName) build for \(mc) found on Modrinth.")
                    return
                }

                let isEnabled = !currentFileName.lowercased().hasSuffix(".disabled")
                let newName = isEnabled ? file.filename : file.filename + ".disabled"
                let dest = folder.appendingPathComponent(newName)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try await ModrinthAPI.downloadVersionFile(best, to: dest)
                if currentFileName != newName {
                    try? FileManager.default.removeItem(at: currentURL)
                }
                let newHash = ModrinthAPI.sha512Hex(of: dest)

                await MainActor.run {
                    if let idx = self.configManager.config.servers.firstIndex(where: { $0.id == cfg.id }) {
                        var links = self.configManager.config.servers[idx].addonLinks ?? [:]
                        var link = links[projectId] ?? AddonLink(
                            projectId: projectId, slug: best.projectId ?? projectId,
                            title: problem.offenderName, provenance: .hashDetected)
                        link.installedVersionId = best.id
                        link.installedFileName = newName
                        link.installedHash = newHash
                        links[projectId] = link
                        self.configManager.config.servers[idx].addonLinks = links
                        self.configManager.save()
                    }
                }
                await self.installRequiredDependencies(of: best, into: cfg)
                await self.finishRepair(problem, ok: true,
                    log: "[Repair] Updated \(problem.offenderName) → \(best.versionNumber) for \(cfg.minecraftVersion ?? "server").",
                    cfg: cfg)
            } catch {
                await self.finishRepair(problem, ok: false,
                    log: "[Repair] Failed to update \(problem.offenderName): \(error.localizedDescription)")
            }
        }
    }

    /// Repairs a "missing dependency" startup problem by finding the dependency on
    /// Modrinth (filtered to the server's loader + Minecraft version) and installing it
    /// (which also pulls its own required dependencies). Removes the problem on success.
    func installMissingDependency(_ problem: StartupProblem, for cfg: ConfigServer) {
        guard let dep = problem.missingDependency,
              !repairingProblemIds.contains(problem.id) else { return }
        repairingProblemIds.insert(problem.id)

        Task { [weak self] in
            guard let self else { return }
            let loaders = cfg.javaFlavor.modrinthLoaderFacets
            let type = (cfg.javaFlavor.addOnKind == .mod) ? "mod" : "plugin"
            let forgeFamily = cfg.javaFlavor.isForgeFamily
            // A missing dependency isn't installed, so its identity can only come from the
            // alias table (c) + Modrinth search (d) — file-hash / persisted-link rungs don't apply.
            let canonical = ModrinthSlugNormalizer.canonicalSlug(for: dep, forgeFamily: forgeFamily)
            let query = ModrinthSlugNormalizer.searchQuery(for: dep, forgeFamily: forgeFamily)
            do {
                let results = try await ModrinthAPI.search(
                    query: query, loaders: loaders, gameVersion: cfg.minecraftVersion,
                    projectType: type, limit: 8)
                let norm = ModrinthSlugNormalizer.normalizedSlug(dep)
                let hit = results.hits.first { $0.slug.lowercased() == canonical }
                    ?? results.hits.first { $0.slug.lowercased() == norm }
                    ?? results.hits.first { $0.title.lowercased() == dep.lowercased() }
                    ?? results.hits.first
                guard let hit else {
                    await self.finishRepair(problem, ok: false, log: "[Repair] Couldn't find \(dep) on Modrinth.")
                    return
                }
                let outcome = await self.installModrinthAddon(hit, into: cfg)
                await self.finishRepair(problem, ok: outcome.ok, log: "[Repair] \(outcome.message)")
            } catch {
                await self.finishRepair(problem, ok: false,
                    log: "[Repair] Failed to install \(dep): \(error.localizedDescription)")
            }
        }
    }

    /// Resolves the best Modrinth identity for a startup problem's offender, for the "View
    /// on Modrinth" action. Runs the layered lookup ladder, most-authoritative first:
    ///   (a) the installed file's SHA-512 → Modrinth version → project (exact match);
    ///   (b) a persisted AddonLink for that file (the cached, hash-derived form of (a));
    ///   (c) the known-alias table (connectormod → connector, etc.), trusted as a real slug;
    ///   (d) a Modrinth search on the canonical query.
    /// Falls back to a bare canonical-slug hit (the detail view refetches by slug), so this
    /// returns nil only when there's no offender text at all.
    func startupProblemModrinthHit(for problem: StartupProblem, cfg: ConfigServer) async -> ModrinthSearchHit? {
        let forgeFamily = cfg.javaFlavor.isForgeFamily
        let projectType = (cfg.javaFlavor.addOnKind == .plugin) ? "plugin" : "mod"
        let rawOffender = problem.offenderId ?? problem.offenderName

        // (a) Installed-file hash → Modrinth version → project.
        if let file = problem.installedFile {
            let folder = (cfg.javaFlavor.addOnKind == .plugin) ? "plugins" : "mods"
            let jarURL = URL(fileURLWithPath: cfg.serverDir)
                .appendingPathComponent(folder, isDirectory: true)
                .appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: jarURL.path),
               let hash = ModrinthAPI.sha512Hex(of: jarURL),
               let version = try? await ModrinthAPI.versionFromHash(hash),
               let projectId = version.projectId {
                if let project = try? await ModrinthAPI.project(idOrSlug: projectId) {
                    return ModrinthSearchHit(
                        projectId: project.id, slug: project.slug, title: project.title,
                        description: "", author: "", downloads: 0, iconUrl: project.iconUrl,
                        clientSide: project.clientSide, serverSide: project.serverSide, projectType: projectType)
                }
                return ModrinthSearchHit(
                    projectId: projectId, slug: projectId, title: problem.offenderName,
                    description: "", author: "", downloads: 0, iconUrl: nil,
                    clientSide: "unknown", serverSide: "unknown", projectType: projectType)
            }
        }

        // (b) Persisted AddonLink (matched by file name, then by installed hash).
        if let link = cfg.addonLinks?.values.first(where: { $0.installedFileName == problem.installedFile }) {
            return ModrinthSearchHit(
                projectId: link.projectId, slug: link.slug, title: link.title,
                description: "", author: "", downloads: 0, iconUrl: link.iconURL,
                clientSide: link.clientSide ?? "unknown", serverSide: link.serverSide ?? "unknown",
                projectType: projectType)
        }

        // (c) Known alias — trust the rewritten slug directly.
        let canonical = ModrinthSlugNormalizer.canonicalSlug(for: rawOffender, forgeFamily: forgeFamily)
        if ModrinthSlugNormalizer.isKnownAlias(rawOffender, forgeFamily: forgeFamily), !canonical.isEmpty {
            return ModrinthSearchHit(
                projectId: canonical, slug: canonical, title: problem.offenderName,
                description: "", author: "", downloads: 0, iconUrl: nil,
                clientSide: "unknown", serverSide: "unknown", projectType: projectType)
        }

        // (d) Modrinth search on the canonical query.
        let loaders = cfg.javaFlavor.modrinthLoaderFacets
        let query = ModrinthSlugNormalizer.searchQuery(for: rawOffender, forgeFamily: forgeFamily)
        if let results = try? await ModrinthAPI.search(
            query: query, loaders: loaders, gameVersion: cfg.minecraftVersion,
            projectType: projectType, limit: 8) {
            let hit = results.hits.first { $0.slug.lowercased() == canonical }
                ?? results.hits.first { $0.title.lowercased() == problem.offenderName.lowercased() }
                ?? results.hits.first
            if let hit { return hit }
        }

        // Floor: a bare canonical-slug hit, so "View" always opens *something* to refine.
        guard !canonical.isEmpty else { return nil }
        return ModrinthSearchHit(
            projectId: canonical, slug: canonical, title: problem.offenderName,
            description: "", author: "", downloads: 0, iconUrl: nil,
            clientSide: "unknown", serverSide: "unknown", projectType: projectType)
    }

    /// Common completion for a repair: logs, clears the spinner, and on success drops the
    /// problem from the sheet and refreshes the add-on lists + cached plan.
    @MainActor
    private func finishRepair(_ problem: StartupProblem, ok: Bool, log: String, cfg: ConfigServer? = nil) {
        logAppMessage(log)
        repairingProblemIds.remove(problem.id)
        guard ok else { return }
        startupProblems.removeAll { $0.id == problem.id }
        invalidateAddonPlan()
        if let cfg { refreshDiscoveredAddons(for: cfg) }
    }
}

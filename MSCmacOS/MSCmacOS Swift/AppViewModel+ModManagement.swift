//
//  AppViewModel+ModManagement.swift
//  MinecraftServerController
//
//  Mod discovery (mods/ folder), enable/disable, remove, Modrinth dependency
//  resolution, and .mrpack modpack import for modded Java servers.
//

import Foundation
import AppKit
import UniformTypeIdentifiers

// MARK: - .mrpack manifest models

enum MrpackReadError: LocalizedError {
    case extractionFailed(Int32)
    case manifestAbsent
    case manifestUnreadable(Error)
    case manifestMalformed(Error)

    var errorDescription: String? {
        switch self {
        case .extractionFailed(let code): return "Extraction failed (exit \(code))."
        case .manifestAbsent: return "not a valid .mrpack (no modrinth.index.json)."
        case .manifestUnreadable(let e): return "modrinth.index.json could not be read: \(e.localizedDescription)"
        case .manifestMalformed(let e): return "modrinth.index.json could not be decoded: \(e.localizedDescription)"
        }
    }
}

struct MrpackManifest: Codable {
    let formatVersion: Int
    let game: String
    let versionId: String
    let name: String
    let summary: String?
    let dependencies: [String: String]?
    let files: [MrpackFile]
}

struct MrpackFile: Codable {
    let path: String
    let hashes: MrpackHashes
    let env: MrpackEnv?
    let downloads: [String]
    let fileSize: Int
}

struct MrpackHashes: Codable {
    let sha1: String?
    let sha512: String?
}

struct MrpackEnv: Codable {
    let client: String?
    let server: String?
}

/// Distilled view of a .mrpack manifest's `dependencies` block: the pinned Minecraft
/// version and (if present) the loader flavor + its pinned version. Used by the Add
/// Server wizard to pre-select flavor and the exact MC/loader build the pack expects.
struct MrpackMetadata {
    let manifest: MrpackManifest
    let minecraftVersion: String?
    let loaderFlavor: JavaServerFlavor?
    let loaderVersion: String?

    /// Maps `dependencies` (e.g. `{"forge":"47.4.1","minecraft":"1.20.1"}`) onto a
    /// flavor + pinned versions. Pure — safe to unit-test with a hand-built manifest.
    static func from(manifest: MrpackManifest) -> MrpackMetadata {
        let dependencies = manifest.dependencies ?? [:]
        let minecraftVersion = dependencies["minecraft"]

        // Modrinth manifest keys → our flavor. Order is the match priority.
        let loaderPairs: [(key: String, flavor: JavaServerFlavor)] = [
            ("forge", .forge),
            ("neoforge", .neoforge),
            ("fabric-loader", .fabric),
            ("quilt-loader", .quilt),
        ]
        let loader = loaderPairs.first { dependencies[$0.key] != nil }

        return MrpackMetadata(
            manifest: manifest,
            minecraftVersion: minecraftVersion,
            loaderFlavor: loader?.flavor,
            loaderVersion: loader.flatMap { dependencies[$0.key] }
        )
    }

    /// A `ServerVersionEntry` carrying the pinned MC + loader version, ready to inject
    /// into the wizard's `availableVersions` and select. Nil if no MC version is pinned.
    var versionEntry: ServerVersionEntry? {
        guard let minecraftVersion, !minecraftVersion.isEmpty else { return nil }
        guard let loaderFlavor else {
            return ServerVersionEntry(
                id: minecraftVersion,
                displayLabel: minecraftVersion,
                mcVersion: minecraftVersion,
                loaderVersion: nil,
                buildLabel: nil,
                isStable: true
            )
        }
        let buildLabel = loaderVersion.map { "\(loaderFlavor.displayName) \($0)" }
        let idSuffix = loaderVersion ?? loaderFlavor.rawValue
        return ServerVersionEntry(
            id: "\(minecraftVersion)—\(idSuffix)",
            displayLabel: minecraftVersion,
            mcVersion: minecraftVersion,
            loaderVersion: loaderVersion,
            buildLabel: buildLabel,
            isStable: true
        )
    }
}

extension AppViewModel {

    // MARK: - Mod discovery

    /// Scans the selected server's mods/ folder and rebuilds `discoveredMods`.
    /// Parses fabric.mod.json / META-INF/mods.toml from each JAR for display name + version.
    /// Falls back to filename heuristics when no manifest is found.
    func refreshDiscoveredMods() {
        guard let cfg = selectedServerConfig, cfg.isModded else {
            discoveredMods = []
            return
        }

        let modsDir = URL(fileURLWithPath: cfg.serverDir, isDirectory: true)
            .appendingPathComponent("mods", isDirectory: true)
        let fm = FileManager.default

        var jarURLs: [URL] = []
        if let contents = try? fm.contentsOfDirectory(at: modsDir, includingPropertiesForKeys: nil,
                                                       options: [.skipsHiddenFiles]) {
            jarURLs = contents.filter { url in
                let name = url.lastPathComponent.lowercased()
                return name.hasSuffix(".jar") || name.hasSuffix(".jar.disabled")
            }
        }

        // Parse metadata off the main thread — unzip subprocesses can be slow for large mod sets
        Task.detached { [weak self] in
            let entries: [ModEntry] = jarURLs.map { url in
                let filename  = url.lastPathComponent
                let isEnabled = !filename.lowercased().hasSuffix(".jar.disabled")
                let jarStem   = isEnabled
                    ? url.deletingPathExtension().lastPathComponent
                    : String(filename.dropLast(".jar.disabled".count))

                let meta        = ModJarMetadataParser.parse(jarURL: url)
                let displayName = meta?.displayName ?? PluginNameParser.extractDisplayName(from: jarStem)
                let version     = meta?.version ?? PluginNameParser.extractVersion(from: jarStem)

                return ModEntry(
                    filename: filename,
                    jarStem: jarStem,
                    displayName: displayName,
                    modId: meta?.modId,
                    version: version,
                    isEnabled: isEnabled
                )
            }
            .sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }

            await MainActor.run { self?.discoveredMods = entries }
        }
    }

    // MARK: - Enable / Disable

    /// Toggles a mod between enabled (.jar) and disabled (.jar.disabled) by renaming on disk.
    func toggleMod(jarStem: String) {
        guard let cfg = selectedServerConfig else { return }
        guard let entry = discoveredMods.first(where: { $0.jarStem == jarStem }) else { return }

        let modsDir = URL(fileURLWithPath: cfg.serverDir, isDirectory: true)
            .appendingPathComponent("mods", isDirectory: true)
        let currentURL = modsDir.appendingPathComponent(entry.filename)

        let newFilename = entry.isEnabled
            ? entry.filename + ".disabled"
            : String(entry.filename.dropLast(".disabled".count))
        let newURL = modsDir.appendingPathComponent(newFilename)

        do {
            try FileManager.default.moveItem(at: currentURL, to: newURL)
            logAppMessage("[Mods] \(entry.isEnabled ? "Disabled" : "Enabled") \(entry.displayName).")
            refreshDiscoveredMods()
        } catch {
            logAppMessage("[Mods] Failed to toggle \(entry.displayName): \(error.localizedDescription)")
        }
    }

    // MARK: - Remove

    /// Permanently deletes a mod JAR from the mods/ folder.
    func removeMod(jarStem: String) {
        guard let cfg = selectedServerConfig else { return }
        guard let entry = discoveredMods.first(where: { $0.jarStem == jarStem }) else { return }

        let modsDir = URL(fileURLWithPath: cfg.serverDir, isDirectory: true)
            .appendingPathComponent("mods", isDirectory: true)
        let url = modsDir.appendingPathComponent(entry.filename)

        do {
            try FileManager.default.removeItem(at: url)
            logAppMessage("[Mods] Removed \(entry.displayName).")
            refreshDiscoveredMods()
            invalidateAddonPlan()
        } catch {
            logAppMessage("[Mods] Failed to remove \(entry.displayName): \(error.localizedDescription)")
        }
    }

    // MARK: - Add mod from file picker

    /// Opens an NSOpenPanel for .jar files and copies the chosen file into the server's mods/ folder.
    func addModFromFilePicker() {
        guard let cfg = selectedServerConfig else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.init(filenameExtension: "jar")!]
        panel.prompt = "Add Mod"
        panel.message = "Choose a mod JAR to add to this server."

        guard panel.runModal() == .OK, let srcURL = panel.url else { return }

        let modsDir = URL(fileURLWithPath: cfg.serverDir, isDirectory: true)
            .appendingPathComponent("mods", isDirectory: true)
        let destURL = modsDir.appendingPathComponent(srcURL.lastPathComponent)

        do {
            let fm = FileManager.default
            try fm.createDirectory(at: modsDir, withIntermediateDirectories: true)
            if fm.fileExists(atPath: destURL.path) { try fm.removeItem(at: destURL) }
            try fm.copyItem(at: srcURL, to: destURL)
            logAppMessage("[Mods] Added \(srcURL.lastPathComponent) to mods folder.")
            refreshDiscoveredMods()
            invalidateAddonPlan()
        } catch {
            logAppMessage("[Mods] Failed to add mod: \(error.localizedDescription)")
        }
    }

    // MARK: - Dependency resolution

    /// Installs all required Modrinth dependencies for a given version that aren't already present.
    /// Called after the primary mod/plugin is installed.
    func installRequiredDependencies(
        of version: ModrinthVersionInfo,
        into cfg: ConfigServer,
        depth: Int = 0
    ) async {
        guard depth < 3 else { return }   // guard against dependency cycles
        let required = version.dependencies.filter { $0.dependencyType == "required" }
        guard !required.isEmpty else { return }

        guard let addOn = cfg.javaFlavor.addOnKind else { return }
        let loaders = cfg.javaFlavor.modrinthLoaderFacets
        let mcVersion = cfg.minecraftVersion

        let folder = URL(fileURLWithPath: cfg.serverDir, isDirectory: true)
            .appendingPathComponent(addOn.folderName, isDirectory: true)

        // Snapshot currently installed mod IDs for quick "already have it?" checks
        let installedModIds = await MainActor.run { discoveredMods.compactMap { $0.modId } }

        for dep in required {
            guard let projectId = dep.projectId else { continue }
            do {
                let project = try await ModrinthAPI.project(idOrSlug: projectId)

                // Skip if already installed by mod ID match (fabric.mod.json / mods.toml)
                if installedModIds.contains(project.slug) { continue }

                // Skip if a file whose name contains the project slug is already present
                let filesOnDisk = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
                let alreadyPresent = filesOnDisk.contains { $0.lowercased().contains(project.slug.lowercased()) }
                if alreadyPresent { continue }

                let versions = try await ModrinthAPI.projectVersions(
                    idOrSlug: project.slug, loaders: loaders, gameVersion: mcVersion)
                guard let best = versions.first, let file = best.primaryFile else {
                    logAppMessage("[Modrinth] No compatible version of dependency \(project.title) found.")
                    continue
                }

                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let dest = folder.appendingPathComponent(file.filename)
                try await ModrinthAPI.downloadVersionFile(best, to: dest)
                logAppMessage("[Modrinth] Auto-installed dependency: \(project.title) \(best.versionNumber)")

                // Recurse for transitive required dependencies
                await installRequiredDependencies(of: best, into: cfg, depth: depth + 1)
            } catch {
                logAppMessage("[Modrinth] Could not auto-install dependency \(projectId): \(error.localizedDescription)")
            }
        }

        // Refresh the mod list after resolving all deps at this level
        if addOn == .mod {
            await MainActor.run { refreshDiscoveredMods() }
        } else {
            await MainActor.run { refreshDiscoveredPlugins() }
        }
    }

    // MARK: - .mrpack modpack import

    /// Extracts a .mrpack archive via ditto and decodes modrinth.index.json.
    /// Exposed as a static testable seam — importModpack uses its own temp dir because
    /// it also needs the overrides/ tree, but this covers manifest-only reads (P7.2 wizard).
    static func readMrpackManifest(from mrpackURL: URL) throws -> MrpackManifest {
        let fm = FileManager.default
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("msc_mrpack_meta_\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", mrpackURL.path, tempDir.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError  = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit() } catch {
            throw MrpackReadError.extractionFailed(-1)
        }
        guard p.terminationStatus == 0 else {
            throw MrpackReadError.extractionFailed(p.terminationStatus)
        }

        let manifestURL = tempDir.appendingPathComponent("modrinth.index.json")
        guard fm.fileExists(atPath: manifestURL.path) else {
            throw MrpackReadError.manifestAbsent
        }
        let data: Data
        do { data = try Data(contentsOf: manifestURL) }
        catch { throw MrpackReadError.manifestUnreadable(error) }
        do { return try JSONDecoder().decode(MrpackManifest.self, from: data) }
        catch { throw MrpackReadError.manifestMalformed(error) }
    }

    /// Reads a .mrpack and distills its `dependencies` block into `MrpackMetadata`
    /// (pinned MC + loader flavor/version) for the Add Server wizard.
    static func readMrpackMetadata(from mrpackURL: URL) throws -> MrpackMetadata {
        MrpackMetadata.from(manifest: try readMrpackManifest(from: mrpackURL))
    }

    /// Imports a Modrinth modpack (.mrpack) into the given server.
    /// Downloads all server-compatible files from the manifest, then copies
    /// the overrides/ and server-overrides/ trees into the server directory.
    func importModpack(from mrpackURL: URL, for cfg: ConfigServer) async {
        let serverDir = URL(fileURLWithPath: cfg.serverDir, isDirectory: true)
        let fm = FileManager.default

        await MainActor.run {
            logAppMessage("[Modpack] Importing \(mrpackURL.lastPathComponent)…")
        }

        // Extract .mrpack (it's a zip) into a temp directory
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("msc_mrpack_\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: tempDir) }

        do { try fm.createDirectory(at: tempDir, withIntermediateDirectories: true) }
        catch {
            await MainActor.run { logAppMessage("[Modpack] Could not create temp dir: \(error.localizedDescription)") }
            return
        }

        // Use ditto (-x -k) instead of unzip: ditto preserves Mac metadata and does not
        // extract entries with mode 000 (a known /usr/bin/unzip quirk that made some packs
        // appear invalid because modrinth.index.json was unreadable after extraction).
        let extract = Process()
        extract.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        extract.arguments = ["-x", "-k", mrpackURL.path, tempDir.path]
        extract.standardOutput = FileHandle.nullDevice
        extract.standardError  = FileHandle.nullDevice
        do { try extract.run(); extract.waitUntilExit() }
        catch {
            await MainActor.run { logAppMessage("[Modpack] Extraction failed: \(error.localizedDescription)") }
            return
        }
        guard extract.terminationStatus == 0 else {
            await MainActor.run { logAppMessage("[Modpack] Extraction failed (exit \(extract.terminationStatus)).") }
            return
        }

        // Parse modrinth.index.json — distinguish absent vs present-but-unreadable vs malformed.
        let manifestURL = tempDir.appendingPathComponent("modrinth.index.json")
        guard fm.fileExists(atPath: manifestURL.path) else {
            await MainActor.run { logAppMessage("[Modpack] not a valid .mrpack (no modrinth.index.json).") }
            return
        }
        let manifestData: Data
        do { manifestData = try Data(contentsOf: manifestURL) }
        catch {
            await MainActor.run { logAppMessage("[Modpack] modrinth.index.json could not be read: \(error.localizedDescription)") }
            return
        }
        let manifest: MrpackManifest
        do { manifest = try JSONDecoder().decode(MrpackManifest.self, from: manifestData) }
        catch {
            await MainActor.run { logAppMessage("[Modpack] Manifest parse error: \(error.localizedDescription)") }
            return
        }

        await MainActor.run {
            logAppMessage("[Modpack] \"\(manifest.name)\" v\(manifest.versionId) — starting download…")
            // Persist pack provenance now so the add-on update guard can check it.
            if let idx = configManager.config.servers.firstIndex(where: { $0.id == cfg.id }) {
                configManager.config.servers[idx].packManaged = true
                configManager.config.servers[idx].packName    = manifest.name
                configManager.config.servers[idx].packVersion = manifest.versionId
                configManager.save()
            }
        }

        // Tier 1: honor the manifest's own env — files marked server=unsupported are
        // client-only and are never downloaded.
        let serverFiles = manifest.files.filter {
            !ModpackClientOnlyClassifier.isManifestServerUnsupported($0.env)
        }
        let skipped = manifest.files.count - serverFiles.count

        await MainActor.run {
            logAppMessage("[Modpack] \(serverFiles.count) files to download, \(skipped) client-only skipped.")
        }

        // Tier 2: batch-fetch Modrinth side metadata for every downloadable project so we
        // can catch client-only mods the manifest wrongly marks server-required (BMC4).
        let projectsById = await fetchMrpackProjectMetadata(for: serverFiles)

        var downloaded = 0
        var failed: [String] = []
        // filename → disable reason, for a single summary log at the end.
        var disabledClientOnly: [(name: String, reason: String)] = []
        // Jars we placed from the manifest, so the override sweep can skip re-checking them.
        var manifestJarFilenames: Set<String> = []

        for file in serverFiles {
            let destURL = serverDir.appendingPathComponent(file.path)
            try? fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            if ModpackClientOnlyClassifier.isModsJar(path: file.path) {
                manifestJarFilenames.insert(destURL.lastPathComponent)
            }

            // Never re-download over an existing .jar.disabled (a prior import already
            // pruned this mod) — leave it disabled and count it as present.
            let disabledURL = ModpackClientOnlyClassifier.disabledURL(forActiveJar: destURL)
            if fm.fileExists(atPath: disabledURL.path) { downloaded += 1; continue }

            // Skip if already present, but still (re)classify it.
            if fm.fileExists(atPath: destURL.path) {
                downloaded += 1
                classifyAndDisableManifestJar(file: file, jarURL: destURL, projectsById: projectsById,
                                              fm: fm, into: &disabledClientOnly)
                continue
            }

            var ok = false
            for urlStr in file.downloads {
                guard let url = URL(string: urlStr) else { continue }
                do {
                    let (data, _) = try await MSCHTTP.get(url)
                    try data.write(to: destURL)
                    ok = true
                    break
                } catch { continue }
            }
            if ok {
                downloaded += 1
                classifyAndDisableManifestJar(file: file, jarURL: destURL, projectsById: projectsById,
                                              fm: fm, into: &disabledClientOnly)
            } else {
                failed.append(file.path)
            }
        }

        // Copy overrides/ and server-overrides/ into the server dir
        for folderName in ["overrides", "server-overrides"] {
            let src = tempDir.appendingPathComponent(folderName, isDirectory: true)
            guard fm.fileExists(atPath: src.path) else { continue }
            let mergeFailures = mergeDirectory(from: src, into: serverDir, fm: fm)
            await MainActor.run {
                if mergeFailures == 0 {
                    logAppMessage("[Modpack] Copied \(folderName)/.")
                } else {
                    logAppMessage("[Modpack] Copied \(folderName)/ with \(mergeFailures) file(s) that failed to copy.")
                }
            }
        }

        // Tiers 2–3 for override-provided jars (they aren't in the manifest, so their
        // Modrinth project is resolved by file hash; jar metadata is the offline fallback).
        let overrideDisabled = await disableClientOnlyOverrideJars(
            in: serverDir, skipping: manifestJarFilenames, fm: fm
        )
        disabledClientOnly.append(contentsOf: overrideDisabled)

        await MainActor.run {
            if !disabledClientOnly.isEmpty {
                let names = disabledClientOnly.map { $0.name }
                let preview = names.prefix(8).joined(separator: ", ")
                let suffix = names.count > 8 ? ", +\(names.count - 8) more" : ""
                logAppMessage("[Modpack] Disabled \(names.count) client-only mod(s) for server use: \(preview)\(suffix)")
            }
            if failed.isEmpty {
                logAppMessage("[Modpack] Done — \(downloaded) files installed.")
            } else {
                logAppMessage("[Modpack] Done — \(downloaded) installed, \(failed.count) failed: \(failed.joined(separator: ", "))")
            }
            refreshDiscoveredMods()
        }
    }

    // MARK: - Client-only mod pruning (P7.4)

    /// Batch-fetches Modrinth project metadata (for `server_side`) for every downloadable
    /// mod jar, keyed by project ID. Degrades gracefully: a failed chunk is logged and simply
    /// absent from the result, so classification falls back to Tier 3 (jar metadata).
    private func fetchMrpackProjectMetadata(for files: [MrpackFile]) async -> [String: ModrinthProject] {
        let ids = Array(Set(files.compactMap {
            ModpackClientOnlyClassifier.modrinthProjectId(fromDownloadURLs: $0.downloads)
        })).sorted()
        guard !ids.isEmpty else { return [:] }

        var byId: [String: ModrinthProject] = [:]
        var i = 0
        while i < ids.count {
            let end = min(i + 100, ids.count)   // Modrinth caps batch project lookups
            let chunk = Array(ids[i..<end])
            do {
                for project in try await ModrinthAPI.projects(ids: chunk) { byId[project.id] = project }
            } catch {
                await MainActor.run {
                    logAppMessage("[Modpack] Could not verify server support for \(chunk.count) project(s) (offline?); using embedded jar metadata instead.")
                }
            }
            i = end
        }
        return byId
    }

    /// Classifies a just-installed manifest jar (Tier 2 via its Modrinth project, Tier 3 via
    /// embedded jar metadata) and disables it if client-only. No-op for non-mods/ files.
    private func classifyAndDisableManifestJar(
        file: MrpackFile,
        jarURL: URL,
        projectsById: [String: ModrinthProject],
        fm: FileManager,
        into disabled: inout [(name: String, reason: String)]
    ) {
        guard ModpackClientOnlyClassifier.isModsJar(path: file.path) else { return }
        let project = ModpackClientOnlyClassifier.modrinthProjectId(fromDownloadURLs: file.downloads)
            .flatMap { projectsById[$0] }
        let jarEnv = ModJarMetadataParser.parse(jarURL: jarURL)?.environment
        guard let reason = ModpackClientOnlyClassifier.clientOnlyReason(
            modrinthServerSide: project?.serverSide,
            modrinthProjectTitle: project?.title,
            jarEnvironment: jarEnv
        ) else { return }
        if let name = ModpackClientOnlyClassifier.disableJar(at: jarURL, fm: fm) {
            disabled.append((name, reason))
        }
    }

    /// Scans active jars in mods/ that came from overrides/ (not the manifest) and disables
    /// the client-only ones. Tier 2: identify each by SHA-512 → Modrinth project → `server_side`.
    /// Tier 3 fallback: embedded `fabric.mod.json` `environment=client`. A failed hash lookup
    /// (offline) is logged and degrades to Tier 3 — it never blocks the import.
    private func disableClientOnlyOverrideJars(
        in serverDir: URL,
        skipping manifestJarFilenames: Set<String>,
        fm: FileManager
    ) async -> [(name: String, reason: String)] {
        let modsDir = serverDir.appendingPathComponent("mods", isDirectory: true)
        guard let entries = try? fm.contentsOfDirectory(
            at: modsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }

        let overrideJars = entries.filter {
            $0.pathExtension.lowercased() == "jar" && !manifestJarFilenames.contains($0.lastPathComponent)
        }
        guard !overrideJars.isEmpty else { return [] }

        // Tier 2: hash → Modrinth version → project id → project (server_side).
        var projectIdByHash: [String: String] = [:]
        var hashByJar: [URL: String] = [:]
        for jar in overrideJars {
            if let hash = ModrinthAPI.sha512Hex(of: jar) { hashByJar[jar] = hash }
        }
        var projectsById: [String: ModrinthProject] = [:]
        if !hashByJar.isEmpty {
            do {
                let versions = try await ModrinthAPI.versionsFromHashes(Array(hashByJar.values))
                for (hash, version) in versions { if let pid = version.projectId { projectIdByHash[hash] = pid } }
                let ids = Array(Set(projectIdByHash.values)).sorted()
                if !ids.isEmpty {
                    for project in try await ModrinthAPI.projects(ids: ids) { projectsById[project.id] = project }
                }
            } catch {
                await MainActor.run {
                    logAppMessage("[Modpack] Could not verify override mods against Modrinth (offline?); using embedded jar metadata instead.")
                }
            }
        }

        var disabled: [(name: String, reason: String)] = []
        for jar in overrideJars {
            let project = hashByJar[jar].flatMap { projectIdByHash[$0] }.flatMap { projectsById[$0] }
            let jarEnv = ModJarMetadataParser.parse(jarURL: jar)?.environment
            guard let reason = ModpackClientOnlyClassifier.clientOnlyReason(
                modrinthServerSide: project?.serverSide,
                modrinthProjectTitle: project?.title,
                jarEnvironment: jarEnv
            ) else { continue }
            if let name = ModpackClientOnlyClassifier.disableJar(at: jar, fm: fm) {
                disabled.append((name, reason))
            }
        }
        return disabled
    }

    /// Recursively copies all contents of `src` into `dst`, overwriting existing files.
    /// Returns the number of items that failed to copy (0 = fully succeeded).
    @discardableResult
    private func mergeDirectory(from src: URL, into dst: URL, fm: FileManager) -> Int {
        guard let items = try? fm.contentsOfDirectory(
            at: src, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
        ) else { return 0 }
        var failures = 0
        for item in items {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            let dest = dst.appendingPathComponent(item.lastPathComponent)
            if isDir {
                do {
                    try fm.createDirectory(at: dest, withIntermediateDirectories: true)
                    failures += mergeDirectory(from: item, into: dest, fm: fm)
                } catch {
                    failures += 1
                }
            } else {
                try? fm.removeItem(at: dest)
                do {
                    try fm.copyItem(at: item, to: dest)
                } catch {
                    failures += 1
                }
            }
        }
        return failures
    }
}

//
//  AddonUpdateResolver.swift
//  MinecraftServerController
//
//  Turns "what's installed in plugins/ or mods/" into "what should I update to."
//  Identity is established by exact file hash against Modrinth (precise, no guessing),
//  falling back to filename/manifest metadata for files Modrinth doesn't host. The
//  whole "latest compatible build" computation is delegated to Modrinth's batch
//  /version_files/update endpoint so a folder of 30 add-ons costs one request.
//
//  Pure service: no AppViewModel dependency. The view model wraps it, persists the
//  hash-detected links it returns, and performs the actual downloads.
//

import Foundation

// MARK: - Result types

/// Which section an installed add-on falls into in the update UI.
enum AddonUpdateBucket {
    case updateAvailable      // linked to Modrinth, a newer compatible build exists
    case noCompatibleVersion  // linked, but nothing built for the selected MC version
    case upToDate             // linked, already on the latest compatible build
    case unlinked             // couldn't be matched to a Modrinth project
}

/// One installed add-on with its resolved update status.
struct AddonUpdateItem: Identifiable, Equatable {
    var id: String { jarStem }

    let jarStem: String
    let fileName: String
    let displayName: String
    let isEnabled: Bool

    // Modrinth association (nil for unlinked items).
    let projectId: String?
    let slug: String?
    let description: String?
    let iconURL: String?

    let currentVersion: String?
    let currentVersionId: String?

    // The latest compatible build, when one is available and newer than installed.
    let availableVersion: String?
    let availableVersionId: String?

    let bucket: AddonUpdateBucket
    let provenance: AddonLinkProvenance?

    /// A best-effort name guess for unlinked items (from manifest/filename), used to
    /// pre-fill a manual "Link…" search. Nil when nothing useful could be derived.
    let nameGuess: String?
}

extension AddonUpdateItem {
    /// Synthesizes a search-hit stand-in so a linked item can open the existing
    /// `ModrinthProjectDetailView` (which refetches full detail by slug). Returns nil
    /// for unlinked items. `projectType` is "mod" or "plugin".
    func modrinthHit(projectType: String) -> ModrinthSearchHit? {
        guard let projectId else { return nil }
        return ModrinthSearchHit(
            projectId: projectId,
            slug: slug ?? projectId,
            title: displayName,
            description: description ?? "",
            author: "",
            downloads: 0,
            iconUrl: iconURL,
            clientSide: "unknown",
            serverSide: "unknown",
            projectType: projectType
        )
    }
}

/// Full output of a resolve pass.
struct AddonResolveResult {
    var items: [AddonUpdateItem] = []
    /// Links discovered by exact hash this pass, keyed by projectId. The caller should
    /// merge these into ConfigServer.addonLinks so associations self-heal over time.
    var discoveredLinks: [String: AddonLink] = [:]
}

// MARK: - Resolver

enum AddonUpdateResolver {

    /// Internal per-file working record.
    private struct DiskFile {
        let url: URL
        let fileName: String
        let jarStem: String
        let isEnabled: Bool
        var sha512: String?

        /// Filename-derived display name, used when no project metadata is available.
        var displayNameFallback: String { PluginNameParser.extractDisplayName(from: jarStem) }
    }

    /// Resolves the full update plan for a server's add-on folder. Safe to call off the
    /// main thread; performs file hashing + network I/O.
    static func resolve(for cfg: ConfigServer) async -> AddonResolveResult {
        guard let addOn = cfg.javaFlavor.addOnKind else { return AddonResolveResult() }

        let folder = URL(fileURLWithPath: cfg.serverDir, isDirectory: true)
            .appendingPathComponent(addOn.folderName, isDirectory: true)
        let fm = FileManager.default

        // 1. Enumerate jars (enabled + disabled).
        let urls: [URL] = ((try? fm.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
            .filter {
                let n = $0.lastPathComponent.lowercased()
                return n.hasSuffix(".jar") || n.hasSuffix(".jar.disabled")
            }
        guard !urls.isEmpty else { return AddonResolveResult() }

        var files: [DiskFile] = urls.map { url in
            let filename  = url.lastPathComponent
            let isEnabled = !filename.lowercased().hasSuffix(".jar.disabled")
            let jarStem   = isEnabled
                ? url.deletingPathExtension().lastPathComponent
                : String(filename.dropLast(".jar.disabled".count))
            return DiskFile(url: url, fileName: filename, jarStem: jarStem, isEnabled: isEnabled, sha512: nil)
        }

        // On plugin servers, exclude Geyser/Floodgate: MSC installs them from GeyserMC's
        // CDN (not Modrinth) and updates them through a dedicated path, so hash-resolving
        // them here would be unreliable and inconsistent. (Mod servers keep them — their
        // Fabric/NeoForge builds have no dedicated updater.)
        if addOn == .plugin {
            files = files.filter { f in
                let s = f.jarStem.lowercased()
                return !s.contains("geyser") && !s.contains("floodgate")
            }
        }
        guard !files.isEmpty else { return AddonResolveResult() }

        // 2. Hash every file (streaming SHA-512).
        for i in files.indices {
            files[i].sha512 = ModrinthAPI.sha512Hex(of: files[i].url)
        }
        let hashes = files.compactMap { $0.sha512 }

        // 3. Identify by hash (exact) + ask for the latest compatible build, both batched.
        let loaders   = cfg.javaFlavor.modrinthLoaderFacets
        let gameVers  = cfg.minecraftVersion.map { [$0] } ?? []

        var identified: [String: ModrinthVersionInfo] = [:]   // hash -> installed version
        var latest: [String: ModrinthVersionInfo] = [:]       // hash -> latest compatible version
        if !hashes.isEmpty {
            async let idTask     = (try? ModrinthAPI.versionsFromHashes(hashes)) ?? [:]
            async let latestTask = (try? ModrinthAPI.latestVersionsForHashes(hashes, loaders: loaders, gameVersions: gameVers)) ?? [:]
            identified = await idTask
            latest     = await latestTask
        }

        // 4. Resolve project metadata (title/description/icon) for everything identified,
        //    plus any already-persisted links, in one bulk call.
        var projectIds = Set(identified.values.compactMap { $0.projectId })
        if let existing = cfg.addonLinks { projectIds.formUnion(existing.keys) }
        var projectsById: [String: ModrinthProject] = [:]
        if !projectIds.isEmpty,
           let fetched = try? await ModrinthAPI.projects(ids: Array(projectIds)) {
            for p in fetched { projectsById[p.id] = p }
        }

        // 5. Build one item per file.
        var result = AddonResolveResult()
        for file in files {
            let hash = file.sha512
            let idVersion = hash.flatMap { identified[$0] }
            let projectId = idVersion?.projectId
                ?? hash.flatMap { h in cfg.addonLinks?.values.first(where: { $0.installedHash == h })?.projectId }
                ?? cfg.addonLinks?.values.first(where: { $0.installedFileName == file.fileName })?.projectId

            if let projectId {
                let project = projectsById[projectId]
                let link = cfg.addonLinks?[projectId]
                let provenance: AddonLinkProvenance = idVersion != nil ? .hashDetected : (link?.provenance ?? .userLinked)

                // Record a self-healing link for hash-detected matches.
                if let idVersion, idVersion.projectId == projectId {
                    result.discoveredLinks[projectId] = AddonLink(
                        projectId: projectId,
                        slug: project?.slug ?? link?.slug ?? projectId,
                        title: project?.title ?? link?.title ?? file.displayNameFallback,
                        provider: "modrinth",
                        provenance: .hashDetected,
                        installedVersionId: idVersion.id,
                        installedFileName: file.fileName,
                        installedHash: hash,
                        iconURL: project?.iconUrl ?? link?.iconURL,
                        clientSide: project?.clientSide,
                        serverSide: project?.serverSide
                    )
                }

                // Human-readable installed version: prefer the Modrinth version number
                // (consistent scheme with the available build), fall back to filename.
                // Never the raw version ID (it's an opaque hash).
                let currentVersion = cleanVersionLabel(
                    idVersion?.versionNumber ?? PluginNameParser.extractVersion(from: file.jarStem))
                let latestVersion = hash.flatMap { latest[$0] }

                let bucket: AddonUpdateBucket
                let availVer: String?
                let availVerId: String?
                if let latestVersion {
                    let isNewer = latestVersion.id != (idVersion?.id ?? link?.installedVersionId)
                    if isNewer {
                        bucket = .updateAvailable
                        availVer = cleanVersionLabel(latestVersion.versionNumber)
                        availVerId = latestVersion.id
                    } else {
                        bucket = .upToDate
                        availVer = nil
                        availVerId = nil
                    }
                } else if cfg.minecraftVersion != nil {
                    // Known project, but no build matching the selected MC version.
                    bucket = .noCompatibleVersion
                    availVer = nil
                    availVerId = nil
                } else {
                    bucket = .upToDate
                    availVer = nil
                    availVerId = nil
                }

                result.items.append(AddonUpdateItem(
                    jarStem: file.jarStem,
                    fileName: file.fileName,
                    displayName: project?.title ?? link?.title ?? file.displayNameFallback,
                    isEnabled: file.isEnabled,
                    projectId: projectId,
                    slug: project?.slug ?? link?.slug,
                    description: project?.description,
                    iconURL: project?.iconUrl ?? link?.iconURL,
                    currentVersion: currentVersion,
                    currentVersionId: idVersion?.id ?? link?.installedVersionId,
                    availableVersion: availVer,
                    availableVersionId: availVerId,
                    bucket: bucket,
                    provenance: provenance,
                    nameGuess: nil
                ))
            } else {
                // Unlinked: derive a best-effort name for a manual link search.
                let meta = ModJarMetadataParser.parseAny(jarURL: file.url)
                let guess = meta?.displayName ?? PluginNameParser.extractDisplayName(from: file.jarStem)
                result.items.append(AddonUpdateItem(
                    jarStem: file.jarStem,
                    fileName: file.fileName,
                    displayName: guess,
                    isEnabled: file.isEnabled,
                    projectId: nil,
                    slug: nil,
                    description: nil,
                    iconURL: nil,
                    currentVersion: meta?.version ?? PluginNameParser.extractVersion(from: file.jarStem),
                    currentVersionId: nil,
                    availableVersion: nil,
                    availableVersionId: nil,
                    bucket: .unlinked,
                    provenance: nil,
                    nameGuess: guess
                ))
            }
        }

        // Stable display order: updates first, then no-compat, up-to-date, unlinked; A→Z within.
        result.items.sort { a, b in
            if a.bucket.sortRank != b.bucket.sortRank { return a.bucket.sortRank < b.bucket.sortRank }
            return a.displayName.lowercased() < b.displayName.lowercased()
        }
        return result
    }
}

private extension AddonUpdateBucket {
    var sortRank: Int {
        switch self {
        case .updateAvailable:     return 0
        case .noCompatibleVersion: return 1
        case .upToDate:            return 2
        case .unlinked:            return 3
        }
    }
}

/// Strips a leading loader prefix from a Modrinth version number so plugin/mod
/// versions read consistently (e.g. "bukkit-2.6.20" → "2.6.20", "paper-1.21" → "1.21").
/// Only strips when what remains looks like a version, so project names aren't mangled.
private func cleanVersionLabel(_ raw: String?) -> String? {
    guard let s = raw?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
    let loaders = ["bukkit", "spigot", "paper", "purpur", "folia", "fabric",
                   "forge", "neoforge", "quilt", "velocity", "bungeecord", "waterfall"]
    let lower = s.lowercased()
    for l in loaders {
        let prefix = l + "-"
        guard lower.hasPrefix(prefix) else { continue }
        let rest = String(s.dropFirst(prefix.count))
        if let f = rest.first, f.isNumber || (f == "v" && rest.dropFirst().first?.isNumber == true) {
            return rest
        }
        break
    }
    return s
}


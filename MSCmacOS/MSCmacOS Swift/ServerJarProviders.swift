//
//  ServerJarProviders.swift
//  MinecraftServerController
//
//  M2 foundation: flavor-aware server-jar acquisition. `ServerJarProvider`
//  dispatches "download the latest jar for this flavor" to the right source.
//  Paper keeps using PaperDownloader; Purpur and Vanilla have their own clean
//  official APIs here. Pufferfish (messy CI) and the modded loaders land later.
//

import Foundation

// MARK: - Version entry (shared by version picker sheet and create flow)

/// One item in the version picker. For simple flavors the label is just the
/// MC version ("1.21.4"). For Forge/NeoForge it is a pre-paired string
/// ("1.20.1 — Forge 47.3.0") because those two versions are inseparable.
struct ServerVersionEntry: Identifiable, Equatable, Hashable {
    let id: String             // unique key
    let displayLabel: String   // primary label shown in picker
    let mcVersion: String      // used for mod-compatibility checks
    let loaderVersion: String? // non-nil for Forge/NeoForge entries
    var buildLabel: String? = nil   // secondary grey text, e.g. "build 132" or "loader 0.16.9"
    var isStable: Bool = true       // false for rc/pre/snapshot/experimental

    static let latest = ServerVersionEntry(
        id: "__latest__",
        displayLabel: "Latest (recommended)",
        mcVersion: "",
        loaderVersion: nil,
        buildLabel: nil,
        isStable: true
    )
    var isLatest: Bool { id == "__latest__" }
}

// MARK: - Shared result / errors

/// Result of acquiring a server jar: the Minecraft version and a build label
/// (a build number for Paper/Purpur, "release" for Vanilla), plus an optional
/// loader version for modded flavors (Fabric loader / NeoForge version).
struct ServerJarDownloadResult {
    let version: String
    let build: String
    var loaderVersion: String? = nil
}

enum ServerJarProviderError: LocalizedError {
    case unsupportedFlavor(JavaServerFlavor)
    case networkError(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFlavor(let f): return "Downloading \(f.displayName) servers isn't supported yet."
        case .networkError(let m):      return "Network error: \(m)"
        case .invalidResponse(let m):   return "Unexpected response: \(m)"
        }
    }
}

// MARK: - Dispatcher

enum ServerJarProvider {

    /// Returns a list of available versions for the version picker, newest first.
    /// For Forge/NeoForge, delegates to NeoForgeInstaller / ForgeInstaller.
    static func listVersions(for flavor: JavaServerFlavor) async throws -> [ServerVersionEntry] {
        switch flavor {
        case .paper:      return try await PaperDownloader.listVersions()
        case .purpur:     return try await PurpurDownloader.listVersions()
        case .vanilla:    return try await VanillaDownloader.listVersions()
        case .fabric:     return try await FabricDownloader.listVersions()
        case .neoforge:   return try await NeoForgeInstaller.listVersionPairs()
        case .forge:      return try await ForgeInstaller.listVersionPairs()
        default:          return []   // pufferfish / spigot / quilt: latest only
        }
    }

    /// Downloads a specific version to `destination`. Only for downloadAndGo flavors;
    /// Forge/NeoForge use their own installers (pass entry to createNewServer instead).
    static func downloadVersion(
        _ entry: ServerVersionEntry,
        flavor: JavaServerFlavor,
        to destination: URL
    ) async throws -> ServerJarDownloadResult {
        switch flavor {
        case .paper:   return try await PaperDownloader.downloadVersion(entry.mcVersion, to: destination)
        case .purpur:  return try await PurpurDownloader.downloadVersion(entry.mcVersion, to: destination)
        case .vanilla: return try await VanillaDownloader.downloadVersion(entry.mcVersion, to: destination)
        case .fabric:  return try await FabricDownloader.downloadVersion(entry.mcVersion, to: destination)
        default:       throw ServerJarProviderError.unsupportedFlavor(flavor)
        }
    }

    /// Downloads the latest stable server jar for `flavor` to `destination`.
    /// Returns the resolved version + build label for persistence/logging.
    static func downloadLatest(
        flavor: JavaServerFlavor,
        to destination: URL
    ) async throws -> ServerJarDownloadResult {
        switch flavor {
        case .paper:
            let r = try await PaperDownloader.downloadLatestPaper(to: destination)
            return ServerJarDownloadResult(version: r.version, build: String(r.build))
        case .purpur:
            return try await PurpurDownloader.downloadLatest(to: destination)
        case .vanilla:
            return try await VanillaDownloader.downloadLatest(to: destination)
        case .fabric:
            return try await FabricDownloader.downloadLatest(to: destination)
        case .pufferfish:
            return try await PufferfishDownloader.downloadLatest(to: destination)
        default:
            throw ServerJarProviderError.unsupportedFlavor(flavor)
        }
    }
}

// MARK: - Version compare (numeric, highest-first)

/// Compares Minecraft version strings numerically ("1.21.4" > "1.21" > "1.20.6").
private func compareMCVersions(_ a: String, _ b: String) -> ComparisonResult {
    let ap = a.split(separator: ".").compactMap { Int($0) }
    let bp = b.split(separator: ".").compactMap { Int($0) }
    for i in 0..<max(ap.count, bp.count) {
        let av = i < ap.count ? ap[i] : 0
        let bv = i < bp.count ? bp[i] : 0
        if av != bv { return av < bv ? .orderedAscending : .orderedDescending }
    }
    return .orderedSame
}

// MARK: - Paper (fill.papermc.io v3 — same endpoint as Components tab)

extension PaperDownloader {

    /// Returns all Paper versions for the create-server version picker, newest first.
    /// Uses the v3 API (`fill.papermc.io`) so build numbers and version names (including
    /// the new 26.x.x scheme) match exactly what the Components tab shows.
    static func listVersions() async throws -> [ServerVersionEntry] {
        let url = URL(string: "https://fill.papermc.io/v3/projects/paper")!
        let (data, resp) = try await MSCHTTP.get(url)
        try ensureOK(resp, "Paper project v3")
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ServerJarProviderError.invalidResponse("Paper v3 project JSON malformed.")
        }

        var allVersions: [String] = []
        if let byGroup = root["versions"] as? [String: Any] {
            for (_, listAny) in byGroup {
                if let list = listAny as? [Any] {
                    allVersions.append(contentsOf: list.compactMap { $0 as? String })
                }
            }
        } else if let flat = root["versions"] as? [Any] {
            allVersions = flat.compactMap { $0 as? String }
        }
        guard !allVersions.isEmpty else {
            throw ServerJarProviderError.invalidResponse("Paper v3 versions list empty.")
        }

        let sorted = allVersions.sorted { compareMCVersions($0, $1) == .orderedDescending }

        return await withTaskGroup(of: ServerVersionEntry.self) { group in
            for v in sorted { group.addTask { await paperVersionEntryV3(v) } }
            var results: [String: ServerVersionEntry] = [:]
            for await entry in group {
                // Drop versions with no recognized builds (ancient RCs etc.)
                if entry.buildLabel != nil { results[entry.id] = entry }
            }
            return sorted.compactMap { results[$0] }
        }
    }

    /// Fetches the best build for one Paper version from the v3 builds endpoint.
    /// - Stable if the version has any STABLE-channel build (highest build wins).
    /// - Experimental if it only has BETA/ALPHA builds (new-scheme dev versions like 26.x.x).
    private static func paperVersionEntryV3(_ version: String) async -> ServerVersionEntry {
        let url = URL(string: "https://fill.papermc.io/v3/projects/paper/versions/\(version)/builds")!
        guard let (data, _) = try? await MSCHTTP.get(url),
              let buildsAny = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return ServerVersionEntry(id: version, displayLabel: version, mcVersion: version,
                                      loaderVersion: nil, buildLabel: nil, isStable: false)
        }

        var bestStable: Int? = nil
        var bestBeta: Int? = nil

        for entryAny in buildsAny {
            guard let entry = entryAny as? [String: Any],
                  let channel = (entry["channel"] as? String)?.uppercased() else { continue }
            let buildId: Int?
            if let i = entry["id"] as? Int { buildId = i }
            else if let n = entry["id"] as? NSNumber { buildId = n.intValue }
            else { buildId = nil }
            guard let bid = buildId else { continue }

            if channel == "STABLE" {
                if bestStable == nil || bid > bestStable! { bestStable = bid }
            } else if channel == "BETA" || channel == "ALPHA" {
                if bestBeta == nil || bid > bestBeta! { bestBeta = bid }
            }
        }

        if let best = bestStable {
            return ServerVersionEntry(id: version, displayLabel: version, mcVersion: version,
                                      loaderVersion: nil, buildLabel: "build \(best)", isStable: true)
        } else if let best = bestBeta {
            return ServerVersionEntry(id: version, displayLabel: version, mcVersion: version,
                                      loaderVersion: nil, buildLabel: "build \(best) · beta", isStable: false)
        } else {
            return ServerVersionEntry(id: version, displayLabel: version, mcVersion: version,
                                      loaderVersion: nil, buildLabel: nil, isStable: false)
        }
    }

    static func downloadVersion(_ version: String, to destination: URL) async throws -> ServerJarDownloadResult {
        // v3 API — v2 (api.papermc.io) does not recognise new-scheme versions like 26.x.x
        let buildsURL = URL(string: "https://fill.papermc.io/v3/projects/paper/versions/\(version)/builds")!
        let (data, resp) = try await MSCHTTP.get(buildsURL)
        try ensureOK(resp, "Paper builds for \(version)")
        guard let buildsAny = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw ServerJarProviderError.invalidResponse("Paper build list for \(version) malformed.")
        }

        var bestId: Int? = nil
        var bestURL: URL? = nil

        for entryAny in buildsAny {
            guard let entry = entryAny as? [String: Any],
                  let downloads = entry["downloads"] as? [String: Any],
                  let serverDefault = downloads["server:default"] as? [String: Any],
                  let urlString = serverDefault["url"] as? String,
                  let downloadURL = URL(string: urlString) else { continue }
            let buildId: Int
            if let i = entry["id"] as? Int { buildId = i }
            else if let n = entry["id"] as? NSNumber { buildId = n.intValue }
            else { continue }
            if bestId == nil || buildId > bestId! {
                bestId = buildId
                bestURL = downloadURL
            }
        }

        guard let buildNumber = bestId, let jarURL = bestURL else {
            throw ServerJarProviderError.invalidResponse("No builds found for Paper \(version).")
        }

        let (jarData, jarResp) = try await MSCHTTP.get(jarURL)
        try ensureOK(jarResp, "Paper download \(version)")
        try jarData.write(to: destination, options: [.atomic])
        return ServerJarDownloadResult(version: version, build: String(buildNumber))
    }
}

// MARK: - Purpur (api.purpurmc.org)

enum PurpurDownloader {

    /// Downloads the latest build of the latest stable Purpur version.
    static func downloadLatest(to destination: URL) async throws -> ServerJarDownloadResult {
        // 1. Decide the target Minecraft version. Purpur's version list includes
        //    experimental builds (e.g. 26.x) above the latest stable release, so we
        //    don't just pick the highest number. Purpur tracks the Paper family, so we
        //    reuse PaperDownloader's stable detection to choose the same version a Paper
        //    server would get, and only fall back to a "1.x" filter if Purpur lacks it.
        let projectURL = URL(string: "https://api.purpurmc.org/v2/purpur")!
        let (projData, projResp) = try await MSCHTTP.get(projectURL)
        try ensureOK(projResp, "Purpur project")
        guard let projRoot = try JSONSerialization.jsonObject(with: projData) as? [String: Any],
              let versions = projRoot["versions"] as? [String], !versions.isEmpty else {
            throw ServerJarProviderError.invalidResponse("Purpur versions list missing.")
        }

        let paperStable = try? await PaperDownloader.fetchLatestMetadata().version
        let newest: String
        if let paperStable, versions.contains(paperStable) {
            newest = paperStable
        } else if let stableLike = versions
            .filter({ $0.hasPrefix("1.") })
            .sorted(by: { compareMCVersions($0, $1) == .orderedDescending })
            .first {
            newest = stableLike
        } else if let highest = versions.sorted(by: { compareMCVersions($0, $1) == .orderedDescending }).first {
            newest = highest
        } else {
            throw ServerJarProviderError.invalidResponse("No Purpur versions found.")
        }

        // 2. Resolve the latest build number for that version (for labeling).
        let verURL = URL(string: "https://api.purpurmc.org/v2/purpur/\(newest)")!
        let (verData, verResp) = try await MSCHTTP.get(verURL)
        try ensureOK(verResp, "Purpur version")
        let buildLabel: String
        if let verRoot = try JSONSerialization.jsonObject(with: verData) as? [String: Any],
           let builds = verRoot["builds"] as? [String: Any],
           let latest = builds["latest"] as? String {
            buildLabel = latest
        } else {
            buildLabel = "latest"
        }

        // 3. Download the latest build jar.
        let dlURL = URL(string: "https://api.purpurmc.org/v2/purpur/\(newest)/latest/download")!
        let (jarData, jarResp) = try await MSCHTTP.get(dlURL)
        try ensureOK(jarResp, "Purpur download")
        try jarData.write(to: destination, options: [.atomic])

        return ServerJarDownloadResult(version: newest, build: buildLabel)
    }

    static func listVersions() async throws -> [ServerVersionEntry] {
        let url = URL(string: "https://api.purpurmc.org/v2/purpur")!
        let (data, resp) = try await MSCHTTP.get(url)
        try ensureOK(resp, "Purpur project")
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let versions = root["versions"] as? [String] else {
            throw ServerJarProviderError.invalidResponse("Purpur versions list malformed.")
        }
        return versions
            .filter { $0.hasPrefix("1.") }
            .sorted { compareMCVersions($0, $1) == .orderedDescending }
            .map { v in ServerVersionEntry(id: v, displayLabel: v, mcVersion: v, loaderVersion: nil, buildLabel: nil, isStable: true) }
    }

    static func downloadVersion(_ version: String, to destination: URL) async throws -> ServerJarDownloadResult {
        let dlURL = URL(string: "https://api.purpurmc.org/v2/purpur/\(version)/latest/download")!
        let (jarData, jarResp) = try await MSCHTTP.get(dlURL)
        try ensureOK(jarResp, "Purpur download \(version)")
        try jarData.write(to: destination, options: [.atomic])
        return ServerJarDownloadResult(version: version, build: "latest")
    }
}

// MARK: - Vanilla (Mojang version manifest)

enum VanillaDownloader {

    /// Downloads the official Mojang server jar for the latest stable release.
    static func downloadLatest(to destination: URL) async throws -> ServerJarDownloadResult {
        // 1. Manifest → latest.release id + the per-version metadata URL.
        let manifestURL = URL(string: "https://launchermeta.mojang.com/mc/game/version_manifest_v2.json")!
        let (manData, manResp) = try await MSCHTTP.get(manifestURL)
        try ensureOK(manResp, "Mojang manifest")
        guard let manRoot = try JSONSerialization.jsonObject(with: manData) as? [String: Any],
              let latest = manRoot["latest"] as? [String: Any],
              let releaseId = latest["release"] as? String,
              let versionList = manRoot["versions"] as? [[String: Any]] else {
            throw ServerJarProviderError.invalidResponse("Mojang manifest malformed.")
        }
        guard let entry = versionList.first(where: { ($0["id"] as? String) == releaseId }),
              let metaURLString = entry["url"] as? String,
              let metaURL = URL(string: metaURLString) else {
            throw ServerJarProviderError.invalidResponse("No manifest entry for \(releaseId).")
        }

        // 2. Per-version metadata → downloads.server.url.
        let (metaData, metaResp) = try await MSCHTTP.get(metaURL)
        try ensureOK(metaResp, "Mojang version metadata")
        guard let metaRoot = try JSONSerialization.jsonObject(with: metaData) as? [String: Any],
              let downloads = metaRoot["downloads"] as? [String: Any],
              let server = downloads["server"] as? [String: Any],
              let serverURLString = server["url"] as? String,
              let serverURL = URL(string: serverURLString) else {
            throw ServerJarProviderError.invalidResponse("No server download for \(releaseId).")
        }

        // 3. Download the official server jar.
        let (jarData, jarResp) = try await MSCHTTP.get(serverURL)
        try ensureOK(jarResp, "Vanilla download")
        try jarData.write(to: destination, options: [.atomic])

        return ServerJarDownloadResult(version: releaseId, build: "release")
    }

    static func listVersions() async throws -> [ServerVersionEntry] {
        let manifestURL = URL(string: "https://launchermeta.mojang.com/mc/game/version_manifest_v2.json")!
        let (data, resp) = try await MSCHTTP.get(manifestURL)
        try ensureOK(resp, "Mojang manifest")
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["versions"] as? [[String: Any]] else {
            throw ServerJarProviderError.invalidResponse("Mojang manifest malformed.")
        }
        return list
            .filter { ($0["type"] as? String) == "release" }
            .compactMap { $0["id"] as? String }
            .map { v in ServerVersionEntry(id: v, displayLabel: v, mcVersion: v, loaderVersion: nil, buildLabel: nil, isStable: true) }
    }

    static func downloadVersion(_ releaseId: String, to destination: URL) async throws -> ServerJarDownloadResult {
        let manifestURL = URL(string: "https://launchermeta.mojang.com/mc/game/version_manifest_v2.json")!
        let (manData, manResp) = try await MSCHTTP.get(manifestURL)
        try ensureOK(manResp, "Mojang manifest")
        guard let manRoot = try JSONSerialization.jsonObject(with: manData) as? [String: Any],
              let versionList = manRoot["versions"] as? [[String: Any]],
              let entry = versionList.first(where: { ($0["id"] as? String) == releaseId }),
              let metaURLString = entry["url"] as? String,
              let metaURL = URL(string: metaURLString) else {
            throw ServerJarProviderError.invalidResponse("No manifest entry for \(releaseId).")
        }
        let (metaData, metaResp) = try await MSCHTTP.get(metaURL)
        try ensureOK(metaResp, "Mojang version metadata")
        guard let metaRoot = try JSONSerialization.jsonObject(with: metaData) as? [String: Any],
              let downloads = metaRoot["downloads"] as? [String: Any],
              let server = downloads["server"] as? [String: Any],
              let serverURLString = server["url"] as? String,
              let serverURL = URL(string: serverURLString) else {
            throw ServerJarProviderError.invalidResponse("No server download for \(releaseId).")
        }
        let (jarData, jarResp) = try await MSCHTTP.get(serverURL)
        try ensureOK(jarResp, "Vanilla download \(releaseId)")
        try jarData.write(to: destination, options: [.atomic])
        return ServerJarDownloadResult(version: releaseId, build: "release")
    }
}

// MARK: - Fabric (meta.fabricmc.net)

enum FabricDownloader {

    /// Downloads the Fabric server launcher jar for the latest stable game version
    /// + latest stable loader/installer. The launcher fetches the vanilla Minecraft
    /// jar itself on first run, so this is a single self-contained jar like Paper.
    static func downloadLatest(to destination: URL) async throws -> ServerJarDownloadResult {
        // 1. Latest stable Minecraft (game) version Fabric supports.
        let game = try await firstStableVersion(
            from: "https://meta.fabricmc.net/v2/versions/game", what: "Fabric game")

        // 2. Latest stable loader compatible with that game version.
        let loaderURL = URL(string: "https://meta.fabricmc.net/v2/versions/loader/\(game)")!
        let (loaderData, loaderResp) = try await MSCHTTP.get(loaderURL)
        try ensureOK(loaderResp, "Fabric loader")
        guard let loaderList = try JSONSerialization.jsonObject(with: loaderData) as? [[String: Any]],
              !loaderList.isEmpty else {
            throw ServerJarProviderError.invalidResponse("No Fabric loaders for \(game).")
        }
        let loaderEntry = loaderList.first { (($0["loader"] as? [String: Any])?["stable"] as? Bool) == true } ?? loaderList[0]
        guard let loader = (loaderEntry["loader"] as? [String: Any])?["version"] as? String else {
            throw ServerJarProviderError.invalidResponse("Malformed Fabric loader entry.")
        }

        // 3. Latest stable installer.
        let installer = try await firstStableVersion(
            from: "https://meta.fabricmc.net/v2/versions/installer", what: "Fabric installer")

        // 4. Download the server launcher jar for this exact combination.
        let dlURL = URL(string: "https://meta.fabricmc.net/v2/versions/loader/\(game)/\(loader)/\(installer)/server/jar")!
        let (jarData, jarResp) = try await MSCHTTP.get(dlURL)
        try ensureOK(jarResp, "Fabric server jar")
        try jarData.write(to: destination, options: [.atomic])

        return ServerJarDownloadResult(version: game, build: "fabric \(loader)", loaderVersion: loader)
    }

    static func listVersions() async throws -> [ServerVersionEntry] {
        let url = URL(string: "https://meta.fabricmc.net/v2/versions/game")!
        let (data, resp) = try await MSCHTTP.get(url)
        try ensureOK(resp, "Fabric game versions")
        guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ServerJarProviderError.invalidResponse("Fabric game list malformed.")
        }
        return list
            .filter { ($0["stable"] as? Bool) == true }
            .compactMap { $0["version"] as? String }
            .map { v in ServerVersionEntry(id: v, displayLabel: v, mcVersion: v, loaderVersion: nil, buildLabel: nil, isStable: true) }
    }

    static func downloadVersion(_ mcVersion: String, to destination: URL) async throws -> ServerJarDownloadResult {
        // Resolve the latest stable loader for this game version.
        let loaderURL = URL(string: "https://meta.fabricmc.net/v2/versions/loader/\(mcVersion)")!
        let (loaderData, loaderResp) = try await MSCHTTP.get(loaderURL)
        try ensureOK(loaderResp, "Fabric loader for \(mcVersion)")
        guard let loaderList = try JSONSerialization.jsonObject(with: loaderData) as? [[String: Any]],
              !loaderList.isEmpty else {
            throw ServerJarProviderError.invalidResponse("No Fabric loaders for \(mcVersion).")
        }
        let loaderEntry = loaderList.first { (($0["loader"] as? [String: Any])?["stable"] as? Bool) == true } ?? loaderList[0]
        guard let loader = (loaderEntry["loader"] as? [String: Any])?["version"] as? String else {
            throw ServerJarProviderError.invalidResponse("Malformed Fabric loader entry for \(mcVersion).")
        }
        let installer = try await firstStableVersion(
            from: "https://meta.fabricmc.net/v2/versions/installer", what: "Fabric installer")
        let dlURL = URL(string: "https://meta.fabricmc.net/v2/versions/loader/\(mcVersion)/\(loader)/\(installer)/server/jar")!
        let (jarData, jarResp) = try await MSCHTTP.get(dlURL)
        try ensureOK(jarResp, "Fabric server jar \(mcVersion)")
        try jarData.write(to: destination, options: [.atomic])
        return ServerJarDownloadResult(version: mcVersion, build: "fabric \(loader)", loaderVersion: loader)
    }

    /// Returns the first stable entry's `version` from a Fabric meta list endpoint,
    /// falling back to the first entry if none are flagged stable.
    private static func firstStableVersion(from urlString: String, what: String) async throws -> String {
        let url = URL(string: urlString)!
        let (data, resp) = try await MSCHTTP.get(url)
        try ensureOK(resp, what)
        guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], !list.isEmpty else {
            throw ServerJarProviderError.invalidResponse("\(what) list empty.")
        }
        let entry = list.first { ($0["stable"] as? Bool) == true } ?? list[0]
        guard let version = entry["version"] as? String else {
            throw ServerJarProviderError.invalidResponse("\(what) entry malformed.")
        }
        return version
    }
}

// MARK: - Pufferfish (ci.pufferfish.host Jenkins CI)

enum PufferfishDownloader {

    // Bump this string when Pufferfish publishes a job for a newer MC major.minor.
    private static let latestMajorMinor = "1.21"
    private static let ciBase = "https://ci.pufferfish.host/job/Pufferfish-"

    static func downloadLatest(to destination: URL) async throws -> ServerJarDownloadResult {
        // Ask Jenkins for the artifact list from the last successful build.
        let apiURL = URL(string: "\(ciBase)\(latestMajorMinor)/lastSuccessfulBuild/api/json")!
        let (data, response) = try await MSCHTTP.get(apiURL)
        try ensureOK(response, "Pufferfish CI")

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let buildNumber = json["number"] as? Int,
              let artifacts = json["artifacts"] as? [[String: Any]],
              let artifact = artifacts.first(where: {
                  ($0["relativePath"] as? String)?.hasSuffix("reobf.jar") == true
              }),
              let relativePath = artifact["relativePath"] as? String else {
            throw ServerJarProviderError.invalidResponse("Pufferfish CI response malformed.")
        }

        // Derive MC version from filename: pufferfish-paperclip-1.21.4-R0.1-SNAPSHOT-reobf.jar
        let filename = URL(fileURLWithPath: relativePath).lastPathComponent
        let mcVersion = parseMCVersion(from: filename) ?? latestMajorMinor

        let jarURL = URL(string: "\(ciBase)\(latestMajorMinor)/lastSuccessfulBuild/artifact/\(relativePath)")!
        let (jarData, jarResponse) = try await MSCHTTP.get(jarURL)
        try ensureOK(jarResponse, "Pufferfish jar")
        try jarData.write(to: destination)

        return ServerJarDownloadResult(version: mcVersion, build: String(buildNumber))
    }

    // "pufferfish-paperclip-1.21.4-R0.1-SNAPSHOT-reobf.jar" → "1.21.4"
    private static func parseMCVersion(from filename: String) -> String? {
        let stem = filename.hasSuffix(".jar") ? String(filename.dropLast(4)) : filename
        return stem.components(separatedBy: "-").first { part in
            part.first?.isNumber == true && part.contains(".")
        }
    }
}

// MARK: - Helpers

/// Shared HTTP helper that always sends a descriptive User-Agent. Some provider
/// APIs (and Modrinth, used later) reject requests without one.
enum MSCHTTP {
    static let userAgent = "MinecraftServerController/1.0 (macOS server manager)"

    static func get(_ url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        return try await URLSession.shared.data(for: request)
    }
}

private func ensureOK(_ response: URLResponse, _ what: String) throws {
    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
        throw ServerJarProviderError.networkError("\(what) returned status \(http.statusCode).")
    }
}

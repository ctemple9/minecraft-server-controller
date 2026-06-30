//
//  ModrinthAPI.swift
//  MinecraftServerController
//
//  Fetches the latest plugin version and download URL from Modrinth.
//  API docs: https://docs.modrinth.com
//

import Foundation
import CryptoKit

enum ModrinthAPIError: Error, LocalizedError {
    case invalidURL
    case networkError(String)
    case noCompatibleVersion
    case noJarAsset
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:               return "Invalid Modrinth URL."
        case .networkError(let m):      return m
        case .noCompatibleVersion:      return "No compatible version found on Modrinth."
        case .noJarAsset:               return "Modrinth release has no JAR download."
        case .decodingError(let m):     return "Modrinth response error: \(m)"
        }
    }
}

enum ModrinthAPI {

    /// Fetches the latest Paper-compatible release for a Modrinth project.
    /// - Parameters:
    ///   - slug:      Modrinth project slug or ID, e.g. "luckperms"
    ///   - mcVersion: Minecraft version string, e.g. "1.21.4"
    static func fetchLatest(
        slug: String,
        mcVersion: String
    ) async throws -> (version: String, downloadURL: URL) {

        // Build query: Paper loader, specific MC version, release channel, latest first
        var components = URLComponents(string: "https://api.modrinth.com/v2/project/\(slug)/version")!
        components.queryItems = [
            URLQueryItem(name: "loaders",       value: "[\"paper\",\"spigot\",\"bukkit\"]"),
            URLQueryItem(name: "game_versions", value: "[\"\(mcVersion)\"]"),
        ]

        guard let url = components.url else { throw ModrinthAPIError.invalidURL }

        let (data, response): (Data, URLResponse)
        do {
            var request = URLRequest(url: url)
            request.setValue("MinecraftServerController/1.0", forHTTPHeaderField: "User-Agent")
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ModrinthAPIError.networkError("Network error fetching Modrinth versions: \(error.localizedDescription)")
        }

        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ModrinthAPIError.networkError("Modrinth returned status \(code) for \(slug).")
        }

        struct ModrinthVersion: Decodable {
            let versionNumber: String
            struct File: Decodable {
                let url: String
                let filename: String
                let primary: Bool
            }
            let files: [File]

            enum CodingKeys: String, CodingKey {
                case versionNumber = "version_number"
                case files
            }
        }

        let versions: [ModrinthVersion]
        do {
            versions = try JSONDecoder().decode([ModrinthVersion].self, from: data)
        } catch {
            throw ModrinthAPIError.decodingError(error.localizedDescription)
        }

        guard let latest = versions.first else {
            throw ModrinthAPIError.noCompatibleVersion
        }

        // Prefer primary file, fall back to first JAR
        let jarFile = latest.files.first(where: { $0.primary && $0.filename.hasSuffix(".jar") })
            ?? latest.files.first(where: { $0.filename.hasSuffix(".jar") })

        guard let file = jarFile, let downloadURL = URL(string: file.url) else {
            throw ModrinthAPIError.noJarAsset
        }

        return (version: latest.versionNumber, downloadURL: downloadURL)
    }
}

// MARK: - Browser models (M5)

/// One search result from Modrinth's `/v2/search`.
struct ModrinthSearchHit: Identifiable, Decodable, Equatable, Hashable {
    let projectId: String
    let slug: String
    let title: String
    let description: String
    let author: String
    let downloads: Int
    let iconUrl: String?
    let clientSide: String      // required / optional / unsupported
    let serverSide: String      // required / optional / unsupported
    let projectType: String

    var id: String { projectId }

    /// True when the add-on does nothing on a server (client-only).
    var isClientOnly: Bool { serverSide == "unsupported" }
}

struct ModrinthSearchResult: Decodable {
    let hits: [ModrinthSearchHit]
    let totalHits: Int
}

struct ModrinthDependency: Decodable, Equatable {
    let projectId: String?
    let versionId: String?
    let dependencyType: String   // required / optional / incompatible / embedded
}

struct ModrinthVersionFile: Decodable, Equatable {
    let url: String
    let filename: String
    let primary: Bool
    let hashes: [String: String]
    let size: Int?
}

/// One version of a Modrinth project, with its files + dependencies.
struct ModrinthVersionInfo: Identifiable, Decodable, Equatable {
    let id: String
    /// Owning project ID. Present on /version, /version_file, and /version_files
    /// responses; nil only if a caller constructs one by hand.
    let projectId: String?
    let name: String
    let versionNumber: String
    let versionType: String       // release / beta / alpha
    let gameVersions: [String]
    let loaders: [String]
    let dependencies: [ModrinthDependency]
    let files: [ModrinthVersionFile]
    let datePublished: String?

    var primaryFile: ModrinthVersionFile? {
        files.first(where: { $0.primary }) ?? files.first
    }
    var isStable: Bool { versionType == "release" }
}

/// One gallery image on a Modrinth project.
struct ModrinthGalleryImage: Decodable, Identifiable, Equatable {
    let url: String
    let title: String?
    let description: String?
    let featured: Bool
    var id: String { url }
}

/// Full project detail from `/v2/project/{id}` (body, gallery, links, stats).
struct ModrinthProject: Decodable {
    let id: String
    let slug: String
    let title: String
    let description: String
    let body: String
    let iconUrl: String?
    let downloads: Int
    let followers: Int
    let updated: String?
    let clientSide: String
    let serverSide: String
    let categories: [String]
    let gameVersions: [String]
    let loaders: [String]
    let gallery: [ModrinthGalleryImage]
    let sourceUrl: String?
    let issuesUrl: String?
    let wikiUrl: String?
    let discordUrl: String?

    var isClientOnly: Bool { serverSide == "unsupported" }
}

// MARK: - Browser API (M5)

extension ModrinthAPI {

    static let browserUserAgent = "MinecraftServerController/1.0 (macOS server manager)"

    private static func snakeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    private static func getData(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ModrinthAPIError.networkError(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ModrinthAPIError.networkError("Modrinth returned status \(code).")
        }
        return data
    }

    /// Builds Modrinth's `facets` value: AND across groups, OR within a group.
    ///
    /// For plugin servers we include BOTH project_type:plugin AND project_type:mod in the
    /// same OR group. Projects like Geyser and Floodgate that support Fabric/NeoForge in
    /// addition to Spigot/Paper are typed as "mod" on Modrinth, which would exclude them
    /// from a pure project_type:plugin search.
    private static func facets(projectType: String, loaders: [String], gameVersion: String?) -> String {
        var groups: [String]
        if projectType == "plugin" {
            // OR: plugin OR mod — catches cross-platform projects (Geyser, Floodgate, etc.)
            groups = ["[\"project_type:plugin\",\"project_type:mod\"]"]
        } else {
            groups = ["[\"project_type:\(projectType)\"]"]
        }
        if !loaders.isEmpty {
            let or = loaders.map { "\"categories:\($0)\"" }.joined(separator: ",")
            groups.append("[\(or)]")
        }
        if let gameVersion, !gameVersion.isEmpty {
            groups.append("[\"versions:\(gameVersion)\"]")
        }
        return "[\(groups.joined(separator: ","))]"
    }

    /// Searches Modrinth, filtered to the given project type, loaders, and Minecraft version.
    /// `query` may be empty (returns popular results for the filters).
    static func search(
        query: String,
        loaders: [String],
        gameVersion: String?,
        projectType: String = "mod",
        limit: Int = 20,
        offset: Int = 0
    ) async throws -> ModrinthSearchResult {
        var comps = URLComponents(string: "https://api.modrinth.com/v2/search")!
        comps.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "facets", value: facets(projectType: projectType, loaders: loaders, gameVersion: gameVersion)),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "index", value: query.isEmpty ? "downloads" : "relevance"),
        ]
        guard let url = comps.url else { throw ModrinthAPIError.invalidURL }
        let data = try await getData(url)
        do { return try snakeDecoder().decode(ModrinthSearchResult.self, from: data) }
        catch { throw ModrinthAPIError.decodingError(error.localizedDescription) }
    }

    /// Lists a project's versions compatible with the given loaders + game version.
    static func projectVersions(
        idOrSlug: String,
        loaders: [String],
        gameVersion: String?
    ) async throws -> [ModrinthVersionInfo] {
        var comps = URLComponents(string: "https://api.modrinth.com/v2/project/\(idOrSlug)/version")!
        var items: [URLQueryItem] = []
        if !loaders.isEmpty {
            items.append(URLQueryItem(name: "loaders", value: "[" + loaders.map { "\"\($0)\"" }.joined(separator: ",") + "]"))
        }
        if let gameVersion, !gameVersion.isEmpty {
            items.append(URLQueryItem(name: "game_versions", value: "[\"\(gameVersion)\"]"))
        }
        comps.queryItems = items.isEmpty ? nil : items
        guard let url = comps.url else { throw ModrinthAPIError.invalidURL }
        let data = try await getData(url)
        do { return try snakeDecoder().decode([ModrinthVersionInfo].self, from: data) }
        catch { throw ModrinthAPIError.decodingError(error.localizedDescription) }
    }

    /// Fetches multiple projects in one request (`GET /v2/projects?ids=[…]`).
    /// Used to populate titles/descriptions/icons for an update plan without N calls.
    static func projects(ids: [String]) async throws -> [ModrinthProject] {
        guard !ids.isEmpty else { return [] }
        var comps = URLComponents(string: "https://api.modrinth.com/v2/projects")!
        comps.queryItems = [
            URLQueryItem(name: "ids", value: "[" + ids.map { "\"\($0)\"" }.joined(separator: ",") + "]")
        ]
        guard let url = comps.url else { throw ModrinthAPIError.invalidURL }
        let data = try await getData(url)
        do { return try snakeDecoder().decode([ModrinthProject].self, from: data) }
        catch { throw ModrinthAPIError.decodingError(error.localizedDescription) }
    }

    /// Fetches full project detail (body, gallery, links) for the detail page.
    static func project(idOrSlug: String) async throws -> ModrinthProject {
        guard let url = URL(string: "https://api.modrinth.com/v2/project/\(idOrSlug)") else {
            throw ModrinthAPIError.invalidURL
        }
        let data = try await getData(url)
        do { return try snakeDecoder().decode(ModrinthProject.self, from: data) }
        catch { throw ModrinthAPIError.decodingError(error.localizedDescription) }
    }

    /// Fetches a single version by its ID (`GET /v2/version/{id}`), including its files
    /// and dependencies — used to download a specific build chosen by the update planner.
    static func version(id: String) async throws -> ModrinthVersionInfo {
        guard let url = URL(string: "https://api.modrinth.com/v2/version/\(id)") else {
            throw ModrinthAPIError.invalidURL
        }
        let data = try await getData(url)
        do { return try snakeDecoder().decode(ModrinthVersionInfo.self, from: data) }
        catch { throw ModrinthAPIError.decodingError(error.localizedDescription) }
    }

    /// Downloads a version's primary jar to `destination`.
    static func downloadVersionFile(_ version: ModrinthVersionInfo, to destination: URL) async throws {
        guard let file = version.primaryFile, let url = URL(string: file.url) else {
            throw ModrinthAPIError.noJarAsset
        }
        let data = try await getData(url)
        do { try data.write(to: destination, options: [.atomic]) }
        catch { throw ModrinthAPIError.networkError("Could not save \(file.filename): \(error.localizedDescription)") }
    }
}

// MARK: - Hash-based identification & batch updates
//
// These endpoints turn "I have this jar on disk" into "this is the Modrinth project
// + version, and here's the latest compatible build." This is the backbone of the
// add-on update workflow — exact hash matching, no fuzzy guessing.

extension ModrinthAPI {

    /// SHA-512 hex digest of a file's contents, computed in a streaming fashion so
    /// large mod jars don't get fully loaded into memory. Modrinth's preferred algorithm.
    static func sha512Hex(of fileURL: URL) -> String? {
        hashHex(of: fileURL, hasher: SHA512())
    }

    /// SHA-1 hex digest of a file's contents (fallback algorithm).
    static func sha1Hex(of fileURL: URL) -> String? {
        hashHex(of: fileURL, hasher: Insecure.SHA1())
    }

    private static func hashHex<H: HashFunction>(of fileURL: URL, hasher: H) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }
        var h = hasher
        while autoreleasepool(invoking: {
            let chunk = (try? handle.read(upToCount: 1 << 20)) ?? nil
            guard let chunk, !chunk.isEmpty else { return false }
            h.update(data: chunk)
            return true
        }) {}
        return h.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Identifies a single file by its SHA-512 hash. Returns the matching version
    /// (including `projectId`), or nil if Modrinth doesn't host this exact file.
    static func versionFromHash(_ sha512: String) async throws -> ModrinthVersionInfo? {
        guard let url = URL(string: "https://api.modrinth.com/v2/version_file/\(sha512)?algorithm=sha512") else {
            throw ModrinthAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw ModrinthAPIError.networkError(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else {
            throw ModrinthAPIError.networkError("No HTTP response from Modrinth.")
        }
        if http.statusCode == 404 { return nil }   // not hosted on Modrinth — expected, not an error
        guard (200..<300).contains(http.statusCode) else {
            throw ModrinthAPIError.networkError("Modrinth returned status \(http.statusCode).")
        }
        do { return try snakeDecoder().decode(ModrinthVersionInfo.self, from: data) }
        catch { throw ModrinthAPIError.decodingError(error.localizedDescription) }
    }

    /// Batch-identifies many files at once by SHA-512. Returns a map of hash → version.
    /// Hashes Modrinth doesn't recognize are simply absent from the result.
    static func versionsFromHashes(_ sha512s: [String]) async throws -> [String: ModrinthVersionInfo] {
        guard !sha512s.isEmpty else { return [:] }
        let body: [String: Any] = ["hashes": sha512s, "algorithm": "sha512"]
        let data = try await postJSON("https://api.modrinth.com/v2/version_files", body: body)
        do { return try snakeDecoder().decode([String: ModrinthVersionInfo].self, from: data) }
        catch { throw ModrinthAPIError.decodingError(error.localizedDescription) }
    }

    /// Given installed file hashes plus the server's loaders and Minecraft version,
    /// returns the latest matching version per hash — Modrinth computes the whole
    /// "what should I update to?" plan server-side in one request. Hashes with no
    /// compatible newer build are absent from the result.
    static func latestVersionsForHashes(
        _ sha512s: [String],
        loaders: [String],
        gameVersions: [String]
    ) async throws -> [String: ModrinthVersionInfo] {
        guard !sha512s.isEmpty else { return [:] }
        var body: [String: Any] = ["hashes": sha512s, "algorithm": "sha512"]
        if !loaders.isEmpty      { body["loaders"] = loaders }
        if !gameVersions.isEmpty { body["game_versions"] = gameVersions }
        let data = try await postJSON("https://api.modrinth.com/v2/version_files/update", body: body)
        do { return try snakeDecoder().decode([String: ModrinthVersionInfo].self, from: data) }
        catch { throw ModrinthAPIError.decodingError(error.localizedDescription) }
    }

    /// POSTs a JSON body and returns the response data, applying the standard
    /// User-Agent and status-code checks.
    private static func postJSON(_ urlString: String, body: [String: Any]) async throws -> Data {
        guard let url = URL(string: urlString) else { throw ModrinthAPIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw ModrinthAPIError.networkError(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ModrinthAPIError.networkError("Modrinth returned status \(code).")
        }
        return data
    }
}

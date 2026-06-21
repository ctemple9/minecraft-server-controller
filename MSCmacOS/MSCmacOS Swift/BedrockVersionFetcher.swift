//  BedrockVersionFetcher.swift
//  MinecraftServerController
//
//  Fetches available Bedrock Dedicated Server version strings.
//  and drives docker pull operations.
//
//  Versions are sourced from the Mojang update manifest via a public proxy.
//  If the network fetch fails, a static fallback list is returned so the
//  picker always has options.

import Foundation

// MARK: - Version entry

struct BedrockVersionEntry: Identifiable, Hashable {
    /// Raw value passed to BEDROCK_SERVER_VERSION env var.
    /// e.g. "1.21.50.07" or "LATEST"
    let version: String

    var id: String { version }

    /// Human-readable label shown in the picker.
    var displayName: String {
        version == "LATEST" ? "Latest (auto)" : version
    }

    var isLatest: Bool { version == "LATEST" }
}

// MARK: - Fetcher

/// Fetches available BDS versions. Results are process-cached after the first
/// successful fetch. Call invalidateCache() before a docker pull so the next
/// fetch reflects any new versions.
enum BedrockVersionFetcher {

    // kittizz/bedrock-server-downloads is the canonical version list used by itzg at runtime.
    private static let manifestURL = URL(string:
        "https://raw.githubusercontent.com/kittizz/bedrock-server-downloads/refs/heads/main/bedrock-server-downloads.json"
    )!

    private static var cachedVersions: [BedrockVersionEntry]? = nil

    /// Fetch available BDS versions, newest first.
    /// Always inserts "LATEST" at index 0.
    /// Never throws — returns the static fallback list on any error.
    static func fetchVersions() async -> [BedrockVersionEntry] {
        if let cached = cachedVersions { return cached }

        let versions: [BedrockVersionEntry]

        do {
            let (data, response) = try await URLSession.shared.data(from: manifestURL)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            guard status == 200 else { throw URLError(.badServerResponse) }
            versions = try parseManifest(data)
        } catch {
            versions = staticFallback()
        }

        cachedVersions = versions
        return versions
    }

    /// Call before a docker pull so the next fetchVersions() re-queries the network.
    static func invalidateCache() {
        cachedVersions = nil
    }

    // MARK: - Parsing

    // Handles the kittizz bedrock-server-downloads.json format:
    // { "release": { "1.26.31": { "linux": { "url": "...bedrock-server-1.26.31.1.zip" } } } }
    // Full version strings are extracted from the download URLs because that is what
    // itzg's VERSION env var expects (e.g. "1.26.30.5", not "1.26.30").
    private static func parseManifest(_ data: Data) throws -> [BedrockVersionEntry] {
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let release = root["release"] as? [String: Any] {
            let versions: [String] = release.values.compactMap { entry in
                guard let platforms = entry as? [String: Any],
                      let linux = platforms["linux"] as? [String: Any],
                      let url = linux["url"] as? String,
                      let match = url.range(of: #"bedrock-server-([0-9.]+)\.zip"#, options: .regularExpression) else { return nil }
                let full = String(url[match])
                // Extract just the version portion from "bedrock-server-X.Y.Z.W.zip"
                return full
                    .replacingOccurrences(of: "bedrock-server-", with: "")
                    .replacingOccurrences(of: ".zip", with: "")
            }
            if !versions.isEmpty { return collate(versions) }
        }
        // Legacy: plain array of strings.
        if let array = try? JSONDecoder().decode([String].self, from: data) {
            return collate(array)
        }
        throw URLError(.cannotParseResponse)
    }

    private static func collate(_ raw: [String]) -> [BedrockVersionEntry] {
        let sorted = raw
            .filter { $0.first?.isNumber == true }
            .sorted { versionGreater($0, $1) }
            .prefix(20)
            .map { BedrockVersionEntry(version: $0) }
        return [BedrockVersionEntry(version: "LATEST")] + sorted
    }

    /// Semantic version comparator for "X.Y.Z.W" strings, descending.
    private static func versionGreater(_ a: String, _ b: String) -> Bool {
        let pa = a.split(separator: ".").compactMap { Int($0) }
        let pb = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(pa.count, pb.count) {
            let va = i < pa.count ? pa[i] : 0
            let vb = i < pb.count ? pb[i] : 0
            if va != vb { return va > vb }
        }
        return false
    }

    // MARK: - Static fallback

    private static func staticFallback() -> [BedrockVersionEntry] {
        let known = [
            "1.26.31.1",
            "1.26.30.5",
            "1.26.23.1",
            "1.26.21.1",
            "1.26.20.5",
            "1.26.14.1",
            "1.26.13.1",
            "1.26.12.2",
            "1.21.132.1",
            "1.21.131.1",
        ]
        return [BedrockVersionEntry(version: "LATEST")] + known.map { BedrockVersionEntry(version: $0) }
    }
}

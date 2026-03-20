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

    // The itzg project publishes a versions.json on their GitHub repo.
    // If that ever moves, update this URL — the fallback list covers the gap.
    private static let manifestURL = URL(string:
        "https://raw.githubusercontent.com/itzg/minecraft-bedrock-server/master/versions.json"
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

    // versions.json may be an array of strings or a dict keyed by version string.
    private static func parseManifest(_ data: Data) throws -> [BedrockVersionEntry] {
        if let array = try? JSONDecoder().decode([String].self, from: data) {
            return collate(array)
        }
        // Dict form — we only need the keys, not the values.
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return collate(Array(dict.keys))
        }
        // Newline-separated plain text fallback.
        if let text = String(data: data, encoding: .utf8) {
            let lines = text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.first?.isNumber == true }
            if !lines.isEmpty { return collate(lines) }
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
            "1.21.50.07",
            "1.21.44.01",
            "1.21.41.01",
            "1.21.40.03",
            "1.21.30.03",
            "1.21.23.01",
            "1.21.20.03",
            "1.21.3.01",
            "1.21.2.02",
            "1.21.1.03",
        ]
        return [BedrockVersionEntry(version: "LATEST")] + known.map { BedrockVersionEntry(version: $0) }
    }
}

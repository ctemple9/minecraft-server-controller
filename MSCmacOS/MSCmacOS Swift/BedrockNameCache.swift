//
//  BedrockNameCache.swift
//  MinecraftServerController
//
//  Persists a XUID→gamertag mapping for Bedrock servers so that player names
//  are remembered after the first time a player connects — even across app
//  restarts and server log rollovers.
//
//  The cache file (bedrock_names.json) is written to the server directory
//  alongside server.properties, allowlist.json, etc.
//
//  Cache file format:
//    { "2535416361514257": "Gamertag", "server_03c5ad1d-...": "OtherName", ... }
//

import Foundation

enum BedrockNameCache {

    private static func cacheURL(serverDir: String) -> URL {
        URL(fileURLWithPath: serverDir).appendingPathComponent("bedrock_names.json")
    }

    // MARK: - Load

    /// Returns the full cached XUID→name dictionary for the given server directory.
    static func load(serverDir: String) -> [String: String] {
        let url = cacheURL(serverDir: serverDir)
        guard let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    // MARK: - Record a single entry (read-modify-write)

    /// Adds or updates the `xuid → name` mapping and saves the cache to disk.
    /// Safe to call from any thread; the write is atomic via a temporary file.
    static func record(xuid: String, name: String, serverDir: String) {
        let trimmedXUID = xuid.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedXUID.isEmpty, !trimmedName.isEmpty else { return }

        let url = cacheURL(serverDir: serverDir)
        var dict = load(serverDir: serverDir)
        dict[trimmedXUID] = trimmedName
        save(dict, to: url)
    }

    // MARK: - Private

    private static func save(_ dict: [String: String], to url: URL) {
        guard let data = try? JSONEncoder().encode(dict) else { return }
        // Write atomically so a crash during write doesn't corrupt the cache
        try? data.write(to: url, options: .atomic)
    }
}

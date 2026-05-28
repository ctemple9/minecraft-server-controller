//
//  BedrockPlayerDataManager.swift
//  MinecraftServerController
//
//  Handles Bedrock Edition player data scanning and Xbox/GeyserMC identity resolution.
//  Player data lives in LevelDB at {serverDir}/worlds/{levelName}/db/
//

import Foundation

enum BedrockPlayerDataManager {

    // MARK: - Profile scan

    /// Scans the Bedrock world's LevelDB database and builds PlayerProfile stubs.
    /// NBT parsing (stats + inventory) is performed here so profiles are immediately
    /// useful — no separate lazy-load step is needed for Bedrock.
    static func scanProfiles(serverDir: String, levelName: String) -> [PlayerProfile] {
        let dbPath = URL(fileURLWithPath: serverDir)
            .appendingPathComponent("worlds")
            .appendingPathComponent(levelName)
            .appendingPathComponent("db")
            .path

        let rawData = BedrockLevelDB.readPlayerData(dbPath: dbPath)
        guard !rawData.isEmpty else { return [] }

        // Use the db directory's modification time as the "last seen" proxy for all players.
        let dbMtime = (try? FileManager.default
            .attributesOfItem(atPath: dbPath))?[.modificationDate] as? Date ?? Date()

        var profiles: [PlayerProfile] = []
        for (key, nbtData) in rawData {
            let xuid: String
            if key == "~local_player" {
                xuid = "local"
            } else if key.hasPrefix("player_") {
                xuid = String(key.dropFirst("player_".count))
            } else {
                continue
            }

            // Parse NBT immediately so stats/inventory are available without a second load.
            let (stats, inventory) = BedrockNBTReader.readAll(from: nbtData)

            var profile = PlayerProfile(
                uuid: UUID(),               // Placeholder; updated to Floodgate UUID later
                username: xuid == "local" ? "Local Player" : nil,
                datFilePath: "",            // No .dat file for Bedrock
                lastModified: dbMtime
            )
            profile.xuid = xuid
            profile.stats = stats
            profile.inventory = inventory
            profiles.append(profile)
        }
        return profiles
    }

    // MARK: - XUID → Gamertag (GeyserMC)

    /// Resolves an Xbox XUID to its gamertag using the GeyserMC public API.
    /// Returns nil on any network/parsing failure.
    static func xuidToGamertag(xuid: String) async -> String? {
        guard let url = URL(string: "https://api.geysermc.org/v2/xbox/gamertag/\(xuid)") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.setValue("MinecraftServerController/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

        struct GeyserGamertag: Decodable { let gamertag: String }
        return (try? JSONDecoder().decode(GeyserGamertag.self, from: data))?.gamertag
    }

    // MARK: - Gamertag → Floodgate UUID (mc-heads.net)

    /// Resolves a Bedrock gamertag to the Floodgate UUID used by mc-heads.net
    /// for Bedrock player head/body rendering.
    /// The Geyser endpoint accepts the gamertag with a leading dot prefix.
    static func resolveFloodgateUUID(gamertag: String) async -> UUID? {
        let dotted = gamertag.hasPrefix(".") ? gamertag : ".\(gamertag)"
        let encoded = dotted.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? dotted
        guard let url = URL(string: "https://api.geysermc.org/v2/utils/uuid/bedrock_or_java/\(encoded)") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.setValue("MinecraftServerController/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

        struct GeyserIdentity: Decodable { let id: String }
        guard let identity = try? JSONDecoder().decode(GeyserIdentity.self, from: data) else {
            return nil
        }
        // GeyserMC returns UUIDs without dashes; insert them.
        return uuidFromNoDashes(identity.id)
    }

    // MARK: - Helpers

    /// Converts a 32-hex-char UUID string (no dashes) to UUID.
    private static func uuidFromNoDashes(_ raw: String) -> UUID? {
        let s = raw.replacingOccurrences(of: "-", with: "")
        guard s.count == 32 else { return UUID(uuidString: raw) }
        let formatted = "\(s.prefix(8))-\(s.dropFirst(8).prefix(4))-\(s.dropFirst(12).prefix(4))-\(s.dropFirst(16).prefix(4))-\(s.dropFirst(20))"
        return UUID(uuidString: formatted)
    }
}

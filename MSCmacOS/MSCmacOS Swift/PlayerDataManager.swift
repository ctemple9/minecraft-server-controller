//
//  PlayerDataManager.swift
//  MinecraftServerController
//
//  Handles all file-system operations for Java Edition player data:
//  scanning the playerdata/ directory, reading usercache.json and ops.json,
//  computing offline UUIDs, and performing copy/delete/duplicate operations.
//

import Foundation
import CryptoKit

enum PlayerDataManager {

    // MARK: - Directory helpers

    /// All candidate directories where player .dat files may live, in priority order.
    /// Different server implementations use different subdirectory layouts:
    ///   - Vanilla / most Spigot configs: `{world}/playerdata/`
    ///   - Paper (some configurations):   `{world}/players/data/`
    static func playerDataDirs(serverDir: String, levelName: String) -> [String] {
        let base = URL(fileURLWithPath: serverDir).appendingPathComponent(levelName)
        return [
            base.appendingPathComponent("playerdata").path,
            base.appendingPathComponent("players/data").path,
        ]
    }

    /// Returns the first playerdata directory that exists on disk,
    /// or the canonical vanilla path as a fallback.
    static func playerDataDir(serverDir: String, levelName: String) -> String {
        let candidates = playerDataDirs(serverDir: serverDir, levelName: levelName)
        return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? candidates[0]
    }

    // MARK: - Profile scan

    /// Scans all known playerdata directory candidates for .dat files and builds profile stubs.
    /// Covers both vanilla (`playerdata/`) and Paper (`players/data/`) server layouts.
    /// Usernames and NBT data are not loaded here — that happens async in the ViewModel.
    static func scanProfiles(serverDir: String, levelName: String) -> [PlayerProfile] {
        let fm = FileManager.default
        let dirs = playerDataDirs(serverDir: serverDir, levelName: levelName)
            .filter { fm.fileExists(atPath: $0) }

        var profiles: [PlayerProfile] = []
        var seen = Set<UUID>()

        for dir in dirs {
            guard let contents = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for filename in contents {
                // Only .dat files; skip .dat_old backup files
                guard filename.hasSuffix(".dat"), !filename.hasSuffix(".dat_old") else { continue }
                let uuidString = (filename as NSString).deletingPathExtension
                guard let uuid = UUID(uuidString: uuidString), !seen.contains(uuid) else { continue }
                seen.insert(uuid)
                let fullPath = (dir as NSString).appendingPathComponent(filename)
                let mtime = (try? fm.attributesOfItem(atPath: fullPath))?[.modificationDate] as? Date
                profiles.append(PlayerProfile(
                    uuid: uuid,
                    username: nil,
                    datFilePath: fullPath,
                    lastModified: mtime ?? Date.distantPast
                ))
            }
        }
        return profiles
    }

    // MARK: - usercache.json

    private struct UsercacheEntry: Codable {
        let name: String
        let uuid: String
    }

    /// Reads `{serverDir}/usercache.json` and returns a UUID → username mapping.
    /// This is the fastest username resolution source — no network required.
    static func readUsercache(serverDir: String) -> [UUID: String] {
        let path = URL(fileURLWithPath: serverDir).appendingPathComponent("usercache.json").path
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let entries = try? JSONDecoder().decode([UsercacheEntry].self, from: data) else {
            return [:]
        }
        var result: [UUID: String] = [:]
        for entry in entries {
            if let uuid = UUID(uuidString: entry.uuid) {
                result[uuid] = entry.name
            }
        }
        return result
    }

    // MARK: - ops.json

    private struct OpsEntry: Codable {
        let uuid: String
    }

    /// Reads `{serverDir}/ops.json` and returns the set of operator UUIDs.
    static func readOps(serverDir: String) -> Set<UUID> {
        let path = URL(fileURLWithPath: serverDir).appendingPathComponent("ops.json").path
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let entries = try? JSONDecoder().decode([OpsEntry].self, from: data) else {
            return []
        }
        return Set(entries.compactMap { UUID(uuidString: $0.uuid) })
    }

    // MARK: - Offline UUID computation

    /// Computes the UUID Minecraft uses for a player in offline (non-authenticated) mode.
    ///
    /// Algorithm matches Java's `UUID.nameUUIDFromBytes`:
    /// 1. MD5 hash of `"OfflinePlayer:{username}"` (UTF-8 bytes)
    /// 2. Set version nibble to 3 (bytes[6] & 0x0f | 0x30)
    /// 3. Set variant bits (bytes[8] & 0x3f | 0x80)
    static func offlineUUID(for username: String) -> UUID {
        let input = Data("OfflinePlayer:\(username)".utf8)
        var h = Array(Insecure.MD5.hash(data: input))
        h[6] = (h[6] & 0x0f) | 0x30   // version 3
        h[8] = (h[8] & 0x3f) | 0x80   // RFC 4122 variant
        return UUID(uuid: (
            h[0], h[1], h[2],  h[3],
            h[4], h[5], h[6],  h[7],
            h[8], h[9], h[10], h[11],
            h[12], h[13], h[14], h[15]
        ))
    }

    // MARK: - File operations

    /// Copies `{sourceUUID}.dat` to `{destUUID}.dat` inside the given playerdata directory.
    /// Overwrites the destination if it already exists.
    static func copyPlayerData(from sourceUUID: UUID, to destUUID: UUID, in playerDataPath: String) throws {
        let fm = FileManager.default
        let src = datPath(for: sourceUUID, in: playerDataPath)
        let dst = datPath(for: destUUID, in: playerDataPath)
        if fm.fileExists(atPath: dst) {
            try fm.removeItem(atPath: dst)
        }
        try fm.copyItem(atPath: src, toPath: dst)
    }

    /// Deletes `{uuid}.dat` from the given playerdata directory.
    static func deletePlayerData(uuid: UUID, in playerDataPath: String) throws {
        try FileManager.default.removeItem(atPath: datPath(for: uuid, in: playerDataPath))
    }

    /// Creates a copy of `{uuid}.dat` under a new random UUID and returns the new UUID.
    static func duplicatePlayerData(uuid: UUID, in playerDataPath: String) throws -> UUID {
        let newUUID = UUID()
        try copyPlayerData(from: uuid, to: newUUID, in: playerDataPath)
        return newUUID
    }

    // MARK: - Internal path helper

    static func datPath(for uuid: UUID, in playerDataPath: String) -> String {
        URL(fileURLWithPath: playerDataPath)
            .appendingPathComponent(uuid.uuidString.lowercased() + ".dat")
            .path
    }
}

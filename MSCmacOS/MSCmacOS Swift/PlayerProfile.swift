//
//  PlayerProfile.swift
//  MinecraftServerController
//
//  Data models for the Java Edition Player Profiles feature.
//

import Foundation

// MARK: - PlayerProfile

/// A player who has ever joined this server, identified by UUID (Java) or XUID (Bedrock).
struct PlayerProfile: Identifiable, Equatable {
    /// Java: the player's Mojang UUID. Bedrock: a random placeholder UUID (used only as
    /// a fallback for mc-heads.net) — update `floodgateUUID` after resolution instead.
    var uuid: UUID
    /// Display name resolved from usercache / Mojang API (Java) or GeyserMC (Bedrock).
    var username: String?
    /// Absolute path to the player's .dat file. Empty string for Bedrock (data is in LevelDB).
    let datFilePath: String
    /// File modification date — proxy for last-seen time.
    let lastModified: Date
    /// True when this player is currently online.
    var isOnline: Bool = false
    /// True when this player appears in ops.json (Java) or has operator permission (Bedrock).
    var isOp: Bool = false
    /// NBT-parsed stats. Nil until loaded (or pre-populated for Bedrock during scan).
    var stats: PlayerStats?
    /// NBT-parsed inventory. Empty until loaded (or pre-populated for Bedrock during scan).
    var inventory: [InventoryItem] = []

    // ── Bedrock-specific ──────────────────────────────────────────────────
    /// Non-nil for Bedrock players. XUID string (e.g. "2535416361514257")
    /// or "local" for the ~local_player entry.
    var xuid: String? = nil
    /// Floodgate UUID resolved via GeyserMC. Used for mc-heads.net image URLs.
    /// Only set after async resolution completes; nil until then.
    var floodgateUUID: UUID? = nil

    // ── Identity ──────────────────────────────────────────────────────────

    /// Stable identifier: XUID-based for Bedrock, UUID string for Java.
    var id: String { xuid.map { "xuid_\($0)" } ?? uuid.uuidString }

    var isBedrockPlayer: Bool { xuid != nil }

    /// The identifier passed to mc-heads.net avatar/body URLs.
    /// Priority: Floodgate UUID → dotted Bedrock gamertag → profile UUID (Java or last-resort).
    var imageIdentifier: String {
        if let floodgate = floodgateUUID {
            return floodgate.uuidString
                .replacingOccurrences(of: "-", with: "")
                .lowercased()
        }
        // Bedrock player without a resolved Floodgate UUID: use the dotted gamertag.
        // mc-heads.net accepts ".GamerTag" for Bedrock avatars.
        if isBedrockPlayer, let name = username, !name.isEmpty {
            return name.hasPrefix(".") ? name : ".\(name)"
        }
        return uuid.uuidString
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
    }

    /// Username if resolved; otherwise the first 8 chars of the UUID (or XUID) followed by "…".
    var displayName: String {
        if let u = username, !u.isEmpty { return u }
        if let x = xuid { return String(x.prefix(8)) + "…" }
        return String(uuid.uuidString.prefix(8)) + "…"
    }
}

// MARK: - PlayerStats

struct PlayerStats: Equatable {
    let health: Float
    let maxHealth: Float
    let foodLevel: Int
    let xpLevel: Int
    let xpTotal: Int
    /// 0 = Survival, 1 = Creative, 2 = Adventure, 3 = Spectator.
    let gameMode: Int
    let posX: Double
    let posY: Double
    let posZ: Double
    let dimension: String
    let score: Int

    var gameModeDisplay: String {
        switch gameMode {
        case 0: return "Survival"
        case 1: return "Creative"
        case 2: return "Adventure"
        case 3: return "Spectator"
        default: return "Unknown (\(gameMode))"
        }
    }

    var dimensionDisplay: String {
        switch dimension {
        case "minecraft:overworld": return "Overworld"
        case "minecraft:the_nether": return "Nether"
        case "minecraft:the_end": return "The End"
        default:
            return dimension.components(separatedBy: ":").last?
                .replacingOccurrences(of: "_", with: " ")
                .capitalized ?? dimension
        }
    }

    var healthFraction: Double {
        guard maxHealth > 0 else { return 0 }
        return Double(min(health, maxHealth)) / Double(maxHealth)
    }

    var foodFraction: Double {
        Double(min(max(foodLevel, 0), 20)) / 20.0
    }
}

// MARK: - InventoryItem

struct InventoryItem: Identifiable, Equatable {
    /// NBT slot number.
    /// 0–8: hotbar, 9–35: main inventory,
    /// 100: boots, 101: leggings, 102: chestplate, 103: helmet, -106: offhand.
    let slot: Int
    /// Full namespaced item ID, e.g. "minecraft:diamond_sword".
    let itemID: String
    let count: Int
    let enchantments: [ItemEnchantment]
    let customName: String?
    /// Current damage value (0 = undamaged).
    let damage: Int

    var id: Int { slot }

    /// Human-readable name: customName if present, else prettified item ID.
    var displayName: String {
        if let n = customName, !n.isEmpty { return n }
        return itemID.components(separatedBy: ":").last?
            .replacingOccurrences(of: "_", with: " ")
            .capitalized ?? itemID
    }

    /// The part of the item ID after the namespace prefix, for icon URL lookups.
    var iconName: String {
        itemID.components(separatedBy: ":").last ?? itemID
    }
}

// MARK: - ItemEnchantment

struct ItemEnchantment: Equatable {
    /// Full namespaced enchantment ID, e.g. "minecraft:sharpness".
    let id: String
    let level: Int

    var displayName: String {
        let name = id.components(separatedBy: ":").last?
            .replacingOccurrences(of: "_", with: " ")
            .capitalized ?? id
        return level <= 5 ? "\(name) \(romanNumeral(level))" : "\(name) \(level)"
    }

    private func romanNumeral(_ n: Int) -> String {
        switch n {
        case 1: return "I"
        case 2: return "II"
        case 3: return "III"
        case 4: return "IV"
        case 5: return "V"
        default: return "\(n)"
        }
    }
}

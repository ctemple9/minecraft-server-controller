//
//  PlayerProfile.swift
//  MinecraftServerController
//
//  Data models for the Java Edition Player Profiles feature.
//

import Foundation

// MARK: - PlayerProfile

/// A player who has ever joined this Java server, identified by their UUID.
struct PlayerProfile: Identifiable, Equatable {
    let uuid: UUID
    /// Display name resolved from usercache.json or Mojang API. Nil while loading or unresolvable.
    var username: String?
    /// Absolute path to the player's .dat file.
    let datFilePath: String
    /// File modification date of the .dat file — proxy for last-seen time.
    let lastModified: Date
    /// True when this UUID matches a currently-online player.
    var isOnline: Bool = false
    /// True when this UUID appears in ops.json.
    var isOp: Bool = false
    /// NBT-parsed stats. Nil until loaded.
    var stats: PlayerStats?
    /// NBT-parsed inventory. Empty until loaded.
    var inventory: [InventoryItem] = []

    var id: String { uuid.uuidString }

    /// Username if resolved; otherwise the first 8 hex chars of the UUID followed by "…".
    var displayName: String {
        if let u = username, !u.isEmpty { return u }
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

//
//  MinecraftCommandRegistry.swift
//  MinecraftServerController
//
//  Static command definitions for Java and Bedrock,
//  plus the suggestion engine that powers autocomplete and the Command Palette.
//

import Foundation
import SwiftUI

// MARK: - Command Argument Slot

/// Describes what kind of value a single positional argument expects.
enum CommandArgSlot {
    case playerName(label: String = "player")
    case keyword(options: [String], label: String)
    case coordinates(label: String = "x y z")
    case integer(label: String)
    case freeText(label: String)

    var label: String {
        switch self {
        case .playerName(let l):    return l
        case .keyword(_, let l):    return l
        case .coordinates(let l):   return l
        case .integer(let l):       return l
        case .freeText(let l):      return l
        }
    }

    var keywordOptions: [String]? {
        if case .keyword(let opts, _) = self { return opts }
        return nil
    }

    var isPlayerName: Bool {
        if case .playerName = self { return true }
        return false
    }

    var isCoordinates: Bool {
        if case .coordinates = self { return true }
        return false
    }

    var isKeyword: Bool {
        if case .keyword = self { return true }
        return false
    }
}

// MARK: - Command Category

enum CommandCategory: String, CaseIterable, Identifiable {
    case players     = "Players"
    case world       = "World"
    case serverAdmin = "Server Admin"
    case gameRules   = "Game Rules"
    case creative    = "Creative"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .players:     return "person.2.fill"
        case .world:       return "globe.americas.fill"
        case .serverAdmin: return "server.rack"
        case .gameRules:   return "slider.horizontal.3"
        case .creative:    return "wand.and.stars"
        }
    }

    var color: Color {
        switch self {
        case .players:     return .blue
        case .world:       return .green
        case .serverAdmin: return .orange
        case .gameRules:   return .purple
        case .creative:    return .pink
        }
    }
}

// MARK: - Command Definition

struct MinecraftCommandDef: Identifiable {
    let name: String
    let description: String
    let category: CommandCategory
    let argumentSlots: [CommandArgSlot]
    let supportsJava: Bool
    let supportsBedrock: Bool

    var id: String { name }
    var hasRequiredArgs: Bool { !argumentSlots.isEmpty }

    var syntaxHint: String {
        let args = argumentSlots.map { "<\($0.label)>" }.joined(separator: " ")
        return args.isEmpty ? "/\(name)" : "/\(name) \(args)"
    }
}

// MARK: - Registry

struct MinecraftCommandRegistry {

    // MARK: All Definitions
    static let all: [MinecraftCommandDef] = [

        // MARK: Players
        .init(name: "tp",
              description: "Teleport a player to another player or to coordinates",
              category: .players,
              argumentSlots: [
                  .playerName(label: "target player"),
                  .playerName(label: "destination player")
              ],
              supportsJava: true, supportsBedrock: true),

        .init(name: "teleport",
              description: "Alias for tp — teleport to player or coordinates",
              category: .players,
              argumentSlots: [
                  .playerName(label: "target player"),
                  .coordinates(label: "destination x y z")
              ],
              supportsJava: true, supportsBedrock: true),

        .init(name: "give",
              description: "Give a player one or more items",
              category: .players,
              argumentSlots: [
                  .playerName(),
                  .freeText(label: "item id (e.g. diamond_sword)"),
                  .integer(label: "count")
              ],
              supportsJava: true, supportsBedrock: true),

        .init(name: "kick",
              description: "Remove a player from the server",
              category: .players,
              argumentSlots: [
                  .playerName(),
                  .freeText(label: "reason (optional)")
              ],
              supportsJava: true, supportsBedrock: true),

        .init(name: "ban",
              description: "Permanently ban a player by name",
              category: .players,
              argumentSlots: [
                  .playerName(),
                  .freeText(label: "reason (optional)")
              ],
              supportsJava: true, supportsBedrock: false),

        .init(name: "ban-ip",
              description: "Ban a player by IP address",
              category: .players,
              argumentSlots: [.freeText(label: "ip address or player name")],
              supportsJava: true, supportsBedrock: false),

        .init(name: "pardon",
              description: "Unban a previously banned player",
              category: .players,
              argumentSlots: [.playerName()],
              supportsJava: true, supportsBedrock: false),

        .init(name: "op",
              description: "Grant operator (admin) status to a player",
              category: .players,
              argumentSlots: [.playerName()],
              supportsJava: true, supportsBedrock: true),

        .init(name: "deop",
              description: "Revoke operator status from a player",
              category: .players,
              argumentSlots: [.playerName()],
              supportsJava: true, supportsBedrock: true),

        .init(name: "msg",
              description: "Send a private message to a player",
              category: .players,
              argumentSlots: [
                  .playerName(),
                  .freeText(label: "message")
              ],
              supportsJava: true, supportsBedrock: true),

        .init(name: "tell",
              description: "Alias for msg — send a private message",
              category: .players,
              argumentSlots: [
                  .playerName(),
                  .freeText(label: "message")
              ],
              supportsJava: true, supportsBedrock: true),

        .init(name: "kill",
              description: "Kill a player or entity",
              category: .players,
              argumentSlots: [.playerName()],
              supportsJava: true, supportsBedrock: true),

        .init(name: "gamemode",
              description: "Change a player's game mode",
              category: .players,
              argumentSlots: [
                  .keyword(options: ["survival", "creative", "adventure", "spectator"], label: "mode"),
                  .playerName(label: "player (optional)")
              ],
              supportsJava: true, supportsBedrock: true),

        .init(name: "effect",
              description: "Apply a status effect to a player",
              category: .players,
              argumentSlots: [
                  .playerName(),
                  .freeText(label: "effect id (e.g. speed, jump_boost)"),
                  .integer(label: "duration (seconds)"),
                  .integer(label: "amplifier (0 = level I)")
              ],
              supportsJava: true, supportsBedrock: true),

        .init(name: "xp",
              description: "Give experience points or levels to a player",
              category: .players,
              argumentSlots: [
                  .freeText(label: "amount (use L suffix for levels, e.g. 5L)"),
                  .playerName()
              ],
              supportsJava: true, supportsBedrock: false),

        .init(name: "experience",
              description: "Add or set experience points or levels",
              category: .players,
              argumentSlots: [
                  .keyword(options: ["add", "set", "query"], label: "action"),
                  .playerName(),
                  .integer(label: "amount"),
                  .keyword(options: ["points", "levels"], label: "type")
              ],
              supportsJava: true, supportsBedrock: false),

        .init(name: "clear",
              description: "Clear a player's inventory or a specific item",
              category: .players,
              argumentSlots: [
                  .playerName(),
                  .freeText(label: "item (optional)")
              ],
              supportsJava: true, supportsBedrock: true),

        // MARK: World
        .init(name: "time",
              description: "Set, add, or query the world time",
              category: .world,
              argumentSlots: [
                  .keyword(options: ["set", "add", "query"], label: "action"),
                  .freeText(label: "value or day/night/noon/midnight")
              ],
              supportsJava: true, supportsBedrock: true),

        .init(name: "weather",
              description: "Change the current weather",
              category: .world,
              argumentSlots: [
                  .keyword(options: ["clear", "rain", "thunder"], label: "type")
              ],
              supportsJava: true, supportsBedrock: true),

        .init(name: "difficulty",
              description: "Set the game difficulty",
              category: .world,
              argumentSlots: [
                  .keyword(options: ["peaceful", "easy", "normal", "hard"], label: "level")
              ],
              supportsJava: true, supportsBedrock: true),

        .init(name: "gamerule",
              description: "Set or query a game rule",
              category: .world,
              argumentSlots: [
                  .freeText(label: "rule name"),
                  .freeText(label: "value (omit to query)")
              ],
              supportsJava: true, supportsBedrock: true),

        .init(name: "setworldspawn",
              description: "Set the world spawn point",
              category: .world,
              argumentSlots: [.coordinates()],
              supportsJava: true, supportsBedrock: true),

        .init(name: "spawnpoint",
              description: "Set a player's personal spawn point",
              category: .world,
              argumentSlots: [
                  .playerName(),
                  .coordinates()
              ],
              supportsJava: true, supportsBedrock: true),

        // MARK: Server Admin
        .init(name: "list",
              description: "List all currently online players",
              category: .serverAdmin,
              argumentSlots: [],
              supportsJava: true, supportsBedrock: true),

        .init(name: "seed",
              description: "Display the current world seed",
              category: .serverAdmin,
              argumentSlots: [],
              supportsJava: true, supportsBedrock: true),

        .init(name: "say",
              description: "Broadcast a message to all players",
              category: .serverAdmin,
              argumentSlots: [.freeText(label: "message")],
              supportsJava: true, supportsBedrock: true),

        .init(name: "title",
              description: "Display a title on screen for a player",
              category: .serverAdmin,
              argumentSlots: [
                  .playerName(),
                  .keyword(options: ["title", "subtitle", "actionbar", "clear", "reset"], label: "type"),
                  .freeText(label: "text (omit for clear/reset)")
              ],
              supportsJava: true, supportsBedrock: true),

        .init(name: "save-all",
              description: "Force save all loaded chunks to disk",
              category: .serverAdmin,
              argumentSlots: [],
              supportsJava: true, supportsBedrock: false),

        .init(name: "save-off",
              description: "Disable automatic chunk saving",
              category: .serverAdmin,
              argumentSlots: [],
              supportsJava: true, supportsBedrock: false),

        .init(name: "save-on",
              description: "Re-enable automatic chunk saving",
              category: .serverAdmin,
              argumentSlots: [],
              supportsJava: true, supportsBedrock: false),

        .init(name: "reload",
              description: "Reload server configuration and plugins",
              category: .serverAdmin,
              argumentSlots: [],
              supportsJava: true, supportsBedrock: false),

        .init(name: "stop",
              description: "Gracefully stop the server",
              category: .serverAdmin,
              argumentSlots: [],
              supportsJava: true, supportsBedrock: true),

        .init(name: "whitelist",
              description: "Manage the server whitelist",
              category: .serverAdmin,
              argumentSlots: [
                  .keyword(options: ["on", "off", "add", "remove", "list", "reload"], label: "action"),
                  .playerName(label: "player (for add/remove)")
              ],
              supportsJava: true, supportsBedrock: true),

        .init(name: "banlist",
              description: "Display the current ban list",
              category: .serverAdmin,
              argumentSlots: [
                  .keyword(options: ["players", "ips"], label: "type (optional)")
              ],
              supportsJava: true, supportsBedrock: false),

        // MARK: Game Rules
        .init(name: "enchant",
              description: "Enchant the item in a player's hand",
              category: .gameRules,
              argumentSlots: [
                  .playerName(),
                  .freeText(label: "enchantment id"),
                  .integer(label: "level")
              ],
              supportsJava: true, supportsBedrock: true),

        .init(name: "attribute",
              description: "Query or modify an entity attribute",
              category: .gameRules,
              argumentSlots: [
                  .playerName(),
                  .freeText(label: "attribute name")
              ],
              supportsJava: true, supportsBedrock: false),

        // MARK: Creative / Building
        .init(name: "setblock",
              description: "Place a specific block at given coordinates",
              category: .creative,
              argumentSlots: [
                  .coordinates(),
                  .freeText(label: "block id")
              ],
              supportsJava: true, supportsBedrock: true),

        .init(name: "fill",
              description: "Fill a region with a block type",
              category: .creative,
              argumentSlots: [
                  .coordinates(label: "from x y z"),
                  .coordinates(label: "to x y z"),
                  .freeText(label: "block id")
              ],
              supportsJava: true, supportsBedrock: true),

        .init(name: "clone",
              description: "Copy a region of blocks to another location",
              category: .creative,
              argumentSlots: [
                  .coordinates(label: "from x y z"),
                  .coordinates(label: "to x y z"),
                  .coordinates(label: "destination x y z")
              ],
              supportsJava: true, supportsBedrock: true),

        .init(name: "summon",
              description: "Spawn an entity at given coordinates",
              category: .creative,
              argumentSlots: [
                  .freeText(label: "entity id"),
                  .coordinates()
              ],
              supportsJava: true, supportsBedrock: true),

        .init(name: "particle",
              description: "Create a particle effect at coordinates",
              category: .creative,
              argumentSlots: [
                  .freeText(label: "particle name"),
                  .coordinates()
              ],
              supportsJava: true, supportsBedrock: false),
    ]

    // MARK: Filtered by Server Type

    static func commands(for serverType: ServerType) -> [MinecraftCommandDef] {
        switch serverType {
        case .java:    return all.filter { $0.supportsJava }
        case .bedrock: return all.filter { $0.supportsBedrock }
        }
    }

    // MARK: Autocomplete Suggestion Engine

    /// Returns up to 6 suggested completions for the current command-line input.
    /// - Typing a command name prefix: suggests matching command names.
    /// - In argument position: suggests players (for playerName slots) or keywords.
    static func suggestions(
        for input: String,
        serverType: ServerType,
        onlinePlayers: [OnlinePlayer]
    ) -> [String] {
        guard !input.isEmpty else { return [] }

        let tokens = input.split(separator: " ", omittingEmptySubsequences: false)
        let endsWithSpace = input.last == " "
        let available = commands(for: serverType)

        // Token 0 — still completing the command name
        if tokens.count == 1 && !endsWithSpace {
            let raw = String(tokens[0])
            let prefix = raw.hasPrefix("/") ? String(raw.dropFirst()) : raw
            if prefix.isEmpty { return [] }
            return available
                .filter { $0.name.hasPrefix(prefix.lowercased()) }
                .prefix(6)
                .map { "/\($0.name)" }
        }

        // Token 1+ — completing an argument
        let rawCommand = String(tokens[0])
        let commandName = rawCommand.hasPrefix("/") ? String(rawCommand.dropFirst()) : rawCommand
        guard let def = available.first(where: { $0.name == commandName }) else { return [] }
        guard !def.argumentSlots.isEmpty else { return [] }

        // Determine which slot index we're filling
        // If input ends with space, we're starting a new slot (next index)
        let filledTokens = tokens.dropFirst()
        let slotIndex = endsWithSpace ? filledTokens.count : max(0, filledTokens.count - 1)
        guard slotIndex < def.argumentSlots.count else { return [] }

        let slot = def.argumentSlots[slotIndex]
        let partialArg: String
        if endsWithSpace {
            partialArg = ""
        } else {
            partialArg = filledTokens.isEmpty ? "" : String(filledTokens.last ?? "")
        }
        let partial = partialArg.lowercased()

        // Build a prefix from the tokens we already have (up to and not including the current partial)
        let baseTokens: [String]
        if endsWithSpace {
            baseTokens = tokens.map { String($0) }
        } else {
            baseTokens = tokens.dropLast().map { String($0) }
        }
        let base = baseTokens.joined(separator: " ")

        switch slot {
        case .playerName:
            let filtered = onlinePlayers
                .filter { partial.isEmpty || $0.name.lowercased().hasPrefix(partial) }
                .prefix(6)
            return filtered.map { "\(base) \($0.name)" }

        case .keyword(let options, _):
            let filtered = options
                .filter { partial.isEmpty || $0.lowercased().hasPrefix(partial) }
                .prefix(6)
            return filtered.map { "\(base) \($0)" }

        default:
            return []
        }
    }
}

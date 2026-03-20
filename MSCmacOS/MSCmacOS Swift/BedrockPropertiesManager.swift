//
//  BedrockPropertiesManager.swift
//  MinecraftServerController
//
//
//  Responsibilities:
//    - Read/write BDS server.properties (different key names from Java)
//    - Read/write allowlist.json  (array of BedrockAllowlistEntry)
//    - Read/write permissions.json (array of BedrockPermissionsEntry)
//
//  Pattern mirrors ServerPropertiesManager so the rest of the codebase
//  has a consistent mental model for both backends.
//

import Foundation

// MARK: - BDS server.properties model

/// Typed representation of the fields MSC surfaces from a BDS server.properties file.
/// Only the keys the app cares about are included; all others are preserved on round-trip
/// via the raw dictionary in BedrockPropertiesManager.readProperties(serverDir:).
struct BedrockPropertiesModel {
    // General
    var levelName: String       = "Bedrock level"
    var maxPlayers: Int         = 10
    var onlineMode: Bool        = true
    var allowCheats: Bool       = false

    // Gameplay
    var difficulty: ServerDifficulty = .easy
    var gamemode: ServerGamemode     = .survival

    // Network
    var serverPort: Int         = 19132
    var serverPortV6: Int       = 19133
}

// MARK: - allowlist.json model

/// One entry in allowlist.json.
/// `xuid` may be absent in older files or when added by name only; we preserve it when
/// present and omit it when nil to avoid writing a null into the JSON.
struct BedrockAllowlistEntry: Codable, Identifiable {
    // Identifiable for SwiftUI lists
    var id: String { name }

    var name: String
    var xuid: String?
    var ignoresPlayerLimit: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case xuid
        case ignoresPlayerLimit
    }

    // Custom decode so a missing xuid doesn't cause failure on older files.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name               = try c.decode(String.self, forKey: .name)
        xuid               = try c.decodeIfPresent(String.self, forKey: .xuid)
        ignoresPlayerLimit = try c.decodeIfPresent(Bool.self, forKey: .ignoresPlayerLimit) ?? false
    }

    init(name: String, xuid: String? = nil, ignoresPlayerLimit: Bool = false) {
        self.name               = name
        self.xuid               = xuid
        self.ignoresPlayerLimit = ignoresPlayerLimit
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(xuid, forKey: .xuid)
        try c.encode(ignoresPlayerLimit, forKey: .ignoresPlayerLimit)
    }
}

// MARK: - permissions.json model

/// Permission level values that BDS accepts.
enum BedrockPermissionLevel: String, Codable, CaseIterable {
    case visitor
    case member
    case operator_ = "operator"

    var displayName: String {
        switch self {
        case .visitor:   return "Visitor"
        case .member:    return "Member"
        case .operator_: return "Operator"
        }
    }
}

/// One entry in permissions.json.
struct BedrockPermissionsEntry: Codable, Identifiable {
    // XUID is the stable identifier; we use it as the list ID.
    var id: String { xuid }

    var permission: BedrockPermissionLevel
    var xuid: String

    enum CodingKeys: String, CodingKey {
        case permission
        case xuid
    }
}

// MARK: - BedrockPropertiesManager

struct BedrockPropertiesManager {

    // MARK: server.properties

    static func propertiesURL(for serverDir: String) -> URL {
        URL(fileURLWithPath: serverDir, isDirectory: true)
            .appendingPathComponent("server.properties")
    }

    /// Read the raw key=value dictionary from BDS server.properties.
    /// Returns an empty dict if the file does not exist yet.
    static func readRawProperties(serverDir: String) -> [String: String] {
        let url = propertiesURL(for: serverDir)
        guard let contents = try? String(contentsOf: url) else { return [:] }

        var dict: [String: String] = [:]
        for line in contents.split(whereSeparator: \.isNewline) {
            let raw     = String(line)
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            guard let idx = trimmed.firstIndex(of: "=") else { continue }
            let key   = trimmed[..<idx].trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: idx)...].trimmingCharacters(in: .whitespaces)
            dict[key] = value
        }
        return dict
    }

    /// Map the raw dictionary into a typed BedrockPropertiesModel.
    /// Unknown or missing keys fall back to the model's declared defaults.
    static func readModel(serverDir: String) -> BedrockPropertiesModel {
        let raw = readRawProperties(serverDir: serverDir)
        var m   = BedrockPropertiesModel()

        if let v = raw["level-name"]  { m.levelName    = v }
        if let v = raw["max-players"], let i = Int(v) { m.maxPlayers  = i }
        if let v = raw["online-mode"] { m.onlineMode   = (v == "true") }
        if let v = raw["allow-cheats"] { m.allowCheats = (v == "true") }
        if let v = raw["server-port"],  let i = Int(v) { m.serverPort   = i }
        if let v = raw["server-portv6"], let i = Int(v) { m.serverPortV6 = i }

        if let v = raw["difficulty"] {
            switch v {
            case "peaceful": m.difficulty = .peaceful
            case "easy":     m.difficulty = .easy
            case "normal":   m.difficulty = .normal
            case "hard":     m.difficulty = .hard
            default:         break
            }
        }

        if let v = raw["gamemode"] {
            switch v {
            case "survival":  m.gamemode = .survival
            case "creative":  m.gamemode = .creative
            case "adventure": m.gamemode = .adventure
            case "spectator": m.gamemode = .spectator
            default:          break
            }
        }

        return m
    }

    /// Merge the typed model back into the raw dictionary and write to disk.
    /// Keys not touched by the model are preserved verbatim (round-trip safety).
    static func writeModel(_ model: BedrockPropertiesModel, serverDir: String) throws {
        var raw = readRawProperties(serverDir: serverDir)

        raw["level-name"]    = model.levelName
        raw["max-players"]   = String(model.maxPlayers)
        raw["online-mode"]   = model.onlineMode ? "true" : "false"
        raw["allow-cheats"]  = model.allowCheats ? "true" : "false"
        raw["server-port"]   = String(model.serverPort)
        raw["server-portv6"] = String(model.serverPortV6)
        raw["difficulty"]    = model.difficulty.bdsKey
        raw["gamemode"]      = model.gamemode.bdsKey

        try writeRawProperties(raw, serverDir: serverDir)
    }

    /// Write a raw key=value dictionary back to server.properties.
    static func writeRawProperties(_ props: [String: String], serverDir: String) throws {
        let url = propertiesURL(for: serverDir)
        var out = "# Modified via MinecraftServerController\n"
        // Sort for deterministic output (easier to diff).
        for key in props.keys.sorted() {
            out += "\(key)=\(props[key]!)\n"
        }
        try out.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: allowlist.json

    static func allowlistURL(for serverDir: String) -> URL {
        URL(fileURLWithPath: serverDir, isDirectory: true)
            .appendingPathComponent("allowlist.json")
    }

    /// Read allowlist.json. Returns an empty array if the file is absent or unreadable.
    static func readAllowlist(serverDir: String) -> [BedrockAllowlistEntry] {
        let url = allowlistURL(for: serverDir)
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([BedrockAllowlistEntry].self, from: data)) ?? []
    }

    /// Write the full allowlist back to allowlist.json (atomic write).
    static func writeAllowlist(_ entries: [BedrockAllowlistEntry], serverDir: String) throws {
        let url = allowlistURL(for: serverDir)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entries)
        try data.write(to: url, options: .atomic)
    }

    /// Add a player to the allowlist. If a player with the same name already exists,
    /// this is a no-op (case-insensitive match).
    static func addToAllowlist(name: String, xuid: String? = nil, serverDir: String) throws {
        var list = readAllowlist(serverDir: serverDir)
        let alreadyPresent = list.contains { $0.name.lowercased() == name.lowercased() }
        guard !alreadyPresent else { return }
        list.append(BedrockAllowlistEntry(name: name, xuid: xuid))
        try writeAllowlist(list, serverDir: serverDir)
    }

    /// Remove a player from the allowlist by name (case-insensitive).
    static func removeFromAllowlist(name: String, serverDir: String) throws {
        var list = readAllowlist(serverDir: serverDir)
        list.removeAll { $0.name.lowercased() == name.lowercased() }
        try writeAllowlist(list, serverDir: serverDir)
    }

    // MARK: permissions.json

    static func permissionsURL(for serverDir: String) -> URL {
        URL(fileURLWithPath: serverDir, isDirectory: true)
            .appendingPathComponent("permissions.json")
    }

    /// Read permissions.json. Returns an empty array if the file is absent or unreadable.
    static func readPermissions(serverDir: String) -> [BedrockPermissionsEntry] {
        let url = permissionsURL(for: serverDir)
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([BedrockPermissionsEntry].self, from: data)) ?? []
    }

    /// Write the full permissions list back to permissions.json (atomic write).
    static func writePermissions(_ entries: [BedrockPermissionsEntry], serverDir: String) throws {
        let url = permissionsURL(for: serverDir)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entries)
        try data.write(to: url, options: .atomic)
    }

    /// Set a player's permission level by XUID. Adds the entry if not present,
    /// updates it if already there.
    static func setPermission(xuid: String, level: BedrockPermissionLevel, serverDir: String) throws {
        var list = readPermissions(serverDir: serverDir)
        if let idx = list.firstIndex(where: { $0.xuid == xuid }) {
            list[idx] = BedrockPermissionsEntry(permission: level, xuid: xuid)
        } else {
            list.append(BedrockPermissionsEntry(permission: level, xuid: xuid))
        }
        try writePermissions(list, serverDir: serverDir)
    }

    /// Remove a player's explicit permission entry by XUID (they revert to default/member).
    static func removePermission(xuid: String, serverDir: String) throws {
        var list = readPermissions(serverDir: serverDir)
        list.removeAll { $0.xuid == xuid }
        try writePermissions(list, serverDir: serverDir)
    }
}

// MARK: - ServerDifficulty / ServerGamemode BDS key extensions
//
// BDS server.properties uses lowercase string values identical to Java in most cases,
// but we centralise the mapping here so it's explicit and not scattered through
// BedrockPropertiesManager.

extension ServerDifficulty {
    /// The raw string value BDS expects in server.properties.
    var bdsKey: String {
        switch self {
        case .peaceful: return "peaceful"
        case .easy:     return "easy"
        case .normal:   return "normal"
        case .hard:     return "hard"
        }
    }
}

extension ServerGamemode {
    /// The raw string value BDS expects in server.properties.
    var bdsKey: String {
        switch self {
        case .survival:  return "survival"
        case .creative:  return "creative"
        case .adventure: return "adventure"
        case .spectator: return "spectator"
        }
    }
}

import Foundation

// MARK: - Models

/// Status of a single transport (playit / Xbox broadcast) during first-time
/// server initiation (pass 2). A transport is "resolved" once it is confirmed
/// ready, has failed/timed out, was skipped by the user, or isn't applicable.
enum InitiationTransportStatus: Equatable {
    case notApplicable   // transport not enabled — not awaited
    case waiting         // coming up
    case ready           // confirmed up
    case failed          // timed out or errored
    case skipped         // user skipped

    /// Whether the orchestrator no longer needs to wait on this transport.
    var isResolved: Bool {
        switch self {
        case .notApplicable, .ready, .failed, .skipped: return true
        case .waiting: return false
        }
    }
}

/// Difficulty options supported by Minecraft's `server.properties` and surfaced in the UI.
enum ServerDifficulty: String, CaseIterable, Identifiable {
    case peaceful
    case easy
    case normal
    case hard

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }
}

/// Gamemode options supported by Minecraft's `server.properties` and surfaced in the UI.
enum ServerGamemode: String, CaseIterable, Identifiable {
    case survival
    case creative
    case adventure
    case spectator

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }
}

/// World type for `level-type` in server.properties.
/// Raw values match the modern namespaced format (e.g. `minecraft\:normal` in the file).
enum LevelType: String, CaseIterable, Identifiable {
    case normal      = "minecraft\\:normal"
    case flat        = "minecraft\\:flat"
    case largeBiomes = "minecraft\\:large_biomes"
    case amplified   = "minecraft\\:amplified"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .normal:      return "Normal"
        case .flat:        return "Flat"
        case .largeBiomes: return "Large Biomes"
        case .amplified:   return "Amplified"
        }
    }

    /// Parses both the modern namespaced format and the legacy ALL-CAPS format.
    static func from(_ raw: String) -> LevelType {
        let lower = raw.lowercased().replacingOccurrences(of: "\\:", with: ":")
        switch lower {
        case "minecraft:flat",         "flat":                      return .flat
        case "minecraft:large_biomes", "largebiomes", "large_biomes": return .largeBiomes
        case "minecraft:amplified",    "amplified":                  return .amplified
        default:                                                     return .normal
        }
    }
}

/// Editable representation of `server.properties` with round-trip preservation of unknown keys.
///
/// Note: `bedrockPort` is sourced from Geyser's config, not `server.properties`.
struct ServerPropertiesModel: Equatable {
    // Server identity
    var motd: String
    var maxPlayers: Int
    var onlineMode: Bool
    var serverPort: Int

    /// Bedrock/Geyser listener port (plugins/Geyser-Spigot/config.yml → bedrock.port)
    /// nil = not set / not found (do NOT default)
    var bedrockPort: Int? = nil

    // World
    var difficulty: ServerDifficulty
    var gamemode: ServerGamemode
    var hardcore: Bool
    var pvp: Bool
    var allowNether: Bool
    var allowFlight: Bool
    var forceGamemode: Bool
    var spawnMonsters: Bool
    var spawnAnimals: Bool
    var spawnNpcs: Bool
    var spawnProtection: Int
    var levelType: LevelType

    // Performance / visibility
    var viewDistance: Int
    var simulationDistance: Int

    // Player management
    var whitelist: Bool
    var enforceWhitelist: Bool
    var playerIdleTimeout: Int
    var opPermissionLevel: Int

    /// Raw properties dictionary so we can preserve unknown keys.
    var rawProperties: [String: String]

    init(
        motd: String,
        maxPlayers: Int,
        onlineMode: Bool,
        serverPort: Int,
        bedrockPort: Int? = nil,
        difficulty: ServerDifficulty,
        gamemode: ServerGamemode,
        hardcore: Bool,
        pvp: Bool,
        allowNether: Bool,
        allowFlight: Bool,
        forceGamemode: Bool,
        spawnMonsters: Bool,
        spawnAnimals: Bool,
        spawnNpcs: Bool,
        spawnProtection: Int,
        levelType: LevelType,
        viewDistance: Int,
        simulationDistance: Int,
        whitelist: Bool,
        enforceWhitelist: Bool,
        playerIdleTimeout: Int,
        opPermissionLevel: Int,
        rawProperties: [String: String] = [:]
    ) {
        self.motd               = motd
        self.maxPlayers         = maxPlayers
        self.onlineMode         = onlineMode
        self.serverPort         = serverPort
        self.bedrockPort        = bedrockPort
        self.difficulty         = difficulty
        self.gamemode           = gamemode
        self.hardcore           = hardcore
        self.pvp                = pvp
        self.allowNether        = allowNether
        self.allowFlight        = allowFlight
        self.forceGamemode      = forceGamemode
        self.spawnMonsters      = spawnMonsters
        self.spawnAnimals       = spawnAnimals
        self.spawnNpcs          = spawnNpcs
        self.spawnProtection    = spawnProtection
        self.levelType          = levelType
        self.viewDistance       = viewDistance
        self.simulationDistance = simulationDistance
        self.whitelist          = whitelist
        self.enforceWhitelist   = enforceWhitelist
        self.playerIdleTimeout  = playerIdleTimeout
        self.opPermissionLevel  = opPermissionLevel
        self.rawProperties      = rawProperties
    }

    /// Build from a raw `[String: String]` dictionary with sane defaults.
    /// Note: bedrockPort is not in server.properties; we leave it nil here and
    /// let the caller (AppViewModel) overlay the real/persisted value if present.
    init(from dict: [String: String], fallbackMotd: String? = nil) {
        self.rawProperties = dict

        func intVal(_ key: String, default d: Int) -> Int {
            guard let s = dict[key], let v = Int(s.trimmingCharacters(in: .whitespaces)) else { return d }
            return v
        }
        func boolVal(_ key: String, default d: Bool) -> Bool {
            switch dict[key]?.trimmingCharacters(in: .whitespaces).lowercased() {
            case "true":  return true
            case "false": return false
            default:      return d
            }
        }

        motd               = dict["motd"] ?? fallbackMotd ?? "A Minecraft Server"
        maxPlayers         = intVal("max-players",         default: 20)
        onlineMode         = boolVal("online-mode",        default: true)
        serverPort         = intVal("server-port",         default: 25565)
        bedrockPort        = nil

        if let raw = dict["difficulty"]?.trimmingCharacters(in: .whitespaces).lowercased(),
           let d = ServerDifficulty(rawValue: raw) { difficulty = d } else { difficulty = .normal }

        if let raw = dict["gamemode"]?.trimmingCharacters(in: .whitespaces).lowercased(),
           let g = ServerGamemode(rawValue: raw) { gamemode = g } else { gamemode = .survival }

        hardcore           = boolVal("hardcore",           default: false)
        pvp                = boolVal("pvp",                default: true)
        allowNether        = boolVal("allow-nether",       default: true)
        allowFlight        = boolVal("allow-flight",       default: false)
        forceGamemode      = boolVal("force-gamemode",     default: false)
        spawnMonsters      = boolVal("spawn-monsters",     default: true)
        spawnAnimals       = boolVal("spawn-animals",      default: true)
        spawnNpcs          = boolVal("spawn-npcs",         default: true)
        spawnProtection    = intVal("spawn-protection",    default: 16)
        levelType          = LevelType.from(dict["level-type"] ?? "")
        viewDistance       = intVal("view-distance",       default: 10)
        simulationDistance = intVal("simulation-distance", default: 10)
        whitelist          = boolVal("white-list",         default: false)
        enforceWhitelist   = boolVal("enforce-whitelist",  default: false)
        playerIdleTimeout  = intVal("player-idle-timeout", default: 0)
        opPermissionLevel  = intVal("op-permission-level", default: 4)
    }

    /// Returns a new dictionary with this model's values overlaid on top of an
    /// existing dictionary, preserving unknown keys.
    ///
    /// Note: Bedrock port lives in Geyser's config.yml and is not stored in server.properties.
    func mergedInto(_ existing: [String: String]) -> [String: String] {
        var r = existing
        r["motd"]                = motd
        r["max-players"]         = String(maxPlayers)
        r["online-mode"]         = onlineMode    ? "true" : "false"
        r["server-port"]         = String(serverPort)
        r["difficulty"]          = difficulty.rawValue
        r["gamemode"]            = gamemode.rawValue
        r["hardcore"]            = hardcore       ? "true" : "false"
        r["pvp"]                 = pvp            ? "true" : "false"
        r["allow-nether"]        = allowNether    ? "true" : "false"
        r["allow-flight"]        = allowFlight    ? "true" : "false"
        r["force-gamemode"]      = forceGamemode  ? "true" : "false"
        r["spawn-monsters"]      = spawnMonsters  ? "true" : "false"
        r["spawn-animals"]       = spawnAnimals   ? "true" : "false"
        r["spawn-npcs"]          = spawnNpcs      ? "true" : "false"
        r["spawn-protection"]    = String(spawnProtection)
        r["level-type"]          = levelType.rawValue
        r["view-distance"]       = String(viewDistance)
        r["simulation-distance"] = String(simulationDistance)
        r["white-list"]          = whitelist       ? "true" : "false"
        r["enforce-whitelist"]   = enforceWhitelist ? "true" : "false"
        r["player-idle-timeout"] = String(playerIdleTimeout)
        r["op-permission-level"] = String(opPermissionLevel)
        return r
    }
}

/// Snapshot of “quick command” settings used by the UI to apply common server changes.
struct QuickCommandsModel {
    var difficulty: ServerDifficulty
    var gamemode: ServerGamemode
    var whitelistEnabled: Bool
}

// MARK: - Console models

/// Tabs used to filter the console view.
enum ConsoleTab: String, CaseIterable, Identifiable {
    case all = "All"
    case server = "Server"
    case plugins = "Plugins"
    case warnings = "Warnings"
    case controller = "Controller"
    case commands = "Commands"
    case custom = "Custom"

    var id: String { rawValue }
    var displayName: String { rawValue }
}

/// Origin of a console entry (server process vs. controller/app).
enum ConsoleSource: String, Hashable {
    case server
    case controller
}

/// Severity bucket used for filtering/highlighting console output.
enum ConsoleLevel: String, Hashable {
    case info
    case warn
    case error
    case other
}

/// A structured console line with metadata used for display and filtering.
struct ConsoleEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    let raw: String
    let source: ConsoleSource
    let level: ConsoleLevel
    let tag: String?          // e.g. "Geyser-Spigot", "floodgate", "App", "Remote API", etc.
    let isAuto: Bool
    let createdAt: Date

    init(raw: String, source: ConsoleSource, level: ConsoleLevel, tag: String?, isAuto: Bool, createdAt: Date = Date()) {
        self.id = UUID()
        self.raw = raw
        self.source = source
        self.level = level
        self.tag = tag
        self.isAuto = isAuto
        self.createdAt = createdAt
    }
}

/// A currently connected player shown in the UI.
struct OnlinePlayer: Identifiable, Hashable {
    let name: String
    let xuid: String?

    var id: String { xuid ?? name }

    init(name: String, xuid: String? = nil) {
        self.name = name
        self.xuid = xuid
    }
}

/// Source of the Paper JAR used by the “Create Server” flow.
enum CreateServerJarSource {
    case template(URL)     // use an existing Paper template JAR
    case downloadLatest    // download the latest Paper build
}

/// User-entered settings gathered during the “Create Server” flow.
struct ServerSettingsData: Identifiable {
    let id = UUID()
    var port: String
    var motd: String
    var maxPlayers: String
    var onlineMode: Bool

    // Geyser
    var bedrockAddress: String
    var bedrockPort: String
}

/// Editable snapshot of user preferences shown in PreferencesView.
struct PreferencesModel {
    var serversRoot: String
    var javaPath: String
    var extraFlags: String
    var duckdnsHostname: String
}


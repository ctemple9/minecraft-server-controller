import Foundation

// MARK: - Models

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

/// Editable representation of `server.properties` with round-trip preservation of unknown keys.
///
/// Note: `bedrockPort` is sourced from Geyser's config, not `server.properties`.
struct ServerPropertiesModel {
    var motd: String
    var maxPlayers: Int
    var difficulty: ServerDifficulty
    var gamemode: ServerGamemode
    var viewDistance: Int
    var onlineMode: Bool
    var serverPort: Int

    /// Bedrock/Geyser listener port (plugins/Geyser-Spigot/config.yml → bedrock.port)
    /// nil = not set / not found (do NOT default)
    var bedrockPort: Int? = nil

    /// Raw properties dictionary so we can preserve unknown keys.
    var rawProperties: [String: String]

    init(
        motd: String,
        maxPlayers: Int,
        difficulty: ServerDifficulty,
        gamemode: ServerGamemode,
        viewDistance: Int,
        onlineMode: Bool,
        serverPort: Int,
        bedrockPort: Int? = nil,
        rawProperties: [String: String] = [:]
    ) {
        self.motd = motd
        self.maxPlayers = maxPlayers
        self.difficulty = difficulty
        self.gamemode = gamemode
        self.viewDistance = viewDistance
        self.onlineMode = onlineMode
        self.serverPort = serverPort
        self.bedrockPort = bedrockPort
        self.rawProperties = rawProperties
    }

    /// Build from a raw `[String: String]` dictionary with sane defaults.
    /// Note: bedrockPort is not in server.properties; we leave it nil here and
    /// let the caller (AppViewModel) overlay the real/persisted value if present.
    init(from dict: [String: String], fallbackMotd: String? = nil) {
        self.rawProperties = dict

        // Defaults
        let defaultMotd = fallbackMotd ?? "A Minecraft Server"
        let defaultMaxPlayers = 20
        let defaultViewDistance = 10
        let defaultOnlineMode = true
        let defaultPort = 25565
        

        func intValue(forKey key: String, default def: Int) -> Int {
            if let value = dict[key],
               let intVal = Int(value.trimmingCharacters(in: .whitespaces)) {
                return intVal
            }
            return def
        }

        func boolValue(forKey key: String, default def: Bool) -> Bool {
            if let value = dict[key]?.trimmingCharacters(in: .whitespaces).lowercased() {
                if value == "true" { return true }
                if value == "false" { return false }
            }
            return def
        }

        // motd
        self.motd = dict["motd"] ?? defaultMotd

        // max-players
        self.maxPlayers = intValue(forKey: "max-players", default: defaultMaxPlayers)

        // difficulty
        if let rawDiff = dict["difficulty"]?.trimmingCharacters(in: .whitespaces).lowercased(),
           let parsed = ServerDifficulty(rawValue: rawDiff) {
            self.difficulty = parsed
        } else {
            self.difficulty = .normal
        }

        // gamemode
        if let rawGM = dict["gamemode"]?.trimmingCharacters(in: .whitespaces).lowercased(),
           let parsed = ServerGamemode(rawValue: rawGM) {
            self.gamemode = parsed
        } else {
            self.gamemode = .survival
        }

        // view-distance
        self.viewDistance = intValue(forKey: "view-distance", default: defaultViewDistance)

        // online-mode
        self.onlineMode = boolValue(forKey: "online-mode", default: defaultOnlineMode)

        // server-port
        self.serverPort = intValue(forKey: "server-port", default: defaultPort)

        // NOTE: Bedrock port lives in Geyser's config.yml, not server.properties.
        self.bedrockPort = nil

    }

    /// Returns a new dictionary with this model's values overlaid on top of an
    /// existing dictionary, preserving unknown keys.
    ///
    /// Note: Bedrock port lives in Geyser's config.yml and is not stored in server.properties.
    func mergedInto(_ existing: [String: String]) -> [String: String] {
        var result = existing

        result["motd"] = motd
        result["max-players"] = String(maxPlayers)
        result["difficulty"] = difficulty.rawValue
        result["gamemode"] = gamemode.rawValue
        result["view-distance"] = String(viewDistance)
        result["online-mode"] = onlineMode ? "true" : "false"
        result["server-port"] = String(serverPort)

        return result
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
struct ConsoleEntry: Identifiable, Hashable {
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


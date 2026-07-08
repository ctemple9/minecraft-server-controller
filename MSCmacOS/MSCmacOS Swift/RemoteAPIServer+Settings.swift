//
//  RemoteAPIServer+Settings.swift
//  MinecraftServerController
//
//  Route handlers for GET/POST /settings plus the pure schema builder/validator
//  (`ServerSettingsSchema`) that turns a ServerPropertiesModel into the typed,
//  self-describing wire schema the iOS client renders as a form — and applies a
//  sparse set of edits back onto the model with per-field validation/clamping.
//
//  P4 adds a `bedrockSections(...)` builder here; the route handlers and the iOS
//  form need no changes to gain Bedrock support.
//

import Foundation

// MARK: - Route handlers

extension RemoteAPIServer {

    // GET /settings
    func handleGetSettings(clientFD: Int32) {
        let dto = settingsProvider()
        sendJSON(statusCode: 200, reason: "OK", encodable: dto, clientFD: clientFD)
    }

    // POST /settings
    func handleUpdateSettings(body: Data, clientFD: Int32) {
        guard !body.isEmpty else {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "missing_body"], clientFD: clientFD)
            return
        }
        do {
            let decoded = try JSONDecoder().decode(SettingsUpdateRequestDTO.self, from: body)
            guard !decoded.changes.isEmpty else {
                sendJSON(statusCode: 400, reason: "Bad Request",
                         jsonObject: ["error": "no_changes"], clientFD: clientFD)
                return
            }
            let result = updateSettingsProvider(decoded.changes)
            let status: Int
            if result.success {
                status = 200
            } else {
                switch result.message {
                case "no_active_server", "not_supported": status = 409
                case "no_valid_changes":                  status = 400
                default:                                   status = 500
                }
            }
            sendJSON(statusCode: status, reason: result.success ? "OK" : "Error",
                     encodable: result, clientFD: clientFD)
        } catch {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "invalid_json"], clientFD: clientFD)
        }
    }
}

// MARK: - Schema builder / validator (pure, no AppViewModel state)

enum ServerSettingsSchema {

    // MARK: Java schema

    /// Builds the typed section list for a Java server.properties model.
    static func javaSections(from m: ServerPropertiesModel) -> [RemoteAPIServer.SettingsSectionDTO] {
        typealias Field = RemoteAPIServer.SettingFieldDTO
        typealias Option = RemoteAPIServer.SettingOptionDTO

        func bool(_ key: String, _ label: String, _ value: Bool, help: String? = nil) -> Field {
            Field(key: key, label: label, help: help, type: "bool", value: value ? "true" : "false")
        }
        func int(_ key: String, _ label: String, _ value: Int, min: Int, max: Int,
                 unit: String? = nil, help: String? = nil) -> Field {
            Field(key: key, label: label, help: help, type: "int", value: String(value),
                  minInt: min, maxInt: max, unit: unit)
        }

        let difficultyOptions = ServerDifficulty.allCases.map { Option(value: $0.rawValue, label: $0.displayName) }
        let gamemodeOptions   = ServerGamemode.allCases.map { Option(value: $0.rawValue, label: $0.displayName) }
        let levelOptions      = LevelType.allCases.map { Option(value: levelToken($0), label: $0.displayName) }
        let opLevelOptions = [
            Option(value: "1", label: "1 — Bypass spawn protection"),
            Option(value: "2", label: "2 — Commands & command blocks"),
            Option(value: "3", label: "3 — Manage players"),
            Option(value: "4", label: "4 — All permissions"),
        ]

        let world = RemoteAPIServer.SettingsSectionDTO(
            id: "world", title: "World", icon: "globe",
            fields: [
                Field(key: "difficulty", label: "Difficulty", help: nil, type: "enum",
                      value: m.difficulty.rawValue, options: difficultyOptions),
                Field(key: "gamemode", label: "Gamemode", help: nil, type: "enum",
                      value: m.gamemode.rawValue, options: gamemodeOptions),
                Field(key: "level-type", label: "World Type", help: nil, type: "enum",
                      value: levelToken(m.levelType), options: levelOptions),
                bool("hardcore", "Hardcore", m.hardcore),
                bool("pvp", "PvP", m.pvp),
                bool("spawn-monsters", "Spawn Monsters", m.spawnMonsters),
                bool("spawn-animals", "Spawn Animals", m.spawnAnimals),
                bool("spawn-npcs", "Spawn NPCs", m.spawnNpcs),
                bool("allow-nether", "Allow Nether", m.allowNether),
                bool("allow-flight", "Allow Flight", m.allowFlight),
                bool("force-gamemode", "Force Gamemode", m.forceGamemode),
                int("spawn-protection", "Spawn Protection", m.spawnProtection, min: 0, max: 10_000,
                    unit: "blocks", help: "Blocks around spawn that non-ops cannot edit. 0 disables."),
            ]
        )

        let server = RemoteAPIServer.SettingsSectionDTO(
            id: "server", title: "Server", icon: "slider.horizontal.3",
            fields: [
                Field(key: "motd", label: "MOTD", help: "Shown in the multiplayer server list.",
                      type: "string", value: m.motd, maxLength: 200),
                int("max-players", "Max Players", m.maxPlayers, min: 1, max: 1000),
                bool("online-mode", "Online Mode", m.onlineMode,
                     help: "Verify players with Mojang. Turn off for cracked / Geyser setups."),
                int("view-distance", "View Distance", m.viewDistance, min: 3, max: 32, unit: "chunks"),
                int("simulation-distance", "Simulation Distance", m.simulationDistance, min: 3, max: 32, unit: "chunks"),
                bool("white-list", "Whitelist", m.whitelist),
                bool("enforce-whitelist", "Enforce Whitelist", m.enforceWhitelist),
                int("player-idle-timeout", "Idle Timeout", m.playerIdleTimeout, min: 0, max: 1440,
                    unit: "min", help: "Minutes before an idle player is kicked. 0 disables."),
                Field(key: "op-permission-level", label: "Op Permission Level", help: nil, type: "enum",
                      value: String(m.opPermissionLevel), options: opLevelOptions),
            ]
        )

        let network = RemoteAPIServer.SettingsSectionDTO(
            id: "network", title: "Network", icon: "network",
            fields: [
                int("server-port", "Server Port (TCP)", m.serverPort, min: 1, max: 65_535,
                    help: "Changing the port may require updating your router / port forwarding."),
            ]
        )

        return [world, server, network]
    }

    // MARK: Apply (validate + clamp a sparse change set onto a Java model)

    /// Mutates `m` with the provided string changes. Returns which keys were
    /// applied and which were rejected (with reason). Ints clamp to their range,
    /// bools/enums validate against their allowed set, unknown keys are rejected.
    static func applyJava(changes: [String: String],
                          onto m: inout ServerPropertiesModel)
        -> (applied: [String], rejected: [RemoteAPIServer.SettingRejectionDTO]) {

        var applied: [String] = []
        var rejected: [RemoteAPIServer.SettingRejectionDTO] = []

        func reject(_ key: String, _ reason: String) {
            rejected.append(RemoteAPIServer.SettingRejectionDTO(key: key, reason: reason))
        }
        func applyInt(_ key: String, _ raw: String, min lo: Int, max hi: Int, set: (Int) -> Void) {
            guard let v = Int(raw.trimmingCharacters(in: .whitespaces)) else {
                reject(key, "not_an_integer"); return
            }
            set(Swift.max(lo, Swift.min(hi, v)))
            applied.append(key)
        }
        func applyBool(_ key: String, _ raw: String, set: (Bool) -> Void) {
            guard let b = parseBool(raw) else { reject(key, "not_a_boolean"); return }
            set(b); applied.append(key)
        }

        for (key, raw) in changes {
            switch key {
            case "difficulty":
                if let v = ServerDifficulty(rawValue: raw.trimmingCharacters(in: .whitespaces).lowercased()) {
                    m.difficulty = v; applied.append(key)
                } else { reject(key, "invalid_value") }
            case "gamemode":
                if let v = ServerGamemode(rawValue: raw.trimmingCharacters(in: .whitespaces).lowercased()) {
                    m.gamemode = v; applied.append(key)
                } else { reject(key, "invalid_value") }
            case "level-type":
                if let v = levelFromToken(raw.trimmingCharacters(in: .whitespaces).lowercased()) {
                    m.levelType = v; applied.append(key)
                } else { reject(key, "invalid_value") }
            case "op-permission-level":
                if let v = Int(raw.trimmingCharacters(in: .whitespaces)), (1...4).contains(v) {
                    m.opPermissionLevel = v; applied.append(key)
                } else { reject(key, "invalid_value") }

            case "hardcore":          applyBool(key, raw) { m.hardcore = $0 }
            case "pvp":               applyBool(key, raw) { m.pvp = $0 }
            case "spawn-monsters":    applyBool(key, raw) { m.spawnMonsters = $0 }
            case "spawn-animals":     applyBool(key, raw) { m.spawnAnimals = $0 }
            case "spawn-npcs":        applyBool(key, raw) { m.spawnNpcs = $0 }
            case "allow-nether":      applyBool(key, raw) { m.allowNether = $0 }
            case "allow-flight":      applyBool(key, raw) { m.allowFlight = $0 }
            case "force-gamemode":    applyBool(key, raw) { m.forceGamemode = $0 }
            case "online-mode":       applyBool(key, raw) { m.onlineMode = $0 }
            case "white-list":        applyBool(key, raw) { m.whitelist = $0 }
            case "enforce-whitelist": applyBool(key, raw) { m.enforceWhitelist = $0 }

            case "spawn-protection":    applyInt(key, raw, min: 0, max: 10_000) { m.spawnProtection = $0 }
            case "max-players":         applyInt(key, raw, min: 1, max: 1000)   { m.maxPlayers = $0 }
            case "view-distance":       applyInt(key, raw, min: 3, max: 32)     { m.viewDistance = $0 }
            case "simulation-distance": applyInt(key, raw, min: 3, max: 32)     { m.simulationDistance = $0 }
            case "player-idle-timeout": applyInt(key, raw, min: 0, max: 1440)   { m.playerIdleTimeout = $0 }
            case "server-port":         applyInt(key, raw, min: 1, max: 65_535) { m.serverPort = $0 }

            case "motd":
                m.motd = String(raw.prefix(200)); applied.append(key)

            default:
                reject(key, "unknown_key")
            }
        }

        return (applied, rejected)
    }

    // MARK: Helpers

    static func parseBool(_ raw: String) -> Bool? {
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "true", "1", "on", "yes":   return true
        case "false", "0", "off", "no":  return false
        default:                          return nil
        }
    }

    static func levelToken(_ t: LevelType) -> String {
        switch t {
        case .normal:      return "normal"
        case .flat:        return "flat"
        case .largeBiomes: return "large_biomes"
        case .amplified:   return "amplified"
        }
    }

    static func levelFromToken(_ s: String) -> LevelType? {
        switch s {
        case "normal":       return .normal
        case "flat":         return .flat
        case "large_biomes": return .largeBiomes
        case "amplified":    return .amplified
        default:             return nil
        }
    }

    // MARK: Bedrock schema

    /// Builds the typed section list for a Bedrock (BDS) server.properties model.
    static func bedrockSections(from m: BedrockPropertiesModel) -> [RemoteAPIServer.SettingsSectionDTO] {
        typealias Field  = RemoteAPIServer.SettingFieldDTO
        typealias Option = RemoteAPIServer.SettingOptionDTO

        func bool(_ key: String, _ label: String, _ value: Bool, help: String? = nil) -> Field {
            Field(key: key, label: label, help: help, type: "bool", value: value ? "true" : "false")
        }
        func int(_ key: String, _ label: String, _ value: Int, min: Int, max: Int,
                 unit: String? = nil, help: String? = nil) -> Field {
            Field(key: key, label: label, help: help, type: "int", value: String(value),
                  minInt: min, maxInt: max, unit: unit)
        }

        let difficultyOptions = ServerDifficulty.allCases.map { Option(value: $0.bdsKey, label: $0.displayName) }
        let gamemodeOptions   = ServerGamemode.allCases.map { Option(value: $0.bdsKey, label: $0.displayName) }

        let world = RemoteAPIServer.SettingsSectionDTO(
            id: "world", title: "World", icon: "globe",
            fields: [
                Field(key: "difficulty", label: "Difficulty", help: nil, type: "enum",
                      value: m.difficulty.bdsKey, options: difficultyOptions),
                Field(key: "gamemode", label: "Default Gamemode", help: nil, type: "enum",
                      value: m.gamemode.bdsKey, options: gamemodeOptions),
                bool("allow-cheats", "Allow Cheats",  m.allowCheats,
                     help: "Enables /gamemode, /give, /tp, and other cheat commands for all players."),
            ]
        )

        let server = RemoteAPIServer.SettingsSectionDTO(
            id: "server", title: "Server", icon: "slider.horizontal.3",
            fields: [
                Field(key: "level-name", label: "World Name",
                      help: "Name of the world folder. Changing this loads a different world on next start.",
                      type: "string", value: m.levelName, maxLength: 80),
                int("max-players", "Max Players", m.maxPlayers, min: 1, max: 100),
                bool("online-mode", "Online Mode", m.onlineMode,
                     help: "Verify players with Xbox Live. Disable for offline/LAN-only setups."),
            ]
        )

        let network = RemoteAPIServer.SettingsSectionDTO(
            id: "network", title: "Network", icon: "network",
            fields: [
                int("server-port", "Server Port (UDP)", m.serverPort, min: 1, max: 65_535,
                    help: "IPv4 UDP port. Changing may require updating your router / port forwarding."),
                int("server-portv6", "Server Port IPv6 (UDP)", m.serverPortV6, min: 1, max: 65_535,
                    help: "IPv6 UDP port used when clients connect over IPv6."),
            ]
        )

        return [world, server, network]
    }

    // MARK: Apply Bedrock (validate + clamp a sparse change set onto a Bedrock model)

    static func applyBedrock(changes: [String: String],
                             onto m: inout BedrockPropertiesModel)
        -> (applied: [String], rejected: [RemoteAPIServer.SettingRejectionDTO]) {

        var applied: [String] = []
        var rejected: [RemoteAPIServer.SettingRejectionDTO] = []

        func reject(_ key: String, _ reason: String) {
            rejected.append(RemoteAPIServer.SettingRejectionDTO(key: key, reason: reason))
        }
        func applyInt(_ key: String, _ raw: String, min lo: Int, max hi: Int, set: (Int) -> Void) {
            guard let v = Int(raw.trimmingCharacters(in: .whitespaces)) else {
                reject(key, "not_an_integer"); return
            }
            set(Swift.max(lo, Swift.min(hi, v)))
            applied.append(key)
        }
        func applyBool(_ key: String, _ raw: String, set: (Bool) -> Void) {
            guard let b = parseBool(raw) else { reject(key, "not_a_boolean"); return }
            set(b); applied.append(key)
        }

        for (key, raw) in changes {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            switch key {
            case "difficulty":
                if let v = ServerDifficulty.allCases.first(where: { $0.bdsKey == trimmed.lowercased() }) {
                    m.difficulty = v; applied.append(key)
                } else { reject(key, "invalid_value") }
            case "gamemode":
                if let v = ServerGamemode.allCases.first(where: { $0.bdsKey == trimmed.lowercased() }) {
                    m.gamemode = v; applied.append(key)
                } else { reject(key, "invalid_value") }
            case "allow-cheats":   applyBool(key, raw) { m.allowCheats = $0 }
            case "online-mode":    applyBool(key, raw) { m.onlineMode = $0 }
            case "level-name":
                let cleaned = trimmed.prefix(80).description
                guard !cleaned.isEmpty else { reject(key, "empty_value"); break }
                m.levelName = cleaned; applied.append(key)
            case "max-players":   applyInt(key, raw, min: 1, max: 100) { m.maxPlayers = $0 }
            case "server-port":   applyInt(key, raw, min: 1, max: 65_535) { m.serverPort = $0 }
            case "server-portv6": applyInt(key, raw, min: 1, max: 65_535) { m.serverPortV6 = $0 }
            default:
                reject(key, "unknown_key")
            }
        }

        return (applied, rejected)
    }
}

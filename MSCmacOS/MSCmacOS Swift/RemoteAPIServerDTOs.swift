import Foundation

/// Minimal status payload for the remote API.
struct RemoteAPIStatus: Codable {
    let running: Bool
    let activeServerId: String?
    let pid: Int?

    // Additive fields used by the iOS client when available.
    /// Raw value of ServerType for the active server: "java" or "bedrock".
    /// Nil when no server is selected.
    let serverType: String?
    /// For Bedrock servers: true when the server VM is confirmed running.
    /// Nil for Java servers (use `running` and `pid` instead).
    /// Field name kept as-is for iOS app wire-format compatibility.
    let dockerContainerRunning: Bool?
    /// For Bedrock servers: "running", "stopped", or "unknown".
    /// Nil for Java servers. Additive alongside dockerContainerRunning.
    /// Field name kept as-is for iOS app wire-format compatibility.
    let dockerContainerStatus: String?

    enum CodingKeys: String, CodingKey {
        case running
        case activeServerId
        case pid
        case serverType
        case dockerContainerRunning
        case dockerContainerStatus
    }

    /// Backwards-compatible initialiser — new fields are optional.
    init(running: Bool,
         activeServerId: String?,
         pid: Int?,
         serverType: String? = nil,
         dockerContainerRunning: Bool? = nil,
         dockerContainerStatus: String? = nil) {
        self.running = running
        self.activeServerId = activeServerId
        self.pid = pid
        self.serverType = serverType
        self.dockerContainerRunning = dockerContainerRunning
        self.dockerContainerStatus = dockerContainerStatus
    }
}

extension RemoteAPIServer {
    struct ServerDTO: Codable {
        let id: String
        let name: String
        let directory: String
        // Allows iOS to display Java vs. Bedrock badges without a separate request.
        let serverType: String
        // Explicit join-card data so iOS does not have to infer from defaults.
        let gamePort: Int?
        let hostAddress: String?
    }

    struct ServerConnectionInfoDTO {
        let gamePort: Int?
        let hostAddress: String?
    }

    struct ConsoleLineDTO: Codable {
        let ts: String
        let source: String
        let level: String?
        let text: String
    }

    // Performance snapshot (for iOS charts)
    struct PerformanceSnapshotDTO: Codable {
        let ts: String
        let tps1m: Double?
        let playersOnline: Int?
        let cpuPercent: Double?
        let ramUsedMB: Double?
        let ramMaxMB: Double?
        let worldSizeMB: Double?
        // Explicit server type so iOS can distinguish Java from Bedrock without inferring.
        let serverType: String?
    }

    // MARK: - Players

    /// A single online player returned by GET /players.
    struct PlayerDTO: Codable {
        let name: String
        let uuid: String?
    }

    /// Full response envelope for GET /players.
    struct PlayersResponseDTO: Codable {
        let players: [PlayerDTO]
        let count: Int
        /// Optional context note. For Bedrock servers, explains the data source.
        /// Nil for Java servers. Additive — older iOS versions ignore unknown fields.
        let note: String?

        init(players: [PlayerDTO], count: Int, note: String? = nil) {
            self.players = players
            self.count = count
            self.note = note
        }
    }

    // MARK: - Allowlist

    /// One Bedrock allowlist entry returned by GET /allowlist.
    struct AllowlistEntryDTO: Codable {
        let name: String
        let xuid: String?
        let ignoresPlayerLimit: Bool
    }

    /// Full response envelope for GET /allowlist.
    struct AllowlistResponseDTO: Codable {
        /// Raw value of the active server's serverType ("java" or "bedrock").
        /// iOS uses this to decide whether to surface the allowlist UI.
        let serverType: String
        let entries: [AllowlistEntryDTO]
    }

    // MARK: - Components

    struct ComponentStatusDTO: Codable {
        let name: String
        let installedBuild: Int?
        let latestBuild: Int?
        let installedVersion: String?
        let latestVersion: String?
        let isUpToDate: Bool
    }

    struct ComponentsStatusDTO: Codable {
        let components: [ComponentStatusDTO]
        let restartRequiredToApply: Bool
    }

    struct ComponentUpdateRequestDTO: Codable {
        let component: String
    }

    struct ComponentUpdateResultDTO: Codable {
        let success: Bool
        let message: String
        let newBuild: Int?
        let newVersion: String?
    }

    // MARK: - Broadcast

    struct BroadcastStatusDTO: Codable {
        let xboxBroadcastRunning: Bool
        let bedrockBroadcastRunning: Bool
    }

    struct BroadcastCredentialsDTO: Codable {
        let email: String
        let password: String
        let gamertag: String
    }

    struct BroadcastAutoStartDTO: Codable {
        let enabled: Bool
    }

    struct BroadcastAuthPromptDTO: Codable {
        let isPresent: Bool
        let code: String?
        let linkURL: String?
    }

    // MARK: - Session Log

    /// One session event returned by GET /session-log.
    struct SessionEventDTO: Codable {
        let id: String
        let playerName: String
        /// "joined" or "left"
        let eventType: String
        let timestamp: String   // ISO 8601
    }

    /// Full response envelope for GET /session-log.
    struct SessionLogResponseDTO: Codable {
        let activeServerId: String?
        let events: [SessionEventDTO]
    }

    // MARK: - Player Profiles

    struct PlayerStatsDTO: Codable {
        let health: Float
        let maxHealth: Float
        let foodLevel: Int
        let xpLevel: Int
        let xpTotal: Int
        let gameMode: Int
        let gameModeDisplay: String
        let posX: Double
        let posY: Double
        let posZ: Double
        let dimensionDisplay: String
        let score: Int
    }

    struct ItemEnchantmentDTO: Codable {
        let id: String
        let level: Int
        let displayName: String
    }

    struct InventoryItemDTO: Codable {
        let slot: Int
        let itemID: String
        /// Last path component of itemID with no namespace (e.g. "diamond_sword").
        let iconName: String
        let count: Int
        let displayName: String
        let enchantments: [ItemEnchantmentDTO]
        let damage: Int
    }

    struct PlayerProfileDTO: Codable {
        let id: String
        let username: String?
        /// UUID-no-dashes (Java) or Floodgate UUID (Bedrock) — for mc-heads.net avatar URLs.
        let imageIdentifier: String
        let isOnline: Bool
        let isOp: Bool
        let lastSeen: String?   // ISO8601
        let isBedrockPlayer: Bool
        let stats: PlayerStatsDTO?
        let inventory: [InventoryItemDTO]
    }

    struct PlayerProfilesResponseDTO: Codable {
        let profiles: [PlayerProfileDTO]
        /// True when NBT loading was just triggered for one or more Java profiles.
        /// iOS should auto-refresh after a short delay to pick up the loaded stats.
        let isLoadingStats: Bool
    }

    // MARK: - World Slots

    struct WorldSlotDTO: Codable {
        let id: String
        let name: String
        let isActive: Bool
        let createdAt: String       // ISO8601
        let zipSizeBytes: Int64?
        let worldSeed: String?
    }

    struct WorldSlotsResponseDTO: Codable {
        let slots: [WorldSlotDTO]
        let activeSlotId: String?
        let serverRunning: Bool
    }

    // MARK: - Backups

    struct BackupItemDTO: Codable {
        let id: String              // filename — sent back as backupId for restore
        let displayName: String
        let fileSize: Int64?
        let modificationDate: String?   // ISO8601
        let isAutomatic: Bool
        let slotId: String?
        let slotName: String?
        let triggerReason: String
    }

    struct BackupsResponseDTO: Codable {
        let backups: [BackupItemDTO]
    }
}

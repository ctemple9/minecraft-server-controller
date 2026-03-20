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
    /// For Bedrock servers: true when the Docker container is confirmed running.
    /// Nil for Java servers (use `running` and `pid` instead).
    let dockerContainerRunning: Bool?
    /// For Bedrock servers: "running", "stopped", or "unknown".
    /// Nil for Java servers. Additive alongside dockerContainerRunning.
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
}

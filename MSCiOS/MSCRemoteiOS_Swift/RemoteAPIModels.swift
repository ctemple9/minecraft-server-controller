import Foundation

// MARK: - Server Type

/// Mirrors the ServerType enum on the macOS side.
/// decodeIfPresent on the macOS API means older servers return nil here — default to .java.
enum ServerType: String, Codable {
    case java
    case bedrock

    var displayName: String {
        switch self {
        case .java:    return "Java"
        case .bedrock: return "Bedrock"
        }
    }

    /// SF Symbol name for the badge shown in server pickers.
    var iconName: String {
        switch self {
        case .java:    return "cup.and.saucer.fill"
        case .bedrock: return "cube.fill"
        }
    }
}

// MARK: - Status & Servers

struct RemoteAPIStatus: Codable, Equatable {
    let running: Bool
    let activeServerId: String?
    let pid: Int?
    /// Nil when connecting to an older macOS app — treated as .java.
    let serverType: ServerType?
    /// Bedrock-only container hints. Nil for Java servers and older macOS builds.
    let dockerContainerRunning: Bool?
    let dockerContainerStatus: String?

    var resolvedServerType: ServerType { serverType ?? .java }
}

struct ServerDTO: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let directory: String
    /// Nil when connecting to an older macOS app that hasn't shipped E1 yet -- treated as .java.
    let serverType: ServerType?
    /// Game port (19132 for Bedrock, 25565 for Java). Nil on older macOS builds -- use type default.
    let gamePort: Int?
    /// Host address for the join card back (DuckDNS domain or public IP). Nil = not configured.
    let hostAddress: String?

    var resolvedServerType: ServerType { serverType ?? .java }

    /// The port to display on the join card. Falls back to protocol default if nil.
    var resolvedGamePort: Int {
        if let p = gamePort { return p }
        return resolvedServerType == .bedrock ? 19132 : 25565
    }

    /// Protocol label for join card.
    var protocolLabel: String { resolvedServerType == .bedrock ? "UDP" : "TCP" }
}

// MARK: - Console

struct ConsoleLineDTO: Identifiable, Equatable {
    /// Stable UUID assigned at decode time.
    ///
    /// Why not derive id from content? Minecraft servers routinely emit
    /// identical consecutive lines (join/leave messages, tick warnings,
    /// repeated status output). A content-derived id causes SwiftUI's
    /// ForEach to silently drop duplicate rows or produce animation glitches.
    /// A UUID generated once per received line is always unique.
    let id: UUID

    let ts: String
    let source: String
    let level: String?
    let text: String
}

// MARK: - Codable

extension ConsoleLineDTO: Codable {
    /// CodingKeys intentionally omits `id` — the server never sends it.
    private enum CodingKeys: String, CodingKey {
        case ts, source, level, text
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.ts     = try c.decode(String.self, forKey: .ts)
        self.source = try c.decode(String.self, forKey: .source)
        self.level  = try c.decodeIfPresent(String.self, forKey: .level)
        self.text   = try c.decode(String.self, forKey: .text)

        // UUID is generated here — once per decoded line, never from content.
        self.id = UUID()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ts,     forKey: .ts)
        try c.encode(source, forKey: .source)
        try c.encodeIfPresent(level, forKey: .level)
        try c.encode(text,   forKey: .text)
        // `id` is intentionally not encoded — it is client-side only.
    }
}

struct SimpleResult: Codable, Equatable {
    let result: String
    let activeServerId: String?
}

struct CommandResult: Codable, Equatable {
    let result: String
    let activeServerId: String?
    let command: String
}

// MARK: - Performance

/// Snapshot payload from the Remote API.
/// Keep fields optional so the client is robust if the server rolls out gradually.
struct PerformanceSnapshotDTO: Codable, Equatable {
    /// Timestamp string (recommended ISO8601). Optional for robustness.
    let ts: String?

    /// Paper TPS (1 minute). Typical range 0...20.
    /// Nil for Bedrock servers — BDS has no TPS concept.
    let tps1m: Double?

    /// Online players count.
    let playersOnline: Int?

    /// CPU usage percent (0...100).
    let cpuPercent: Double?

    /// RAM used (MB).
    let ramUsedMB: Double?

    /// RAM max/total (MB).
    let ramMaxMB: Double?

    /// World size (MB), if available.
    let worldSizeMB: Double?

    /// Server type of the currently active server.
    /// Nil when connecting to an older macOS app — treated as .java.
    let serverType: ServerType?

    var resolvedServerType: ServerType { serverType ?? .java }
}

// MARK: - Players

/// A single online player. UUID is optional — some server configs
/// don't expose it. Bedrock players have XUIDs, not Java UUIDs, so
/// the iOS client treats a nil UUID as "show generic icon".
struct PlayerDTO: Codable, Identifiable, Equatable {
    let name: String
    /// Java UUID (used for Crafatar avatar lookup). Nil for Bedrock players.
    let uuid: String?

    // Identifiable conformance — use name since UUIDs can be nil.
    // This is safe because two players with the same name cannot be
    // online simultaneously on a vanilla/Paper/BDS server.
    var id: String { name }
}

struct PlayersResponse: Codable, Equatable {
    let players: [PlayerDTO]
    let count: Int
    /// Optional context note from macOS. Currently used for Bedrock player-list caveats.
    let note: String?
}




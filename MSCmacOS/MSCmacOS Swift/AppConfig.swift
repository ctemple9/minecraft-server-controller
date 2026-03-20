//
//  AppConfig.swift
//

import Foundation

/// One server entry in server_config.json
// MARK: - Xbox Broadcast IP mode

/// Controls which host address MCXboxBroadcast is configured to advertise.
/// - `auto`:      DuckDNS hostname if set → public IP → private/LAN IP (recommended default)
/// - `publicIP`:  Always use the machine's fetched public IP, even if DuckDNS is available
/// - `privateIP`: Always use the LAN IP (10.x / 192.168.x) — for same-network players only
enum XboxBroadcastIPMode: String, Codable, CaseIterable {
    case auto
    case publicIP  = "public_ip"
    case privateIP = "private_ip"

    var displayName: String {
        switch self {
        case .auto:      return "Auto"
        case .publicIP:  return "Public IP"
        case .privateIP: return "Private IP"
        }
    }
}

// MARK: - Notification Preferences

/// Per-server notification preferences. Each flag controls whether that event type
/// delivers a macOS UNUserNotificationCenter notification.
/// Defaults are all-off to avoid surprising users on update.
struct ServerNotificationPrefs: Codable, Equatable {
    var notifyOnStart: Bool       = false
    var notifyOnStop: Bool        = false
    var notifyOnPlayerJoin: Bool  = false
    var notifyOnPlayerLeave: Bool = false

    enum CodingKeys: String, CodingKey {
        case notifyOnStart       = "notify_on_start"
        case notifyOnStop        = "notify_on_stop"
        case notifyOnPlayerJoin  = "notify_on_player_join"
        case notifyOnPlayerLeave = "notify_on_player_leave"
    }

    init(notifyOnStart: Bool = false,
         notifyOnStop: Bool = false,
         notifyOnPlayerJoin: Bool = false,
         notifyOnPlayerLeave: Bool = false) {
        self.notifyOnStart = notifyOnStart
        self.notifyOnStop = notifyOnStop
        self.notifyOnPlayerJoin = notifyOnPlayerJoin
        self.notifyOnPlayerLeave = notifyOnPlayerLeave
    }
}

// MARK: - Server Type

/// Distinguishes Java (Paper) servers from native Bedrock Dedicated Server (BDS) instances.
/// Raw value is persisted to JSON as a string.
enum ServerType: String, Codable, CaseIterable {
    case java
    case bedrock

    var displayName: String {
        switch self {
        case .java:    return "Java"
        case .bedrock: return "Bedrock"
        }
    }
}

struct ConfigServer: Codable, Identifiable {

    var id: String
    var displayName: String
    var serverDir: String
    var paperJarPath: String
    var minRamGB: Int
    var maxRamGB: Int

    // Convenience aliases (AppViewModel references minRam/maxRam in a few places)
    var minRam: Int {
        get { minRamGB }
        set { minRamGB = newValue }
    }

    var maxRam: Int {
        get { maxRamGB }
        set { maxRamGB = newValue }
    }

    /// Persisted last-known Bedrock/Geyser port (nil = unknown/unset).
    var bedrockPort: Int? = nil

    // Cross-play (Geyser/Floodgate) toggle
    var bedrockEnabled: Bool = false

    // Global “public join” host override per server
    var publicHostOverride: String? = nil

    var notes: String = ""

    /// Optional per-server banner color override (hex RGB, e.g. "#AABBCC").
    /// When nil, the UI uses the app default banner color.
    var bannerColorHex: String? = nil

      /// Hex color for the shareable join card (independent of banner color).
      /// Nil = use the default forest green preset.
      var joinCardColorHex: String? = nil

    /// Used for the “Initiate” first-run UX.
    var hasEverStarted: Bool = false

    /// Tracks whether the one-time “first start” popup has been shown for this server.
    /// (We show it after we detect Paper's startup completion line and auto-stop.)
    var hasShownFirstStartPopup: Bool = false

    // Auto Backups (per-server)
    /// When true, the app creates a backup every 30 minutes while the server is running,
    /// keeps at most 12 automatic backups (oldest pruned first), and creates one final
    /// backup when the user clicks Stop. Defaults to off so existing servers are unaffected.
    var autoBackupEnabled: Bool = false

    // Xbox Broadcast (per-server)
    /// Whether this server should start MCXboxBroadcast when the server starts.
    var xboxBroadcastIPMode: XboxBroadcastIPMode = .auto
    var xboxBroadcastEnabled: Bool = false

    /// Optional override for the public host Broadcaster should use.
    /// If nil, we’ll later default to the app-level DuckDNS / host.
    var xboxBroadcastHostOverride: String? = nil

    /// Optional override for the Bedrock port Broadcaster should use.
    var xboxBroadcastPortOverride: Int? = nil

    /// Stored absolute path to this server’s MCXboxBroadcast config directory.
    var xboxBroadcastConfigPath: String? = nil

    // MARK: - Server Type

        /// Whether this is a Java (Paper) or Bedrock Dedicated Server instance.
        /// Defaults to .java so all existing servers are unaffected.
        var serverType: ServerType = .java

        /// Docker image tag for Bedrock servers. Nil = use the app default image.
        /// Example: "itzg/minecraft-bedrock-server"
        var bedrockDockerImage: String? = nil
    var bedrockVersion: String? = nil   // Pinned BEDROCK_SERVER_VERSION; nil = "LATEST"

            // MARK: - Bedrock Connect Standalone (Bedrock servers only)
            // bedrockConnectStandaloneEnabled: whether this server is included in BC's servers.json.
            // The global DNS port lives on AppConfig, not here — BC is one process for all servers.
            var bedrockConnectStandaloneEnabled: Bool = false
            var bedrockConnectStandalonePath: String? = nil  // optional override for JAR path

            // MARK: - Notification Preferences
        var notificationPrefs: ServerNotificationPrefs = ServerNotificationPrefs()

        // MARK: - Convenience helpers

        /// True when this server runs the Java (Paper) backend.
        var isJava: Bool { serverType == .java }

        /// True when this server runs the Bedrock Dedicated Server (Docker) backend.
        var isBedrock: Bool { serverType == .bedrock }

        /// Optional alt-account fields for MCXboxBroadcast.
        var xboxBroadcastAltEmail: String? = nil
    var xboxBroadcastAltGamertag: String? = nil
    /// Loaded from Keychain at runtime; never written to JSON. See KeychainManager.
    var xboxBroadcastAltPassword: String? = nil
    var xboxBroadcastAltAvatarPath: String? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case serverDir = "server_dir"
        case paperJarPath = "paper_jar_path"
        case minRamGB = "min_ram_gb"
        case maxRamGB = "max_ram_gb"

        case bedrockPort = "bedrock_port"
        case bedrockEnabled = "bedrock_enabled"
        case publicHostOverride = "public_host_override"
        case notes
        case bannerColorHex = "banner_color_hex"
        case joinCardColorHex = "join_card_color_hex"
        case hasEverStarted = "has_ever_started"
        case hasShownFirstStartPopup = "has_shown_first_start_popup"

        case autoBackupEnabled = "auto_backup_enabled"

        case xboxBroadcastIPMode    = "xbox_broadcast_ip_mode"
        case xboxBroadcastEnabled = "xbox_broadcast_enabled"
        case xboxBroadcastHostOverride = "xbox_broadcast_host_override"
        case xboxBroadcastPortOverride = "xbox_broadcast_port_override"
        case xboxBroadcastConfigPath = "xbox_broadcast_config_path"
        case xboxBroadcastAltEmail = "xbox_broadcast_alt_email"
        case xboxBroadcastAltGamertag = "xbox_broadcast_alt_gamertag"
        // xboxBroadcastAltPassword intentionally omitted — stored in Keychain, not JSON.
        case xboxBroadcastAltAvatarPath = "xbox_broadcast_alt_avatar_path"

        case serverType          = "server_type"
                        case bedrockDockerImage  = "bedrock_docker_image"
                        case bedrockVersion      = "bedrock_version"

                        // Bedrock Connect standalone (Bedrock servers)
                        case bedrockConnectStandaloneEnabled = "bedrock_connect_standalone_enabled"
                        case bedrockConnectStandalonePath    = "bedrock_connect_standalone_path"

                        case notificationPrefs   = "notification_prefs"
            }
        }

// MARK: - ConfigServer backwards-compatible decoding
//
// Swift's synthesized Codable treats every non-Optional property as required.
// That means adding a new field (like autoBackupEnabled) causes the entire
// servers array to fail decoding when reading older config files that don't
// have the key yet — wiping the server list on first launch after an update.
//
// The fix: a custom init(from:) that uses decodeIfPresent for every field that
// has been added after the initial schema, falling back to a safe default.
// New fields added in the future should always go through decodeIfPresent here.

extension ConfigServer {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // Required fields — these have always existed; decoding failure is legitimate.
        id          = try c.decode(String.self, forKey: .id)
        displayName = try c.decode(String.self, forKey: .displayName)
        serverDir   = try c.decode(String.self, forKey: .serverDir)
        paperJarPath = try c.decode(String.self, forKey: .paperJarPath)
        minRamGB    = try c.decode(Int.self, forKey: .minRamGB)
        maxRamGB    = try c.decode(Int.self, forKey: .maxRamGB)

        // Optional / backwards-compatible fields — use decodeIfPresent with a safe default.
        bedrockPort            = try c.decodeIfPresent(Int.self,    forKey: .bedrockPort)
        bedrockEnabled         = try c.decodeIfPresent(Bool.self,   forKey: .bedrockEnabled)         ?? false
        publicHostOverride     = try c.decodeIfPresent(String.self, forKey: .publicHostOverride)
        notes                  = try c.decodeIfPresent(String.self, forKey: .notes)                  ?? ""
        bannerColorHex         = try c.decodeIfPresent(String.self, forKey: .bannerColorHex)
        joinCardColorHex       = try c.decodeIfPresent(String.self, forKey: .joinCardColorHex)
        hasEverStarted         = try c.decodeIfPresent(Bool.self,   forKey: .hasEverStarted)         ?? false
        hasShownFirstStartPopup = try c.decodeIfPresent(Bool.self,  forKey: .hasShownFirstStartPopup) ?? false

        autoBackupEnabled      = try c.decodeIfPresent(Bool.self,   forKey: .autoBackupEnabled)      ?? false

        xboxBroadcastIPMode         = try c.decodeIfPresent(XboxBroadcastIPMode.self, forKey: .xboxBroadcastIPMode) ?? .auto
        xboxBroadcastEnabled        = try c.decodeIfPresent(Bool.self,   forKey: .xboxBroadcastEnabled)        ?? false
        xboxBroadcastHostOverride   = try c.decodeIfPresent(String.self, forKey: .xboxBroadcastHostOverride)
        xboxBroadcastPortOverride   = try c.decodeIfPresent(Int.self,    forKey: .xboxBroadcastPortOverride)
        xboxBroadcastConfigPath     = try c.decodeIfPresent(String.self, forKey: .xboxBroadcastConfigPath)
        xboxBroadcastAltEmail       = try c.decodeIfPresent(String.self, forKey: .xboxBroadcastAltEmail)
        xboxBroadcastAltGamertag    = try c.decodeIfPresent(String.self, forKey: .xboxBroadcastAltGamertag)
        xboxBroadcastAltPassword    = nil   // never decoded from JSON — loaded from Keychain at runtime
                xboxBroadcastAltAvatarPath  = try c.decodeIfPresent(String.self, forKey: .xboxBroadcastAltAvatarPath)
        serverType         = try c.decodeIfPresent(ServerType.self, forKey: .serverType)         ?? .java
                        bedrockDockerImage = try c.decodeIfPresent(String.self,     forKey: .bedrockDockerImage)
                        bedrockVersion     = try c.decodeIfPresent(String.self, forKey: .bedrockVersion)

                        // Bedrock Connect standalone fields — safe defaults preserve existing configs
                        bedrockConnectStandaloneEnabled = try c.decodeIfPresent(Bool.self,   forKey: .bedrockConnectStandaloneEnabled) ?? false
                        bedrockConnectStandalonePath    = try c.decodeIfPresent(String.self, forKey: .bedrockConnectStandalonePath)
                        notificationPrefs  = try c.decodeIfPresent(ServerNotificationPrefs.self, forKey: .notificationPrefs) ?? ServerNotificationPrefs()
            }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        try c.encode(id,           forKey: .id)
        try c.encode(displayName,  forKey: .displayName)
        try c.encode(serverDir,    forKey: .serverDir)
        try c.encode(paperJarPath, forKey: .paperJarPath)
        try c.encode(minRamGB,     forKey: .minRamGB)
        try c.encode(maxRamGB,     forKey: .maxRamGB)

        try c.encodeIfPresent(bedrockPort,          forKey: .bedrockPort)
        try c.encodeIfPresent(bedrockVersion,       forKey: .bedrockVersion)
        try c.encode(bedrockEnabled,                forKey: .bedrockEnabled)
        try c.encodeIfPresent(publicHostOverride,   forKey: .publicHostOverride)
        try c.encode(notes,                         forKey: .notes)
        try c.encodeIfPresent(bannerColorHex,       forKey: .bannerColorHex)
        try c.encodeIfPresent(joinCardColorHex,     forKey: .joinCardColorHex)
        try c.encode(hasEverStarted,                forKey: .hasEverStarted)
        try c.encode(hasShownFirstStartPopup,       forKey: .hasShownFirstStartPopup)

        try c.encode(autoBackupEnabled,             forKey: .autoBackupEnabled)

        try c.encode(xboxBroadcastIPMode,              forKey: .xboxBroadcastIPMode)
        try c.encode(xboxBroadcastEnabled,              forKey: .xboxBroadcastEnabled)
        try c.encodeIfPresent(xboxBroadcastHostOverride, forKey: .xboxBroadcastHostOverride)
        try c.encodeIfPresent(xboxBroadcastPortOverride, forKey: .xboxBroadcastPortOverride)
        try c.encodeIfPresent(xboxBroadcastConfigPath,   forKey: .xboxBroadcastConfigPath)
        try c.encodeIfPresent(xboxBroadcastAltEmail,     forKey: .xboxBroadcastAltEmail)
        try c.encodeIfPresent(xboxBroadcastAltGamertag,  forKey: .xboxBroadcastAltGamertag)
        // xboxBroadcastAltPassword intentionally omitted — stored in Keychain, not JSON.
                try c.encodeIfPresent(xboxBroadcastAltAvatarPath, forKey: .xboxBroadcastAltAvatarPath)

        try c.encode(serverType,                       forKey: .serverType)
                        try c.encodeIfPresent(bedrockDockerImage,      forKey: .bedrockDockerImage)

                        // Bedrock Connect standalone
                        try c.encode(bedrockConnectStandaloneEnabled,  forKey: .bedrockConnectStandaloneEnabled)
                        try c.encodeIfPresent(bedrockConnectStandalonePath, forKey: .bedrockConnectStandalonePath)

                try c.encode(notificationPrefs, forKey: .notificationPrefs)
            }
}

/// One shared-access entry for the Remote API.
/// Friends/devices can be issued individual tokens which can be revoked at any time.
struct RemoteAPISharedAccessEntry: Codable, Identifiable {
    var id: String
    var label: String
    var token: String
    var createdAtISO8601: String?

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case token
        case createdAtISO8601 = "created_at"
    }

    static func make(label: String, token: String) -> RemoteAPISharedAccessEntry {
        RemoteAPISharedAccessEntry(
            id: UUID().uuidString,
            label: label,
            token: token,
            createdAtISO8601: ISO8601DateFormatter().string(from: Date())
        )
    }
}

/// Top-level app config, matching the Python JSON with additions for Swift.
struct AppConfig: Codable {
    var configVersion: Int
    var javaPath: String
    var extraFlags: String
    var serversRoot: String
    var pluginTemplateDir: String
    var paperTemplateDir: String
    var servers: [ConfigServer]
    var activeServerId: String?
    var initialSetupDone: Bool

    /// Localhost-only HTTP API port.
    var remoteAPIPort: Int

    /// Bearer token required for all Remote API requests.
    /// Loaded from Keychain at runtime; never written to JSON. See KeychainManager.
    var remoteAPIToken: String

    /// When true, the Remote API listens on all interfaces (LAN + VPN).
    /// When false, it binds to localhost only.
    var remoteAPIExposeOnLAN: Bool

    /// Optional override for pairing host (MagicDNS recommended), used for QR/link generation.
    /// Example: your-mac.ts.net
    var remoteAPIPreferredPairingHost: String?

    /// Optional shared-access tokens for friends/devices (full control, owner can revoke).
    var remoteAPISharedAccess: [RemoteAPISharedAccessEntry]

    var duckdnsHostname: String?

    /// Tracks whether the Welcome Guide has been shown at least once.
    var hasShownWelcomeGuide: Bool

    // Xbox Broadcast (global)
    /// Path to MCXboxBroadcastStandalone.jar
    var xboxBroadcastJarPath: String?

    // Bedrock Connect (global)
    /// Path to BedrockConnect.jar
    var bedrockConnectJarPath: String?

    /// Port that BedrockConnect's DNS listener runs on.
    /// Consoles must have their DNS set to this Mac's IP for the redirect to work.
    /// Default nil = BedrockConnect uses its own default (19132).
    /// Must NOT collide with any server's Bedrock game port.
    var bedrockConnectDNSPort: Int?

    // Services — per-service auto-start behaviour (both default to true)
    /// When true, XboxBroadcast starts automatically 30 seconds after the server starts.
    var xboxBroadcastAutoStartEnabled: Bool
    /// When true, Bedrock Connect starts automatically 30 seconds after the server starts.
    var bedrockConnectAutoStartEnabled: Bool

    /// Minecraft Java Edition username used to fetch the player's skin avatar.
    var minecraftUsername: String?

    /// Minecraft Bedrock gamertag used to fetch the player's skin avatar.
    var minecraftBedrockGamertag: String?

    /// Persisted avatar edition selector raw value ("java" or "bedrock").
    var minecraftAvatarEditionRawValue: String?

    /// Global default accent/banner color hex used for onboarding tours and
    /// seeding new servers. Nil = use built-in green default.
    var defaultBannerColorHex: String?

    /// When true, controller errors can present popup alerts.
    /// Default false so users are not interrupted after upgrade.
    var errorPopupsEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case configVersion = "config_version"
        case javaPath = "java_path"
        case extraFlags = "extra_flags"
        case serversRoot = "servers_root"
        case pluginTemplateDir = "plugin_template_dir"
        case paperTemplateDir = "paper_template_dir"
        case servers
        case activeServerId = "active_server_id"
        case initialSetupDone = "initial_setup_done"

        case remoteAPIPort = "remote_api_port"
        // remoteAPIToken intentionally omitted — stored in Keychain, not JSON.
        case remoteAPIExposeOnLAN = "remote_api_expose_on_lan"
        case remoteAPIPreferredPairingHost = "remote_api_preferred_pairing_host"
        case remoteAPISharedAccess = "remote_api_shared_access"

        case duckdnsHostname = "duckdns_hostname"
        case hasShownWelcomeGuide = "has_shown_welcome_guide"

        case xboxBroadcastJarPath = "xbox_broadcast_jar_path"
        case bedrockConnectJarPath = "bedrock_connect_jar_path"
        case bedrockConnectDNSPort = "bedrock_connect_dns_port"
        case xboxBroadcastAutoStartEnabled = "xbox_broadcast_auto_start_enabled"
        case bedrockConnectAutoStartEnabled = "bedrock_connect_auto_start_enabled"
        case minecraftUsername = "minecraft_username"
        case minecraftBedrockGamertag = "minecraft_bedrock_gamertag"
        case minecraftAvatarEditionRawValue = "minecraft_avatar_edition"
        case defaultBannerColorHex = "default_banner_color_hex"
        case errorPopupsEnabled = "error_popups_enabled"
    }

    static let defaultRemoteAPIPort: Int = 48400

    /// Bump this when the persisted config schema changes in a backwards-incompatible way.
    static let latestConfigVersion: Int = 1

    static func generateRemoteAPIToken() -> String {
        // 64 hex-ish chars (two UUIDs without dashes).
        return UUID().uuidString.replacingOccurrences(of: "-", with: "")
            + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }

    static func defaultServersRootPath() -> String {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        return home.appendingPathComponent("MinecraftServers", isDirectory: true).path
    }

    static func defaultPluginTemplateDirPath() -> String {
        (defaultServersRootPath() as NSString).appendingPathComponent("_plugin_templates")
    }

    static func defaultPaperTemplateDirPath() -> String {
        (defaultServersRootPath() as NSString).appendingPathComponent("_paper_templates")
    }

    /// Default config for new installs
    static func defaultConfig() -> AppConfig {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let serversRootURL = home.appendingPathComponent("MinecraftServers", isDirectory: true)

        let serversRootPath = serversRootURL.path

        return AppConfig(
            configVersion: latestConfigVersion,
            javaPath: "java",
            extraFlags: "",
            serversRoot: defaultServersRootPath(),
            pluginTemplateDir: defaultPluginTemplateDirPath(),
            paperTemplateDir: defaultPaperTemplateDirPath(),
            servers: [],
            activeServerId: nil,
            initialSetupDone: false,

            remoteAPIPort: defaultRemoteAPIPort,
            remoteAPIToken: "",   // populated from Keychain by ConfigManager
            remoteAPIExposeOnLAN: false,
            remoteAPIPreferredPairingHost: nil,
            remoteAPISharedAccess: [],

            duckdnsHostname: nil,
            hasShownWelcomeGuide: false,
            xboxBroadcastJarPath: nil,
            bedrockConnectJarPath: nil,
            bedrockConnectDNSPort: nil,
            xboxBroadcastAutoStartEnabled: true,
            bedrockConnectAutoStartEnabled: true,
            minecraftUsername: nil,
            minecraftBedrockGamertag: nil,
            minecraftAvatarEditionRawValue: nil,
            defaultBannerColorHex: nil,
            errorPopupsEnabled: false
        )

    }
}

// MARK: - Backwards-friendly decoding

extension AppConfig {
    init(from decoder: Decoder) throws {
        let defaults = AppConfig.defaultConfig()
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.configVersion =
            try container.decodeIfPresent(Int.self, forKey: .configVersion)
                ?? defaults.configVersion
        self.javaPath =
            try container.decodeIfPresent(String.self, forKey: .javaPath)
                ?? defaults.javaPath
        self.extraFlags =
            try container.decodeIfPresent(String.self, forKey: .extraFlags)
                ?? defaults.extraFlags
        self.serversRoot =
            try container.decodeIfPresent(String.self, forKey: .serversRoot)
                ?? defaults.serversRoot
        self.pluginTemplateDir =
            try container.decodeIfPresent(String.self, forKey: .pluginTemplateDir)
                ?? (self.serversRoot as NSString).appendingPathComponent("_plugin_templates")
        self.paperTemplateDir =
            try container.decodeIfPresent(String.self, forKey: .paperTemplateDir)
                ?? (self.serversRoot as NSString).appendingPathComponent("_paper_templates")
        self.servers =
            try container.decodeIfPresent([ConfigServer].self, forKey: .servers)
                ?? []
        self.activeServerId =
            try container.decodeIfPresent(String.self, forKey: .activeServerId)
        self.initialSetupDone =
            try container.decodeIfPresent(Bool.self, forKey: .initialSetupDone)
                ?? !self.servers.isEmpty

        self.remoteAPIPort =
            try container.decodeIfPresent(Int.self, forKey: .remoteAPIPort)
                ?? defaults.remoteAPIPort

        // remoteAPIToken is not decoded from JSON — ConfigManager loads it from Keychain.
        self.remoteAPIToken = ""

        self.remoteAPIExposeOnLAN =
            try container.decodeIfPresent(Bool.self, forKey: .remoteAPIExposeOnLAN)
                ?? defaults.remoteAPIExposeOnLAN

        // Preferred pairing host + shared access
        let rawPreferred =
            try container.decodeIfPresent(String.self, forKey: .remoteAPIPreferredPairingHost)
                ?? defaults.remoteAPIPreferredPairingHost
        if let rawPreferred {
            let trimmed = rawPreferred.trimmingCharacters(in: .whitespacesAndNewlines)
            self.remoteAPIPreferredPairingHost = trimmed.isEmpty ? nil : trimmed
        } else {
            self.remoteAPIPreferredPairingHost = nil
        }

        let decodedShared =
            try container.decodeIfPresent([RemoteAPISharedAccessEntry].self, forKey: .remoteAPISharedAccess)
                ?? defaults.remoteAPISharedAccess

        // Normalize: trim fields, drop empties, dedupe by token (keep first).
        var seenTokens = Set<String>()
        var normalizedShared: [RemoteAPISharedAccessEntry] = []
        for var entry in decodedShared {
            entry.label = entry.label.trimmingCharacters(in: .whitespacesAndNewlines)
            entry.token = entry.token.trimmingCharacters(in: .whitespacesAndNewlines)
            if entry.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                entry.id = UUID().uuidString
            }
            guard !entry.token.isEmpty else { continue }
            guard seenTokens.insert(entry.token).inserted else { continue }
            normalizedShared.append(entry)
        }
        self.remoteAPISharedAccess = normalizedShared

        // NEW FIELD
        self.duckdnsHostname =
            try container.decodeIfPresent(String.self, forKey: .duckdnsHostname)
                ?? defaults.duckdnsHostname

        self.hasShownWelcomeGuide =
            try container.decodeIfPresent(Bool.self, forKey: .hasShownWelcomeGuide)
                ?? defaults.hasShownWelcomeGuide

        // Xbox Broadcast JAR path
        self.xboxBroadcastJarPath =
            try container.decodeIfPresent(String.self, forKey: .xboxBroadcastJarPath)
                ?? defaults.xboxBroadcastJarPath

        // Bedrock Connect JAR path
        self.bedrockConnectJarPath =
            try container.decodeIfPresent(String.self, forKey: .bedrockConnectJarPath)
                ?? defaults.bedrockConnectJarPath
        self.bedrockConnectDNSPort =
            try container.decodeIfPresent(Int.self, forKey: .bedrockConnectDNSPort)
                ?? defaults.bedrockConnectDNSPort

        // Per-service auto-start toggles (default to true for backwards compatibility)
        self.xboxBroadcastAutoStartEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .xboxBroadcastAutoStartEnabled)
                ?? defaults.xboxBroadcastAutoStartEnabled
        self.bedrockConnectAutoStartEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .bedrockConnectAutoStartEnabled)
                ?? defaults.bedrockConnectAutoStartEnabled
        self.minecraftUsername =
            try container.decodeIfPresent(String.self, forKey: .minecraftUsername)
                ?? defaults.minecraftUsername
        self.minecraftBedrockGamertag =
            try container.decodeIfPresent(String.self, forKey: .minecraftBedrockGamertag)
                ?? defaults.minecraftBedrockGamertag
        self.minecraftAvatarEditionRawValue =
            try container.decodeIfPresent(String.self, forKey: .minecraftAvatarEditionRawValue)
                ?? defaults.minecraftAvatarEditionRawValue
        self.defaultBannerColorHex =
            try container.decodeIfPresent(String.self, forKey: .defaultBannerColorHex)
                ?? defaults.defaultBannerColorHex
        self.errorPopupsEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .errorPopupsEnabled)
                ?? defaults.errorPopupsEnabled
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(configVersion, forKey: .configVersion)
        try container.encode(javaPath, forKey: .javaPath)
        try container.encode(extraFlags, forKey: .extraFlags)
        try container.encode(serversRoot, forKey: .serversRoot)
        try container.encode(pluginTemplateDir, forKey: .pluginTemplateDir)
        try container.encode(paperTemplateDir, forKey: .paperTemplateDir)
        try container.encode(servers, forKey: .servers)
        try container.encodeIfPresent(activeServerId, forKey: .activeServerId)
        try container.encode(initialSetupDone, forKey: .initialSetupDone)
        try container.encode(remoteAPIPort, forKey: .remoteAPIPort)
        // remoteAPIToken is not encoded to JSON — ConfigManager writes it to Keychain.
        try container.encode(remoteAPIExposeOnLAN, forKey: .remoteAPIExposeOnLAN)

        try container.encodeIfPresent(remoteAPIPreferredPairingHost, forKey: .remoteAPIPreferredPairingHost)
        try container.encode(remoteAPISharedAccess, forKey: .remoteAPISharedAccess)

        try container.encodeIfPresent(duckdnsHostname, forKey: .duckdnsHostname)

        try container.encode(hasShownWelcomeGuide, forKey: .hasShownWelcomeGuide)
        try container.encodeIfPresent(xboxBroadcastJarPath, forKey: .xboxBroadcastJarPath)
        try container.encodeIfPresent(bedrockConnectJarPath, forKey: .bedrockConnectJarPath)
        try container.encodeIfPresent(bedrockConnectDNSPort, forKey: .bedrockConnectDNSPort)
        try container.encode(xboxBroadcastAutoStartEnabled, forKey: .xboxBroadcastAutoStartEnabled)
        try container.encode(bedrockConnectAutoStartEnabled, forKey: .bedrockConnectAutoStartEnabled)
        try container.encodeIfPresent(minecraftUsername, forKey: .minecraftUsername)
        try container.encodeIfPresent(minecraftBedrockGamertag, forKey: .minecraftBedrockGamertag)
        try container.encodeIfPresent(defaultBannerColorHex, forKey: .defaultBannerColorHex)
        try container.encodeIfPresent(minecraftAvatarEditionRawValue, forKey: .minecraftAvatarEditionRawValue)
        try container.encode(errorPopupsEnabled, forKey: .errorPopupsEnabled)
    }
}


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

// Java server flavor / category model lives in JavaServerFlavor.swift (M0).

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
    /// When true, the app creates a backup on the configured interval while the server is
    /// running, keeps at most autoBackupMaxCount automatic backups (oldest pruned first),
    /// and creates one final backup when the user clicks Stop.
    var autoBackupEnabled: Bool = false
    /// How often (in minutes) to create an automatic backup while the server is running.
    var autoBackupIntervalMinutes: Int = 30
    /// Maximum number of automatic backups to keep before pruning the oldest.
    var autoBackupMaxCount: Int = 12

    // Xbox Broadcast (per-server)
    /// Whether this server should start MCXboxBroadcast when the server starts.
    var xboxBroadcastIPMode: XboxBroadcastIPMode = .auto
    var xboxBroadcastEnabled: Bool = false

    /// Optional override for the public host Broadcaster should use.
    /// If nil, we’ll later default to the app-level DuckDNS / host.
    var xboxBroadcastHostOverride: String? = nil

    /// Optional override for the Bedrock port Broadcaster should use.
    var xboxBroadcastPortOverride: Int? = nil

    /// Port the app's resource-pack HTTP host serves on for Java clients (Option B hosting).
    var resourcePackHostPort: Int = 8123

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

    // MARK: - Java Server Flavor (M0)

    /// Which Java server software this runs (Paper, Purpur, Fabric, NeoForge, …).
    /// Defaults to `.paper` so every existing/imported server is unaffected.
    /// Only meaningful when `isJava`.
    var javaFlavor: JavaServerFlavor = .paper

    /// Pinned Minecraft version for Java servers (e.g. "1.21.4"). Nil = unknown
    /// (older configs predate this field; backfilled when known).
    var minecraftVersion: String? = nil

    /// Loader version for modded flavors: the Fabric loader version, or the
    /// NeoForge version. Nil for non-modded flavors or when tracking "latest".
    var loaderVersion: String? = nil

    /// Build/source identifier for the installed server jar (e.g. a Paper build
    /// number). Nil = unknown.
    var serverBuild: String? = nil

            // MARK: - Notification Preferences
        var notificationPrefs: ServerNotificationPrefs = ServerNotificationPrefs()

        // MARK: - Convenience helpers

        /// True when this server runs the Java (Paper) backend.
        var isJava: Bool { serverType == .java }

        /// True when this server runs the Bedrock Dedicated Server (Docker) backend.
        var isBedrock: Bool { serverType == .bedrock }

        /// Category (Standard vs Modded) for Java servers; nil for Bedrock.
        var javaCategory: JavaServerCategory? { isJava ? javaFlavor.category : nil }

        /// True when this is a Java server running a mod loader (Fabric/NeoForge/…).
        var isModded: Bool { isJava && javaFlavor.category == .modded }

        /// What add-ons this server accepts (plugins vs mods); nil for Bedrock or
        /// for Java flavors with no add-on API (Vanilla).
        var addOnKind: AddOnKind? { isJava ? javaFlavor.addOnKind : nil }

        /// Optional alt-account fields for MCXboxBroadcast.
        var xboxBroadcastAltEmail: String? = nil
    var xboxBroadcastAltGamertag: String? = nil
    /// Loaded from Keychain at runtime; never written to JSON. See KeychainManager.
    var xboxBroadcastAltPassword: String? = nil
    var xboxBroadcastAltAvatarPath: String? = nil

    /// Per-plugin source configs, keyed by jarStem (filename without extension / .disabled).
    /// Nil for old configs — treated as empty (all plugins unmanaged).
    var pluginSources: [String: PluginSourceConfig]? = nil

    /// Modrinth project associations for installed add-ons (plugins AND mods), keyed by
    /// Modrinth projectId so they survive version bumps. Nil for old configs.
    var addonLinks: [String: AddonLink]? = nil

    // MARK: - playit.gg tunnel

    /// When true, the app starts the playit agent alongside this server so friends
    /// can join without the server owner needing to configure port forwarding.
    var playitEnabled: Bool = false

    /// When true, a second UDP tunnel is opened for Simple Voice Chat on the standard
    /// voice chat port (24454). Requires playitEnabled to be true.
    var playitVoiceChatEnabled: Bool = false

    // MARK: - Simple Voice Chat prompt preferences (per-server)

    /// Flow 1: user chose "Don't ask again" for the playit.gg voice tunnel mismatch prompt.
    /// Cleared automatically when playitVoiceChatEnabled is toggled back off.
    var svcTunnelPromptDismissed: Bool = false

    /// Flow 2: user confirmed they've forwarded UDP 24454 for SVC on their router.
    /// Stays true permanently (never ask again). Cleared if SVC is removed/disabled.
    var svcPortForwardingConfirmed: Bool = false

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
        case autoBackupIntervalMinutes = "auto_backup_interval_minutes"
        case autoBackupMaxCount = "auto_backup_max_count"

        case xboxBroadcastIPMode    = "xbox_broadcast_ip_mode"
        case xboxBroadcastEnabled = "xbox_broadcast_enabled"
        case xboxBroadcastHostOverride = "xbox_broadcast_host_override"
        case xboxBroadcastPortOverride = "xbox_broadcast_port_override"
        case resourcePackHostPort = "resource_pack_host_port"
        case xboxBroadcastConfigPath = "xbox_broadcast_config_path"
        case xboxBroadcastAltEmail = "xbox_broadcast_alt_email"
        case xboxBroadcastAltGamertag = "xbox_broadcast_alt_gamertag"
        // xboxBroadcastAltPassword intentionally omitted — stored in Keychain, not JSON.
        case xboxBroadcastAltAvatarPath = "xbox_broadcast_alt_avatar_path"

        case serverType          = "server_type"
                        case bedrockDockerImage  = "bedrock_docker_image"
                        case bedrockVersion      = "bedrock_version"

                        case javaFlavor          = "java_flavor"
                        case minecraftVersion    = "minecraft_version"
                        case loaderVersion       = "loader_version"
                        case serverBuild         = "server_build"

                        case notificationPrefs   = "notification_prefs"
                        case pluginSources       = "plugin_sources"
                        case addonLinks          = "addon_links"

        case playitEnabled              = "playit_enabled"
        case playitVoiceChatEnabled     = "playit_voice_chat_enabled"
        case svcTunnelPromptDismissed   = "svc_tunnel_prompt_dismissed"
        case svcPortForwardingConfirmed = "svc_port_forwarding_confirmed"
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

        autoBackupEnabled          = try c.decodeIfPresent(Bool.self, forKey: .autoBackupEnabled)          ?? false
        autoBackupIntervalMinutes  = try c.decodeIfPresent(Int.self,  forKey: .autoBackupIntervalMinutes)  ?? 30
        autoBackupMaxCount         = try c.decodeIfPresent(Int.self,  forKey: .autoBackupMaxCount)         ?? 12

        xboxBroadcastIPMode         = try c.decodeIfPresent(XboxBroadcastIPMode.self, forKey: .xboxBroadcastIPMode) ?? .auto
        xboxBroadcastEnabled        = try c.decodeIfPresent(Bool.self,   forKey: .xboxBroadcastEnabled)        ?? false
        xboxBroadcastHostOverride   = try c.decodeIfPresent(String.self, forKey: .xboxBroadcastHostOverride)
        xboxBroadcastPortOverride   = try c.decodeIfPresent(Int.self,    forKey: .xboxBroadcastPortOverride)
        resourcePackHostPort        = try c.decodeIfPresent(Int.self,    forKey: .resourcePackHostPort)        ?? 8123
        xboxBroadcastConfigPath     = try c.decodeIfPresent(String.self, forKey: .xboxBroadcastConfigPath)
        xboxBroadcastAltEmail       = try c.decodeIfPresent(String.self, forKey: .xboxBroadcastAltEmail)
        xboxBroadcastAltGamertag    = try c.decodeIfPresent(String.self, forKey: .xboxBroadcastAltGamertag)
        xboxBroadcastAltPassword    = nil   // never decoded from JSON — loaded from Keychain at runtime
                xboxBroadcastAltAvatarPath  = try c.decodeIfPresent(String.self, forKey: .xboxBroadcastAltAvatarPath)
        serverType         = try c.decodeIfPresent(ServerType.self, forKey: .serverType)         ?? .java
                        bedrockDockerImage = try c.decodeIfPresent(String.self,     forKey: .bedrockDockerImage)
                        bedrockVersion     = try c.decodeIfPresent(String.self, forKey: .bedrockVersion)

                        // Java flavor: use try? so a future/unknown flavor string never wipes the
                        // whole server list — it falls back to .paper (the migration default).
                        javaFlavor         = (try? c.decodeIfPresent(JavaServerFlavor.self, forKey: .javaFlavor)) ?? .paper
                        minecraftVersion   = try c.decodeIfPresent(String.self, forKey: .minecraftVersion)
                        loaderVersion      = try c.decodeIfPresent(String.self, forKey: .loaderVersion)
                        serverBuild        = try c.decodeIfPresent(String.self, forKey: .serverBuild)

                        notificationPrefs  = try c.decodeIfPresent(ServerNotificationPrefs.self, forKey: .notificationPrefs) ?? ServerNotificationPrefs()
                        pluginSources      = try c.decodeIfPresent([String: PluginSourceConfig].self, forKey: .pluginSources)
                        addonLinks         = try c.decodeIfPresent([String: AddonLink].self, forKey: .addonLinks)

        playitEnabled              = try c.decodeIfPresent(Bool.self, forKey: .playitEnabled)              ?? false
        playitVoiceChatEnabled     = try c.decodeIfPresent(Bool.self, forKey: .playitVoiceChatEnabled)     ?? false
        svcTunnelPromptDismissed   = try c.decodeIfPresent(Bool.self, forKey: .svcTunnelPromptDismissed)   ?? false
        svcPortForwardingConfirmed = try c.decodeIfPresent(Bool.self, forKey: .svcPortForwardingConfirmed) ?? false
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

        try c.encode(autoBackupEnabled,            forKey: .autoBackupEnabled)
        try c.encode(autoBackupIntervalMinutes,    forKey: .autoBackupIntervalMinutes)
        try c.encode(autoBackupMaxCount,           forKey: .autoBackupMaxCount)

        try c.encode(xboxBroadcastIPMode,              forKey: .xboxBroadcastIPMode)
        try c.encode(xboxBroadcastEnabled,              forKey: .xboxBroadcastEnabled)
        try c.encodeIfPresent(xboxBroadcastHostOverride, forKey: .xboxBroadcastHostOverride)
        try c.encodeIfPresent(xboxBroadcastPortOverride, forKey: .xboxBroadcastPortOverride)
        try c.encode(resourcePackHostPort,         forKey: .resourcePackHostPort)
        try c.encodeIfPresent(xboxBroadcastConfigPath,   forKey: .xboxBroadcastConfigPath)
        try c.encodeIfPresent(xboxBroadcastAltEmail,     forKey: .xboxBroadcastAltEmail)
        try c.encodeIfPresent(xboxBroadcastAltGamertag,  forKey: .xboxBroadcastAltGamertag)
        // xboxBroadcastAltPassword intentionally omitted — stored in Keychain, not JSON.
                try c.encodeIfPresent(xboxBroadcastAltAvatarPath, forKey: .xboxBroadcastAltAvatarPath)

        try c.encode(serverType,                       forKey: .serverType)
                        try c.encodeIfPresent(bedrockDockerImage,      forKey: .bedrockDockerImage)

                        try c.encode(javaFlavor,                       forKey: .javaFlavor)
                        try c.encodeIfPresent(minecraftVersion,        forKey: .minecraftVersion)
                        try c.encodeIfPresent(loaderVersion,           forKey: .loaderVersion)
                        try c.encodeIfPresent(serverBuild,             forKey: .serverBuild)

                try c.encode(notificationPrefs, forKey: .notificationPrefs)
                try c.encodeIfPresent(pluginSources, forKey: .pluginSources)
                try c.encodeIfPresent(addonLinks, forKey: .addonLinks)

        try c.encode(playitEnabled,              forKey: .playitEnabled)
        try c.encode(playitVoiceChatEnabled,     forKey: .playitVoiceChatEnabled)
        try c.encode(svcTunnelPromptDismissed,   forKey: .svcTunnelPromptDismissed)
        try c.encode(svcPortForwardingConfirmed, forKey: .svcPortForwardingConfirmed)
            }
}

/// One shared-access entry for the Remote API.
/// Friends/devices can be issued individual tokens which can be revoked at any time.
struct RemoteAPISharedAccessEntry: Codable, Identifiable {
    var id: String
    var label: String
    var token: String
    /// "admin" or "guest". Defaults to "admin" for entries created before this field existed.
    var role: String
    var createdAtISO8601: String?

    enum CodingKeys: String, CodingKey {
        case id, label, token, role
        case createdAtISO8601 = "created_at"
    }

    init(id: String, label: String, token: String, role: String = "admin", createdAtISO8601: String? = nil) {
        self.id = id
        self.label = label
        self.token = token
        self.role = role
        self.createdAtISO8601 = createdAtISO8601
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id    = try c.decode(String.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        token = try c.decode(String.self, forKey: .token)
        role  = (try? c.decodeIfPresent(String.self, forKey: .role)) ?? "admin"
        createdAtISO8601 = try? c.decodeIfPresent(String.self, forKey: .createdAtISO8601)
    }

    static func make(label: String, token: String, role: String = "admin") -> RemoteAPISharedAccessEntry {
        RemoteAPISharedAccessEntry(
            id: UUID().uuidString,
            label: label,
            token: token,
            role: role,
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

    // MARK: - playit.gg tunnel addresses (global — one agent, fixed addresses)
    /// Public Java tunnel address e.g. "something.joinmc.link". Set once in Server Settings.
    var playitJavaAddress: String?
    /// Public Bedrock tunnel address e.g. "something.ply.gg:35803". Set once in Server Settings.
    var playitBedrockAddress: String?
    /// Public Simple Voice Chat tunnel address (IP:port) e.g. "147.185.221.18:25732".
    /// Written into voicechat-server.properties as `voice_host`.
    var playitVoiceAddress: String?
    /// The playit.gg agent UUID from claim setup. Persisted so voice/extra tunnels can be
    /// created later (via the stored secret key) without another sign-in.
    var playitAgentId: String?

    /// Tracks whether the Server Handbook has been shown at least once.
    var hasShownHandbook: Bool

    /// Tracks whether the Concept Guide (mental model walkthrough) has been shown at least once.
    var hasShownConceptGuide: Bool

    // Xbox Broadcast (global)
    /// Path to MCXboxBroadcastStandalone.jar
    var xboxBroadcastJarPath: String?

    // Services — auto-start behaviour (default true)
    /// When true, XboxBroadcast starts automatically 30 seconds after the server starts.
    var xboxBroadcastAutoStartEnabled: Bool

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

    /// When true, every downloaded server-core JAR (Paper, Purpur, Vanilla, Fabric)
    /// is automatically copied into the JAR archive for offline reuse.
    var saveDownloadedJars: Bool

    /// Saved NeoForge/Forge installation profiles for the version library.
    var loaderVersionRecords: [LoaderVersionRecord]

    /// Run Bedrock servers in the native Virtualization.framework VM appliance instead
    /// of Docker. Transitional flag while the VM backend is validated; once stable this
    /// becomes the only path and Docker is removed.
    var useVMBedrockBackend: Bool = true

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
        case playitJavaAddress    = "playit_java_address"
        case playitBedrockAddress = "playit_bedrock_address"
        case playitVoiceAddress   = "playit_voice_address"
        case playitAgentId        = "playit_agent_id"
        case hasShownHandbook = "has_shown_welcome_guide"
        case hasShownConceptGuide = "has_shown_concept_guide"

        case xboxBroadcastJarPath = "xbox_broadcast_jar_path"
        case xboxBroadcastAutoStartEnabled = "xbox_broadcast_auto_start_enabled"
        case minecraftUsername = "minecraft_username"
        case minecraftBedrockGamertag = "minecraft_bedrock_gamertag"
        case minecraftAvatarEditionRawValue = "minecraft_avatar_edition"
        case defaultBannerColorHex = "default_banner_color_hex"
        case errorPopupsEnabled = "error_popups_enabled"
        case saveDownloadedJars = "save_downloaded_jars"
        case loaderVersionRecords = "loader_version_records"
        case useVMBedrockBackend = "use_vm_bedrock_backend"
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
            playitJavaAddress: nil,
            playitBedrockAddress: nil,
            playitVoiceAddress: nil,
            playitAgentId: nil,
            hasShownHandbook: false,
            hasShownConceptGuide: false,
            xboxBroadcastJarPath: nil,
            xboxBroadcastAutoStartEnabled: true,
            minecraftUsername: nil,
            minecraftBedrockGamertag: nil,
            minecraftAvatarEditionRawValue: nil,
            defaultBannerColorHex: nil,
            errorPopupsEnabled: false,
            saveDownloadedJars: true,
            loaderVersionRecords: []
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
        self.useVMBedrockBackend =
            try container.decodeIfPresent(Bool.self, forKey: .useVMBedrockBackend)
                ?? defaults.useVMBedrockBackend
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
        self.playitJavaAddress    = try container.decodeIfPresent(String.self, forKey: .playitJavaAddress)
        self.playitBedrockAddress = try container.decodeIfPresent(String.self, forKey: .playitBedrockAddress)
        self.playitVoiceAddress   = try container.decodeIfPresent(String.self, forKey: .playitVoiceAddress)
        self.playitAgentId        = try container.decodeIfPresent(String.self, forKey: .playitAgentId)

        self.hasShownHandbook =
            try container.decodeIfPresent(Bool.self, forKey: .hasShownHandbook)
                ?? defaults.hasShownHandbook

        // For existing users who already saw the old "Welcome Guide" (now Handbook),
        // skip the new concept guide automatically — only show to genuinely new installs.
        self.hasShownConceptGuide =
            try container.decodeIfPresent(Bool.self, forKey: .hasShownConceptGuide)
                ?? self.hasShownHandbook

        // Xbox Broadcast JAR path
        self.xboxBroadcastJarPath =
            try container.decodeIfPresent(String.self, forKey: .xboxBroadcastJarPath)
                ?? defaults.xboxBroadcastJarPath

        self.xboxBroadcastAutoStartEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .xboxBroadcastAutoStartEnabled)
                ?? defaults.xboxBroadcastAutoStartEnabled
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
        self.saveDownloadedJars =
            try container.decodeIfPresent(Bool.self, forKey: .saveDownloadedJars)
                ?? true
        self.loaderVersionRecords =
            try container.decodeIfPresent([LoaderVersionRecord].self, forKey: .loaderVersionRecords) ?? []
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

        try container.encodeIfPresent(duckdnsHostname,      forKey: .duckdnsHostname)
        try container.encodeIfPresent(playitJavaAddress,    forKey: .playitJavaAddress)
        try container.encodeIfPresent(playitBedrockAddress, forKey: .playitBedrockAddress)
        try container.encodeIfPresent(playitVoiceAddress,   forKey: .playitVoiceAddress)
        try container.encodeIfPresent(playitAgentId,        forKey: .playitAgentId)

        try container.encode(hasShownHandbook,      forKey: .hasShownHandbook)
        try container.encode(hasShownConceptGuide,  forKey: .hasShownConceptGuide)
        try container.encodeIfPresent(xboxBroadcastJarPath, forKey: .xboxBroadcastJarPath)
        try container.encode(xboxBroadcastAutoStartEnabled, forKey: .xboxBroadcastAutoStartEnabled)
        try container.encodeIfPresent(minecraftUsername, forKey: .minecraftUsername)
        try container.encodeIfPresent(minecraftBedrockGamertag, forKey: .minecraftBedrockGamertag)
        try container.encodeIfPresent(defaultBannerColorHex, forKey: .defaultBannerColorHex)
        try container.encodeIfPresent(minecraftAvatarEditionRawValue, forKey: .minecraftAvatarEditionRawValue)
        try container.encode(errorPopupsEnabled, forKey: .errorPopupsEnabled)
        try container.encode(saveDownloadedJars, forKey: .saveDownloadedJars)
        if !loaderVersionRecords.isEmpty {
            try container.encode(loaderVersionRecords, forKey: .loaderVersionRecords)
        }
    }
}


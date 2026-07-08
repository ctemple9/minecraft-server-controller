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

    struct ServerRenameRequestDTO: Codable {
        let serverId: String
        let name: String
    }

    struct ServerRenameResultDTO: Codable {
        let success: Bool
        let message: String
        let serverId: String?
        let name: String?

        init(success: Bool, message: String, serverId: String? = nil, name: String? = nil) {
            self.success = success
            self.message = message
            self.serverId = serverId
            self.name = name
        }
    }

    struct ServerDeleteRequestDTO: Codable {
        let serverId: String
    }

    struct ServerDeleteResultDTO: Codable {
        let success: Bool
        let message: String
        let serverId: String?

        init(success: Bool, message: String, serverId: String? = nil) {
            self.success = success
            self.message = message
            self.serverId = serverId
        }
    }

    // MARK: - Templates / server import

    struct TemplateItemDTO: Codable {
        let id: String
        let kind: String
        let filename: String
        let displayName: String
        let sizeBytes: Int64?
        let modifiedAt: String?
        let version: String?
        let build: Int?

        init(id: String, kind: String, filename: String, displayName: String,
             sizeBytes: Int64? = nil, modifiedAt: String? = nil,
             version: String? = nil, build: Int? = nil) {
            self.id = id
            self.kind = kind
            self.filename = filename
            self.displayName = displayName
            self.sizeBytes = sizeBytes
            self.modifiedAt = modifiedAt
            self.version = version
            self.build = build
        }
    }

    struct TemplatesResponseDTO: Codable {
        let serverName: String?
        let serverRunning: Bool
        let paperTemplates: [TemplateItemDTO]
        let pluginTemplates: [TemplateItemDTO]
        let note: String?

        init(serverName: String? = nil, serverRunning: Bool = false,
             paperTemplates: [TemplateItemDTO] = [], pluginTemplates: [TemplateItemDTO] = [],
             note: String? = nil) {
            self.serverName = serverName
            self.serverRunning = serverRunning
            self.paperTemplates = paperTemplates
            self.pluginTemplates = pluginTemplates
            self.note = note
        }
    }

    struct TemplateMutationRequestDTO: Codable {
        /// "exportServer" | "createServer"
        let action: String
        let serverId: String?
        let name: String?
        let templateId: String?
        let port: Int?
        let enableCrossPlay: Bool?
        let crossPlayBedrockPort: Int?
        let enablePlayit: Bool?
        let difficulty: String?
        let gamemode: String?
        let worldName: String?
        let worldSeed: String?
        let acceptEula: Bool?
        let includePlugins: Bool?
    }

    struct TemplateMutationResultDTO: Codable {
        let success: Bool
        let message: String
        let createdServerId: String?
        let createdServerName: String?
        let exportedCount: Int?
        let templates: TemplatesResponseDTO?

        init(success: Bool, message: String, createdServerId: String? = nil,
             createdServerName: String? = nil, exportedCount: Int? = nil,
             templates: TemplatesResponseDTO? = nil) {
            self.success = success
            self.message = message
            self.createdServerId = createdServerId
            self.createdServerName = createdServerName
            self.exportedCount = exportedCount
            self.templates = templates
        }
    }

    struct ServerImportRequestDTO: Codable {
        /// "scan" | "importExisting" | "importTransfer"
        let action: String
        let sourcePath: String
        /// "folder" | "zip" | "transfer" | "auto"
        let importKind: String?
        let displayName: String?
        let serverType: String?
        let activeWorldName: String?
        let port: Int?
        let maxPlayers: Int?
        let acceptEula: Bool?
        let enablePlayit: Bool?
        /// Transfer imports only: "merge" | "replaceAll"
        let transferMode: String?
        /// Required for replaceAll transfer imports so current servers can be backed up first.
        let backupPath: String?
        let javaPortOverrides: [String: Int]?
        let bedrockPortOverrides: [String: Int]?
    }

    struct ServerImportWorldDTO: Codable {
        let id: String
        let name: String
        let sizeBytes: Int64
        let dimensionsLabel: String
    }

    struct ServerImportScanResponseDTO: Codable {
        let success: Bool
        let message: String
        let sourcePath: String?
        let isZip: Bool?
        let serverType: String?
        let port: Int?
        let maxPlayers: Int?
        let eulaAccepted: Bool?
        let worlds: [ServerImportWorldDTO]?
        let defaultWorldName: String?
        let javaFlavor: String?
        let detectedMCVersion: String?
        let detectedLoaderVersion: String?

        init(success: Bool, message: String, sourcePath: String? = nil, isZip: Bool? = nil,
             serverType: String? = nil, port: Int? = nil, maxPlayers: Int? = nil,
             eulaAccepted: Bool? = nil, worlds: [ServerImportWorldDTO]? = nil,
             defaultWorldName: String? = nil, javaFlavor: String? = nil,
             detectedMCVersion: String? = nil, detectedLoaderVersion: String? = nil) {
            self.success = success
            self.message = message
            self.sourcePath = sourcePath
            self.isZip = isZip
            self.serverType = serverType
            self.port = port
            self.maxPlayers = maxPlayers
            self.eulaAccepted = eulaAccepted
            self.worlds = worlds
            self.defaultWorldName = defaultWorldName
            self.javaFlavor = javaFlavor
            self.detectedMCVersion = detectedMCVersion
            self.detectedLoaderVersion = detectedLoaderVersion
        }
    }

    struct ServerImportResultDTO: Codable {
        let success: Bool
        let message: String
        let serverId: String?
        let serverName: String?
        let imported: Int?
        let skipped: Int?
        let replaced: Bool?

        init(success: Bool, message: String, serverId: String? = nil, serverName: String? = nil,
             imported: Int? = nil, skipped: Int? = nil, replaced: Bool? = nil) {
            self.success = success
            self.message = message
            self.serverId = serverId
            self.serverName = serverName
            self.imported = imported
            self.skipped = skipped
            self.replaced = replaced
        }
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

    /// Body for POST /allowlist. `action` is "add" or "remove"; `name` is the gamertag.
    struct AllowlistMutationRequestDTO: Codable {
        let action: String
        let name: String
    }

    /// Response for POST /allowlist. Echoes the freshly-read allowlist so iOS can
    /// update its UI in one round-trip, plus the active serverType for consistency
    /// with GET /allowlist.
    struct AllowlistMutationResultDTO: Codable {
        let success: Bool
        let message: String
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
        /// System component: "paper" | "geyser" | "floodgate". Optional — new clients use jarStem.
        let component: String?
        /// Modrinth-tracked add-on to update by jarStem. Mutually exclusive with component.
        let jarStem: String?
        /// true = update all add-ons that have an available update.
        let updateAll: Bool?
    }

    struct ComponentUpdateResultDTO: Codable {
        let success: Bool
        let message: String
        let newBuild: Int?
        let newVersion: String?
    }

    // MARK: - Add-ons (Modrinth-tracked mods / plugins)

    /// One Modrinth-tracked add-on with its resolved update status.
    struct AddonItemDTO: Codable {
        let jarStem: String
        let displayName: String
        let isEnabled: Bool
        let projectId: String?
        let currentVersion: String?
        /// Non-nil when a newer compatible version exists on Modrinth.
        let availableVersion: String?
        /// "updateAvailable" | "upToDate" | "noCompatibleVersion" | "unlinked"
        let bucket: String
        let iconURL: String?
    }

    /// Response for GET /addons.
    struct AddonsResponseDTO: Codable {
        let addons: [AddonItemDTO]
        let isResolving: Bool
        /// false for Paper/Vanilla servers that have no plugins/ or mods/ folder.
        let serverSupportsAddons: Bool
    }

    /// Response for POST /components/update when updating a Modrinth add-on (fire-and-forget).
    struct AddonUpdateResultDTO: Codable {
        /// "update_started" | "no_updates_available" | "not_found" | "not_supported" | "invalid_request"
        let result: String
        let jarStem: String?
        /// Number of add-ons whose update was started.
        let count: Int
    }

    /// Response for POST /components/remove.
    struct AddonRemoveResultDTO: Codable {
        let success: Bool
        let message: String
        let jarStem: String
    }

    // MARK: - Settings (typed server.properties schema)
    //
    // The server emits a self-describing schema (sections → typed fields) and the
    // iOS client renders a real form from it. Values are ALWAYS string-encoded
    // (server.properties is natively all-strings); `type` tells the client which
    // control to render and how to validate. This same shape serves Bedrock (P4)
    // and other config surfaces — the client never hardcodes the field set.

    /// One selectable choice for an `enum` field.
    struct SettingOptionDTO: Codable {
        let value: String   // raw persisted value, e.g. "hard"
        let label: String   // display, e.g. "Hard"
    }

    /// A single typed, self-describing setting.
    struct SettingFieldDTO: Codable {
        let key: String              // server.properties key & POST key, e.g. "max-players"
        let label: String            // "Max Players"
        let help: String?            // optional hint shown under the control
        let type: String             // "bool" | "int" | "string" | "enum"
        let value: String            // current value, string-encoded
        // int constraints
        let minInt: Int?
        let maxInt: Int?
        let unit: String?            // display suffix, e.g. "chunks", "blocks", "min"
        // string constraints
        let maxLength: Int?
        // enum constraints
        let options: [SettingOptionDTO]?

        init(key: String, label: String, help: String? = nil, type: String, value: String,
             minInt: Int? = nil, maxInt: Int? = nil, unit: String? = nil,
             maxLength: Int? = nil, options: [SettingOptionDTO]? = nil) {
            self.key = key; self.label = label; self.help = help; self.type = type; self.value = value
            self.minInt = minInt; self.maxInt = maxInt; self.unit = unit
            self.maxLength = maxLength; self.options = options
        }
    }

    /// A titled, icon-tagged group of fields.
    struct SettingsSectionDTO: Codable {
        let id: String       // stable id, e.g. "world"
        let title: String    // "World"
        let icon: String     // SF Symbol, e.g. "globe"
        let fields: [SettingFieldDTO]
    }

    /// Response for GET /settings.
    struct SettingsResponseDTO: Codable {
        let serverType: String     // "java" | "bedrock"
        let serverName: String
        /// UI hint: while running, applied changes take effect on the next restart.
        let serverRunning: Bool
        /// false when there is no active server, or the type isn't supported yet.
        let editable: Bool
        let sections: [SettingsSectionDTO]
        let note: String?

        init(serverType: String, serverName: String, serverRunning: Bool,
             editable: Bool, sections: [SettingsSectionDTO], note: String? = nil) {
            self.serverType = serverType; self.serverName = serverName
            self.serverRunning = serverRunning; self.editable = editable
            self.sections = sections; self.note = note
        }
    }

    /// Body for POST /settings — a sparse key→string map of only the changed values.
    struct SettingsUpdateRequestDTO: Codable {
        let changes: [String: String]
    }

    /// One rejected key from POST /settings validation.
    struct SettingRejectionDTO: Codable {
        let key: String
        let reason: String
    }

    /// Response for POST /settings.
    struct SettingsUpdateResultDTO: Codable {
        let success: Bool
        let message: String
        /// True when the server is running (changes apply on next restart).
        let restartRequired: Bool
        let appliedKeys: [String]
        let rejected: [SettingRejectionDTO]?
        /// Freshly-read schema so iOS re-syncs its form in a single round-trip.
        let sections: [SettingsSectionDTO]?

        init(success: Bool, message: String, restartRequired: Bool,
             appliedKeys: [String], rejected: [SettingRejectionDTO]? = nil,
             sections: [SettingsSectionDTO]? = nil) {
            self.success = success; self.message = message
            self.restartRequired = restartRequired; self.appliedKeys = appliedKeys
            self.rejected = rejected; self.sections = sections
        }
    }

    // MARK: - Catalog (add-on search + install)

    /// One Modrinth search hit, flattened for the iOS browser.
    struct CatalogItemDTO: Codable {
        let projectId: String
        let slug: String
        let title: String
        let description: String
        let author: String
        let downloads: Int
        let iconURL: String?
        let isClientOnly: Bool
        let projectType: String    // "mod" | "plugin" | ...
    }

    /// Result of `GET /catalog/search`. `supportsAddons=false` + `note` covers
    /// Vanilla / Bedrock / no-active-server so the client shows a friendly card.
    struct CatalogSearchResponseDTO: Codable {
        let supportsAddons: Bool
        let addonKind: String?     // "plugin" | "mod"
        let loaderName: String?    // e.g. "Paper", "Fabric"
        let gameVersion: String?
        let results: [CatalogItemDTO]
        let note: String?
        init(supportsAddons: Bool, addonKind: String? = nil, loaderName: String? = nil,
             gameVersion: String? = nil, results: [CatalogItemDTO] = [], note: String? = nil) {
            self.supportsAddons = supportsAddons; self.addonKind = addonKind
            self.loaderName = loaderName; self.gameVersion = gameVersion
            self.results = results; self.note = note
        }
    }

    /// Body for `POST /components/install` — echoes the fields the client got from search.
    struct CatalogInstallRequestDTO: Codable {
        let projectId: String
        let slug: String
        let title: String
    }

    /// Result of an install attempt. `message` carries the human-readable outcome
    /// (success text or the specific failure reason from the Mac's installer).
    struct CatalogInstallResultDTO: Codable {
        let success: Bool
        let message: String
        let projectId: String
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
        let isHidden: Bool?
        let skinOverrideIdentifier: String?
        let hasSkinFileOverride: Bool?
        let stats: PlayerStatsDTO?
        let inventory: [InventoryItemDTO]
    }

    struct PlayerProfilesResponseDTO: Codable {
        let profiles: [PlayerProfileDTO]
        /// True when NBT loading was just triggered for one or more Java profiles.
        /// iOS should auto-refresh after a short delay to pick up the loaded stats.
        let isLoadingStats: Bool
    }

    struct PlayerSkinResponseDTO: Codable {
        let success: Bool
        let message: String
        let profileId: String?
        let imageBase64: String?
        let imageMimeType: String?
        let lookupIdentifier: String?
        let isOverride: Bool?
        let source: String?

        init(success: Bool, message: String, profileId: String? = nil,
             imageBase64: String? = nil, imageMimeType: String? = nil,
             lookupIdentifier: String? = nil, isOverride: Bool? = nil,
             source: String? = nil) {
            self.success = success
            self.message = message
            self.profileId = profileId
            self.imageBase64 = imageBase64
            self.imageMimeType = imageMimeType
            self.lookupIdentifier = lookupIdentifier
            self.isOverride = isOverride
            self.source = source
        }
    }

    struct PlayerSkinOverrideRequestDTO: Codable {
        let profileId: String
        /// Nil or empty clears the override. Non-empty sets a lookup identifier
        /// accepted by mc-heads.net / Bedrock dotted-name resolution.
        let lookupIdentifier: String?
    }

    struct PlayerSkinOverrideResultDTO: Codable {
        let success: Bool
        let message: String
        let profileId: String?
        let lookupIdentifier: String?
    }

    struct HiddenProfileMutationRequestDTO: Codable {
        let profileId: String
        let hidden: Bool
    }

    struct HiddenProfileMutationResultDTO: Codable {
        let success: Bool
        let message: String
        let profileId: String?
        let isHidden: Bool?
    }

    // MARK: - Server files (P16)

    struct ServerFileItemDTO: Codable {
        let id: String
        let name: String
        let path: String
        let isDirectory: Bool
        let sizeBytes: Int64?
        let modifiedAt: String?
        let fileExtension: String?
        let isPreviewable: Bool?
    }

    struct ServerFilesResponseDTO: Codable {
        let serverName: String?
        let path: String
        let parentPath: String?
        let items: [ServerFileItemDTO]
        let note: String?

        init(serverName: String? = nil, path: String = "", parentPath: String? = nil,
             items: [ServerFileItemDTO] = [], note: String? = nil) {
            self.serverName = serverName
            self.path = path
            self.parentPath = parentPath
            self.items = items
            self.note = note
        }
    }

    struct ServerFileReadResponseDTO: Codable {
        let success: Bool
        let message: String
        let path: String?
        let name: String?
        let sizeBytes: Int64?
        let content: String?
        let encoding: String?
        let truncated: Bool?

        init(success: Bool, message: String, path: String? = nil, name: String? = nil,
             sizeBytes: Int64? = nil, content: String? = nil, encoding: String? = nil,
             truncated: Bool? = nil) {
            self.success = success
            self.message = message
            self.path = path
            self.name = name
            self.sizeBytes = sizeBytes
            self.content = content
            self.encoding = encoding
            self.truncated = truncated
        }
    }

    // MARK: - Client export (P16)

    struct ClientExportItemDTO: Codable {
        let id: String
        let fileName: String
        let displayName: String
        let iconURL: String?
        let projectURL: String?
        let clientStatus: String
        let statusSource: String
        let selectedByDefault: Bool
    }

    struct ClientExportResponseDTO: Codable {
        let serverName: String?
        let serverType: String
        let exportKind: String      // "zip" | "links" | "none"
        let isPaperLike: Bool
        let items: [ClientExportItemDTO]
        let selectedCount: Int
        let shareText: String?
        let zipFileName: String?
        let zipBase64: String?
        let note: String?

        init(serverName: String? = nil, serverType: String = "java", exportKind: String = "none",
             isPaperLike: Bool = false, items: [ClientExportItemDTO] = [], selectedCount: Int = 0,
             shareText: String? = nil, zipFileName: String? = nil, zipBase64: String? = nil,
             note: String? = nil) {
            self.serverName = serverName
            self.serverType = serverType
            self.exportKind = exportKind
            self.isPaperLike = isPaperLike
            self.items = items
            self.selectedCount = selectedCount
            self.shareText = shareText
            self.zipFileName = zipFileName
            self.zipBase64 = zipBase64
            self.note = note
        }
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
        /// True while a Bedrock level.dat repair is running (POST /worlds/repair).
        /// iOS polls GET /worlds and treats the false→true→false transition as "repair done".
        let isRepairing: Bool?

        init(slots: [WorldSlotDTO], activeSlotId: String?, serverRunning: Bool, isRepairing: Bool? = nil) {
            self.slots = slots
            self.activeSlotId = activeSlotId
            self.serverRunning = serverRunning
            self.isRepairing = isRepairing
        }
    }

    // MARK: - World Management (P9) — create / rename / replace / repair verbs.

    /// Result of any world-management mutation. `updated` echoes the fresh slot list
    /// so the iOS client can refresh in one round-trip (mirrors ResourcePackMutationResultDTO).
    struct WorldMutationResultDTO: Codable {
        let success: Bool
        let message: String
        let updated: WorldSlotsResponseDTO?

        init(success: Bool, message: String, updated: WorldSlotsResponseDTO? = nil) {
            self.success = success
            self.message = message
            self.updated = updated
        }
    }

    struct WorldCreateRequestDTO: Codable { let name: String; let seed: String? }
    struct WorldRenameRequestDTO: Codable { let slotId: String; let name: String }
    struct WorldReplaceRequestDTO: Codable { let slotId: String; let sourceSlotId: String }
    struct WorldRepairRequestDTO: Codable { let slotId: String }

    // MARK: - Diagnostics: Health cards + startup problems (P10)

    /// One diagnostic health card, mirroring the Mac's HealthCardResult with the small
    /// presentational id→title/icon mapping folded in (so iOS renders without re-deriving).
    struct HealthCardDTO: Codable {
        let id: String            // "directory","java","vm","jar","ram","worldData","port","lastStartup"
        let title: String         // long title, e.g. "Server Directory"
        let shortLabel: String    // e.g. "Directory"
        let severity: String      // "green" | "yellow" | "red" | "gray"
        let detail: String?       // detectedValue (card back text)
        let iconSystemName: String
        let actionLabel: String?
        /// Machine-readable action hint, e.g. "diagnoseStartup", "openComponentsTab",
        /// "openConsoleLog", "locateFolder", "openRouterPortForwardGuide", "triggerDownload",
        /// "openURL:https://…". Nil when the card has no action.
        let actionCode: String?
    }

    struct HealthResponseDTO: Codable {
        let serverType: String
        let serverName: String
        let serverRunning: Bool
        /// Worst card severity: red > yellow > green > gray.
        let overallSeverity: String
        let cards: [HealthCardDTO]
        let note: String?

        init(serverType: String, serverName: String = "", serverRunning: Bool = false,
             overallSeverity: String = "gray", cards: [HealthCardDTO] = [], note: String? = nil) {
            self.serverType = serverType
            self.serverName = serverName
            self.serverRunning = serverRunning
            self.overallSeverity = overallSeverity
            self.cards = cards
            self.note = note
        }
    }

    /// One parsed startup problem, with the repair actions the client may trigger.
    struct StartupProblemDTO: Codable {
        let id: String
        let kind: String          // missingDependency | incompatibleVersion | duplicate | loadError | unknown
        let kindTitle: String
        let iconSystemName: String
        let offenderName: String
        let requirement: String?
        let installedFile: String?
        let installedJarStem: String?
        let missingDependency: String?
        let rawExcerpt: String
        let isRepairing: Bool
        /// Subset of ["update","install","disable","delete"] valid for this problem.
        let availableActions: [String]
        /// Optional web link to view the offender on Modrinth.
        let modrinthURL: String?
    }

    struct HealthProblemsResponseDTO: Codable {
        let serverType: String
        let serverRunning: Bool
        /// True when the server started but some add-ons failed (soft fail) vs couldn't start.
        let isSoftFail: Bool
        let problems: [StartupProblemDTO]
        let note: String?

        init(serverType: String, serverRunning: Bool = false, isSoftFail: Bool = false,
             problems: [StartupProblemDTO] = [], note: String? = nil) {
            self.serverType = serverType
            self.serverRunning = serverRunning
            self.isSoftFail = isSoftFail
            self.problems = problems
            self.note = note
        }
    }

    struct HealthRepairRequestDTO: Codable { let problemId: String; let action: String }

    struct HealthRepairResultDTO: Codable {
        let success: Bool
        let message: String
        let updated: HealthProblemsResponseDTO?

        init(success: Bool, message: String, updated: HealthProblemsResponseDTO? = nil) {
            self.success = success
            self.message = message
            self.updated = updated
        }
    }

    // MARK: - Connectivity (P11) — "is the server joinable right now?"

    struct ConnectivityPlayitDTO: Codable {
        let enabled: Bool
        let running: Bool
        let address: String?
    }

    struct ConnectivityBroadcastDTO: Codable {
        let xboxRunning: Bool
        let bedrockRunning: Bool
    }

    struct ConnectivityResponseDTO: Codable {
        let serverType: String
        let serverName: String
        let serverRunning: Bool
        /// reachable | unreachable | offline | starting | unknown
        let status: String
        /// green | yellow | red | gray
        let severity: String
        let headline: String
        let detail: String?
        /// The effective public endpoint players should use, e.g. "1.2.3.4:25565".
        let joinAddress: String?
        /// How joinAddress was derived: playit | duckdns | public-ip | none
        let method: String
        let localListening: Bool?
        /// nil = external reachability couldn't be verified.
        let externallyReachable: Bool?
        let playersOnline: Int?
        let playersMax: Int?
        let motd: String?
        let playit: ConnectivityPlayitDTO?
        let broadcast: ConnectivityBroadcastDTO?
        let note: String?

        init(serverType: String, serverName: String = "", serverRunning: Bool = false,
             status: String, severity: String, headline: String, detail: String? = nil,
             joinAddress: String? = nil, method: String = "none",
             localListening: Bool? = nil, externallyReachable: Bool? = nil,
             playersOnline: Int? = nil, playersMax: Int? = nil, motd: String? = nil,
             playit: ConnectivityPlayitDTO? = nil, broadcast: ConnectivityBroadcastDTO? = nil,
             note: String? = nil) {
            self.serverType = serverType
            self.serverName = serverName
            self.serverRunning = serverRunning
            self.status = status
            self.severity = severity
            self.headline = headline
            self.detail = detail
            self.joinAddress = joinAddress
            self.method = method
            self.localListening = localListening
            self.externallyReachable = externallyReachable
            self.playersOnline = playersOnline
            self.playersMax = playersMax
            self.motd = motd
            self.playit = playit
            self.broadcast = broadcast
            self.note = note
        }
    }

    // MARK: - Backups

    struct BackupConfigResponseDTO: Codable {
        let serverName: String
        let autoBackupEnabled: Bool
        let autoBackupIntervalMinutes: Int
        let autoBackupMaxCount: Int
        let intervalOptions: [Int]
        let note: String?
        init(serverName: String, autoBackupEnabled: Bool, autoBackupIntervalMinutes: Int,
             autoBackupMaxCount: Int, intervalOptions: [Int] = [15,30,45,60,120,240,360],
             note: String? = nil) {
            self.serverName = serverName
            self.autoBackupEnabled = autoBackupEnabled
            self.autoBackupIntervalMinutes = autoBackupIntervalMinutes
            self.autoBackupMaxCount = autoBackupMaxCount
            self.intervalOptions = intervalOptions
            self.note = note
        }
    }

    struct BackupConfigUpdateRequestDTO: Codable {
        let autoBackupEnabled: Bool?
        let autoBackupIntervalMinutes: Int?
        let autoBackupMaxCount: Int?
    }

    struct BackupConfigUpdateResultDTO: Codable {
        let success: Bool
        let message: String
        let config: BackupConfigResponseDTO?
        init(success: Bool, message: String, config: BackupConfigResponseDTO? = nil) {
            self.success = success; self.message = message; self.config = config
        }
    }

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

    // MARK: - Versions (server JAR / version picker)

    struct VersionEntryDTO: Codable {
        let id: String
        let displayLabel: String
        let mcVersion: String
        let loaderVersion: String?
        let buildLabel: String?
        let isStable: Bool
        let isLatest: Bool
    }

    struct VersionsResponseDTO: Codable {
        let supportsVersions: Bool
        let flavorName: String
        let currentVersion: String?
        let isBedrock: Bool
        let versions: [VersionEntryDTO]
        let note: String?
        init(supportsVersions: Bool, flavorName: String = "", currentVersion: String? = nil,
             isBedrock: Bool = false, versions: [VersionEntryDTO] = [], note: String? = nil) {
            self.supportsVersions = supportsVersions; self.flavorName = flavorName
            self.currentVersion = currentVersion; self.isBedrock = isBedrock
            self.versions = versions; self.note = note
        }
    }

    struct VersionChangeRequestDTO: Codable {
        let versionId: String
        let loaderVersion: String?
    }

    struct VersionChangeResultDTO: Codable {
        let success: Bool
        let message: String
        let requiresRestart: Bool
    }

    // MARK: - Resource Packs

    struct ResourcePackItemDTO: Codable {
        let id: String             // pack.id (filename, or "geyser:<filename>" for Geyser)
        let name: String           // display name (no extension)
        let fileName: String       // with extension
        let fileSizeDisplay: String // formatted size e.g. "1.4 MB"
        let packKind: String       // "java" | "bedrock" | "geyser"
        let isActive: Bool         // Java: in server.properties; Geyser: in packs/ (not packs-disabled/)
        let typeLabel: String      // "Java ZIP", "Bedrock .mcpack", "Bedrock (folder)"
    }

    struct ResourcePacksResponseDTO: Codable {
        let serverType: String        // "java" | "bedrock"
        let isJava: Bool
        let packs: [ResourcePackItemDTO]
        let geyserPacks: [ResourcePackItemDTO]
        let isGeyserAvailable: Bool
        let activePackUrl: String?    // current resource-pack URL from server.properties (Java only)
        let requirePack: Bool         // require-resource-pack (Java only)
        let note: String?

        init(serverType: String, isJava: Bool = true, packs: [ResourcePackItemDTO] = [],
             geyserPacks: [ResourcePackItemDTO] = [], isGeyserAvailable: Bool = false,
             activePackUrl: String? = nil, requirePack: Bool = false, note: String? = nil) {
            self.serverType = serverType; self.isJava = isJava
            self.packs = packs; self.geyserPacks = geyserPacks
            self.isGeyserAvailable = isGeyserAvailable
            self.activePackUrl = activePackUrl; self.requirePack = requirePack; self.note = note
        }
    }

    struct ResourcePackMutationResultDTO: Codable {
        let success: Bool
        let message: String
        let updated: ResourcePacksResponseDTO?  // fresh list after mutation (nil on failure)

        init(success: Bool, message: String, updated: ResourcePacksResponseDTO? = nil) {
            self.success = success; self.message = message; self.updated = updated
        }
    }

    // Request bodies (decoded server-side only)

    struct ResourcePackActivateRequestDTO: Codable {
        let packId: String?   // nil = clear active pack; set = activate this local pack
        let require: Bool?
    }

    struct ResourcePackSetURLRequestDTO: Codable {
        let url: String       // direct URL to write to server.properties
        let sha1: String?
        let require: Bool?
    }

    struct ResourcePackToggleRequestDTO: Codable {
        let packId: String    // geyser pack id
        let enabled: Bool
    }

    struct ResourcePackRemoveRequestDTO: Codable {
        let packId: String    // pack id
        let packKind: String  // "java" | "geyser" | "bedrock"
    }

    // MARK: - Playit tunnel (P12)

    struct PlayitStatusResponseDTO: Codable {
        let serverName: String
        let serverType: String      // "java" | "bedrock"
        let playitEnabled: Bool     // enabled on the active server
        let isRunning: Bool         // tunnel subprocess is running
        let hasSecretKey: Bool      // secret key saved in Keychain
        let javaAddress: String?    // stored Java tunnel address
        let bedrockAddress: String? // stored Bedrock tunnel address
        let voiceAddress: String?   // stored Voice tunnel address
        let voiceChatEnabled: Bool  // voice chat enabled on active server
        let note: String?

        init(serverName: String, serverType: String, playitEnabled: Bool, isRunning: Bool,
             hasSecretKey: Bool, javaAddress: String? = nil, bedrockAddress: String? = nil,
             voiceAddress: String? = nil, voiceChatEnabled: Bool = false, note: String? = nil) {
            self.serverName = serverName; self.serverType = serverType
            self.playitEnabled = playitEnabled; self.isRunning = isRunning
            self.hasSecretKey = hasSecretKey; self.javaAddress = javaAddress
            self.bedrockAddress = bedrockAddress; self.voiceAddress = voiceAddress
            self.voiceChatEnabled = voiceChatEnabled; self.note = note
        }
    }

    struct PlayitActionResultDTO: Codable {
        // started | stopped | already_running | not_running | not_enabled | no_secret_key | no_server
        let result: String
        let message: String?

        init(result: String, message: String? = nil) {
            self.result = result; self.message = message
        }
    }

    // MARK: - DuckDNS (P13)

    struct DuckDNSStatusResponseDTO: Codable {
        let hostname: String?
        let isConfigured: Bool

        init(hostname: String? = nil) {
            self.hostname = hostname
            self.isConfigured = hostname != nil && !hostname!.isEmpty
        }
    }

    struct DuckDNSUpdateResultDTO: Codable {
        let success: Bool
        let hostname: String?
        let message: String?

        init(success: Bool, hostname: String? = nil, message: String? = nil) {
            self.success = success; self.hostname = hostname; self.message = message
        }
    }

    // MARK: - Geyser config (P13)

    struct GeyserConfigResponseDTO: Codable {
        let serverName: String
        let serverType: String      // "java" | "bedrock"
        let isGeyserInstalled: Bool
        let address: String?
        let port: Int?
        let configFileExists: Bool
        let note: String?

        init(serverName: String = "", serverType: String = "java", isGeyserInstalled: Bool = false,
             address: String? = nil, port: Int? = nil, configFileExists: Bool = false, note: String? = nil) {
            self.serverName = serverName; self.serverType = serverType
            self.isGeyserInstalled = isGeyserInstalled
            self.address = address; self.port = port
            self.configFileExists = configFileExists; self.note = note
        }
    }

    struct GeyserConfigUpdateResultDTO: Codable {
        let success: Bool
        let message: String  // "updated" | "no_server" | "not_installed" | "write_failed"
        let address: String?
        let port: Int?

        init(success: Bool, message: String, address: String? = nil, port: Int? = nil) {
            self.success = success; self.message = message; self.address = address; self.port = port
        }
    }

    // MARK: - /me (P17 — extended)

    /// Returned by GET /me. Additive: old iOS builds only read `role`.
    struct MeResponseDTO: Codable {
        let role: String        // "admin" | "guest" | "named"
        let name: String?       // nil for the owner's Keychain token and the legacy guest token
        let permissions: [String]?  // nil for admin (all), omitted/nil for guest (none), list for named
        let isNamedToken: Bool  // false for the two legacy shared tokens and the owner token

        init(role: String, name: String? = nil, permissions: [String]? = nil, isNamedToken: Bool = false) {
            self.role = role; self.name = name
            self.permissions = permissions; self.isNamedToken = isNamedToken
        }
    }

    // MARK: - Named users (P17)

    /// Safe summary of one shared-access entry — never includes the raw token string.
    struct UserSummaryDTO: Codable {
        let id: String
        let label: String
        let role: String            // "admin" | "guest" | "named"
        let permissions: [String]?  // nil when using role semantics
        let createdAtISO8601: String?
        let expiresAtISO8601: String?
        let isExpired: Bool

        init(id: String, label: String, role: String, permissions: [String]? = nil,
             createdAtISO8601: String? = nil, expiresAtISO8601: String? = nil, isExpired: Bool = false) {
            self.id = id; self.label = label; self.role = role
            self.permissions = permissions
            self.createdAtISO8601 = createdAtISO8601; self.expiresAtISO8601 = expiresAtISO8601
            self.isExpired = isExpired
        }
    }

    struct UserListResponseDTO: Codable {
        let users: [UserSummaryDTO]

        init(users: [UserSummaryDTO] = []) { self.users = users }
    }

    struct UserCreateResultDTO: Codable {
        let success: Bool
        let message: String     // "created" | "label_empty" | "invalid_role" | "invalid_permissions"
        let user: UserSummaryDTO?
        /// Raw token string — returned ONCE at creation, never retrievable again.
        let token: String?

        init(success: Bool, message: String, user: UserSummaryDTO? = nil, token: String? = nil) {
            self.success = success; self.message = message; self.user = user; self.token = token
        }
    }

    struct UserRevokeResultDTO: Codable {
        let success: Bool
        let message: String     // "revoked" | "not_found"

        init(success: Bool, message: String) { self.success = success; self.message = message }
    }

    struct UserUpdateResultDTO: Codable {
        let success: Bool
        let message: String     // "updated" | "not_found" | "label_empty" | "invalid_role"
        let user: UserSummaryDTO?

        init(success: Bool, message: String, user: UserSummaryDTO? = nil) {
            self.success = success; self.message = message; self.user = user
        }
    }
}

//
//  iOSModelMirrors.swift
//  MSCmacOSTests
//
//  NAMESPACE WRAPPER for iOS DTO contract tests (M3, Prompt 2.3).
//
//  WHY THIS FILE EXISTS (not the iOS source file itself):
//  Compiling MSCiOS/MSCRemoteiOS_Swift/RemoteAPIModels.swift directly into this
//  test target would cause Swift redeclaration errors: the macOS module (imported
//  via @testable import Minecraft_Server_Controller) already exports top-level
//  types named `RemoteAPIStatus` and `ServerType` that collide with the iOS file's
//  identically-named top-level types.  Swift has no per-file module scoping in a
//  monolithic test bundle, so the only collision-free approach is to redeclare the
//  iOS types inside an enum namespace.
//
//  MAINTENANCE RULE: Keep this file in sync with
//      MSCiOS/MSCRemoteiOS_Swift/RemoteAPIModels.swift
//  Any CodingKey or type change in the iOS file must be reflected here AND in
//  DTOContractTests.swift.  If the files drift, the contract tests will fail at
//  runtime (fields decode to nil / wrong values), which is the detection we want.
//
//  TRADEOFF: This file is a secondary hand-maintained copy.  The benefit is that
//  tests exercise real JSON round-trips and catch wire-key drift.  The risk is a
//  false-negative if THIS file drifts from RemoteAPIModels.swift.  Guard against
//  that by reviewing both files together on any iOS DTO change.

import Foundation

enum iOSModels {

    // MARK: - Status

    struct RemoteAPIStatus: Codable, Equatable {
        let running: Bool
        let activeServerId: String?
        let pid: Int?
        /// iOS decodes serverType as a typed enum; older macOS builds omit it → default .java.
        let serverType: ServerTypeRaw?
        let dockerContainerRunning: Bool?
        let dockerContainerStatus: String?
    }

    /// Mirrors the iOS ServerType enum's raw string values.
    enum ServerTypeRaw: String, Codable {
        case java
        case bedrock
    }

    // MARK: - Players

    struct PlayerDTO: Codable, Equatable {
        let name: String
        let uuid: String?
    }

    /// iOS calls this PlayersResponse (macOS calls it PlayersResponseDTO).
    /// JSON wire keys are identical: `players`, `count`, `note`.
    struct PlayersResponse: Codable, Equatable {
        let players: [PlayerDTO]
        let count: Int
        let note: String?
    }

    // MARK: - Settings Schema

    struct SettingOptionDTO: Codable, Equatable {
        let value: String
        let label: String
    }

    struct SettingFieldDTO: Codable, Equatable {
        let key: String
        let label: String
        let help: String?
        let type: String
        let value: String
        let minInt: Int?
        let maxInt: Int?
        let unit: String?
        let maxLength: Int?
        let options: [SettingOptionDTO]?
    }

    struct SettingsSectionDTO: Codable, Equatable {
        let id: String
        let title: String
        let icon: String
        let fields: [SettingFieldDTO]
    }

    struct SettingsResponseDTO: Codable, Equatable {
        let serverType: String
        let serverName: String
        let serverRunning: Bool
        let editable: Bool
        let sections: [SettingsSectionDTO]
        let note: String?
    }

    struct SettingRejectionDTO: Codable, Equatable {
        let key: String
        let reason: String
    }

    struct SettingsUpdateResultDTO: Codable, Equatable {
        let success: Bool
        let message: String
        let restartRequired: Bool
        let appliedKeys: [String]
        let rejected: [SettingRejectionDTO]?
        let sections: [SettingsSectionDTO]?
    }

    // MARK: - Components

    struct ComponentStatusDTO: Codable, Equatable {
        let name: String
        let installedBuild: Int?
        let latestBuild: Int?
        let installedVersion: String?
        let latestVersion: String?
        let isUpToDate: Bool
    }

    struct ComponentsStatusDTO: Codable, Equatable {
        let components: [ComponentStatusDTO]
        let restartRequiredToApply: Bool
    }

    struct ComponentUpdateResultDTO: Codable, Equatable {
        let success: Bool
        let message: String
        let newBuild: Int?
        let newVersion: String?
    }

    // MARK: - Add-ons

    struct AddonItemDTO: Codable, Equatable {
        let jarStem: String
        let displayName: String
        let isEnabled: Bool
        let projectId: String?
        let currentVersion: String?
        let availableVersion: String?
        let bucket: String
        let iconURL: String?
    }

    struct AddonsResponseDTO: Codable, Equatable {
        let addons: [AddonItemDTO]
        let isResolving: Bool
        let serverSupportsAddons: Bool
        let packManaged: Bool?
        let packName: String?
    }

    struct AddonUpdateResultDTO: Codable, Equatable {
        let result: String
        let jarStem: String?
        let count: Int
    }

    struct AddonRemoveResultDTO: Codable, Equatable {
        let success: Bool
        let message: String
        let jarStem: String
    }

    // MARK: - World Slots

    struct WorldSlotDTO: Codable, Equatable {
        let id: String
        let name: String
        let isActive: Bool
        let createdAt: String
        let zipSizeBytes: Int64?
        let worldSeed: String?
    }

    struct WorldSlotsResponseDTO: Codable, Equatable {
        let slots: [WorldSlotDTO]
        let activeSlotId: String?
        let serverRunning: Bool
        let isRepairing: Bool?
    }

    struct WorldMutationResultDTO: Codable, Equatable {
        let success: Bool
        let message: String
        let updated: WorldSlotsResponseDTO?
    }

    // MARK: - Backups

    struct BackupItemDTO: Codable, Equatable {
        let id: String
        let displayName: String
        let fileSize: Int64?
        let modificationDate: String?
        let isAutomatic: Bool
        let slotId: String?
        let slotName: String?
        let triggerReason: String
    }

    struct BackupsResponseDTO: Codable, Equatable {
        let backups: [BackupItemDTO]
    }

    struct BackupConfigResponseDTO: Codable, Equatable {
        let serverName: String
        let autoBackupEnabled: Bool
        let autoBackupIntervalMinutes: Int
        let autoBackupMaxCount: Int
        let intervalOptions: [Int]
        let note: String?
    }

    struct BackupConfigUpdateResultDTO: Codable, Equatable {
        let success: Bool
        let message: String
        let config: BackupConfigResponseDTO?
    }

    // MARK: - Users / Me

    /// iOS declares isNamedToken as Bool? (handles older servers that omit the field).
    /// macOS declares it as Bool (always present). Wire-compatible: both decode from JSON.
    struct MeResponseDTO: Codable, Equatable {
        let role: String
        let name: String?
        let permissions: [String]?
        let isNamedToken: Bool?
    }

    struct UserSummaryDTO: Codable, Equatable {
        let id: String
        let label: String
        let role: String
        let permissions: [String]?
        let createdAtISO8601: String?
        let expiresAtISO8601: String?
        let isExpired: Bool
    }

    struct UserListResponseDTO: Codable, Equatable {
        let users: [UserSummaryDTO]
    }

    struct UserCreateResultDTO: Codable, Equatable {
        let success: Bool
        let message: String
        let user: UserSummaryDTO?
        let token: String?
    }

    struct UserRevokeResultDTO: Codable, Equatable {
        let success: Bool
        let message: String
    }

    struct UserUpdateResultDTO: Codable, Equatable {
        let success: Bool
        let message: String
        let user: UserSummaryDTO?
    }

    // MARK: - Broadcast

    struct BroadcastStatusDTO: Codable, Equatable {
        let xboxBroadcastRunning: Bool
        let bedrockBroadcastRunning: Bool
    }

    struct BroadcastAutoStartDTO: Codable, Equatable {
        let enabled: Bool
    }

    struct BroadcastAuthPromptDTO: Codable, Equatable {
        let isPresent: Bool
        let code: String?
        let linkURL: String?
    }

    // MARK: - Health

    struct HealthCardDTO: Codable, Equatable {
        let id: String
        let title: String
        let shortLabel: String
        let severity: String
        let detail: String?
        let iconSystemName: String
        let actionLabel: String?
        let actionCode: String?
    }

    struct HealthResponseDTO: Codable, Equatable {
        let serverType: String
        let serverName: String
        let serverRunning: Bool
        let overallSeverity: String
        let cards: [HealthCardDTO]
        let note: String?
    }

    struct StartupProblemDTO: Codable, Equatable {
        let id: String
        let kind: String
        let kindTitle: String
        let iconSystemName: String
        let offenderName: String
        let requirement: String?
        let installedFile: String?
        let installedJarStem: String?
        let missingDependency: String?
        let rawExcerpt: String
        let isRepairing: Bool
        let availableActions: [String]
        let modrinthURL: String?
    }

    struct HealthProblemsResponseDTO: Codable, Equatable {
        let serverType: String
        let serverRunning: Bool
        let isSoftFail: Bool
        let problems: [StartupProblemDTO]
        let note: String?
    }

    struct HealthRepairResultDTO: Codable, Equatable {
        let success: Bool
        let message: String
        let updated: HealthProblemsResponseDTO?
    }

    // MARK: - Connectivity

    struct ConnectivityPlayitDTO: Codable, Equatable {
        let enabled: Bool
        let running: Bool
        let address: String?
    }

    struct ConnectivityBroadcastDTO: Codable, Equatable {
        let xboxRunning: Bool
        let bedrockRunning: Bool
    }

    struct ConnectivityResponseDTO: Codable, Equatable {
        let serverType: String
        let serverName: String
        let serverRunning: Bool
        let status: String
        let severity: String
        let headline: String
        let detail: String?
        let joinAddress: String?
        let method: String
        let localListening: Bool?
        let externallyReachable: Bool?
        let playersOnline: Int?
        let playersMax: Int?
        let motd: String?
        let playit: ConnectivityPlayitDTO?
        let broadcast: ConnectivityBroadcastDTO?
        let note: String?
    }

    // MARK: - Resource Packs

    struct ResourcePackItemDTO: Codable, Equatable {
        let id: String
        let name: String
        let fileName: String
        let fileSizeDisplay: String
        let packKind: String
        let isActive: Bool
        let typeLabel: String
    }

    struct ResourcePacksResponseDTO: Codable, Equatable {
        let serverType: String
        let isJava: Bool
        let packs: [ResourcePackItemDTO]
        let geyserPacks: [ResourcePackItemDTO]
        let isGeyserAvailable: Bool
        let activePackUrl: String?
        let requirePack: Bool
        let note: String?
    }

    struct ResourcePackMutationResultDTO: Codable, Equatable {
        let success: Bool
        let message: String
        let updated: ResourcePacksResponseDTO?
    }

    // MARK: - Versions

    struct VersionEntryDTO: Codable, Equatable {
        let id: String
        let displayLabel: String
        let mcVersion: String
        let loaderVersion: String?
        let buildLabel: String?
        let isStable: Bool
        let isLatest: Bool
    }

    struct VersionsResponseDTO: Codable, Equatable {
        let supportsVersions: Bool
        let flavorName: String
        let currentVersion: String?
        let isBedrock: Bool
        let versions: [VersionEntryDTO]
        let note: String?
    }

    struct VersionChangeResultDTO: Codable, Equatable {
        let success: Bool
        let message: String
        let requiresRestart: Bool
    }

    // MARK: - Playit

    struct PlayitStatusResponseDTO: Codable, Equatable {
        let serverName: String
        let serverType: String
        let playitEnabled: Bool
        let isRunning: Bool
        let hasSecretKey: Bool
        let javaAddress: String?
        let bedrockAddress: String?
        let voiceAddress: String?
        let voiceChatEnabled: Bool
        let note: String?
    }

    struct PlayitActionResultDTO: Codable, Equatable {
        let result: String
        let message: String?
    }

    // MARK: - DuckDNS / Geyser

    struct DuckDNSStatusResponseDTO: Codable, Equatable {
        let hostname: String?
        let isConfigured: Bool
    }

    struct DuckDNSUpdateResultDTO: Codable, Equatable {
        let success: Bool
        let hostname: String?
        let message: String?
    }

    struct GeyserConfigResponseDTO: Codable, Equatable {
        let serverName: String
        let serverType: String
        let isGeyserInstalled: Bool
        let address: String?
        let port: Int?
        let configFileExists: Bool
        let note: String?
    }

    struct GeyserConfigUpdateResultDTO: Codable, Equatable {
        let success: Bool
        let message: String
        let address: String?
        let port: Int?
    }

    // MARK: - Server Files

    struct ServerFileItemDTO: Codable, Equatable {
        let id: String
        let name: String
        let path: String
        let isDirectory: Bool
        let sizeBytes: Int64?
        let modifiedAt: String?
        let fileExtension: String?
        let isPreviewable: Bool?
    }

    struct ServerFilesResponseDTO: Codable, Equatable {
        let serverName: String?
        let path: String
        let parentPath: String?
        let items: [ServerFileItemDTO]
        let note: String?
    }

    struct ServerFileReadResponseDTO: Codable, Equatable {
        let success: Bool
        let message: String
        let path: String?
        let name: String?
        let sizeBytes: Int64?
        let content: String?
        let encoding: String?
        let truncated: Bool?
    }

    // MARK: - SimpleResult / CommandResult
    //
    // macOS defines these as private local structs inside respond(to:) in
    // RemoteAPIServer+HTTP.swift (not in RemoteAPIServerDTOs.swift).
    // iOS has them as top-level types in RemoteAPIModels.swift.
    // The JSON wire format is identical.

    struct SimpleResult: Codable, Equatable {
        let result: String
        let activeServerId: String?
    }

    struct CommandResult: Codable, Equatable {
        let result: String
        let activeServerId: String?
        let command: String
    }

    // MARK: - Request DTOs (iOS → macOS direction)
    //
    // macOS decodes these request bodies sent by iOS.  Wire compatibility means:
    // macOS must be able to decode whatever iOS encodes, and vice versa.

    /// macOS decodes: RemoteAPIServer.SettingsUpdateRequestDTO
    struct SettingsUpdateRequestDTO: Codable, Equatable {
        let changes: [String: String]
    }

    /// macOS decodes: RemoteAPIServer.CatalogInstallRequestDTO
    struct CatalogInstallRequestDTO: Codable, Equatable {
        let projectId: String
        let slug: String
        let title: String
    }

    /// macOS decodes: BroadcastCredentialsDTO
    /// iOS sends as BroadcastCredentialsRequest (private in RemoteAPIClient.swift).
    struct BroadcastCredentialsDTO: Codable, Equatable {
        let email: String
        let password: String
        let gamertag: String
    }
}

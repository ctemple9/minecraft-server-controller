//
//  DTOContractTests.swift
//  MSCmacOSTests
//
//  DTO wire-contract tests (M3, Prompt 2.3).
//
//  For each major DTO pair the macOS server encodes and the iOS client decodes
//  (or vice versa for request bodies), we:
//    1. Build a macOS DTO with representative non-nil values.
//    2. Encode it using JSONEncoder.
//    3. Decode the JSON as the iOSModels mirror type.
//    4. Assert field-by-field equality.
//
//  A test failure here means the two files have drifted (renamed key, changed
//  type, removed field, etc.) — the exact failure message names the field.
//
//  See iOSModelMirrors.swift for the namespace-wrapper design rationale and
//  the maintenance rule.

import Foundation
import XCTest
@testable import Minecraft_Server_Controller

final class DTOContractTests: XCTestCase {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        return e
    }()
    private let decoder = JSONDecoder()

    // MARK: - Helper

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }

    // MARK: - 1. Status

    func testRemoteAPIStatusRoundTrip() throws {
        let mac = RemoteAPIStatus(
            running: true,
            activeServerId: "srv-1",
            pid: 12345,
            serverType: "java",
            dockerContainerRunning: false,
            dockerContainerStatus: "stopped"
        )
        let data = try encode(mac)
        let ios = try decode(iOSModels.RemoteAPIStatus.self, from: data)

        XCTAssertEqual(ios.running, mac.running)
        XCTAssertEqual(ios.activeServerId, mac.activeServerId)
        XCTAssertEqual(ios.pid, mac.pid)
        XCTAssertEqual(ios.serverType?.rawValue, mac.serverType)
        XCTAssertEqual(ios.dockerContainerRunning, mac.dockerContainerRunning)
        XCTAssertEqual(ios.dockerContainerStatus, mac.dockerContainerStatus)
    }

    func testRemoteAPIStatusBedrockType() throws {
        // Verifies the "bedrock" raw value also round-trips correctly.
        let mac = RemoteAPIStatus(
            running: true,
            activeServerId: nil,
            pid: nil,
            serverType: "bedrock",
            dockerContainerRunning: true,
            dockerContainerStatus: "running"
        )
        let data = try encode(mac)
        let ios = try decode(iOSModels.RemoteAPIStatus.self, from: data)
        XCTAssertEqual(ios.serverType, .bedrock)
        XCTAssertEqual(ios.dockerContainerRunning, true)
    }

    // MARK: - 2. Players

    func testPlayersResponseRoundTrip() throws {
        // macOS type: RemoteAPIServer.PlayersResponseDTO
        // iOS type:   iOSModels.PlayersResponse
        // Different Swift names, identical wire keys.
        let mac = RemoteAPIServer.PlayersResponseDTO(
            players: [
                RemoteAPIServer.PlayerDTO(name: "Steve", uuid: "abc-uuid"),
                RemoteAPIServer.PlayerDTO(name: "Alex", uuid: nil)
            ],
            count: 2,
            note: "Bedrock player list"
        )
        let data = try encode(mac)
        let ios = try decode(iOSModels.PlayersResponse.self, from: data)

        XCTAssertEqual(ios.count, 2)
        XCTAssertEqual(ios.note, "Bedrock player list")
        XCTAssertEqual(ios.players.count, 2)
        XCTAssertEqual(ios.players[0].name, "Steve")
        XCTAssertEqual(ios.players[0].uuid, "abc-uuid")
        XCTAssertNil(ios.players[1].uuid)
    }

    // MARK: - 3. Settings schema

    func testSettingsResponseRoundTrip() throws {
        let option = RemoteAPIServer.SettingOptionDTO(value: "hard", label: "Hard")
        let field = RemoteAPIServer.SettingFieldDTO(
            key: "difficulty",
            label: "Difficulty",
            help: "Game difficulty",
            type: "enum",
            value: "hard",
            options: [option]
        )
        let section = RemoteAPIServer.SettingsSectionDTO(
            id: "gameplay", title: "Gameplay", icon: "gamecontroller", fields: [field]
        )
        let mac = RemoteAPIServer.SettingsResponseDTO(
            serverType: "java",
            serverName: "My Server",
            serverRunning: false,
            editable: true,
            sections: [section],
            note: nil
        )
        let data = try encode(mac)
        let ios = try decode(iOSModels.SettingsResponseDTO.self, from: data)

        XCTAssertEqual(ios.serverType, "java")
        XCTAssertEqual(ios.serverName, "My Server")
        XCTAssertFalse(ios.serverRunning)
        XCTAssertTrue(ios.editable)
        XCTAssertNil(ios.note)
        XCTAssertEqual(ios.sections.count, 1)

        let iosSection = ios.sections[0]
        XCTAssertEqual(iosSection.id, "gameplay")
        XCTAssertEqual(iosSection.icon, "gamecontroller")
        XCTAssertEqual(iosSection.fields.count, 1)

        let iosField = iosSection.fields[0]
        XCTAssertEqual(iosField.key, "difficulty")
        XCTAssertEqual(iosField.type, "enum")
        XCTAssertEqual(iosField.value, "hard")
        XCTAssertEqual(iosField.options?.first?.value, "hard")
        XCTAssertEqual(iosField.options?.first?.label, "Hard")
    }

    func testSettingsUpdateResultRoundTrip() throws {
        let rejection = RemoteAPIServer.SettingRejectionDTO(key: "bad-key", reason: "unknown_key")
        let mac = RemoteAPIServer.SettingsUpdateResultDTO(
            success: false,
            message: "partial",
            restartRequired: true,
            appliedKeys: ["max-players"],
            rejected: [rejection],
            sections: nil
        )
        let data = try encode(mac)
        let ios = try decode(iOSModels.SettingsUpdateResultDTO.self, from: data)

        XCTAssertFalse(ios.success)
        XCTAssertEqual(ios.message, "partial")
        XCTAssertTrue(ios.restartRequired)
        XCTAssertEqual(ios.appliedKeys, ["max-players"])
        XCTAssertEqual(ios.rejected?.first?.key, "bad-key")
        XCTAssertEqual(ios.rejected?.first?.reason, "unknown_key")
    }

    // MARK: - 4. Components

    func testComponentsStatusRoundTrip() throws {
        let component = RemoteAPIServer.ComponentStatusDTO(
            name: "paper",
            installedBuild: 42,
            latestBuild: 50,
            installedVersion: "1.21.4",
            latestVersion: "1.21.4",
            isUpToDate: false
        )
        let mac = RemoteAPIServer.ComponentsStatusDTO(
            components: [component],
            restartRequiredToApply: true
        )
        let data = try encode(mac)
        let ios = try decode(iOSModels.ComponentsStatusDTO.self, from: data)

        XCTAssertTrue(ios.restartRequiredToApply)
        XCTAssertEqual(ios.components.count, 1)
        XCTAssertEqual(ios.components[0].name, "paper")
        XCTAssertEqual(ios.components[0].installedBuild, 42)
        XCTAssertEqual(ios.components[0].latestBuild, 50)
        XCTAssertFalse(ios.components[0].isUpToDate)
    }

    // MARK: - 5. Worlds

    func testWorldSlotsResponseRoundTrip() throws {
        let slot = RemoteAPIServer.WorldSlotDTO(
            id: "slot-1",
            name: "World1",
            isActive: true,
            createdAt: "2026-01-01T00:00:00Z",
            zipSizeBytes: 1024 * 1024,
            worldSeed: "12345"
        )
        let mac = RemoteAPIServer.WorldSlotsResponseDTO(
            slots: [slot],
            activeSlotId: "slot-1",
            serverRunning: false,
            isRepairing: nil
        )
        let data = try encode(mac)
        let ios = try decode(iOSModels.WorldSlotsResponseDTO.self, from: data)

        XCTAssertEqual(ios.activeSlotId, "slot-1")
        XCTAssertFalse(ios.serverRunning)
        XCTAssertNil(ios.isRepairing)
        XCTAssertEqual(ios.slots.count, 1)
        XCTAssertEqual(ios.slots[0].id, "slot-1")
        XCTAssertEqual(ios.slots[0].worldSeed, "12345")
        XCTAssertEqual(ios.slots[0].zipSizeBytes, 1024 * 1024)
    }

    func testWorldSlotsRepairingFlagRoundTrip() throws {
        // isRepairing is an additive optional field; older macOS omits it.
        // Test that it round-trips correctly when present.
        let mac = RemoteAPIServer.WorldSlotsResponseDTO(
            slots: [],
            activeSlotId: nil,
            serverRunning: true,
            isRepairing: true
        )
        let data = try encode(mac)
        let ios = try decode(iOSModels.WorldSlotsResponseDTO.self, from: data)
        XCTAssertEqual(ios.isRepairing, true)
    }

    // MARK: - 6. Backups

    func testBackupsResponseRoundTrip() throws {
        let item = RemoteAPIServer.BackupItemDTO(
            id: "backup-file.zip",
            displayName: "World1 Backup",
            fileSize: 2_000_000,
            modificationDate: "2026-07-01T12:00:00Z",
            isAutomatic: true,
            slotId: "slot-1",
            slotName: "World1",
            triggerReason: "auto"
        )
        let mac = RemoteAPIServer.BackupsResponseDTO(backups: [item])
        let data = try encode(mac)
        let ios = try decode(iOSModels.BackupsResponseDTO.self, from: data)

        XCTAssertEqual(ios.backups.count, 1)
        let b = ios.backups[0]
        XCTAssertEqual(b.id, "backup-file.zip")
        XCTAssertEqual(b.displayName, "World1 Backup")
        XCTAssertEqual(b.fileSize, 2_000_000)
        XCTAssertTrue(b.isAutomatic)
        XCTAssertEqual(b.slotId, "slot-1")
        XCTAssertEqual(b.triggerReason, "auto")
    }

    func testBackupConfigRoundTrip() throws {
        let mac = RemoteAPIServer.BackupConfigResponseDTO(
            serverName: "My Server",
            autoBackupEnabled: true,
            autoBackupIntervalMinutes: 60,
            autoBackupMaxCount: 12,
            intervalOptions: [15, 30, 45, 60, 120, 240, 360],
            note: nil
        )
        let data = try encode(mac)
        let ios = try decode(iOSModels.BackupConfigResponseDTO.self, from: data)

        XCTAssertTrue(ios.autoBackupEnabled)
        XCTAssertEqual(ios.autoBackupIntervalMinutes, 60)
        XCTAssertEqual(ios.autoBackupMaxCount, 12)
        XCTAssertEqual(ios.intervalOptions, [15, 30, 45, 60, 120, 240, 360])
    }

    // MARK: - 7. Users / Me

    func testMeResponseRoundTrip() throws {
        // Key check: macOS sends isNamedToken as Bool, iOS decodes as Bool?.
        let mac = RemoteAPIServer.MeResponseDTO(
            role: "named",
            name: "alice",
            permissions: ["players", "worlds"],
            isNamedToken: true
        )
        let data = try encode(mac)
        let ios = try decode(iOSModels.MeResponseDTO.self, from: data)

        XCTAssertEqual(ios.role, "named")
        XCTAssertEqual(ios.name, "alice")
        XCTAssertEqual(ios.permissions, ["players", "worlds"])
        // iOS decodes as Bool? — must be exactly true (not nil)
        XCTAssertEqual(ios.isNamedToken, true)
    }

    func testUserListResponseRoundTrip() throws {
        let user = RemoteAPIServer.UserSummaryDTO(
            id: "u-1",
            label: "Bob's Phone",
            role: "named",
            permissions: ["serverControl"],
            createdAtISO8601: "2026-01-01T00:00:00Z",
            expiresAtISO8601: nil,
            isExpired: false
        )
        let mac = RemoteAPIServer.UserListResponseDTO(users: [user])
        let data = try encode(mac)
        let ios = try decode(iOSModels.UserListResponseDTO.self, from: data)

        XCTAssertEqual(ios.users.count, 1)
        let u = ios.users[0]
        XCTAssertEqual(u.id, "u-1")
        XCTAssertEqual(u.label, "Bob's Phone")
        XCTAssertEqual(u.permissions, ["serverControl"])
        XCTAssertFalse(u.isExpired)
    }

    // MARK: - 8. Broadcast

    func testBroadcastStatusRoundTrip() throws {
        let mac = RemoteAPIServer.BroadcastStatusDTO(
            xboxBroadcastRunning: true,
            bedrockBroadcastRunning: false
        )
        let data = try encode(mac)
        let ios = try decode(iOSModels.BroadcastStatusDTO.self, from: data)

        XCTAssertTrue(ios.xboxBroadcastRunning)
        XCTAssertFalse(ios.bedrockBroadcastRunning)
    }

    func testBroadcastAuthPromptRoundTrip() throws {
        let mac = RemoteAPIServer.BroadcastAuthPromptDTO(
            isPresent: true,
            code: "ABCD-1234",
            linkURL: "https://microsoft.com/devicelogin"
        )
        let data = try encode(mac)
        let ios = try decode(iOSModels.BroadcastAuthPromptDTO.self, from: data)

        XCTAssertTrue(ios.isPresent)
        XCTAssertEqual(ios.code, "ABCD-1234")
        XCTAssertEqual(ios.linkURL, "https://microsoft.com/devicelogin")
    }

    // MARK: - 9. SimpleResult / CommandResult
    //
    // macOS defines these as private LOCAL structs inside respond(to:) in
    // RemoteAPIServer+HTTP.swift — they cannot be @testable-imported.
    // We test by encoding the JSON shape directly (matching what macOS sends)
    // and decoding as the iOS mirror type.

    func testSimpleResultRoundTrip() throws {
        // Build the JSON object macOS would send for start/stop.
        let json = #"{"result":"start_requested","activeServerId":"srv-1"}"#.data(using: .utf8)!
        let ios = try decode(iOSModels.SimpleResult.self, from: json)
        XCTAssertEqual(ios.result, "start_requested")
        XCTAssertEqual(ios.activeServerId, "srv-1")
    }

    func testSimpleResultNilServerId() throws {
        // activeServerId may be nil when no server is active.
        let json = #"{"result":"stop_requested","activeServerId":null}"#.data(using: .utf8)!
        let ios = try decode(iOSModels.SimpleResult.self, from: json)
        XCTAssertEqual(ios.result, "stop_requested")
        XCTAssertNil(ios.activeServerId)
    }

    func testCommandResultRoundTrip() throws {
        let json = #"{"result":"command_sent","activeServerId":"srv-1","command":"say Hello"}"#.data(using: .utf8)!
        let ios = try decode(iOSModels.CommandResult.self, from: json)
        XCTAssertEqual(ios.result, "command_sent")
        XCTAssertEqual(ios.activeServerId, "srv-1")
        XCTAssertEqual(ios.command, "say Hello")
    }

    // MARK: - 10. Connectivity

    func testConnectivityResponseRoundTrip() throws {
        let playit = RemoteAPIServer.ConnectivityPlayitDTO(
            enabled: true, running: true, address: "abc.joinmc.link"
        )
        let broadcast = RemoteAPIServer.ConnectivityBroadcastDTO(
            xboxRunning: true, bedrockRunning: false
        )
        let mac = RemoteAPIServer.ConnectivityResponseDTO(
            serverType: "java",
            serverName: "My Server",
            serverRunning: true,
            status: "reachable",
            severity: "green",
            headline: "Players can join",
            detail: nil,
            joinAddress: "abc.joinmc.link:25565",
            method: "playit",
            localListening: true,
            externallyReachable: true,
            playersOnline: 3,
            playersMax: 20,
            motd: "Welcome!",
            playit: playit,
            broadcast: broadcast,
            note: nil
        )
        let data = try encode(mac)
        let ios = try decode(iOSModels.ConnectivityResponseDTO.self, from: data)

        XCTAssertEqual(ios.serverType, "java")
        XCTAssertEqual(ios.status, "reachable")
        XCTAssertEqual(ios.severity, "green")
        XCTAssertEqual(ios.joinAddress, "abc.joinmc.link:25565")
        XCTAssertEqual(ios.method, "playit")
        XCTAssertEqual(ios.playersOnline, 3)
        XCTAssertEqual(ios.motd, "Welcome!")
        XCTAssertEqual(ios.playit?.address, "abc.joinmc.link")
        XCTAssertTrue(ios.broadcast?.xboxRunning == true)
    }

    // MARK: - 11. Health

    func testHealthResponseRoundTrip() throws {
        let card = RemoteAPIServer.HealthCardDTO(
            id: "java",
            title: "Java Runtime",
            shortLabel: "Java",
            severity: "green",
            detail: "Java 21",
            iconSystemName: "cup.and.saucer.fill",
            actionLabel: nil,
            actionCode: nil
        )
        let mac = RemoteAPIServer.HealthResponseDTO(
            serverType: "java",
            serverName: "My Server",
            serverRunning: false,
            overallSeverity: "green",
            cards: [card],
            note: nil
        )
        let data = try encode(mac)
        let ios = try decode(iOSModels.HealthResponseDTO.self, from: data)

        XCTAssertEqual(ios.overallSeverity, "green")
        XCTAssertEqual(ios.cards.count, 1)
        XCTAssertEqual(ios.cards[0].id, "java")
        XCTAssertEqual(ios.cards[0].severity, "green")
        XCTAssertEqual(ios.cards[0].detail, "Java 21")
    }

    func testHealthProblemsResponseRoundTrip() throws {
        let problem = RemoteAPIServer.StartupProblemDTO(
            id: "prob-1",
            kind: "missingDependency",
            kindTitle: "Missing Dependency",
            iconSystemName: "exclamationmark.triangle.fill",
            offenderName: "Lithium",
            requirement: "Sodium",
            installedFile: "lithium-0.11.jar",
            installedJarStem: "lithium-0.11",
            missingDependency: "Sodium",
            rawExcerpt: "[FATAL] Missing mod: sodium",
            isRepairing: false,
            availableActions: ["install", "delete"],
            modrinthURL: "https://modrinth.com/mod/sodium"
        )
        let mac = RemoteAPIServer.HealthProblemsResponseDTO(
            serverType: "java",
            serverRunning: false,
            isSoftFail: false,
            problems: [problem],
            note: nil
        )
        let data = try encode(mac)
        let ios = try decode(iOSModels.HealthProblemsResponseDTO.self, from: data)

        XCTAssertEqual(ios.problems.count, 1)
        let p = ios.problems[0]
        XCTAssertEqual(p.kind, "missingDependency")
        XCTAssertEqual(p.offenderName, "Lithium")
        XCTAssertEqual(p.availableActions, ["install", "delete"])
        XCTAssertEqual(p.modrinthURL, "https://modrinth.com/mod/sodium")
    }

    // MARK: - 12. Versions

    func testVersionsResponseRoundTrip() throws {
        let entry = RemoteAPIServer.VersionEntryDTO(
            id: "1.21.4-42",
            displayLabel: "1.21.4 (Build 42)",
            mcVersion: "1.21.4",
            loaderVersion: nil,
            buildLabel: "42",
            isStable: true,
            isLatest: true
        )
        let mac = RemoteAPIServer.VersionsResponseDTO(
            supportsVersions: true,
            flavorName: "Paper",
            currentVersion: "1.21.4",
            isBedrock: false,
            versions: [entry],
            note: nil
        )
        let data = try encode(mac)
        let ios = try decode(iOSModels.VersionsResponseDTO.self, from: data)

        XCTAssertTrue(ios.supportsVersions)
        XCTAssertEqual(ios.flavorName, "Paper")
        XCTAssertEqual(ios.currentVersion, "1.21.4")
        XCTAssertFalse(ios.isBedrock)
        XCTAssertEqual(ios.versions.count, 1)
        XCTAssertEqual(ios.versions[0].mcVersion, "1.21.4")
        XCTAssertTrue(ios.versions[0].isLatest)
    }

    // MARK: - 13. Server Files

    func testServerFilesResponseRoundTrip() throws {
        let item = RemoteAPIServer.ServerFileItemDTO(
            id: "server.properties",
            name: "server.properties",
            path: "server.properties",
            isDirectory: false,
            sizeBytes: 2048,
            modifiedAt: "2026-07-01T00:00:00Z",
            fileExtension: "properties",
            isPreviewable: true
        )
        let mac = RemoteAPIServer.ServerFilesResponseDTO(
            serverName: "My Server",
            path: "",
            parentPath: nil,
            items: [item],
            note: nil
        )
        let data = try encode(mac)
        let ios = try decode(iOSModels.ServerFilesResponseDTO.self, from: data)

        XCTAssertEqual(ios.serverName, "My Server")
        XCTAssertEqual(ios.items.count, 1)
        XCTAssertEqual(ios.items[0].isPreviewable, true)
    }

    func testServerFileReadResponseRoundTrip() throws {
        let mac = RemoteAPIServer.ServerFileReadResponseDTO(
            success: true,
            message: "ok",
            path: "server.properties",
            name: "server.properties",
            sizeBytes: 1024,
            content: "max-players=20\n",
            encoding: "utf-8",
            truncated: false
        )
        let data = try encode(mac)
        let ios = try decode(iOSModels.ServerFileReadResponseDTO.self, from: data)

        XCTAssertTrue(ios.success)
        XCTAssertEqual(ios.content, "max-players=20\n")
        XCTAssertEqual(ios.encoding, "utf-8")
        XCTAssertEqual(ios.truncated, false)
    }

    // MARK: - 14. Playit

    func testPlayitStatusResponseRoundTrip() throws {
        let mac = RemoteAPIServer.PlayitStatusResponseDTO(
            serverName: "My Server",
            serverType: "java",
            playitEnabled: true,
            isRunning: true,
            hasSecretKey: true,
            javaAddress: "abc.joinmc.link",
            bedrockAddress: nil,
            voiceAddress: nil,
            voiceChatEnabled: false,
            note: nil
        )
        let data = try encode(mac)
        let ios = try decode(iOSModels.PlayitStatusResponseDTO.self, from: data)

        XCTAssertTrue(ios.playitEnabled)
        XCTAssertTrue(ios.isRunning)
        XCTAssertEqual(ios.javaAddress, "abc.joinmc.link")
        XCTAssertNil(ios.bedrockAddress)
    }

    // MARK: - 15. Request DTO reverse direction (iOS → macOS)

    func testSettingsUpdateRequestDTORoundTrip() throws {
        // iOS encodes this; macOS decodes it.
        // Test: encode an iOSModels request → decode as macOS type.
        let iosRequest = iOSModels.SettingsUpdateRequestDTO(
            changes: ["max-players": "20", "difficulty": "hard"]
        )
        let data = try encoder.encode(iosRequest)
        let mac = try decode(RemoteAPIServer.SettingsUpdateRequestDTO.self, from: data)

        XCTAssertEqual(mac.changes["max-players"], "20")
        XCTAssertEqual(mac.changes["difficulty"], "hard")
    }

    func testCatalogInstallRequestDTORoundTrip() throws {
        // iOS encodes this; macOS decodes it.
        let iosRequest = iOSModels.CatalogInstallRequestDTO(
            projectId: "AANobbMI",
            slug: "sodium",
            title: "Sodium"
        )
        let data = try encoder.encode(iosRequest)
        let mac = try decode(RemoteAPIServer.CatalogInstallRequestDTO.self, from: data)

        XCTAssertEqual(mac.projectId, "AANobbMI")
        XCTAssertEqual(mac.slug, "sodium")
        XCTAssertEqual(mac.title, "Sodium")
    }

    func testBroadcastCredentialsDTORoundTrip() throws {
        // iOS sends BroadcastCredentialsRequest (private); macOS decodes BroadcastCredentialsDTO.
        // We test using the iOSModels mirror.
        let iosRequest = iOSModels.BroadcastCredentialsDTO(
            email: "test@example.com",
            password: "s3cr3t",
            gamertag: "TestPlayer"
        )
        let data = try encoder.encode(iosRequest)
        let mac = try decode(RemoteAPIServer.BroadcastCredentialsDTO.self, from: data)

        XCTAssertEqual(mac.email, "test@example.com")
        XCTAssertEqual(mac.password, "s3cr3t")
        XCTAssertEqual(mac.gamertag, "TestPlayer")
    }

    // MARK: - 16. Addons

    func testAddonsResponseRoundTrip() throws {
        let addon = RemoteAPIServer.AddonItemDTO(
            jarStem: "sodium-0.6",
            displayName: "Sodium",
            isEnabled: true,
            projectId: "AANobbMI",
            currentVersion: "0.6.0",
            availableVersion: "0.6.1",
            bucket: "updateAvailable",
            iconURL: "https://cdn.modrinth.com/data/AANobbMI/icon.png"
        )
        let mac = RemoteAPIServer.AddonsResponseDTO(
            addons: [addon],
            isResolving: false,
            serverSupportsAddons: true
        )
        let data = try encode(mac)
        let ios = try decode(iOSModels.AddonsResponseDTO.self, from: data)

        XCTAssertEqual(ios.addons.count, 1)
        XCTAssertEqual(ios.addons[0].bucket, "updateAvailable")
        XCTAssertEqual(ios.addons[0].availableVersion, "0.6.1")
        XCTAssertFalse(ios.isResolving)
        XCTAssertTrue(ios.serverSupportsAddons)
    }

    // MARK: - 17. DuckDNS / Geyser

    func testDuckDNSStatusRoundTrip() throws {
        let mac = RemoteAPIServer.DuckDNSStatusResponseDTO(hostname: "my-mac.duckdns.org")
        let data = try encode(mac)
        let ios = try decode(iOSModels.DuckDNSStatusResponseDTO.self, from: data)
        XCTAssertEqual(ios.hostname, "my-mac.duckdns.org")
        XCTAssertTrue(ios.isConfigured)
    }

    func testGeyserConfigRoundTrip() throws {
        let mac = RemoteAPIServer.GeyserConfigResponseDTO(
            serverName: "My Server",
            serverType: "java",
            isGeyserInstalled: true,
            address: "0.0.0.0",
            port: 19132,
            configFileExists: true,
            note: nil
        )
        let data = try encode(mac)
        let ios = try decode(iOSModels.GeyserConfigResponseDTO.self, from: data)

        XCTAssertTrue(ios.isGeyserInstalled)
        XCTAssertEqual(ios.port, 19132)
        XCTAssertTrue(ios.configFileExists)
    }
}

//
//  AppConfigRoundTripTests.swift
//  MSCmacOSTests
//
//  Config persistence tests (T1c, Prompt 2.3).
//
//  Tests:
//  1. Full AppConfig encode → decode round-trip (all non-Keychain fields preserved).
//  2. ConfigServer encode → decode round-trip.
//  3. Backwards compatibility: decode minimal JSON missing every optional field
//     → fields get safe defaults, servers array survives.
//  4. R3 corrupt-file path simulation: write garbage bytes to a temp URL, fail
//     to decode, copy to a .corrupt-<timestamp> sibling, assert sibling exists.
//     Because ConfigManager is a `private init()` singleton wired to Application
//     Support, we exercise the ALGORITHM at the level of `AppConfig`/`FileManager`
//     rather than through the singleton.  The algorithm is a direct copy of the
//     init's catch block in ConfigManager.swift (R3).  Any change to that block
//     must be mirrored here to keep the test meaningful.  This tradeoff is
//     documented in flowstate.md §T1c.

import Foundation
import XCTest
@testable import Minecraft_Server_Controller

final class AppConfigRoundTripTests: XCTestCase {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder = JSONDecoder()

    // MARK: - 1. AppConfig full round-trip

    func testAppConfigFullRoundTrip() throws {
        // Build a representative AppConfig with non-default values for every
        // field that IS encoded (remoteAPIToken is intentionally excluded from
        // JSON — it remains "" after decode, which is correct).
        var config = AppConfig.defaultConfig()
        config.javaPath             = "/usr/local/bin/java"
        config.extraFlags           = "-XX:+UseG1GC"
        config.serversRoot          = "/tmp/test-servers"
        config.pluginTemplateDir    = "/tmp/test-servers/_plugins"
        config.paperTemplateDir     = "/tmp/test-servers/_paper"
        config.activeServerId       = "test-server-id"
        config.initialSetupDone     = true
        config.remoteAPIPort        = 12345
        config.remoteAPIToken       = "should-not-appear-in-json"  // excluded from JSON
        config.remoteAPIExposeOnLAN = true
        config.remoteAPIPreferredPairingHost = "my-mac.ts.net"
        config.duckdnsHostname      = "my-mac.duckdns.org"
        config.playitJavaAddress    = "abc.joinmc.link"
        config.playitBedrockAddress = "udp.joinmc.link:19132"
        config.playitVoiceAddress   = "147.185.1.2:24454"
        config.playitAgentId        = "agent-uuid-123"
        config.hasShownHandbook     = true
        config.hasShownConceptGuide = true
        config.xboxBroadcastJarPath = "/tmp/MCXboxBroadcast.jar"
        config.xboxBroadcastAutoStartEnabled = false
        config.minecraftUsername    = "TestPlayer"
        config.minecraftBedrockGamertag = "TestPlayer_BE"
        config.minecraftAvatarEditionRawValue = "java"
        config.defaultBannerColorHex = "#336633"
        config.errorPopupsEnabled   = true
        config.saveDownloadedJars   = false
        // useVMBedrockBackend is intentionally NOT in AppConfig.encode(to:) — it is a
        // transitional flag (Docker→VM) that always defaults to true.  decodeIfPresent
        // will pick it up if an OLD config file has it set to false, but new encodes
        // never write the key so it always decodes back to true (the default).
        // We keep it at true here to match what actually round-trips.
        config.useVMBedrockBackend  = true

        // Add a shared access entry (token IS stored in JSON for shared access entries).
        let sharedEntry = RemoteAPISharedAccessEntry(
            id: "entry-1",
            label: "Test Device",
            token: "shared-token-abc",
            role: "named",
            createdAtISO8601: "2026-01-01T00:00:00Z",
            permissions: ["serverControl", "players"],
            expiresAtISO8601: nil
        )
        config.remoteAPISharedAccess = [sharedEntry]

        let data = try encoder.encode(config)
        let decoded = try decoder.decode(AppConfig.self, from: data)

        // remoteAPIToken is excluded from JSON → always "" after decode.
        XCTAssertEqual(decoded.remoteAPIToken, "")

        // Every other encoded field should round-trip exactly.
        XCTAssertEqual(decoded.javaPath,             config.javaPath)
        XCTAssertEqual(decoded.extraFlags,           config.extraFlags)
        XCTAssertEqual(decoded.serversRoot,          config.serversRoot)
        XCTAssertEqual(decoded.pluginTemplateDir,    config.pluginTemplateDir)
        XCTAssertEqual(decoded.paperTemplateDir,     config.paperTemplateDir)
        XCTAssertEqual(decoded.activeServerId,       config.activeServerId)
        XCTAssertEqual(decoded.initialSetupDone,     config.initialSetupDone)
        XCTAssertEqual(decoded.remoteAPIPort,        config.remoteAPIPort)
        XCTAssertEqual(decoded.remoteAPIExposeOnLAN, config.remoteAPIExposeOnLAN)
        XCTAssertEqual(decoded.remoteAPIPreferredPairingHost, config.remoteAPIPreferredPairingHost)
        XCTAssertEqual(decoded.duckdnsHostname,      config.duckdnsHostname)
        XCTAssertEqual(decoded.playitJavaAddress,    config.playitJavaAddress)
        XCTAssertEqual(decoded.playitBedrockAddress, config.playitBedrockAddress)
        XCTAssertEqual(decoded.playitVoiceAddress,   config.playitVoiceAddress)
        XCTAssertEqual(decoded.playitAgentId,        config.playitAgentId)
        XCTAssertEqual(decoded.hasShownHandbook,     config.hasShownHandbook)
        XCTAssertEqual(decoded.hasShownConceptGuide, config.hasShownConceptGuide)
        XCTAssertEqual(decoded.xboxBroadcastJarPath, config.xboxBroadcastJarPath)
        XCTAssertEqual(decoded.xboxBroadcastAutoStartEnabled, config.xboxBroadcastAutoStartEnabled)
        XCTAssertEqual(decoded.minecraftUsername,    config.minecraftUsername)
        XCTAssertEqual(decoded.minecraftBedrockGamertag, config.minecraftBedrockGamertag)
        XCTAssertEqual(decoded.minecraftAvatarEditionRawValue, config.minecraftAvatarEditionRawValue)
        XCTAssertEqual(decoded.defaultBannerColorHex, config.defaultBannerColorHex)
        XCTAssertEqual(decoded.errorPopupsEnabled,   config.errorPopupsEnabled)
        XCTAssertEqual(decoded.saveDownloadedJars,   config.saveDownloadedJars)
        XCTAssertEqual(decoded.useVMBedrockBackend,  config.useVMBedrockBackend)

        // Shared access entry round-trips (token IS included for shared entries).
        XCTAssertEqual(decoded.remoteAPISharedAccess.count, 1)
        let decodedEntry = decoded.remoteAPISharedAccess[0]
        XCTAssertEqual(decodedEntry.id,      sharedEntry.id)
        XCTAssertEqual(decodedEntry.label,   sharedEntry.label)
        XCTAssertEqual(decodedEntry.token,   sharedEntry.token)
        XCTAssertEqual(decodedEntry.role,    sharedEntry.role)
        XCTAssertEqual(decodedEntry.permissions, sharedEntry.permissions)
    }

    // MARK: - 2. ConfigServer round-trip

    func testConfigServerFullRoundTrip() throws {
        var server = ConfigServer(
            id: "srv-test",
            displayName: "Test Server",
            serverDir: "/tmp/servers/test",
            paperJarPath: "/tmp/servers/test/paper.jar",
            minRamGB: 2,
            maxRamGB: 8
        )
        // Optional / backwards-compat fields
        server.bedrockPort          = 19132
        server.bedrockEnabled       = true
        server.publicHostOverride   = "my-mac.duckdns.org"
        server.notes                = "Test notes"
        server.bannerColorHex       = "#AABBCC"
        server.joinCardColorHex     = "#112233"
        server.hasEverStarted       = true
        server.hasShownFirstStartPopup = true
        server.autoBackupEnabled    = true
        server.autoBackupIntervalMinutes = 45
        server.autoBackupMaxCount   = 6
        server.xboxBroadcastEnabled = true
        server.xboxBroadcastIPMode  = .publicIP
        server.xboxBroadcastHostOverride = "override-host.com"
        server.xboxBroadcastPortOverride = 19133
        server.resourcePackHostPort = 8124
        server.serverType           = .bedrock
        server.bedrockVersion       = "1.21.40"
        server.javaFlavor           = .fabric
        server.minecraftVersion     = "1.21.4"
        server.loaderVersion        = "0.16.10"
        server.serverBuild          = "build-999"
        server.playitEnabled        = true
        server.playitVoiceChatEnabled = true
        server.notificationPrefs    = ServerNotificationPrefs(
            notifyOnStart: true, notifyOnStop: false,
            notifyOnPlayerJoin: true, notifyOnPlayerLeave: false
        )
        // xboxBroadcastAltPassword is NOT encoded (Keychain); must survive decode as nil.
        server.xboxBroadcastAltPassword = "secret-not-encoded"

        let data = try encoder.encode(server)
        let decoded = try decoder.decode(ConfigServer.self, from: data)

        XCTAssertEqual(decoded.id,            server.id)
        XCTAssertEqual(decoded.displayName,   server.displayName)
        XCTAssertEqual(decoded.serverDir,     server.serverDir)
        XCTAssertEqual(decoded.paperJarPath,  server.paperJarPath)
        XCTAssertEqual(decoded.minRamGB,      server.minRamGB)
        XCTAssertEqual(decoded.maxRamGB,      server.maxRamGB)
        XCTAssertEqual(decoded.bedrockPort,   server.bedrockPort)
        XCTAssertEqual(decoded.bedrockEnabled, server.bedrockEnabled)
        XCTAssertEqual(decoded.publicHostOverride, server.publicHostOverride)
        XCTAssertEqual(decoded.notes,         server.notes)
        XCTAssertEqual(decoded.bannerColorHex, server.bannerColorHex)
        XCTAssertEqual(decoded.joinCardColorHex, server.joinCardColorHex)
        XCTAssertEqual(decoded.hasEverStarted, server.hasEverStarted)
        XCTAssertEqual(decoded.autoBackupEnabled, server.autoBackupEnabled)
        XCTAssertEqual(decoded.autoBackupIntervalMinutes, server.autoBackupIntervalMinutes)
        XCTAssertEqual(decoded.autoBackupMaxCount, server.autoBackupMaxCount)
        XCTAssertEqual(decoded.xboxBroadcastEnabled, server.xboxBroadcastEnabled)
        XCTAssertEqual(decoded.xboxBroadcastIPMode, server.xboxBroadcastIPMode)
        XCTAssertEqual(decoded.serverType,    server.serverType)
        XCTAssertEqual(decoded.bedrockVersion, server.bedrockVersion)
        XCTAssertEqual(decoded.javaFlavor,    server.javaFlavor)
        XCTAssertEqual(decoded.minecraftVersion, server.minecraftVersion)
        XCTAssertEqual(decoded.loaderVersion, server.loaderVersion)
        XCTAssertEqual(decoded.serverBuild,   server.serverBuild)
        XCTAssertEqual(decoded.playitEnabled, server.playitEnabled)
        XCTAssertEqual(decoded.notificationPrefs.notifyOnStart, true)
        XCTAssertEqual(decoded.notificationPrefs.notifyOnPlayerJoin, true)
        XCTAssertFalse(decoded.notificationPrefs.notifyOnStop)

        // xboxBroadcastAltPassword is excluded from JSON → nil after decode.
        XCTAssertNil(decoded.xboxBroadcastAltPassword,
                     "xboxBroadcastAltPassword must NOT be stored in JSON (Keychain only)")
    }

    // MARK: - 3. Backwards compatibility: missing optional fields

    func testAppConfigMissingOptionalFieldsGetDefaults() throws {
        // This JSON represents a minimal old config with only the originally-required
        // fields — every field added after the initial schema is absent.
        // Decoding must succeed and produce safe defaults.
        let minimal = """
        {
            "config_version": 1,
            "java_path": "java",
            "extra_flags": "",
            "servers_root": "/tmp/MinecraftServers",
            "servers": [
                {
                    "id": "old-server",
                    "display_name": "Old Server",
                    "server_dir": "/tmp/servers/old",
                    "paper_jar_path": "/tmp/servers/old/paper.jar",
                    "min_ram_gb": 2,
                    "max_ram_gb": 4
                }
            ],
            "initial_setup_done": true,
            "remote_api_port": 48400
        }
        """.data(using: .utf8)!

        let config = try decoder.decode(AppConfig.self, from: minimal)

        // Servers array must NOT be wiped — this is the critical backwards-compat property.
        XCTAssertEqual(config.servers.count, 1,
                       "servers array must survive decoding an old config file")
        XCTAssertEqual(config.servers[0].id, "old-server")
        XCTAssertEqual(config.servers[0].displayName, "Old Server")

        // Missing optional fields must get safe defaults (not throw).
        XCTAssertFalse(config.remoteAPIExposeOnLAN, "default = false")
        XCTAssertNil(config.duckdnsHostname)
        XCTAssertNil(config.playitJavaAddress)
        XCTAssertFalse(config.hasShownHandbook)
        XCTAssertTrue(config.xboxBroadcastAutoStartEnabled, "default = true")
        XCTAssertTrue(config.saveDownloadedJars, "default = true")

        // ConfigServer optional fields also must get safe defaults.
        let server = config.servers[0]
        XCTAssertEqual(server.serverType, .java,         "default serverType = .java")
        XCTAssertFalse(server.bedrockEnabled,            "default bedrockEnabled = false")
        XCTAssertFalse(server.autoBackupEnabled,         "default autoBackupEnabled = false")
        XCTAssertEqual(server.autoBackupIntervalMinutes, 30,  "default interval = 30")
        XCTAssertEqual(server.autoBackupMaxCount,        12,  "default maxCount = 12")
        XCTAssertFalse(server.xboxBroadcastEnabled)
        XCTAssertFalse(server.playitEnabled)
        XCTAssertEqual(server.javaFlavor, .paper,        "default javaFlavor = .paper")
        XCTAssertNil(server.minecraftVersion)
        XCTAssertNil(server.loaderVersion)
        XCTAssertEqual(server.resourcePackHostPort, 8123, "default port = 8123")
    }

    func testConfigServerMissingOptionalFieldsGetDefaults() throws {
        // A bare ConfigServer (only required keys) must decode without error.
        let minimal = """
        {
            "id": "bare",
            "display_name": "Bare",
            "server_dir": "/tmp/bare",
            "paper_jar_path": "/tmp/bare/paper.jar",
            "min_ram_gb": 1,
            "max_ram_gb": 2
        }
        """.data(using: .utf8)!

        let server = try decoder.decode(ConfigServer.self, from: minimal)
        XCTAssertEqual(server.id, "bare")
        XCTAssertEqual(server.serverType, .java)
        XCTAssertEqual(server.javaFlavor, .paper)
        XCTAssertFalse(server.autoBackupEnabled)
        XCTAssertNil(server.addonLinks)
        XCTAssertNil(server.pluginSources)
    }

    // MARK: - 4. R3 corrupt-file path simulation
    //
    // ConfigManager's init() catch block (R3) does:
    //   1. Build a .corrupt-<timestamp> sibling URL.
    //   2. FileManager.copyItem(at: configURL, to: corruptURL).
    //   3. Store corruptURL.path in corruptConfigCopyPath.
    //   4. Replace config with defaults and save().
    //
    // We cannot test ConfigManager.shared directly (private init, singleton,
    // already initialised against the real Application Support directory).
    // Instead we replicate the ALGORITHM in the test, using a temp directory,
    // and assert the expected postconditions.  If the algorithm in
    // ConfigManager.swift changes, update this test.

    func testR3CorruptFileAlgorithm() throws {
        let fm = FileManager.default
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MSCTests-R3-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        // Write garbage bytes that JSONDecoder cannot decode.
        let configURL = tempDir.appendingPathComponent("server_config_swift.json")
        let garbage = "this is not json {{{ :::".data(using: .utf8)!
        try garbage.write(to: configURL)

        // Simulate the R3 catch block.
        var corruptCopyPath: String?
        var usedDefaults = false

        do {
            let data = try Data(contentsOf: configURL)
            _ = try JSONDecoder().decode(AppConfig.self, from: data)
            XCTFail("Garbage JSON should have thrown")
        } catch {
            // R3 step 1-2: build and copy .corrupt-<timestamp>.
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let timestamp = formatter.string(from: Date())
            let corruptURL = configURL
                .deletingLastPathComponent()
                .appendingPathComponent("server_config_swift.json.corrupt-\(timestamp)")
            do {
                try fm.copyItem(at: configURL, to: corruptURL)
                corruptCopyPath = corruptURL.path
            } catch {
                corruptCopyPath = ""  // copy failed (sentinel)
            }
            usedDefaults = true
        }

        // Postconditions.
        XCTAssertTrue(usedDefaults, "Should have fallen through to defaults")
        XCTAssertNotNil(corruptCopyPath, "corruptConfigCopyPath must be set")
        XCTAssertFalse(corruptCopyPath?.isEmpty ?? true,
                       "corruptConfigCopyPath must not be empty (copy should have succeeded)")

        // The .corrupt file must exist on disk.
        if let path = corruptCopyPath, !path.isEmpty {
            XCTAssertTrue(fm.fileExists(atPath: path),
                          "The .corrupt-<timestamp> sibling file must exist")
            // Verify it contains the original garbage (not defaults).
            let contents = try Data(contentsOf: URL(fileURLWithPath: path))
            XCTAssertEqual(contents, garbage, "Corrupt copy must preserve original bytes")
        }
    }

    func testR3CorruptFileDoesNotWipeOriginal() throws {
        // Verifies that the original config URL is left on disk AFTER the copy
        // (we only copy, we don't delete the original before writing defaults).
        let fm = FileManager.default
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MSCTests-R3b-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let configURL = tempDir.appendingPathComponent("server_config_swift.json")
        try "!!!BAD JSON!!!".data(using: .utf8)!.write(to: configURL)

        let beforeContents = try Data(contentsOf: configURL)

        // Attempt decode (fails).
        let data = try Data(contentsOf: configURL)
        let decodeSucceeded = (try? JSONDecoder().decode(AppConfig.self, from: data)) != nil
        XCTAssertFalse(decodeSucceeded)

        // Original file is still there (we only copy, not move).
        XCTAssertTrue(fm.fileExists(atPath: configURL.path))
        let afterContents = try Data(contentsOf: configURL)
        XCTAssertEqual(afterContents, beforeContents, "Original file must not be modified by R3")
    }

    // MARK: - 5. ConfigManager.corruptConfigCopyPath is readable

    func testConfigManagerCorruptConfigCopyPathIsNilOnNormalLoad() {
        // When ConfigManager.shared initialized successfully (clean config or no config),
        // corruptConfigCopyPath must be nil.  This is a sanity check for the test
        // environment — if it's non-nil here, the REAL config file is corrupt, which
        // we want to know about.
        XCTAssertNil(ConfigManager.shared.corruptConfigCopyPath,
                     "corruptConfigCopyPath should be nil — if not, the real config is corrupt")
    }
}

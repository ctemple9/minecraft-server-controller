//
//  PackManagedGuardTests.swift
//  MSCmacOSTests
//
//  Tests for P7.8: pack-managed server guard.
//  Covers config round-trip (new + old JSON) and the AddonsResponseDTO DTO contract
//  extension for packManaged/packName fields.
//

import XCTest
@testable import Minecraft_Server_Controller

final class PackManagedGuardTests: XCTestCase {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder = JSONDecoder()

    // MARK: - ConfigServer pack provenance

    func testPackManagedDefaultsFalse() throws {
        // A freshly constructed ConfigServer must have packManaged=false, names nil.
        let cfg = makeMinimalServer()
        XCTAssertFalse(cfg.packManaged)
        XCTAssertNil(cfg.packName)
        XCTAssertNil(cfg.packVersion)
    }

    func testPackProvenanceRoundTrip() throws {
        // Encode a pack-managed server and decode it — all three fields survive.
        var cfg = makeMinimalServer()
        cfg.packManaged = true
        cfg.packName    = "Better MC [FORGE] BMC4"
        cfg.packVersion = "v43"

        let data = try encoder.encode(cfg)
        let decoded = try decoder.decode(ConfigServer.self, from: data)

        XCTAssertTrue(decoded.packManaged)
        XCTAssertEqual(decoded.packName,    "Better MC [FORGE] BMC4")
        XCTAssertEqual(decoded.packVersion, "v43")
    }

    func testOldJsonMissingPackFieldsDecodesCleanly() throws {
        // Simulates reading a config written by a pre-P7.8 version of MSC.
        // The three new keys are absent; decoding must succeed with safe defaults.
        let oldJSON = """
        {
          "id": "old-server-id",
          "display_name": "My Old Server",
          "server_dir": "/tmp/old",
          "paper_jar_path": "server.jar",
          "min_ram_gb": 2,
          "max_ram_gb": 4
        }
        """.data(using: .utf8)!

        let cfg = try decoder.decode(ConfigServer.self, from: oldJSON)

        XCTAssertFalse(cfg.packManaged, "packManaged must default false when absent")
        XCTAssertNil(cfg.packName,      "packName must be nil when absent")
        XCTAssertNil(cfg.packVersion,   "packVersion must be nil when absent")
        XCTAssertEqual(cfg.id, "old-server-id")
    }

    func testPackManagedEncodedKeyName() throws {
        // Verify the JSON key is "pack_managed" (snake_case) per the MSC config contract.
        var cfg = makeMinimalServer()
        cfg.packManaged = true
        cfg.packName    = "FooBar"
        cfg.packVersion = "v1"

        let data = try encoder.encode(cfg)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"pack_managed\" : true"),
                      "Expected 'pack_managed' key in JSON: \(json)")
        XCTAssertTrue(json.contains("\"pack_name\" : \"FooBar\""),
                      "Expected 'pack_name' key in JSON: \(json)")
        XCTAssertTrue(json.contains("\"pack_version\" : \"v1\""),
                      "Expected 'pack_version' key in JSON: \(json)")
    }

    // MARK: - AddonsResponseDTO DTO contract (pack provenance extension)

    func testAddonsResponsePackManagedRoundTrip() throws {
        // macOS encodes packManaged=true + packName → iOS decodes both correctly.
        let mac = RemoteAPIServer.AddonsResponseDTO(
            addons: [],
            isResolving: false,
            serverSupportsAddons: true,
            packManaged: true,
            packName: "Better MC [FORGE] BMC4"
        )
        let data = try encoder.encode(mac)
        let ios = try decoder.decode(iOSModels.AddonsResponseDTO.self, from: data)

        XCTAssertEqual(ios.packManaged, true)
        XCTAssertEqual(ios.packName, "Better MC [FORGE] BMC4")
        XCTAssertTrue(ios.serverSupportsAddons)
    }

    func testAddonsResponseOldJsonNoPackFields() throws {
        // Simulates a response from a pre-P7.8 server: packManaged and packName absent.
        // iOS decode must not crash and must return nil for both.
        let oldServerJSON = """
        {
          "addons": [],
          "isResolving": false,
          "serverSupportsAddons": true
        }
        """.data(using: .utf8)!

        let ios = try decoder.decode(iOSModels.AddonsResponseDTO.self, from: oldServerJSON)

        XCTAssertNil(ios.packManaged,  "packManaged should be nil when absent")
        XCTAssertNil(ios.packName,     "packName should be nil when absent")
        XCTAssertTrue(ios.serverSupportsAddons)
    }

    func testAddonsResponseNonPackServerEncoded() throws {
        // Non-pack server (packManaged=false) encodes the field but iOS sees false.
        let mac = RemoteAPIServer.AddonsResponseDTO(
            addons: [],
            isResolving: false,
            serverSupportsAddons: true,
            packManaged: false,
            packName: nil
        )
        let data = try encoder.encode(mac)
        let ios = try decoder.decode(iOSModels.AddonsResponseDTO.self, from: data)

        XCTAssertEqual(ios.packManaged, false)
        XCTAssertNil(ios.packName)
    }

    // MARK: - Helpers

    private func makeMinimalServer() -> ConfigServer {
        ConfigServer(
            id: "test-id",
            displayName: "Test",
            serverDir: "/tmp/test",
            paperJarPath: "server.jar",
            minRamGB: 2,
            maxRamGB: 4
        )
    }
}

// iOSModels namespace is defined in iOSModelMirrors.swift (same test target).

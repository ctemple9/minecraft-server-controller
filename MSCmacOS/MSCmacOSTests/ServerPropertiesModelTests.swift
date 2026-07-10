//
//  ServerPropertiesModelTests.swift
//  MSCmacOSTests
//
//  Pins ServerPropertiesModel.mergedInto — unknown keys on disk survive a
//  round-trip (T1a, tranche #3). Behavior read from AppViewModelModels.swift.
//

import XCTest
@testable import Minecraft_Server_Controller

final class ServerPropertiesModelTests: XCTestCase {

    func testUnknownKeysSurviveRoundTrip() {
        // A real server.properties carries keys MSC doesn't model (rcon, resource
        // packs, custom plugin keys). They must be preserved verbatim.
        let disk: [String: String] = [
            "motd": "Hello",
            "max-players": "20",
            "enable-rcon": "true",
            "rcon.password": "s3cret",
            "rcon.port": "25575",
            "generator-settings": "{}",
            "some.plugin.custom-key": "value-42"
        ]
        let model = ServerPropertiesModel(from: disk)
        let merged = model.mergedInto(model.rawProperties)

        XCTAssertEqual(merged["enable-rcon"], "true")
        XCTAssertEqual(merged["rcon.password"], "s3cret")
        XCTAssertEqual(merged["rcon.port"], "25575")
        XCTAssertEqual(merged["generator-settings"], "{}")
        XCTAssertEqual(merged["some.plugin.custom-key"], "value-42")
    }

    func testKnownKeysAreOverlaidFromModel() {
        var model = ServerPropertiesModel(from: ["motd": "Old", "max-players": "20"])
        model.motd = "New"
        model.maxPlayers = 42
        let merged = model.mergedInto(model.rawProperties)
        XCTAssertEqual(merged["motd"], "New")
        XCTAssertEqual(merged["max-players"], "42")
    }

    func testMergedIntoWritesCanonicalBoolStrings() {
        var model = ServerPropertiesModel(from: [:])
        model.pvp = false
        model.onlineMode = true
        let merged = model.mergedInto(model.rawProperties)
        XCTAssertEqual(merged["pvp"], "false")
        XCTAssertEqual(merged["online-mode"], "true")
    }

    func testMergedIntoWritesEscapedLevelTypeRawValue() {
        var model = ServerPropertiesModel(from: [:])
        model.levelType = .largeBiomes
        let merged = model.mergedInto(model.rawProperties)
        // The on-disk form is the escaped namespaced rawValue.
        XCTAssertEqual(merged["level-type"], "minecraft\\:large_biomes")
    }

    func testMergedIntoPreservesUnknownKeysFromArbitraryTargetDict() {
        // mergedInto overlays onto whatever dict is passed, not just rawProperties.
        let model = ServerPropertiesModel(from: ["max-players": "10"])
        let target: [String: String] = ["untouched-key": "keep-me", "motd": "will-be-overwritten"]
        let merged = model.mergedInto(target)
        XCTAssertEqual(merged["untouched-key"], "keep-me")
        // motd gets overlaid with the model's value.
        XCTAssertEqual(merged["motd"], model.motd)
    }

    func testInitFromDictAppliesDefaultsForMissingKeys() {
        let model = ServerPropertiesModel(from: [:])
        XCTAssertEqual(model.maxPlayers, 20)
        XCTAssertEqual(model.serverPort, 25565)
        XCTAssertEqual(model.onlineMode, true)
        XCTAssertEqual(model.difficulty, .normal)
        XCTAssertEqual(model.gamemode, .survival)
        XCTAssertEqual(model.opPermissionLevel, 4)
    }

    func testLevelTypeLegacyAllCapsParsing() {
        // LevelType.from handles both namespaced and legacy forms.
        let model = ServerPropertiesModel(from: ["level-type": "LARGEBIOMES"])
        XCTAssertEqual(model.levelType, .largeBiomes)
        let flat = ServerPropertiesModel(from: ["level-type": "flat"])
        XCTAssertEqual(flat.levelType, .flat)
        let unknown = ServerPropertiesModel(from: ["level-type": "gobbledygook"])
        XCTAssertEqual(unknown.levelType, .normal)   // safe default
    }
}

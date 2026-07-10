//
//  ServerSettingsSchemaTests.swift
//  MSCmacOSTests
//
//  Pins ServerSettingsSchema apply/clamp/reject behavior + the escaped level-type
//  token mapping (T1a, tranche #2). Behavior read from RemoteAPIServer+Settings.swift.
//

import XCTest
@testable import Minecraft_Server_Controller

final class ServerSettingsSchemaTests: XCTestCase {

    /// A model with known baseline values so we can detect exactly what changed.
    private func baselineModel() -> ServerPropertiesModel {
        ServerPropertiesModel(from: [:], fallbackMotd: "Base")
    }

    // MARK: - Int clamping

    func testIntClampsAboveMax() {
        var m = baselineModel()
        let r = ServerSettingsSchema.applyJava(changes: ["max-players": "5000"], onto: &m)
        XCTAssertEqual(m.maxPlayers, 1000)              // clamped to max
        XCTAssertEqual(r.applied, ["max-players"])
        XCTAssertTrue(r.rejected.isEmpty)
    }

    func testIntClampsBelowMin() {
        var m = baselineModel()
        let r = ServerSettingsSchema.applyJava(changes: ["view-distance": "1"], onto: &m)
        XCTAssertEqual(m.viewDistance, 3)               // clamped to min
        XCTAssertEqual(r.applied, ["view-distance"])
    }

    func testIntWithinRangeAppliedVerbatim() {
        var m = baselineModel()
        let r = ServerSettingsSchema.applyJava(changes: ["server-port": "25570"], onto: &m)
        XCTAssertEqual(m.serverPort, 25570)
        XCTAssertEqual(r.applied, ["server-port"])
    }

    func testNonIntegerIntRejected() {
        var m = baselineModel()
        let before = m.maxPlayers
        let r = ServerSettingsSchema.applyJava(changes: ["max-players": "lots"], onto: &m)
        XCTAssertEqual(m.maxPlayers, before)
        XCTAssertTrue(r.applied.isEmpty)
        XCTAssertEqual(r.rejected.first?.key, "max-players")
        XCTAssertEqual(r.rejected.first?.reason, "not_an_integer")
    }

    // MARK: - Bool parsing

    func testBoolAcceptsSynonyms() {
        for (raw, expected) in [("on", true), ("yes", true), ("1", true),
                                ("off", false), ("no", false), ("0", false)] {
            var m = baselineModel()
            let r = ServerSettingsSchema.applyJava(changes: ["pvp": raw], onto: &m)
            XCTAssertEqual(m.pvp, expected, "raw=\(raw)")
            XCTAssertEqual(r.applied, ["pvp"])
        }
    }

    func testBoolRejectsGarbage() {
        var m = baselineModel()
        let r = ServerSettingsSchema.applyJava(changes: ["hardcore": "maybe"], onto: &m)
        XCTAssertEqual(r.rejected.first?.reason, "not_a_boolean")
        XCTAssertTrue(r.applied.isEmpty)
    }

    // MARK: - Enum validation

    func testDifficultyEnumAppliedAndCaseInsensitive() {
        var m = baselineModel()
        let r = ServerSettingsSchema.applyJava(changes: ["difficulty": "HARD"], onto: &m)
        XCTAssertEqual(m.difficulty, .hard)
        XCTAssertEqual(r.applied, ["difficulty"])
    }

    func testInvalidEnumRejected() {
        var m = baselineModel()
        let r = ServerSettingsSchema.applyJava(changes: ["gamemode": "sleeping"], onto: &m)
        XCTAssertEqual(r.rejected.first?.reason, "invalid_value")
        XCTAssertTrue(r.applied.isEmpty)
    }

    func testOpPermissionLevelBoundsEnforced() {
        var m = baselineModel()
        let ok = ServerSettingsSchema.applyJava(changes: ["op-permission-level": "3"], onto: &m)
        XCTAssertEqual(m.opPermissionLevel, 3)
        XCTAssertEqual(ok.applied, ["op-permission-level"])

        var m2 = baselineModel()
        let bad = ServerSettingsSchema.applyJava(changes: ["op-permission-level": "9"], onto: &m2)
        XCTAssertEqual(bad.rejected.first?.reason, "invalid_value")
    }

    // MARK: - Unknown keys

    func testUnknownKeyRejected() {
        var m = baselineModel()
        let r = ServerSettingsSchema.applyJava(changes: ["totally-made-up": "x"], onto: &m)
        XCTAssertEqual(r.rejected.first?.key, "totally-made-up")
        XCTAssertEqual(r.rejected.first?.reason, "unknown_key")
        XCTAssertTrue(r.applied.isEmpty)
    }

    // MARK: - MOTD truncation

    func testMOTDTruncatedTo200Chars() {
        var m = baselineModel()
        let long = String(repeating: "z", count: 250)
        let r = ServerSettingsSchema.applyJava(changes: ["motd": long], onto: &m)
        XCTAssertEqual(m.motd.count, 200)
        XCTAssertEqual(r.applied, ["motd"])
    }

    // MARK: - Escaped level-type token mapping

    func testLevelTokenMapsLargeBiomesToUnderscoreForm() {
        // Wire token is the clean "large_biomes", NOT the escaped rawValue.
        XCTAssertEqual(ServerSettingsSchema.levelToken(.largeBiomes), "large_biomes")
        XCTAssertEqual(ServerSettingsSchema.levelToken(.normal), "normal")
        XCTAssertEqual(ServerSettingsSchema.levelToken(.flat), "flat")
        XCTAssertEqual(ServerSettingsSchema.levelToken(.amplified), "amplified")
    }

    func testLevelFromTokenRoundTrips() {
        for t in LevelType.allCases {
            let token = ServerSettingsSchema.levelToken(t)
            XCTAssertEqual(ServerSettingsSchema.levelFromToken(token), t, "token=\(token)")
        }
    }

    func testLevelFromTokenRejectsUnknown() {
        XCTAssertNil(ServerSettingsSchema.levelFromToken("void"))
    }

    func testApplyLevelTypeUsesWireTokenAndSetsEscapedRawValue() {
        var m = baselineModel()
        let r = ServerSettingsSchema.applyJava(changes: ["level-type": "large_biomes"], onto: &m)
        XCTAssertEqual(r.applied, ["level-type"])
        XCTAssertEqual(m.levelType, .largeBiomes)
        // The stored rawValue is the escaped/namespaced file form.
        XCTAssertEqual(m.levelType.rawValue, "minecraft\\:large_biomes")
    }

    // MARK: - Mixed batch: applied + rejected partition

    func testMixedBatchPartitionsAppliedAndRejected() {
        var m = baselineModel()
        let r = ServerSettingsSchema.applyJava(
            changes: ["pvp": "false", "max-players": "NaN", "unknown": "1"], onto: &m)
        XCTAssertTrue(r.applied.contains("pvp"))
        XCTAssertEqual(m.pvp, false)
        let reasons = Dictionary(uniqueKeysWithValues: r.rejected.map { ($0.key, $0.reason) })
        XCTAssertEqual(reasons["max-players"], "not_an_integer")
        XCTAssertEqual(reasons["unknown"], "unknown_key")
    }
}

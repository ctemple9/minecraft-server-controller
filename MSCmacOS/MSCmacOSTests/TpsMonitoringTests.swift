//
//  TpsMonitoringTests.swift
//  MSCmacOSTests
//
//  Tests for P7.6: flavor-specific TPS monitoring. Covers the pure TpsLineParser
//  against both console formats (Paper trio + Forge/NeoForge single overall value)
//  plus garbage input, and the JavaServerFlavor.autoTpsCommand mapping that gates
//  which flavors get polled at all.
//

import XCTest
@testable import Minecraft_Server_Controller

final class TpsMonitoringTests: XCTestCase {

    // MARK: - Paper-family "TPS from last 1m, 5m, 15m: …"

    func testPaperTpsThreeValues() {
        let sample = TpsLineParser.parse("TPS from last 1m, 5m, 15m: 19.98, 20.0, 20.0")
        XCTAssertEqual(sample?.t1, 19.98)
        XCTAssertEqual(sample?.t5, 20.0)
        XCTAssertEqual(sample?.t15, 20.0)
    }

    func testPaperTpsWithColorCodeStrippedShape() {
        // After AppUtilities.sanitized() strips §-color codes the line is plain text;
        // the trailing colon before the numbers must still be the one we split on.
        let sample = TpsLineParser.parse("TPS from last 1m, 5m, 15m: 5.12, 12.34, 18.90")
        XCTAssertEqual(sample?.t1, 5.12)
        XCTAssertEqual(sample?.t5, 12.34)
        XCTAssertEqual(sample?.t15, 18.90)
    }

    func testPaperTpsMalformedTrioReturnsNil() {
        XCTAssertNil(TpsLineParser.parse("TPS from last 1m, 5m, 15m: 20.0, twenty, 20.0"))
        XCTAssertNil(TpsLineParser.parse("TPS from last 1m, 5m, 15m: 20.0"))
    }

    // MARK: - Forge/NeoForge "Overall: Mean tick time: X ms. Mean TPS: Y"

    func testForgeTpsOverallSingleValue() {
        let sample = TpsLineParser.parse("Overall: Mean tick time: 3.456 ms. Mean TPS: 20.000")
        XCTAssertEqual(sample?.t1, 20.0)
        // Forge has no 1m/5m/15m breakdown — the trio slots must be cleared so the
        // Performance tab renders a single value instead of stale Paper numbers.
        XCTAssertNil(sample?.t5)
        XCTAssertNil(sample?.t15)
    }

    func testForgeTpsDegradedTickCount() {
        let sample = TpsLineParser.parse("Overall: Mean tick time: 112.7 ms. Mean TPS: 8.87")
        XCTAssertEqual(sample?.t1, 8.87)
        XCTAssertNil(sample?.t5)
        XCTAssertNil(sample?.t15)
    }

    func testForgeTpsCaseAndSpacingTolerant() {
        // Real Forge builds vary punctuation/casing slightly; the regex is
        // case-insensitive and tolerant of the "ms." period being present or not.
        let a = TpsLineParser.parse("overall: mean tick time: 4.0 ms  mean tps: 19.5")
        XCTAssertEqual(a?.t1, 19.5)
        XCTAssertNil(a?.t5)
    }

    // MARK: - Garbage / neither format

    func testGarbageLinesYieldNil() {
        XCTAssertNil(TpsLineParser.parse("hello world"))
        XCTAssertNil(TpsLineParser.parse("[12:00:00] [Server thread/INFO]: Done (5.2s)!"))
        XCTAssertNil(TpsLineParser.parse("Unknown or incomplete command, see below for error"))
        XCTAssertNil(TpsLineParser.parse("Mean tick time is not a real line without Mean TPS"))
        XCTAssertNil(TpsLineParser.parse(""))
    }

    // MARK: - autoTpsCommand mapping

    func testAutoTpsCommandPaperFamily() {
        XCTAssertEqual(JavaServerFlavor.paper.autoTpsCommand, "tps")
        XCTAssertEqual(JavaServerFlavor.purpur.autoTpsCommand, "tps")
        XCTAssertEqual(JavaServerFlavor.pufferfish.autoTpsCommand, "tps")
        XCTAssertEqual(JavaServerFlavor.spigot.autoTpsCommand, "tps")
    }

    func testAutoTpsCommandForgeFamily() {
        XCTAssertEqual(JavaServerFlavor.forge.autoTpsCommand, "forge tps")
        XCTAssertEqual(JavaServerFlavor.neoforge.autoTpsCommand, "neoforge tps")
    }

    func testAutoTpsCommandNilForFlavorsWithoutBuiltIn() {
        // Vanilla/Fabric/Quilt have no stable built-in TPS command — nil so MSC
        // skips the poll rather than spamming "Unknown or incomplete command".
        XCTAssertNil(JavaServerFlavor.vanilla.autoTpsCommand)
        XCTAssertNil(JavaServerFlavor.fabric.autoTpsCommand)
        XCTAssertNil(JavaServerFlavor.quilt.autoTpsCommand)
    }

    func testEveryFlavorAutoTpsCommandIsExhaustive() {
        // Guards against a new flavor being added without a TPS decision.
        for flavor in JavaServerFlavor.allCases {
            switch flavor {
            case .paper, .purpur, .pufferfish, .spigot:
                XCTAssertEqual(flavor.autoTpsCommand, "tps")
            case .forge:
                XCTAssertEqual(flavor.autoTpsCommand, "forge tps")
            case .neoforge:
                XCTAssertEqual(flavor.autoTpsCommand, "neoforge tps")
            case .vanilla, .fabric, .quilt:
                XCTAssertNil(flavor.autoTpsCommand)
            }
        }
    }
}

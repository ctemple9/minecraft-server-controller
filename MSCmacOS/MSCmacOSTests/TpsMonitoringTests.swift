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

    // MARK: - Modern NeoForge (MC 1.21+) "Overall: X TPS (Y ms/tick)"

    func testNeoForge121OverallSingleValue() {
        let sample = TpsLineParser.parse("Overall: 20.000 TPS (0.354 ms/tick)")
        XCTAssertEqual(sample?.t1, 20.0)
        XCTAssertNil(sample?.t5)
        XCTAssertNil(sample?.t15)
    }

    func testNeoForge121DegradedTps() {
        let sample = TpsLineParser.parse("Overall: 8.87 TPS (112.700 ms/tick)")
        XCTAssertEqual(sample?.t1, 8.87)
        XCTAssertNil(sample?.t5)
    }

    func testNeoForge121PerDimensionLineIsIgnored() {
        // Only the "Overall:" summary should feed the live stat; per-dimension
        // lines ("minecraft:overworld: X TPS (…)") must not match.
        XCTAssertNil(TpsLineParser.parse("minecraft:overworld: 20.000 TPS (0.05 ms/tick)"))
    }

    // MARK: - Vanilla /tick query "Average time per tick: X ms" (Fabric/Quilt/Vanilla)

    func testVanillaTickHealthyDerivesTwenty() {
        // Well under the 50 ms budget → capped at the vanilla target of 20 TPS.
        let sample = TpsLineParser.parse("Average time per tick: 0.7ms (Target: 50.0ms)")
        XCTAssertEqual(sample?.t1, 20.0)
        XCTAssertNil(sample?.t5)
        XCTAssertNil(sample?.t15)
    }

    func testVanillaTickAtBudgetIsTwenty() {
        let sample = TpsLineParser.parse("Average time per tick: 50.0ms (Target: 50.0ms)")
        XCTAssertEqual(sample?.t1, 20.0)
    }

    func testVanillaTickOverloadedDerivesReducedTps() {
        // 100 ms/tick → 1000/100 = 10 TPS.
        let sample = TpsLineParser.parse("Average time per tick: 100.0ms (Target: 50.0ms)")
        XCTAssertEqual(sample?.t1, 10.0)
        XCTAssertNil(sample?.t5)
    }

    func testVanillaTickWithServerPrefix() {
        let sample = TpsLineParser.parse("[11:22:33] [Server thread/INFO]: Average time per tick: 62.5ms (Target: 50.0ms)")
        XCTAssertEqual(sample?.t1, 16.0)
    }

    func testVanillaTickSiblingLinesIgnored() {
        // The other two lines of the /tick query reply must not parse as TPS.
        XCTAssertNil(TpsLineParser.parse("Target tick rate: 20.0 per second."))
        XCTAssertNil(TpsLineParser.parse("Percentiles: P50: 0.6ms P95: 1.2ms P99: 2.8ms, sample: 100"))
    }

    // MARK: - spark /spark tps (Fabric/Quilt/Vanilla with the spark mod)

    func testSparkHeaderDetection() {
        XCTAssertTrue(TpsLineParser.isSparkTpsHeader("[11:48:55] [Server thread/INFO]: TPS from last 5s, 10s, 1m, 5m, 15m:"))
        // Paper's 3-window header must NOT be mistaken for spark's 5-window one.
        XCTAssertFalse(TpsLineParser.isSparkTpsHeader("TPS from last 1m, 5m, 15m: 20.0, 20.0, 20.0"))
    }

    func testSparkValuesMapWindowsTo1m5m15m() {
        // spark order is 5s, 10s, 1m, 5m, 15m → t1/t5/t15 take 1m/5m/15m.
        let sample = TpsLineParser.parseSparkValues("[11:48:55] [Server thread/INFO]: 20.0, 19.9, 19.8, 19.5, 18.0")
        XCTAssertEqual(sample?.t1, 19.8)
        XCTAssertEqual(sample?.t5, 19.5)
        XCTAssertEqual(sample?.t15, 18.0)
    }

    func testSparkValuesToleratesColourCodesAndAsterisks() {
        let sample = TpsLineParser.parseSparkValues("§a20.0§r, §a19.9§r, §e18.5§r, §c12.0§r, *§c8.0§r")
        XCTAssertEqual(sample?.t1, 18.5)
        XCTAssertEqual(sample?.t5, 12.0)
        XCTAssertEqual(sample?.t15, 8.0)
    }

    func testSparkValuesNeedsFiveNumbers() {
        XCTAssertNil(TpsLineParser.parseSparkValues("20.0, 20.0, 20.0, 20.0"))
        // A bare timestamp has no decimals, so it can't be misread as values.
        XCTAssertNil(TpsLineParser.parseSparkValues("[11:48:55] [Server thread/INFO]: done"))
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

    // MARK: - tpsPollCommand (version-aware, incl. vanilla /tick query)

    func testTpsPollCommandLoaderNativeIgnoresVersion() {
        // Paper/Forge/NeoForge commands exist regardless of MC version.
        XCTAssertEqual(JavaServerFlavor.paper.tpsPollCommand(minecraftVersion: "1.16.5"), "tps")
        XCTAssertEqual(JavaServerFlavor.forge.tpsPollCommand(minecraftVersion: "1.20.1"), "forge tps")
        XCTAssertEqual(JavaServerFlavor.neoforge.tpsPollCommand(minecraftVersion: "1.21.4"), "neoforge tps")
    }

    func testTpsPollCommandVanillaFamilyUsesTickQueryOn1203Plus() {
        for flavor in [JavaServerFlavor.vanilla, .fabric, .quilt] {
            XCTAssertEqual(flavor.tpsPollCommand(minecraftVersion: "1.20.3"), "tick query")
            XCTAssertEqual(flavor.tpsPollCommand(minecraftVersion: "1.21"), "tick query")
            XCTAssertEqual(flavor.tpsPollCommand(minecraftVersion: "1.21.4"), "tick query")
        }
    }

    func testTpsPollCommandVanillaFamilyNilBelow1203OrUnknown() {
        for flavor in [JavaServerFlavor.vanilla, .fabric, .quilt] {
            XCTAssertNil(flavor.tpsPollCommand(minecraftVersion: "1.20.2"))
            XCTAssertNil(flavor.tpsPollCommand(minecraftVersion: "1.19.4"))
            XCTAssertNil(flavor.tpsPollCommand(minecraftVersion: nil))
            XCTAssertNil(flavor.tpsPollCommand(minecraftVersion: ""))
        }
    }

    func testSupportsVanillaTickQueryNumericBoundary() {
        // Numeric compare so multi-digit components order correctly.
        XCTAssertTrue(JavaServerFlavor.supportsVanillaTickQuery("1.20.10"))
        XCTAssertTrue(JavaServerFlavor.supportsVanillaTickQuery("1.20.3"))
        XCTAssertFalse(JavaServerFlavor.supportsVanillaTickQuery("1.20.2"))
        XCTAssertFalse(JavaServerFlavor.supportsVanillaTickQuery("1.9.4"))
    }
}

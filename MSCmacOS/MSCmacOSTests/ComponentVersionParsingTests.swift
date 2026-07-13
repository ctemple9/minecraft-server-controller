//
//  ComponentVersionParsingTests.swift
//  MSCmacOSTests
//
//  Pins ComponentVersionParsing jar-name → version parsing (T1a, tranche #5).
//  Behavior read from ComponentVersionParsing.swift.
//

import XCTest
@testable import Minecraft_Server_Controller

final class ComponentVersionParsingTests: XCTestCase {

    // MARK: - Paper jar filename

    func testPaperBuildKeywordForm() {
        let v = ComponentVersionParsing.parsePaperJarFilename("paper-1.21.1-build130.jar")
        XCTAssertEqual(v, PaperJarVersion(mcVersion: "1.21.1", build: 130))
        XCTAssertEqual(v?.displayString, "1.21.1 (build 130)")
        XCTAssertEqual(v?.compactString, "1.21.1-130")
    }

    func testPaperBareBuildNumberForm() {
        let v = ComponentVersionParsing.parsePaperJarFilename("paper-1.20.4-435.jar")
        XCTAssertEqual(v, PaperJarVersion(mcVersion: "1.20.4", build: 435))
    }

    func testPaperCaseInsensitivePrefix() {
        let v = ComponentVersionParsing.parsePaperJarFilename("Paper-1.21-100.jar")
        XCTAssertEqual(v?.mcVersion, "1.21")
        XCTAssertEqual(v?.build, 100)
    }

    func testNonPaperPrefixRejected() {
        XCTAssertNil(ComponentVersionParsing.parsePaperJarFilename("purpur-1.21-2000.jar"))
    }

    func testPaperMissingBuildRejected() {
        XCTAssertNil(ComponentVersionParsing.parsePaperJarFilename("paper-1.21.jar"))
    }

    func testPaperNonNumericBuildRejected() {
        XCTAssertNil(ComponentVersionParsing.parsePaperJarFilename("paper-1.21-latest.jar"))
    }

    // MARK: - Trailing build number

    func testTrailingBuildNumberGeyser() {
        XCTAssertEqual(
            ComponentVersionParsing.parseTrailingBuildNumber(fromJarFilename: "Geyser-spigot-1004.jar"), 1004)
    }

    func testTrailingBuildNumberFloodgate() {
        XCTAssertEqual(
            ComponentVersionParsing.parseTrailingBuildNumber(fromJarFilename: "floodgate-spigot-121.jar"), 121)
    }

    func testTrailingBuildNumberNonNumericTailIsNil() {
        XCTAssertNil(
            ComponentVersionParsing.parseTrailingBuildNumber(fromJarFilename: "Geyser-spigot-snapshot.jar"))
    }

    func testTrailingBuildNumberNoSeparatorUsesWholeStem() {
        // No '-' → the whole stem is the "last" token; "plugin" isn't an Int → nil.
        XCTAssertNil(ComponentVersionParsing.parseTrailingBuildNumber(fromJarFilename: "plugin.jar"))
        // A pure-number stem parses.
        XCTAssertEqual(ComponentVersionParsing.parseTrailingBuildNumber(fromJarFilename: "42.jar"), 42)
    }

    // MARK: - buildDisplayString

    func testBuildDisplayString() {
        XCTAssertEqual(ComponentVersionParsing.buildDisplayString(77), "build 77")
        XCTAssertNil(ComponentVersionParsing.buildDisplayString(nil))
    }
}

// MARK: - MCVersionComparator (U4b)

final class MCVersionComparatorTests: XCTestCase {

    func testUpgradeReturnsFalse() {
        XCTAssertFalse(MCVersionComparator.isDowngrade(from: "1.20.4", to: "1.21.0"))
        XCTAssertFalse(MCVersionComparator.isDowngrade(from: "1.20", to: "1.21"))
        XCTAssertFalse(MCVersionComparator.isDowngrade(from: "1.21.3", to: "1.21.4"))
    }

    func testDowngradeReturnsTrue() {
        XCTAssertTrue(MCVersionComparator.isDowngrade(from: "1.21.4", to: "1.20.6"))
        XCTAssertTrue(MCVersionComparator.isDowngrade(from: "1.21.4", to: "1.21.3"))
        XCTAssertTrue(MCVersionComparator.isDowngrade(from: "1.21", to: "1.20.4"))
    }

    func testSameVersionReturnsFalse() {
        XCTAssertFalse(MCVersionComparator.isDowngrade(from: "1.21.4", to: "1.21.4"))
    }

    func testPaddedComponents() {
        // "1.21" and "1.21.0" are the same version (trailing zeros padded).
        XCTAssertFalse(MCVersionComparator.isDowngrade(from: "1.21", to: "1.21.0"))
        XCTAssertFalse(MCVersionComparator.isDowngrade(from: "1.21.0", to: "1.21"))
    }

    func testBedrockFourPartVersions() {
        XCTAssertTrue(MCVersionComparator.isDowngrade(from: "1.21.30.03", to: "1.21.10.01"))
        XCTAssertFalse(MCVersionComparator.isDowngrade(from: "1.21.10.01", to: "1.21.30.03"))
        XCTAssertFalse(MCVersionComparator.isDowngrade(from: "1.21.30.03", to: "1.21.30.03"))
    }

    func testNilCurrentSkipsCheck() {
        XCTAssertFalse(MCVersionComparator.isDowngrade(from: nil, to: "1.20.0"))
    }

    func testEmptyCurrentSkipsCheck() {
        XCTAssertFalse(MCVersionComparator.isDowngrade(from: "", to: "1.20.0"))
    }

    func testLatestTargetSkipsCheck() {
        XCTAssertFalse(MCVersionComparator.isDowngrade(from: "1.21.4", to: "LATEST"))
        XCTAssertFalse(MCVersionComparator.isDowngrade(from: "1.21.4", to: "latest"))
    }

    func testLatestCurrentSkipsCheck() {
        XCTAssertFalse(MCVersionComparator.isDowngrade(from: "LATEST", to: "1.20.0"))
    }

    func testNonNumericSnapshotSkipsCheck() {
        // Snapshot-style versions have a letter suffix — not safely ordered.
        XCTAssertFalse(MCVersionComparator.isDowngrade(from: "24w14a", to: "1.20.4"))
        XCTAssertFalse(MCVersionComparator.isDowngrade(from: "1.21.4", to: "24w14a"))
    }
}

//
//  StartupCrashAnalyzerTests.swift
//  MSCmacOSTests
//
//  Pins StartupCrashAnalyzer against realistic loader failure logs, and its
//  return-nothing-rather-than-guess policy (T1a, tranche #4). Logs are fed via the
//  `consoleExcerpt` seam; serverDir points at a non-existent temp path so no real
//  logs/latest.log or crash-reports are read. Line formats taken from the parser's
//  own documented examples in StartupCrashAnalyzer.swift.
//

import XCTest
@testable import Minecraft_Server_Controller

final class StartupCrashAnalyzerTests: XCTestCase {

    /// A directory URL that does not exist, so only consoleExcerpt feeds the parser.
    private func emptyServerDir() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("msc-tests-\(UUID().uuidString)", isDirectory: true)
            .path
    }

    // MARK: - Fabric: missing dependency

    func testFabricMissingDependencyParsed() {
        let log = [
            "A mod requires a dependency that is missing:",
            "\t - Mod 'MyMod' (mymod) 1.0 requires any version of fabric api, which is missing!"
        ]
        let problems = StartupCrashAnalyzer.analyze(
            serverDir: emptyServerDir(), flavor: .fabric,
            consoleExcerpt: log, installedMods: [])
        XCTAssertEqual(problems.count, 1)
        let p = problems.first
        XCTAssertEqual(p?.kind, .missingDependency)
        XCTAssertEqual(p?.offenderName, "MyMod")
        XCTAssertEqual(p?.offenderId, "mymod")
        XCTAssertEqual(p?.missingDependency, "fabric api")
    }

    // MARK: - Fabric: incompatible version + installed-mod attribution

    func testFabricIncompatibleVersionAttributedToInstalledMod() {
        let installed = ModEntry(
            filename: "sodium-fabric-0.4.0.jar", jarStem: "sodium-fabric-0.4.0",
            displayName: "Sodium", modId: "sodium", version: "0.4.0", isEnabled: true)
        let log = [
            "\t - Mod 'Sodium' (sodium) 0.4.0 requires version 1.21 of minecraft, but only 1.20.1 is present!"
        ]
        let problems = StartupCrashAnalyzer.analyze(
            serverDir: emptyServerDir(), flavor: .fabric,
            consoleExcerpt: log, installedMods: [installed])
        XCTAssertEqual(problems.count, 1)
        let p = problems.first
        XCTAssertEqual(p?.kind, .incompatibleVersion)
        XCTAssertEqual(p?.offenderName, "Sodium")
        XCTAssertEqual(p?.installedFile, "sodium-fabric-0.4.0.jar")
        XCTAssertEqual(p?.installedJarStem, "sodium-fabric-0.4.0")
        XCTAssertNil(p?.missingDependency)          // not a missing-dep line
        XCTAssertEqual(p?.requirement?.hasPrefix("Requires version 1.21 of minecraft"), true)
    }

    // MARK: - NeoForge / Forge: structured dependency line

    func testForgeMissingDependencyParsed() {
        let log = [
            "Mod ID: 'jei', Requested by: 'somemod', Expected range: '[15.2,)', Actual version: '[MISSING]'"
        ]
        let problems = StartupCrashAnalyzer.analyze(
            serverDir: emptyServerDir(), flavor: .neoforge,
            consoleExcerpt: log, installedMods: [])
        XCTAssertEqual(problems.count, 1)
        let p = problems.first
        XCTAssertEqual(p?.kind, .missingDependency)
        // Offender is the requester (the mod we can act on), dep is the missing target.
        XCTAssertEqual(p?.offenderId, "somemod")
        XCTAssertEqual(p?.missingDependency, "jei")
    }

    func testForgeWrongDependencyVersionAttributesToDependency() {
        let log = [
            "Mod ID: 'jei', Requested by: 'somemod', Expected range: '[15.2,)', Actual version: '15.0.1'"
        ]
        let problems = StartupCrashAnalyzer.analyze(
            serverDir: emptyServerDir(), flavor: .forge,
            consoleExcerpt: log, installedMods: [])
        XCTAssertEqual(problems.count, 1)
        let p = problems.first
        XCTAssertEqual(p?.kind, .incompatibleVersion)
        // A concrete (non-loader) dependency at the wrong version → offender is the dep.
        XCTAssertEqual(p?.offenderId, "jei")
        XCTAssertNil(p?.missingDependency)
    }

    // MARK: - Garbage log: must return nothing rather than guess

    func testGarbageLogReturnsNothingForParseableFlavor() {
        let log = [
            "[12:00:00] [Server thread/INFO]: Starting minecraft server version 1.21",
            "random noise line that mentions requires but not in the Mod '...' shape",
            "======= a decorative banner =======",
            "Done (5.231s)! For help, type \"help\""
        ]
        let problems = StartupCrashAnalyzer.analyze(
            serverDir: emptyServerDir(), flavor: .fabric,
            consoleExcerpt: log, installedMods: [])
        XCTAssertTrue(problems.isEmpty)
    }

    // MARK: - Unsupported flavor short-circuits to []

    func testUnsupportedFlavorReturnsEmptyEvenWithParseableLines() {
        let log = [
            "\t - Mod 'MyMod' (mymod) 1.0 requires any version of fabric api, which is missing!"
        ]
        let problems = StartupCrashAnalyzer.analyze(
            serverDir: emptyServerDir(), flavor: .paper,
            consoleExcerpt: log, installedMods: [])
        XCTAssertTrue(problems.isEmpty)
    }

    func testEmptyExcerptReturnsEmpty() {
        let problems = StartupCrashAnalyzer.analyze(
            serverDir: emptyServerDir(), flavor: .fabric,
            consoleExcerpt: [], installedMods: [])
        XCTAssertTrue(problems.isEmpty)
    }
}

//
//  ModpackClientOnlyTests.swift
//  MSCmacOSTests
//
//  Tests for P7.4: auto-disable client-only mods during .mrpack import.
//  Covers the three-tier classification decision table, Modrinth CDN projectId
//  extraction, and the never-clobber-.disabled filesystem rule. All pure — no network.
//

import XCTest
@testable import Minecraft_Server_Controller

final class ModpackClientOnlyTests: XCTestCase {

    // MARK: - Tier 1: manifest env

    func testManifestEnvUnsupportedIsClientOnly() {
        XCTAssertTrue(ModpackClientOnlyClassifier.isManifestServerUnsupported(MrpackEnv(client: "required", server: "unsupported")))
        XCTAssertTrue(ModpackClientOnlyClassifier.isManifestServerUnsupported(MrpackEnv(client: nil, server: "Unsupported")))
    }

    func testManifestEnvServerSupportedIsNotClientOnly() {
        XCTAssertFalse(ModpackClientOnlyClassifier.isManifestServerUnsupported(MrpackEnv(client: "required", server: "required")))
        XCTAssertFalse(ModpackClientOnlyClassifier.isManifestServerUnsupported(MrpackEnv(client: "optional", server: "optional")))
        XCTAssertFalse(ModpackClientOnlyClassifier.isManifestServerUnsupported(nil))
        XCTAssertFalse(ModpackClientOnlyClassifier.isManifestServerUnsupported(MrpackEnv(client: nil, server: nil)))
    }

    // MARK: - Tiers 2 + 3: decision table

    func testModrinthUnsupportedDisables() {
        let reason = ModpackClientOnlyClassifier.clientOnlyReason(
            modrinthServerSide: "unsupported", modrinthProjectTitle: "Continuity", jarEnvironment: nil)
        XCTAssertNotNil(reason)
        XCTAssertTrue(reason?.contains("Continuity") == true)
        XCTAssertTrue(reason?.contains("Modrinth") == true)
    }

    func testModrinthRequiredKeepsEnabledEvenIfJarSaysClient() {
        // Conflict: Modrinth says server-usable, jar embeds environment=client → Modrinth wins.
        let reason = ModpackClientOnlyClassifier.clientOnlyReason(
            modrinthServerSide: "required", modrinthProjectTitle: "Sinytra Connector", jarEnvironment: "client")
        XCTAssertNil(reason)
    }

    func testModrinthOptionalKeepsEnabled() {
        let reason = ModpackClientOnlyClassifier.clientOnlyReason(
            modrinthServerSide: "optional", modrinthProjectTitle: "Some Mod", jarEnvironment: nil)
        XCTAssertNil(reason)
    }

    func testModrinthUnsupportedWinsOverJarServer() {
        // Conflict the other way: Modrinth unsupported, jar says server → still disabled.
        let reason = ModpackClientOnlyClassifier.clientOnlyReason(
            modrinthServerSide: "unsupported", modrinthProjectTitle: "BadOptimizations", jarEnvironment: "server")
        XCTAssertNotNil(reason)
    }

    func testJarClientFallbackWhenModrinthUnknown() {
        let reason = ModpackClientOnlyClassifier.clientOnlyReason(
            modrinthServerSide: nil, modrinthProjectTitle: nil, jarEnvironment: "client")
        XCTAssertNotNil(reason)
        XCTAssertTrue(reason?.contains("fabric.mod.json") == true)
    }

    func testJarServerFallbackKeepsEnabled() {
        XCTAssertNil(ModpackClientOnlyClassifier.clientOnlyReason(
            modrinthServerSide: nil, modrinthProjectTitle: nil, jarEnvironment: "server"))
    }

    func testNoSignalsKeepsEnabled() {
        XCTAssertNil(ModpackClientOnlyClassifier.clientOnlyReason(
            modrinthServerSide: nil, modrinthProjectTitle: nil, jarEnvironment: nil))
        // Empty Modrinth string is treated as "no signal", not a keep-enabled verdict.
        XCTAssertNotNil(ModpackClientOnlyClassifier.clientOnlyReason(
            modrinthServerSide: "", modrinthProjectTitle: nil, jarEnvironment: "client"))
    }

    // MARK: - CDN projectId extraction

    func testProjectIdFromModrinthCDNURL() {
        let urls = ["https://cdn.modrinth.com/data/1IjD5062/versions/abcd1234/continuity-3.0.0.jar"]
        XCTAssertEqual(ModpackClientOnlyClassifier.modrinthProjectId(fromDownloadURLs: urls), "1IjD5062")
    }

    func testProjectIdPrefersModrinthAmongMultipleMirrors() {
        let urls = [
            "https://example.com/mirror/continuity.jar",
            "https://cdn.modrinth.com/data/AaBbCcDd/versions/xyz/continuity.jar",
        ]
        XCTAssertEqual(ModpackClientOnlyClassifier.modrinthProjectId(fromDownloadURLs: urls), "AaBbCcDd")
    }

    func testProjectIdNilForNonModrinthURLs() {
        XCTAssertNil(ModpackClientOnlyClassifier.modrinthProjectId(
            fromDownloadURLs: ["https://example.com/data/whatever/versions/1/foo.jar"]))
    }

    func testProjectIdNilForMalformedModrinthURL() {
        // No "data" path segment.
        XCTAssertNil(ModpackClientOnlyClassifier.modrinthProjectId(
            fromDownloadURLs: ["https://cdn.modrinth.com/versions/1/foo.jar"]))
    }

    func testProjectIdNilForEmptyDownloads() {
        XCTAssertNil(ModpackClientOnlyClassifier.modrinthProjectId(fromDownloadURLs: []))
    }

    // MARK: - isModsJar

    func testIsModsJar() {
        XCTAssertTrue(ModpackClientOnlyClassifier.isModsJar(path: "mods/continuity-3.0.0.jar"))
        XCTAssertTrue(ModpackClientOnlyClassifier.isModsJar(path: "MODS/Foo.JAR"))
        XCTAssertFalse(ModpackClientOnlyClassifier.isModsJar(path: "config/foo.json"))
        XCTAssertFalse(ModpackClientOnlyClassifier.isModsJar(path: "mods/readme.txt"))
        XCTAssertFalse(ModpackClientOnlyClassifier.isModsJar(path: "resourcepacks/foo.jar"))
    }

    // MARK: - Never-clobber disableJar (filesystem)

    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModpackClientOnlyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testDisableJarRenamesToDisabled() throws {
        let fm = FileManager.default
        let jar = tmpDir.appendingPathComponent("foo.jar")
        try Data("active".utf8).write(to: jar)

        let name = ModpackClientOnlyClassifier.disableJar(at: jar, fm: fm)
        XCTAssertEqual(name, "foo.jar.disabled")
        XCTAssertFalse(fm.fileExists(atPath: jar.path))
        XCTAssertTrue(fm.fileExists(atPath: tmpDir.appendingPathComponent("foo.jar.disabled").path))
    }

    func testDisableJarNeverClobbersExistingDisabled() throws {
        let fm = FileManager.default
        let jar = tmpDir.appendingPathComponent("foo.jar")
        let disabled = tmpDir.appendingPathComponent("foo.jar.disabled")
        try Data("fresh".utf8).write(to: jar)
        try Data("original-disabled".utf8).write(to: disabled)

        let name = ModpackClientOnlyClassifier.disableJar(at: jar, fm: fm)
        XCTAssertEqual(name, "foo.jar.disabled")
        // The fresh active jar is dropped, not written over the existing .disabled.
        XCTAssertFalse(fm.fileExists(atPath: jar.path))
        XCTAssertEqual(try String(contentsOf: disabled, encoding: .utf8), "original-disabled")
    }

    func testDisableJarReturnsNilWhenNothingToDisable() {
        let jar = tmpDir.appendingPathComponent("missing.jar")
        XCTAssertNil(ModpackClientOnlyClassifier.disableJar(at: jar, fm: .default))
    }
}

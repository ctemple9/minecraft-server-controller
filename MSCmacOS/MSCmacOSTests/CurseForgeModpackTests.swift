//
//  CurseForgeModpackTests.swift
//  MSCmacOSTests
//
//  Tests for P7.10: CurseForge modpack import.
//  Covers the pure surfaces: manifest parsing, loader-id parsing (forge/fabric/malformed),
//  pack-type detection (mrpack vs CurseForge vs plain zip), and the null-downloadUrl →
//  manual-download-list assembly. Network + filesystem import orchestration is not exercised
//  here (it needs a live CF API key + a pack zip — the human-in-loop E2E).
//

import XCTest
@testable import Minecraft_Server_Controller

final class CurseForgeModpackTests: XCTestCase {

    // MARK: - Manifest parsing

    /// A trimmed CurseForge manifest.json with a primary Forge loader.
    private let forgeManifestJSON = """
    {
      "minecraft": {
        "version": "1.20.1",
        "modLoaders": [{ "id": "forge-47.4.1", "primary": true }]
      },
      "manifestType": "minecraftModpack",
      "manifestVersion": 1,
      "name": "Better MC [FORGE] BMC4",
      "version": "43",
      "author": "Luna Pixel Studios",
      "files": [
        { "projectID": 306612, "fileID": 5000001, "required": true },
        { "projectID": 238222, "fileID": 5000002, "required": true }
      ],
      "overrides": "overrides"
    }
    """

    func testForgeManifestParses() throws {
        let m = try JSONDecoder().decode(CurseForgeManifest.self, from: Data(forgeManifestJSON.utf8))
        XCTAssertEqual(m.manifestType, "minecraftModpack")
        XCTAssertEqual(m.name, "Better MC [FORGE] BMC4")
        XCTAssertEqual(m.version, "43")
        XCTAssertEqual(m.minecraft.version, "1.20.1")
        XCTAssertEqual(m.minecraft.modLoaders.first?.id, "forge-47.4.1")
        XCTAssertEqual(m.files.count, 2)
        XCTAssertEqual(m.files.first?.projectID, 306612)
        XCTAssertEqual(m.files.first?.fileID, 5000001)
        XCTAssertEqual(m.overrides, "overrides")
    }

    func testForgeManifestMetadataPinsLoader() throws {
        let m = try JSONDecoder().decode(CurseForgeManifest.self, from: Data(forgeManifestJSON.utf8))
        let meta = try CurseForgeMetadata.from(manifest: m)
        XCTAssertEqual(meta.name, "Better MC [FORGE] BMC4")
        XCTAssertEqual(meta.versionId, "43")
        XCTAssertEqual(meta.minecraftVersion, "1.20.1")
        XCTAssertEqual(meta.loaderFlavor, .forge)
        XCTAssertEqual(meta.loaderVersion, "47.4.1")

        let entry = meta.versionEntry
        XCTAssertEqual(entry?.mcVersion, "1.20.1")
        XCTAssertEqual(entry?.loaderVersion, "47.4.1")
        XCTAssertEqual(entry?.buildLabel, "Forge 47.4.1")
        XCTAssertEqual(entry?.id, "1.20.1—47.4.1")
    }

    func testFabricManifestMetadataPinsFabric() throws {
        let json = """
        {
          "minecraft": { "version": "1.21.1", "modLoaders": [{ "id": "fabric-0.16.9", "primary": true }] },
          "manifestType": "minecraftModpack", "name": "Fabric Pack", "version": "1.0",
          "files": [], "overrides": "overrides"
        }
        """
        let m = try JSONDecoder().decode(CurseForgeManifest.self, from: Data(json.utf8))
        let meta = try CurseForgeMetadata.from(manifest: m)
        XCTAssertEqual(meta.loaderFlavor, .fabric)
        XCTAssertEqual(meta.loaderVersion, "0.16.9")
        XCTAssertEqual(meta.versionEntry?.buildLabel, "Fabric 0.16.9")
    }

    func testNeoForgeManifestMetadataPinsNeoForge() throws {
        let json = """
        {
          "minecraft": { "version": "1.21.1", "modLoaders": [{ "id": "neoforge-21.1.72", "primary": true }] },
          "manifestType": "minecraftModpack", "name": "Neo Pack", "version": "2",
          "files": [], "overrides": "overrides"
        }
        """
        let m = try JSONDecoder().decode(CurseForgeManifest.self, from: Data(json.utf8))
        let meta = try CurseForgeMetadata.from(manifest: m)
        XCTAssertEqual(meta.loaderFlavor, .neoforge)
        XCTAssertEqual(meta.loaderVersion, "21.1.72")
    }

    /// A manifest whose loader id is unrecognized must throw, not pin a guessed flavor.
    func testMalformedLoaderIdThrows() throws {
        let json = """
        {
          "minecraft": { "version": "1.20.1", "modLoaders": [{ "id": "totallybogus-1.2.3", "primary": true }] },
          "manifestType": "minecraftModpack", "name": "Bad Pack", "version": "1",
          "files": [], "overrides": "overrides"
        }
        """
        let m = try JSONDecoder().decode(CurseForgeManifest.self, from: Data(json.utf8))
        XCTAssertThrowsError(try CurseForgeMetadata.from(manifest: m)) { error in
            guard case CurseForgeManifestError.unknownLoader = error else {
                return XCTFail("Expected unknownLoader, got \(error)")
            }
        }
    }

    // MARK: - Loader-id parsing

    func testParseLoaderIdForge() throws {
        let p = try CurseForgeModpack.parseLoaderId("forge-47.4.1")
        XCTAssertEqual(p.flavor, .forge)
        XCTAssertEqual(p.loaderVersion, "47.4.1")
    }

    func testParseLoaderIdNeoForgeWithHyphenatedVersion() throws {
        // NeoForge versions themselves never contain hyphens, but guard the split-on-first
        // behavior so a version keeps everything after the first hyphen intact.
        let p = try CurseForgeModpack.parseLoaderId("fabric-0.16.9-beta.1")
        XCTAssertEqual(p.flavor, .fabric)
        XCTAssertEqual(p.loaderVersion, "0.16.9-beta.1")
    }

    func testParseLoaderIdUnknownThrows() {
        XCTAssertThrowsError(try CurseForgeModpack.parseLoaderId("liteloader-1.0")) { error in
            guard case CurseForgeManifestError.unknownLoader(let name) = error else {
                return XCTFail("Expected unknownLoader, got \(error)")
            }
            XCTAssertEqual(name, "liteloader")
        }
    }

    func testParseLoaderIdEmptyThrows() {
        XCTAssertThrowsError(try CurseForgeModpack.parseLoaderId("   ")) { error in
            guard case CurseForgeManifestError.malformedLoaderId = error else {
                return XCTFail("Expected malformedLoaderId, got \(error)")
            }
        }
    }

    // MARK: - Pack-type detection

    func testDetectKindModrinth() throws {
        let dir = try makeTempDir()
        try Data("{}".utf8).write(to: dir.appendingPathComponent("modrinth.index.json"))
        XCTAssertEqual(CurseForgeModpack.detectKind(inExtractedRoot: dir), .modrinth)
    }

    func testDetectKindCurseForge() throws {
        let dir = try makeTempDir()
        try Data(forgeManifestJSON.utf8).write(to: dir.appendingPathComponent("manifest.json"))
        XCTAssertEqual(CurseForgeModpack.detectKind(inExtractedRoot: dir), .curseForge)
    }

    func testDetectKindPlainZipIsUnknown() throws {
        let dir = try makeTempDir()
        // A plain jars zip: some .jar files, no modpack manifest.
        try Data("jar".utf8).write(to: dir.appendingPathComponent("SomeMod.jar"))
        XCTAssertEqual(CurseForgeModpack.detectKind(inExtractedRoot: dir), .unknown)
    }

    func testDetectKindNonModpackManifestIsUnknown() throws {
        // A manifest.json that is NOT a minecraftModpack must not be treated as CurseForge.
        let dir = try makeTempDir()
        let json = #"{ "manifestType": "something-else", "minecraft": { "version": "1.20.1", "modLoaders": [] }, "files": [] }"#
        try Data(json.utf8).write(to: dir.appendingPathComponent("manifest.json"))
        XCTAssertEqual(CurseForgeModpack.detectKind(inExtractedRoot: dir), .unknown)
    }

    func testModrinthWinsWhenBothMarkersPresent() throws {
        let dir = try makeTempDir()
        try Data("{}".utf8).write(to: dir.appendingPathComponent("modrinth.index.json"))
        try Data(forgeManifestJSON.utf8).write(to: dir.appendingPathComponent("manifest.json"))
        XCTAssertEqual(CurseForgeModpack.detectKind(inExtractedRoot: dir), .modrinth)
    }

    func testIsCurseForgeModpackManifest() {
        XCTAssertTrue(CurseForgeModpack.isCurseForgeModpackManifest(Data(forgeManifestJSON.utf8)))
        XCTAssertFalse(CurseForgeModpack.isCurseForgeModpackManifest(Data("{}".utf8)))
        XCTAssertFalse(CurseForgeModpack.isCurseForgeModpackManifest(Data("not json".utf8)))
    }

    // MARK: - Manual-download list (distribution-blocked files)

    func testManualDownloadsAssembly() {
        // Two blocked files: one with a matching project (name + page), one without.
        let blocked = [
            CFFile(id: 1, modId: 100, displayName: "SomeMod-1.0.jar", fileName: "SomeMod-1.0.jar", downloadUrl: nil),
            CFFile(id: 2, modId: 200, displayName: "OtherMod-2.0.jar", fileName: "OtherMod-2.0.jar", downloadUrl: nil),
        ]
        let projects: [Int: CFMod] = [
            100: CFMod(id: 100, name: "Some Mod", slug: "some-mod",
                       links: CFModLinks(websiteUrl: "https://www.curseforge.com/minecraft/mc-mods/some-mod")),
        ]

        let list = CurseForgeModpack.manualDownloads(blockedFiles: blocked, projectsById: projects)
        XCTAssertEqual(list.count, 2)

        let first = list[0]
        XCTAssertEqual(first.modName, "Some Mod")
        XCTAssertEqual(first.fileName, "SomeMod-1.0.jar")
        XCTAssertEqual(first.projectPageURL, "https://www.curseforge.com/minecraft/mc-mods/some-mod")

        // No project record → fall back to the file's display name and a search link.
        let second = list[1]
        XCTAssertEqual(second.modName, "OtherMod-2.0.jar")
        XCTAssertTrue(second.projectPageURL.contains("curseforge.com"))
    }

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cf_test_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }
}

//
//  ModpackPinningTests.swift
//  MSCmacOSTests
//
//  Tests for P7.2: manifest-pinned modpack provisioning + full Forge Maven listing.
//  Covers:
//    1. ForgeInstaller.parseMavenMetadata — non-promoted builds (e.g. 47.4.1) are listed,
//       sorted newest-MC then newest-Forge, and de-duplicated.
//    2. MrpackMetadata.from(manifest:) — BMC4-shaped {forge,minecraft} and a
//       {fabric-loader,minecraft} manifest map to the right flavor + pinned versions.
//    3. MrpackMetadata.versionEntry — pinned MC + loader version become a picker entry
//       carrying loaderVersion + a "Forge 47.4.1" style build label.
//

import XCTest
@testable import Minecraft_Server_Controller

final class ModpackPinningTests: XCTestCase {

    // MARK: - Forge Maven metadata parsing

    /// A trimmed maven-metadata.xml with a non-promoted build (47.4.1) alongside promoted
    /// ones (47.4.10 / 47.4.21), a second MC line, and a junk entry that must be ignored.
    private let forgeMavenXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <metadata>
      <groupId>net.minecraftforge</groupId>
      <artifactId>forge</artifactId>
      <versioning>
        <versions>
          <version>1.19.2-43.2.0</version>
          <version>1.20.1-47.4.1</version>
          <version>1.20.1-47.4.10</version>
          <version>1.20.1-47.4.21</version>
          <version>garbage-entry</version>
          <version>1.20.1-47.4.1</version>
        </versions>
      </versioning>
    </metadata>
    """

    func testForgeMavenListsNonPromotedBuild() {
        let entries = ForgeInstaller.parseMavenMetadata(forgeMavenXML)
        // BMC4's exact build must be selectable — this is the whole point of the change.
        let bmc4 = entries.first { $0.mcVersion == "1.20.1" && $0.loaderVersion == "47.4.1" }
        XCTAssertNotNil(bmc4, "Non-promoted Forge 47.4.1 should be listed")
        XCTAssertEqual(bmc4?.buildLabel, "Forge 47.4.1")
        XCTAssertEqual(bmc4?.id, "1.20.1—47.4.1")
    }

    func testForgeMavenDeduplicates() {
        let entries = ForgeInstaller.parseMavenMetadata(forgeMavenXML)
        let matches = entries.filter { $0.id == "1.20.1—47.4.1" }
        XCTAssertEqual(matches.count, 1, "Duplicate maven versions should collapse to one entry")
    }

    func testForgeMavenIgnoresMalformedVersions() {
        let entries = ForgeInstaller.parseMavenMetadata(forgeMavenXML)
        XCTAssertFalse(entries.contains { $0.mcVersion == "garbage" || $0.id.contains("garbage") })
    }

    func testForgeMavenSortsNewestMCThenNewestBuild() {
        let entries = ForgeInstaller.parseMavenMetadata(forgeMavenXML)
        // 1.20.1 line must come before 1.19.2 line.
        guard let firstIdx = entries.firstIndex(where: { $0.mcVersion == "1.20.1" }),
              let lastIdx = entries.firstIndex(where: { $0.mcVersion == "1.19.2" }) else {
            return XCTFail("Both MC lines should be present")
        }
        XCTAssertLessThan(firstIdx, lastIdx, "Newer MC version should sort first")

        // Within 1.20.1: 47.4.21 > 47.4.10 > 47.4.1
        let oneTwentyOne = entries.filter { $0.mcVersion == "1.20.1" }.compactMap { $0.loaderVersion }
        XCTAssertEqual(oneTwentyOne, ["47.4.21", "47.4.10", "47.4.1"])
    }

    func testForgeMavenEmptyXMLYieldsNoEntries() {
        XCTAssertTrue(ForgeInstaller.parseMavenMetadata("<metadata></metadata>").isEmpty)
    }

    // MARK: - Manifest dependency-block parsing

    private func manifest(dependencies: [String: String], name: String = "Test Pack") throws -> MrpackManifest {
        let deps = dependencies
            .map { "\"\($0.key)\": \"\($0.value)\"" }
            .joined(separator: ", ")
        let json = """
        {"formatVersion":1,"game":"minecraft","versionId":"43","name":"\(name)","dependencies":{\(deps)},"files":[]}
        """
        return try JSONDecoder().decode(MrpackManifest.self, from: Data(json.utf8))
    }

    func testBMC4ShapedManifestSelectsForge() throws {
        let m = try manifest(dependencies: ["forge": "47.4.1", "minecraft": "1.20.1"], name: "Better MC BMC4")
        let meta = MrpackMetadata.from(manifest: m)
        XCTAssertEqual(meta.minecraftVersion, "1.20.1")
        XCTAssertEqual(meta.loaderFlavor, .forge)
        XCTAssertEqual(meta.loaderVersion, "47.4.1")
    }

    func testFabricShapedManifestSelectsFabric() throws {
        let m = try manifest(dependencies: ["fabric-loader": "0.16.9", "minecraft": "1.21.1"])
        let meta = MrpackMetadata.from(manifest: m)
        XCTAssertEqual(meta.minecraftVersion, "1.21.1")
        XCTAssertEqual(meta.loaderFlavor, .fabric)
        XCTAssertEqual(meta.loaderVersion, "0.16.9")
    }

    func testNeoForgeShapedManifestSelectsNeoForge() throws {
        let m = try manifest(dependencies: ["neoforge": "21.1.90", "minecraft": "1.21.1"])
        let meta = MrpackMetadata.from(manifest: m)
        XCTAssertEqual(meta.loaderFlavor, .neoforge)
        XCTAssertEqual(meta.loaderVersion, "21.1.90")
    }

    func testManifestWithNoLoaderHasNilFlavor() throws {
        let m = try manifest(dependencies: ["minecraft": "1.20.1"])
        let meta = MrpackMetadata.from(manifest: m)
        XCTAssertEqual(meta.minecraftVersion, "1.20.1")
        XCTAssertNil(meta.loaderFlavor)
        XCTAssertNil(meta.loaderVersion)
    }

    // MARK: - versionEntry mapping

    func testVersionEntryCarriesPinnedLoader() throws {
        let m = try manifest(dependencies: ["forge": "47.4.1", "minecraft": "1.20.1"])
        let entry = MrpackMetadata.from(manifest: m).versionEntry
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.mcVersion, "1.20.1")
        XCTAssertEqual(entry?.loaderVersion, "47.4.1")
        XCTAssertEqual(entry?.buildLabel, "Forge 47.4.1")
        XCTAssertEqual(entry?.displayLabel, "1.20.1")
        XCTAssertEqual(entry?.id, "1.20.1—47.4.1")
    }

    func testVersionEntryFabricLoaderIsHonored() throws {
        // The pinned fabric-loader must survive into the entry so the download path can use it.
        let m = try manifest(dependencies: ["fabric-loader": "0.16.9", "minecraft": "1.21.1"])
        let entry = MrpackMetadata.from(manifest: m).versionEntry
        XCTAssertEqual(entry?.loaderVersion, "0.16.9")
        XCTAssertEqual(entry?.buildLabel, "Fabric 0.16.9")
    }

    func testVersionEntryNilWhenNoMinecraftVersion() throws {
        let m = try manifest(dependencies: ["forge": "47.4.1"])
        XCTAssertNil(MrpackMetadata.from(manifest: m).versionEntry)
    }

    func testVersionEntryNoLoaderStillMapsMinecraft() throws {
        let m = try manifest(dependencies: ["minecraft": "1.20.1"])
        let entry = MrpackMetadata.from(manifest: m).versionEntry
        XCTAssertEqual(entry?.mcVersion, "1.20.1")
        XCTAssertNil(entry?.loaderVersion)
        XCTAssertNil(entry?.buildLabel)
    }
}

//
//  MrpackExtractionTests.swift
//  MSCmacOSTests
//
//  Tests for P7.1: ditto-based .mrpack extraction and manifest error diagnostics.
//  Covers:
//    1. mode-000 ZIP entry — /usr/bin/unzip extracts as unreadable; ditto must yield a readable manifest.
//    2. absent modrinth.index.json — MrpackReadError.manifestAbsent with the right user-facing message.
//    3. malformed modrinth.index.json — MrpackReadError.manifestMalformed.
//

import XCTest
@testable import Minecraft_Server_Controller

final class MrpackExtractionTests: XCTestCase {

    // Minimal valid modrinth.index.json
    private let validManifestJSON = #"{"formatVersion":1,"game":"minecraft","versionId":"1.0","name":"Test Pack","dependencies":{},"files":[]}"#

    // MARK: - Helpers

    /// Creates a .mrpack (ZIP) via Python3 so we can control stored file permissions precisely.
    /// Pass nil for `manifest` to create a pack with no modrinth.index.json.
    /// `unixMode` is the POSIX permission bits stored in the ZIP's external_attr (e.g. 0 = mode 000).
    private func makeMrpack(manifest: String?, unixMode: Int = 0o644) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("msc_test_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: tmp) }
        let mrpackURL = tmp.appendingPathComponent("test.mrpack")

        let script: String
        if let manifest {
            // external_attr upper 16 bits = Unix mode (type bits + permission bits).
            // S_IFREG (0o100000) | unixMode gives a regular file with the given permissions.
            let extAttr = (0o100000 | unixMode) << 16
            script = """
import zipfile, os
info = zipfile.ZipInfo('modrinth.index.json')
info.external_attr = \(extAttr)
with zipfile.ZipFile('\(mrpackURL.path)', 'w') as z:
    z.writestr(info, r'''\(manifest)''')
"""
        } else {
            script = """
import zipfile
info = zipfile.ZipInfo('other_file.txt')
info.external_attr = (0o100644) << 16
with zipfile.ZipFile('\(mrpackURL.path)', 'w') as z:
    z.writestr(info, 'placeholder')
"""
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = ["-c", script]
        p.standardOutput = FileHandle.nullDevice
        p.standardError  = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0, "python3 zip creation failed")
        return mrpackURL
    }

    // MARK: - mode-000 entry test

    func testMode000EntryBecomesReadableViaDitto() throws {
        // Create a .mrpack whose modrinth.index.json is stored with mode 000.
        // /usr/bin/unzip would extract this as an unreadable file (mode 000 preserved verbatim).
        // ditto must make it readable — this is the root fix for the BMC4 import failure.
        let mrpackURL = try makeMrpack(manifest: validManifestJSON, unixMode: 0)
        let manifest = try AppViewModel.readMrpackManifest(from: mrpackURL)
        XCTAssertEqual(manifest.name, "Test Pack")
        XCTAssertEqual(manifest.versionId, "1.0")
        XCTAssertEqual(manifest.game, "minecraft")
        XCTAssertTrue(manifest.files.isEmpty)
    }

    // MARK: - absent manifest

    func testAbsentManifestThrowsManifestAbsent() throws {
        let mrpackURL = try makeMrpack(manifest: nil)
        XCTAssertThrowsError(try AppViewModel.readMrpackManifest(from: mrpackURL)) { error in
            guard case MrpackReadError.manifestAbsent = error else {
                XCTFail("Expected MrpackReadError.manifestAbsent, got \(error)")
                return
            }
            // Verify the user-facing message matches what importModpack logs.
            let desc = (error as? MrpackReadError)?.errorDescription ?? ""
            XCTAssertTrue(desc.contains("no modrinth.index.json"), "Wrong error message: \(desc)")
        }
    }

    // MARK: - malformed manifest

    func testMalformedManifestThrowsManifestMalformed() throws {
        let mrpackURL = try makeMrpack(manifest: "{not valid json}", unixMode: 0o644)
        XCTAssertThrowsError(try AppViewModel.readMrpackManifest(from: mrpackURL)) { error in
            guard case MrpackReadError.manifestMalformed = error else {
                XCTFail("Expected MrpackReadError.manifestMalformed, got \(error)")
                return
            }
        }
    }
}

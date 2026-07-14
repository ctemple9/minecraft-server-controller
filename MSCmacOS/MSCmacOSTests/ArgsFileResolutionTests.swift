//
//  ArgsFileResolutionTests.swift
//  MSCmacOSTests
//
//  Tests for P7.3: version-aware Forge / NeoForge args-file resolution.
//  All tests are pure filesystem fixtures — no network, no app state.
//

import XCTest
@testable import Minecraft_Server_Controller

final class ArgsFileResolutionTests: XCTestCase {

    // MARK: - Helpers

    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArgsFileResolutionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    private func makeArgsFile(relativePath: String) throws {
        let url = tmpDir.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("@args".utf8).write(to: url)
    }

    // MARK: - NeoForge

    func testNeoForgeSingleVersionFound() throws {
        try makeArgsFile(relativePath: "libraries/net/neoforged/neoforge/21.1.234/unix_args.txt")
        let result = NeoForgeInstaller.findArgsFile(in: tmpDir, specificVersion: "21.1.234")
        XCTAssertEqual(result, "libraries/net/neoforged/neoforge/21.1.234/unix_args.txt")
    }

    func testNeoForgePicksConfiguredVersionAmongMultiple() throws {
        try makeArgsFile(relativePath: "libraries/net/neoforged/neoforge/21.1.100/unix_args.txt")
        try makeArgsFile(relativePath: "libraries/net/neoforged/neoforge/21.1.234/unix_args.txt")
        let result = NeoForgeInstaller.findArgsFile(in: tmpDir, specificVersion: "21.1.234")
        XCTAssertEqual(result, "libraries/net/neoforged/neoforge/21.1.234/unix_args.txt")
    }

    func testNeoForgeFallsBackWhenConfiguredVersionMissing() throws {
        // Only 21.1.100 is on disk; configured version is 21.1.234.
        try makeArgsFile(relativePath: "libraries/net/neoforged/neoforge/21.1.100/unix_args.txt")
        let result = NeoForgeInstaller.findArgsFile(in: tmpDir, specificVersion: "21.1.234")
        // Fallback finds the one that exists.
        XCTAssertEqual(result, "libraries/net/neoforged/neoforge/21.1.100/unix_args.txt")
    }

    func testNeoForgeNilVersionFallsBackToFirstMatch() throws {
        try makeArgsFile(relativePath: "libraries/net/neoforged/neoforge/21.1.50/unix_args.txt")
        let result = NeoForgeInstaller.findArgsFile(in: tmpDir, specificVersion: nil)
        XCTAssertEqual(result, "libraries/net/neoforged/neoforge/21.1.50/unix_args.txt")
    }

    func testNeoForgeEmptyVersionFallsBackToFirstMatch() throws {
        try makeArgsFile(relativePath: "libraries/net/neoforged/neoforge/21.1.50/unix_args.txt")
        let result = NeoForgeInstaller.findArgsFile(in: tmpDir, specificVersion: "")
        XCTAssertEqual(result, "libraries/net/neoforged/neoforge/21.1.50/unix_args.txt")
    }

    func testNeoForgeReturnsNilWhenNothingInstalled() {
        XCTAssertNil(NeoForgeInstaller.findArgsFile(in: tmpDir, specificVersion: "21.1.234"))
    }

    // MARK: - Forge

    func testForgeSingleVersionFound() throws {
        try makeArgsFile(relativePath: "libraries/net/minecraftforge/forge/1.20.1-47.4.1/unix_args.txt")
        let result = ForgeInstaller.findArgsFile(in: tmpDir, mcVersion: "1.20.1", forgeVersion: "47.4.1")
        XCTAssertEqual(result, "libraries/net/minecraftforge/forge/1.20.1-47.4.1/unix_args.txt")
    }

    func testForgePicksConfiguredPairAmongMultiple() throws {
        try makeArgsFile(relativePath: "libraries/net/minecraftforge/forge/1.20.1-47.3.0/unix_args.txt")
        try makeArgsFile(relativePath: "libraries/net/minecraftforge/forge/1.20.1-47.4.1/unix_args.txt")
        let result = ForgeInstaller.findArgsFile(in: tmpDir, mcVersion: "1.20.1", forgeVersion: "47.4.1")
        XCTAssertEqual(result, "libraries/net/minecraftforge/forge/1.20.1-47.4.1/unix_args.txt")
    }

    func testForgeFallsBackWhenConfiguredPairMissing() throws {
        // Only 47.3.0 on disk; configured is 47.4.1.
        try makeArgsFile(relativePath: "libraries/net/minecraftforge/forge/1.20.1-47.3.0/unix_args.txt")
        let result = ForgeInstaller.findArgsFile(in: tmpDir, mcVersion: "1.20.1", forgeVersion: "47.4.1")
        XCTAssertEqual(result, "libraries/net/minecraftforge/forge/1.20.1-47.3.0/unix_args.txt")
    }

    func testForgeNilMCVersionFallsBackToFirstMatch() throws {
        try makeArgsFile(relativePath: "libraries/net/minecraftforge/forge/1.20.1-47.4.1/unix_args.txt")
        let result = ForgeInstaller.findArgsFile(in: tmpDir, mcVersion: nil, forgeVersion: "47.4.1")
        XCTAssertEqual(result, "libraries/net/minecraftforge/forge/1.20.1-47.4.1/unix_args.txt")
    }

    func testForgeNilForgeVersionFallsBackToFirstMatch() throws {
        try makeArgsFile(relativePath: "libraries/net/minecraftforge/forge/1.20.1-47.4.1/unix_args.txt")
        let result = ForgeInstaller.findArgsFile(in: tmpDir, mcVersion: "1.20.1", forgeVersion: nil)
        XCTAssertEqual(result, "libraries/net/minecraftforge/forge/1.20.1-47.4.1/unix_args.txt")
    }

    func testForgeReturnsNilWhenNothingInstalled() {
        XCTAssertNil(ForgeInstaller.findArgsFile(in: tmpDir, mcVersion: "1.20.1", forgeVersion: "47.4.1"))
    }
}

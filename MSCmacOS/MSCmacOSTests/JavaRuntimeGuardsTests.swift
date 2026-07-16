//
//  JavaRuntimeGuardsTests.swift
//  MSCmacOSTests
//
//  Tests for P7.7: Java too-new warning + java-home path normalization.
//  Covers the pure helpers on JavaRuntimeManager that don't need a live JVM process:
//  `normalizedJavaExecutablePath` (FS-based) and `compatibilityWarningText` (logic-only).
//

import XCTest
@testable import Minecraft_Server_Controller

final class JavaRuntimeGuardsTests: XCTestCase {

    // MARK: - Path normalization

    func testNormalizationBareCommandPassesThrough() {
        // "java" has no "/" so FS checks are skipped — PATH resolves it at launch.
        let (path, err) = JavaRuntimeManager.normalizedJavaExecutablePath("java")
        XCTAssertEqual(path, "java")
        XCTAssertNil(err)
    }

    func testNormalizationAlreadyExecutablePathUnchanged() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let bin = tmp.appendingPathComponent("java")
        FileManager.default.createFile(atPath: bin.path, contents: Data("#!/bin/sh".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.path)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let (path, err) = JavaRuntimeManager.normalizedJavaExecutablePath(bin.path)
        XCTAssertEqual(path, bin.path)
        XCTAssertNil(err)
    }

    func testNormalizationHomeDirToBinJava() throws {
        // Reproduces the user mistake: pasting a JAVA_HOME directory path into
        // Preferences, which causes "permission denied" (exec on a directory).
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let binDir = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        let javaExe = binDir.appendingPathComponent("java")
        FileManager.default.createFile(atPath: javaExe.path, contents: Data("#!/bin/sh".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: javaExe.path)
        defer { try? FileManager.default.removeItem(at: home) }

        let (path, err) = JavaRuntimeManager.normalizedJavaExecutablePath(home.path)
        XCTAssertEqual(path, javaExe.path, "Expected HOME dir to be expanded to bin/java")
        XCTAssertNil(err)
    }

    func testNormalizationNonexistentPathReturnsError() {
        let (path, err) = JavaRuntimeManager.normalizedJavaExecutablePath("/nonexistent/fake/path/java")
        XCTAssertNil(path)
        XCTAssertTrue(err?.contains("does not exist") == true,
                      "Expected 'does not exist' in error: \(err ?? "<nil>")")
    }

    func testNormalizationDirectoryWithoutBinJavaReturnsError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let (path, err) = JavaRuntimeManager.normalizedJavaExecutablePath(dir.path)
        XCTAssertNil(path)
        XCTAssertTrue(err?.contains("bin/java") == true,
                      "Expected 'bin/java' in error: \(err ?? "<nil>")")
    }

    // MARK: - Installed runtime discovery

    func testDetectInstalledJavaRuntimesFindsMacOSJDKBundle() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let java = try makeFakeJavaExecutable(
            home: root.appendingPathComponent("temurin-21.jdk/Contents/Home", isDirectory: true)
        )

        let runtimes = JavaRuntimeManager.detectInstalledJavaRuntimes(searchRoots: [root])

        XCTAssertEqual(runtimes.map(\.executablePath), [java.path])
        XCTAssertEqual(runtimes.first?.majorVersion, 21)
        XCTAssertEqual(runtimes.first?.name, "temurin-21")
    }

    func testDetectInstalledJavaRuntimesFindsPlainJavaHome() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let java8 = try makeFakeJavaExecutable(
            home: root.appendingPathComponent("8.0.402-tem", isDirectory: true)
        )
        let java17 = try makeFakeJavaExecutable(
            home: root.appendingPathComponent("17.0.11-tem", isDirectory: true)
        )

        let runtimes = JavaRuntimeManager.detectInstalledJavaRuntimes(searchRoots: [root])

        XCTAssertEqual(Set(runtimes.map(\.executablePath)), Set([java8.path, java17.path]))
        XCTAssertEqual(runtimes.first?.majorVersion, 17, "Newest detected major should sort first")
    }

    func testDetectInstalledJavaRuntimesIgnoresInvalidCandidates() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let invalidHome = root.appendingPathComponent("broken-21.jdk/Contents/Home", isDirectory: true)
        try FileManager.default.createDirectory(
            at: invalidHome.appendingPathComponent("bin", isDirectory: true),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(
            atPath: invalidHome.appendingPathComponent("bin/java").path,
            contents: Data("#!/bin/sh\n".utf8)
        )

        let runtimes = JavaRuntimeManager.detectInstalledJavaRuntimes(searchRoots: [root])

        XCTAssertTrue(runtimes.isEmpty, "Non-executable java files should not be offered in Settings")
    }

    // MARK: - Too-new warning (compatibilityWarningText)

    func testRequiredJavaMajorMapping() {
        // Verify the MC→Java mapping used by both guards.
        XCTAssertEqual(JavaRuntimeManager.requiredJavaMajor(forMinecraftVersion: "1.16.5"), 8)
        XCTAssertEqual(JavaRuntimeManager.requiredJavaMajor(forMinecraftVersion: "1.17"), 17)
        XCTAssertEqual(JavaRuntimeManager.requiredJavaMajor(forMinecraftVersion: "1.20.1"), 17)
        XCTAssertEqual(JavaRuntimeManager.requiredJavaMajor(forMinecraftVersion: "1.21"), 21)
        XCTAssertEqual(JavaRuntimeManager.requiredJavaMajor(forMinecraftVersion: "1.21.1"), 21)
    }

    func testTooNewWarningJava17EraWithJava21() {
        // 1.20.1 targets Java 17; detected Java 21 → should warn (not block).
        let w = JavaRuntimeManager.compatibilityWarningText(
            minecraftVersion: "1.20.1", required: 17, detected: 21)
        XCTAssertNotNil(w)
        XCTAssertTrue(w!.contains("Java 17"),    "Should mention required Java 17: \(w!)")
        XCTAssertTrue(w!.contains("version 21"), "Should mention detected Java 21: \(w!)")
        XCTAssertTrue(w!.contains("modpacks are usually"),
                      "Should be the too-new phrasing, not the too-old phrasing: \(w!)")
    }

    func testTooNewWarningJava17EraWithJava25() {
        let w = JavaRuntimeManager.compatibilityWarningText(
            minecraftVersion: "1.20.1", required: 17, detected: 25)
        XCTAssertNotNil(w)
        XCTAssertTrue(w!.contains("Java 17"))
        XCTAssertTrue(w!.contains("version 25"))
        XCTAssertTrue(w!.contains("modpacks are usually"))
    }

    func testNoWarningJava17EraWithExactJava17() {
        // Exact match → nil.
        let w = JavaRuntimeManager.compatibilityWarningText(
            minecraftVersion: "1.20.1", required: 17, detected: 17)
        XCTAssertNil(w)
    }

    func testNoWarningJava21EraWithJava21() {
        // 1.21 targets Java 21; detected 21 → no warning.
        let w = JavaRuntimeManager.compatibilityWarningText(
            minecraftVersion: "1.21", required: 21, detected: 21)
        XCTAssertNil(w)
    }

    func testNoWarningJava21EraWithJava25() {
        // 1.21 targets Java 21; detected 25 → required=21 > 17 so too-new guard does NOT fire.
        // Java 21-era Minecraft is generally forward-compatible with newer LTS versions.
        let w = JavaRuntimeManager.compatibilityWarningText(
            minecraftVersion: "1.21", required: 21, detected: 25)
        XCTAssertNil(w)
    }

    func testTooOldWarningStillFires() {
        // Regression guard: too-old path must still fire after the refactor.
        let w = JavaRuntimeManager.compatibilityWarningText(
            minecraftVersion: "1.20.1", required: 17, detected: 8)
        XCTAssertNotNil(w)
        XCTAssertTrue(w!.contains("needs Java 17"), "Should say 'needs Java 17': \(w!)")
        XCTAssertTrue(w!.contains("version 8"),     "Should mention version 8: \(w!)")
        XCTAssertFalse(w!.contains("modpacks are usually"),
                       "Should be the too-old phrasing, not too-new: \(w!)")
    }

    // MARK: - Helpers

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func makeFakeJavaExecutable(home: URL) throws -> URL {
        let bin = home.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let java = bin.appendingPathComponent("java")
        FileManager.default.createFile(atPath: java.path, contents: Data("#!/bin/sh\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: java.path)
        return java
    }
}

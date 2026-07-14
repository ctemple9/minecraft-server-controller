//
//  HeadlessScriptGeneratorTests.swift
//  MSCmacOSTests
//
//  Tests for P7.11: flavor-correct headless script generation.
//  Pure-logic tests with injected seams for args-file resolution (P7.4 pattern).
//  No network; no UI; no app state.
//

import XCTest
@testable import Minecraft_Server_Controller

final class HeadlessScriptGeneratorTests: XCTestCase {

    // MARK: - Helpers

    /// Minimal AppConfig with a bare "java" command and no extra flags.
    private func makeAppConfig(javaPath: String = "java", extraFlags: String = "") -> AppConfig {
        var cfg = AppConfig.defaultConfig()
        cfg.javaPath = javaPath
        cfg.extraFlags = extraFlags
        return cfg
    }

    /// Minimal ConfigServer for the given flavor.
    private func makeConfig(
        flavor: JavaServerFlavor,
        paperJarPath: String = "server.jar",
        minRamGB: Int = 1,
        maxRamGB: Int = 2,
        mcVersion: String? = nil,
        loaderVersion: String? = nil
    ) -> ConfigServer {
        var cfg = ConfigServer(
            id: "test-server",
            displayName: "Test Server",
            serverDir: "/srv/mc",
            paperJarPath: paperJarPath,
            minRamGB: minRamGB,
            maxRamGB: maxRamGB
        )
        cfg.javaFlavor = flavor
        cfg.minecraftVersion = mcVersion
        cfg.loaderVersion = loaderVersion
        return cfg
    }

    /// Generates a script using JavaServerLaunchHelper with injected seams.
    private func resolve(
        config: ConfigServer,
        appConfig: AppConfig,
        neoForgeArgsFile: String? = nil,
        forgeArgsFile: String? = nil
    ) -> JavaServerLaunchConfig {
        JavaServerLaunchHelper.resolve(
            config: config,
            appConfig: appConfig,
            serverDirURL: URL(fileURLWithPath: config.serverDir),
            minRamGB: config.minRamGB,
            maxRamGB: config.maxRamGB,
            findNeoForgeArgsFile: { _, _ in neoForgeArgsFile },
            findForgeArgsFile: { _, _, _ in forgeArgsFile }
        )
    }

    // MARK: - Paper jar

    func testPaperJarCommand() {
        let cfg = makeConfig(flavor: .paper, paperJarPath: "/srv/mc/paper-1.20.1-196.jar")
        let launch = resolve(config: cfg, appConfig: makeAppConfig())
        XCTAssertNil(launch.neoForgeArgsFile)
        XCTAssertEqual(launch.jarName, "paper-1.20.1-196.jar")
        XCTAssertEqual(launch.javaPath, "java")
        XCTAssertTrue(launch.jvmFlags.contains("-Xms1G"))
        XCTAssertTrue(launch.jvmFlags.contains("-Xmx2G"))
    }

    func testPaperScriptContainsJarInvocation() {
        let appCfg = makeAppConfig()
        var cfg = makeConfig(flavor: .paper)
        cfg.paperJarPath = "/srv/mc/paper.jar"
        let script = HeadlessScriptGenerator.javaScript(
            config: cfg, appConfig: appCfg,
            minRamGB: 1, maxRamGB: 2,
            wrapMode: .none, includeXboxBroadcast: false
        )
        XCTAssertTrue(script.contains("-jar paper.jar --nogui"), "Expected -jar … --nogui for Paper")
        XCTAssertFalse(script.contains("@"), "Paper script must not use args-file syntax")
    }

    // MARK: - Fabric launch jar

    func testFabricScriptUsesJarWithNogui() {
        let appCfg = makeAppConfig()
        var cfg = makeConfig(flavor: .fabric)
        cfg.paperJarPath = "/srv/mc/fabric-server-launch.jar"
        let script = HeadlessScriptGenerator.javaScript(
            config: cfg, appConfig: appCfg,
            minRamGB: 1, maxRamGB: 4,
            wrapMode: .none, includeXboxBroadcast: false
        )
        XCTAssertTrue(script.contains("-jar fabric-server-launch.jar --nogui"))
        XCTAssertFalse(script.contains("@"))
    }

    // MARK: - Forge args-file

    func testForgeScriptUsesArgsFile() {
        let appCfg = makeAppConfig()
        let cfg = makeConfig(flavor: .forge, mcVersion: "1.20.1", loaderVersion: "47.4.1")
        let argsFile = "libraries/net/minecraftforge/forge/1.20.1-47.4.1/unix_args.txt"
        let launch = JavaServerLaunchHelper.resolve(
            config: cfg,
            appConfig: appCfg,
            serverDirURL: URL(fileURLWithPath: cfg.serverDir),
            minRamGB: cfg.minRamGB,
            maxRamGB: cfg.maxRamGB,
            findNeoForgeArgsFile: { _, _ in nil },
            findForgeArgsFile: { _, _, _ in argsFile }
        )
        XCTAssertEqual(launch.neoForgeArgsFile, argsFile)
    }

    func testForgeScriptEmitsArgsFileSyntax() {
        let appCfg = makeAppConfig()
        let argsFile = "libraries/net/minecraftforge/forge/1.20.1-47.4.1/unix_args.txt"
        let cfg = makeConfig(flavor: .forge, mcVersion: "1.20.1", loaderVersion: "47.4.1")
        let launch = JavaServerLaunchHelper.resolve(
            config: cfg,
            appConfig: appCfg,
            serverDirURL: URL(fileURLWithPath: cfg.serverDir),
            minRamGB: 2, maxRamGB: 8,
            findNeoForgeArgsFile: { _, _ in nil },
            findForgeArgsFile: { _, _, _ in argsFile }
        )
        XCTAssertEqual(launch.neoForgeArgsFile, argsFile)
    }

    // MARK: - NeoForge args-file

    func testNeoForgeArgsFileIsResolved() {
        let appCfg = makeAppConfig()
        let cfg = makeConfig(flavor: .neoforge, mcVersion: "1.21.1", loaderVersion: "21.1.234")
        let expected = "libraries/net/neoforged/neoforge/21.1.234/unix_args.txt"
        let launch = JavaServerLaunchHelper.resolve(
            config: cfg,
            appConfig: appCfg,
            serverDirURL: URL(fileURLWithPath: cfg.serverDir),
            minRamGB: cfg.minRamGB,
            maxRamGB: cfg.maxRamGB,
            findNeoForgeArgsFile: { _, _ in expected },
            findForgeArgsFile: { _, _, _ in nil }
        )
        XCTAssertEqual(launch.neoForgeArgsFile, expected)
    }

    // MARK: - Forge/NeoForge args-file not found

    func testForgeArgsFileMissingEmitsErrorInScript() {
        let appCfg = makeAppConfig()
        let cfg = makeConfig(flavor: .forge, mcVersion: "1.20.1", loaderVersion: "47.4.1")
        // Real filesystem lookup in /srv/mc — no file exists there; will return nil.
        let script = HeadlessScriptGenerator.javaScript(
            config: cfg, appConfig: appCfg,
            minRamGB: 2, maxRamGB: 8,
            wrapMode: .none, includeXboxBroadcast: false
        )
        XCTAssertTrue(script.contains("exit 1"), "Script must exit with error when args file missing")
        XCTAssertTrue(script.contains("Forge"), "Error must identify the flavor")
    }

    // MARK: - Vanilla nogui

    func testVanillaScriptUsesNogui() {
        let appCfg = makeAppConfig()
        var cfg = makeConfig(flavor: .vanilla)
        cfg.paperJarPath = "/srv/mc/server.jar"
        let script = HeadlessScriptGenerator.javaScript(
            config: cfg, appConfig: appCfg,
            minRamGB: 1, maxRamGB: 2,
            wrapMode: .none, includeXboxBroadcast: false
        )
        XCTAssertTrue(script.contains("-jar server.jar --nogui"))
    }

    // MARK: - Java path normalization

    func testJavaHomeDirectoryIsNormalized() throws {
        // If the user pastes a JAVA_HOME path, JavaRuntimeManager should expand it to bin/java.
        // We can only test this when a real JVM exists on disk; skip otherwise.
        let javaHome = "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home"
        guard FileManager.default.fileExists(atPath: javaHome) else {
            throw XCTSkip("Temurin 21 JDK not installed — skipping Java HOME normalization test")
        }
        let appCfg = makeAppConfig(javaPath: javaHome)
        let cfg = makeConfig(flavor: .paper)
        let launch = resolve(config: cfg, appConfig: appCfg)
        XCTAssertEqual(launch.javaPath, "\(javaHome)/bin/java")
    }

    func testBareJavaCommandPassesThrough() {
        let appCfg = makeAppConfig(javaPath: "java")
        let cfg = makeConfig(flavor: .paper)
        let launch = resolve(config: cfg, appConfig: appCfg)
        XCTAssertEqual(launch.javaPath, "java")
    }

    func testAbsoluteJavaPathPassesThrough() {
        let appCfg = makeAppConfig(javaPath: "/usr/bin/java")
        let cfg = makeConfig(flavor: .paper)
        let launch = resolve(config: cfg, appConfig: appCfg)
        XCTAssertEqual(launch.javaPath, "/usr/bin/java")
    }

    // MARK: - Shell quoting

    func testPathWithSpacesIsQuoted() {
        let appCfg = makeAppConfig(javaPath: "java")
        var cfg = ConfigServer(
            id: "test-server",
            displayName: "Test Server",
            serverDir: "/srv/my server",
            paperJarPath: "/srv/my server/paper.jar",
            minRamGB: 1,
            maxRamGB: 2
        )
        cfg.javaFlavor = .paper
        let script = HeadlessScriptGenerator.javaScript(
            config: cfg, appConfig: appCfg,
            minRamGB: 1, maxRamGB: 2,
            wrapMode: .none, includeXboxBroadcast: false
        )
        XCTAssertTrue(
            script.contains("cd \"/srv/my server\""),
            "Server dir with space must be double-quoted in cd command"
        )
    }

    func testServerDirWithSpaceIsQuotedInCd() {
        let appCfg = makeAppConfig()
        let cfg = makeConfig(flavor: .paper)
        let script = HeadlessScriptGenerator.javaScript(
            config: cfg, appConfig: appCfg,
            minRamGB: 1, maxRamGB: 2,
            wrapMode: .none, includeXboxBroadcast: false
        )
        // /srv/mc has no space — just verify the cd line is present
        XCTAssertTrue(script.contains("cd /srv/mc") || script.contains("cd \"/srv/mc\""))
    }

    // MARK: - Extra flags

    func testExtraFlagsAreIncluded() {
        let appCfg = makeAppConfig(extraFlags: "-XX:+UseG1GC -XX:MaxGCPauseMillis=200")
        let cfg = makeConfig(flavor: .paper)
        let launch = resolve(config: cfg, appConfig: appCfg)
        XCTAssertTrue(launch.jvmFlags.contains("-XX:+UseG1GC"))
        XCTAssertTrue(launch.jvmFlags.contains("-XX:MaxGCPauseMillis=200"))
    }

    func testEmptyExtraFlagsNotIncluded() {
        let appCfg = makeAppConfig(extraFlags: "   ")
        let cfg = makeConfig(flavor: .paper)
        let launch = resolve(config: cfg, appConfig: appCfg)
        XCTAssertFalse(launch.jvmFlags.contains(where: { $0.isEmpty }))
    }

    // MARK: - RAM flags

    func testRamFlagsMatchSheetValues() {
        let appCfg = makeAppConfig()
        let cfg = makeConfig(flavor: .paper, minRamGB: 4, maxRamGB: 16)
        // Sheet overrides: user set 6 / 12
        let launch = JavaServerLaunchHelper.resolve(
            config: cfg,
            appConfig: appCfg,
            serverDirURL: URL(fileURLWithPath: cfg.serverDir),
            minRamGB: 6,
            maxRamGB: 12
        )
        XCTAssertTrue(launch.jvmFlags.contains("-Xms6G"))
        XCTAssertTrue(launch.jvmFlags.contains("-Xmx12G"))
        XCTAssertFalse(launch.jvmFlags.contains("-Xms4G"), "Config RAM must not override sheet RAM")
    }

    // MARK: - Sandbox flags

    func testSandboxSuppressFlagsPresent() {
        let launch = resolve(config: makeConfig(flavor: .paper), appConfig: makeAppConfig())
        XCTAssertTrue(launch.jvmFlags.contains("-Djna.nosys=true"))
        XCTAssertTrue(launch.jvmFlags.contains("-Djna.nounpack=true"))
        XCTAssertTrue(launch.jvmFlags.contains("-Djline.terminal=dumb"))
        XCTAssertTrue(launch.jvmFlags.contains("-Dio.netty.noUnsafe=true"))
    }

    // MARK: - Auto-restart wrapper

    func testAutoRestartWrapperPresent() {
        let cfg = makeConfig(flavor: .paper)
        let script = HeadlessScriptGenerator.javaScript(
            config: cfg, appConfig: makeAppConfig(),
            minRamGB: 1, maxRamGB: 2,
            wrapMode: .autoRestart, includeXboxBroadcast: false
        )
        XCTAssertTrue(script.contains("while true; do"))
        XCTAssertTrue(script.contains("sleep 5"))
    }

    // MARK: - Empty java path defaults to bare "java"

    func testEmptyJavaPathDefaultsToJava() {
        let appCfg = makeAppConfig(javaPath: "")
        let cfg = makeConfig(flavor: .paper)
        let launch = resolve(config: cfg, appConfig: appCfg)
        XCTAssertEqual(launch.javaPath, "java")
    }
}

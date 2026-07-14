//
//  ConnectorCrashAnalysisTests.swift
//  MSCmacOSTests
//
//  Tests for P7.5: Sinytra Connector / Fabric entrypoint crash analysis inside Forge
//  starts, mod-id/display-name/stem normalization, and the forge-family-aware Modrinth
//  slug alias ladder. Analyzer fixtures use the EXACT log shapes from bettermcMSC.md.
//

import XCTest
@testable import Minecraft_Server_Controller

final class ConnectorCrashAnalysisTests: XCTestCase {

    private func mod(_ file: String, stem: String, name: String, id: String?) -> ModEntry {
        ModEntry(filename: file, jarStem: stem, displayName: name, modId: id, version: nil, isEnabled: true)
    }

    private func analyzeForge(_ lines: [String], mods: [ModEntry]) -> [StartupProblem] {
        // serverDir is nonexistent → combinedLog falls back to the console excerpt only.
        StartupCrashAnalyzer.analyze(
            serverDir: "/nonexistent-\(UUID().uuidString)",
            flavor: .forge, consoleExcerpt: lines, installedMods: mods)
    }

    // MARK: - Forge "Mod ID:/Requested by:/Actual version:" block (exact bettermcMSC shape)

    func testForgeDependencyBlockParses() {
        let lines = [
            "Mod ID: 'fabric_api', Requested by: 'continuity', Actual version: '0.92.6+1.11.14+1.20.1'",
            "Mod ID: 'puzzlesapi', Requested by: 'netherchested', Actual version: '[MISSING]'",
            "Mod ID: 'puzzlesaccessapi', Requested by: 'puzzleslib', Actual version: '[MISSING]'",
            "Mod ID: 'diagonalblocks', Requested by: 'diagonalfences', Actual version: '[MISSING]'",
            "Mod ID: 'connectormod', Requested by: 'continuity', Actual version: '1.0.0-beta.49+1.20.1'",
            "Mod ID: 'kotlinforforge', Requested by: 'fzzy_config', Actual version: '[MISSING]'",
        ]
        let problems = analyzeForge(lines, mods: [])
        XCTAssertFalse(problems.isEmpty)

        // Missing deps become .missingDependency attributed to the requester.
        let puzzles = problems.first { $0.missingDependency == "puzzlesapi" }
        XCTAssertNotNil(puzzles)
        XCTAssertEqual(puzzles?.kind, .missingDependency)
        XCTAssertEqual(puzzles?.offenderId, "netherchested")

        XCTAssertTrue(problems.contains { $0.missingDependency == "kotlinforforge" })
        // A present-but-wrong dependency is an incompatibleVersion, not a missing one.
        XCTAssertTrue(problems.contains { $0.offenderId == "fabric_api" && $0.kind == .incompatibleVersion })
    }

    // MARK: - Connector / Fabric entrypoint EarlyLoadingException (exact bettermcMSC shape)

    func testConnectorEntrypointFailureBecomesLoadError() {
        let line = "net.minecraftforge.fml.loading.EarlyLoadingException: Could not execute entrypoint stage 'main' due to errors, provided by 'particle_effects'"
        let installed = mod("ParticleEffects-1.0.3+1.20.1.jar", stem: "ParticleEffects-1.0.3+1.20.1",
                            name: "Particle Effects", id: "particle_effects")
        let problems = analyzeForge([line], mods: [installed])
        XCTAssertEqual(problems.count, 1)
        let p = problems[0]
        XCTAssertEqual(p.kind, .loadError)
        XCTAssertEqual(p.offenderName, "Particle Effects")
        XCTAssertEqual(p.installedFile, "ParticleEffects-1.0.3+1.20.1.jar")
        XCTAssertEqual(p.installedJarStem, "ParticleEffects-1.0.3+1.20.1")
        XCTAssertTrue(p.requirement?.contains("Connector/Fabric entrypoint") == true)
    }

    func testConnectorEntrypointMatchesByDisplayNameWhenModIdMissing() {
        // Log names the fabric id with an underscore; the installed jar only exposes a
        // human display name — normalization must still bridge them.
        let line = "Could not execute entrypoint stage 'main' due to errors, provided by 'particle_effects'"
        let installed = mod("particleeffects.jar", stem: "particleeffects", name: "Particle Effects", id: nil)
        let problems = analyzeForge([line], mods: [installed])
        XCTAssertEqual(problems.first?.offenderName, "Particle Effects")
        XCTAssertEqual(problems.first?.installedFile, "particleeffects.jar")
    }

    func testConnectorEntrypointUnmatchedKeepsRawIdButStillReports() {
        let line = "Could not execute entrypoint stage 'main' due to errors, provided by 'some_unknown_mod'"
        let problems = analyzeForge([line], mods: [])
        XCTAssertEqual(problems.count, 1)
        XCTAssertEqual(problems.first?.offenderName, "some_unknown_mod")
        XCTAssertEqual(problems.first?.kind, .loadError)
        XCTAssertNil(problems.first?.installedFile)
    }

    // MARK: - Discipline: garbage yields nothing

    func testGarbageLogYieldsNothing() {
        let junk = ["hello world", "[12:00:00] INFO: server starting", "random noise ~~~", "provided by nothing"]
        XCTAssertTrue(analyzeForge(junk, mods: []).isEmpty)
    }

    // MARK: - Identifier normalization

    func testNormalizedIdentifierCollapsesSeparators() {
        XCTAssertEqual(StartupCrashAnalyzer.normalizedIdentifier("particle_effects"), "particle-effects")
        XCTAssertEqual(StartupCrashAnalyzer.normalizedIdentifier("particle-effects"), "particle-effects")
        XCTAssertEqual(StartupCrashAnalyzer.normalizedIdentifier("Particle Effects"), "particle-effects")
        XCTAssertEqual(StartupCrashAnalyzer.normalizedIdentifier("  Particle   Effects!! "), "particle-effects")
    }

    func testMatchInstalledModAcrossSeparatorForms() {
        let byName = mod("pe.jar", stem: "pe", name: "Particle Effects", id: nil)
        let byId = mod("pe.jar", stem: "pe", name: "PE", id: "particle_effects")
        XCTAssertEqual(StartupCrashAnalyzer.matchInstalledMod("particle_effects", installedMods: [byName])?.displayName, "Particle Effects")
        XCTAssertEqual(StartupCrashAnalyzer.matchInstalledMod("particle-effects", installedMods: [byId])?.modId, "particle_effects")
        XCTAssertNil(StartupCrashAnalyzer.matchInstalledMod("totally-different", installedMods: [byName]))
    }

    // MARK: - Modrinth slug alias ladder (forge-family conditional)

    func testCommonAliasesApplyRegardlessOfLoader() {
        for forge in [true, false] {
            XCTAssertEqual(ModrinthSlugNormalizer.canonicalSlug(for: "connectormod", forgeFamily: forge), "connector")
            XCTAssertEqual(ModrinthSlugNormalizer.canonicalSlug(for: "kotlinforforge", forgeFamily: forge), "kotlin-for-forge")
        }
    }

    func testFabricApiAliasIsForgeFamilyOnly() {
        // On Forge/NeoForge the server-usable project is forgified-fabric-api…
        XCTAssertEqual(ModrinthSlugNormalizer.canonicalSlug(for: "fabric_api", forgeFamily: true), "forgified-fabric-api")
        XCTAssertEqual(ModrinthSlugNormalizer.canonicalSlug(for: "fabric-api", forgeFamily: true), "forgified-fabric-api")
        // …but on a real Fabric server fabric-api is correct and must NOT be rewritten.
        XCTAssertEqual(ModrinthSlugNormalizer.canonicalSlug(for: "fabric_api", forgeFamily: false), "fabric-api")
        XCTAssertEqual(ModrinthSlugNormalizer.canonicalSlug(for: "fabric-api", forgeFamily: false), "fabric-api")
    }

    func testUnknownSlugNormalizesButIsNotAnAlias() {
        XCTAssertEqual(ModrinthSlugNormalizer.canonicalSlug(for: "Some Random Mod", forgeFamily: true), "some-random-mod")
        XCTAssertFalse(ModrinthSlugNormalizer.isKnownAlias("Some Random Mod", forgeFamily: true))
        XCTAssertTrue(ModrinthSlugNormalizer.isKnownAlias("connectormod", forgeFamily: false))
        XCTAssertTrue(ModrinthSlugNormalizer.isKnownAlias("fabric_api", forgeFamily: true))
        XCTAssertFalse(ModrinthSlugNormalizer.isKnownAlias("fabric_api", forgeFamily: false))
    }

    func testNormalizedSlugBasics() {
        XCTAssertEqual(ModrinthSlugNormalizer.normalizedSlug("Fabric API"), "fabric-api")
        XCTAssertEqual(ModrinthSlugNormalizer.normalizedSlug("  Kotlin__For  Forge "), "kotlin-for-forge")
    }
}

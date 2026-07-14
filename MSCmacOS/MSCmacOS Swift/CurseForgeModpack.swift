//
//  CurseForgeModpack.swift
//  MinecraftServerController
//
//  P7.10: CurseForge modpack (.zip / manifest.json) import support.
//
//  A CurseForge modpack is a plain .zip whose root holds a `manifest.json` with
//  `manifestType: "minecraftModpack"`. Unlike a Modrinth .mrpack it carries NO download
//  URLs (only projectID/fileID pairs, resolved through the official CurseForge API) and
//  NO per-file client/server env info — so client-only detection at import time falls
//  back to the same hash→Modrinth / jar-metadata tiers the .mrpack path already uses.
//
//  Everything in this file is network-free and pure so it is fully unit-testable: the
//  models, pack-type detection, loader-id parsing, and manual-download-list assembly.
//  The actual downloads live in CurseForgeAPI.swift; the import orchestration in
//  AppViewModel+ModManagement.swift.
//

import Foundation

// MARK: - CurseForge manifest models

/// The decoded `manifest.json` at a CurseForge modpack's root.
struct CurseForgeManifest: Codable {
    let manifestType: String?
    let manifestVersion: Int?
    let name: String?
    let version: String?
    let author: String?
    let minecraft: CurseForgeMinecraft
    let files: [CurseForgeFileRef]
    /// Name of the folder holding client configs/resources to copy verbatim ("overrides").
    let overrides: String?
}

struct CurseForgeMinecraft: Codable {
    let version: String
    let modLoaders: [CurseForgeModLoader]
}

struct CurseForgeModLoader: Codable {
    /// e.g. "forge-47.4.1", "neoforge-21.1.72", "fabric-0.16.9".
    let id: String
    let primary: Bool?
}

struct CurseForgeFileRef: Codable {
    let projectID: Int
    let fileID: Int
    let required: Bool?
}

// MARK: - Errors

enum CurseForgeManifestError: LocalizedError {
    case notCurseForgeModpack
    case malformedLoaderId(String)
    case unknownLoader(String)

    var errorDescription: String? {
        switch self {
        case .notCurseForgeModpack:
            return "Not a CurseForge modpack (no manifest.json with manifestType \"minecraftModpack\")."
        case .malformedLoaderId(let id):
            return "Could not read the modpack's loader id \"\(id)\"."
        case .unknownLoader(let name):
            return "Unsupported modpack loader \"\(name)\". MSC supports Forge, NeoForge, Fabric, and Quilt."
        }
    }
}

// MARK: - Pack-type detection

/// Which modpack format an extracted archive root represents. Detection sniffs the root:
/// a `modrinth.index.json` is a Modrinth .mrpack; a `manifest.json` with manifestType
/// "minecraftModpack" is a CurseForge pack; anything else is left to existing behavior.
enum ModpackArchiveKind: Equatable {
    case modrinth
    case curseForge
    case unknown
}

enum CurseForgeModpack {

    /// Classifies an already-extracted archive root. Modrinth wins if both markers exist
    /// (a pack is never both). Pure over the filesystem so it is easy to test with temp dirs.
    static func detectKind(inExtractedRoot root: URL, fm: FileManager = .default) -> ModpackArchiveKind {
        if fm.fileExists(atPath: root.appendingPathComponent("modrinth.index.json").path) {
            return .modrinth
        }
        let cfManifest = root.appendingPathComponent("manifest.json")
        if fm.fileExists(atPath: cfManifest.path),
           let data = try? Data(contentsOf: cfManifest),
           isCurseForgeModpackManifest(data) {
            return .curseForge
        }
        return .unknown
    }

    /// True when `data` decodes as a CurseForge manifest whose `manifestType` is
    /// "minecraftModpack" (case-insensitive). Cheap, so callers can sniff before committing.
    static func isCurseForgeModpackManifest(_ data: Data) -> Bool {
        guard let manifest = try? JSONDecoder().decode(CurseForgeManifest.self, from: data) else {
            return false
        }
        return manifest.manifestType?.lowercased() == "minecraftmodpack"
    }

    // MARK: - Loader-id parsing

    /// Result of mapping a CurseForge `modLoaders` id onto MSC's flavor + pinned version.
    struct LoaderParse: Equatable {
        let flavor: JavaServerFlavor
        let loaderVersion: String?
    }

    /// Parses a CurseForge loader id ("forge-47.4.1", "neoforge-21.1.72", "fabric-0.16.9")
    /// into a flavor + loader version. The prefix before the first "-" names the loader;
    /// the remainder is the version. Unknown prefixes and empty ids throw rather than guess.
    static func parseLoaderId(_ raw: String) throws -> LoaderParse {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { throw CurseForgeManifestError.malformedLoaderId(raw) }

        let name: String
        let version: String?
        if let dash = id.firstIndex(of: "-") {
            name = String(id[..<dash]).lowercased()
            let rest = String(id[id.index(after: dash)...])
            version = rest.isEmpty ? nil : rest
        } else {
            name = id.lowercased()
            version = nil
        }

        let flavor: JavaServerFlavor
        switch name {
        case "forge":    flavor = .forge
        case "neoforge": flavor = .neoforge
        case "fabric":   flavor = .fabric
        case "quilt":    flavor = .quilt
        default:
            throw CurseForgeManifestError.unknownLoader(name)
        }
        return LoaderParse(flavor: flavor, loaderVersion: version)
    }

    // MARK: - Manual-download list (distribution-blocked files)

    /// A CurseForge file whose author opted out of API distribution (`downloadUrl == null`).
    /// The user must fetch it manually from CurseForge and drop it into `mods/`.
    struct ManualDownload: Equatable {
        let modName: String
        let fileName: String
        let projectPageURL: String
    }

    /// Assembles the manual-download list from the CF API responses for the blocked files.
    /// `blockedFiles` are file records whose `downloadUrl` was nil; `projectsById` maps a
    /// mod (project) id to its project record for the human-readable name + CurseForge page.
    /// Pure — no network — so the null-url → manual-list path is unit-testable.
    static func manualDownloads(
        blockedFiles: [CFFile],
        projectsById: [Int: CFMod]
    ) -> [ManualDownload] {
        blockedFiles.map { file in
            let project = projectsById[file.modId]
            let name = project?.name ?? file.displayName ?? file.fileName
            let page = project?.links?.websiteUrl
                ?? "https://www.curseforge.com/minecraft/search?search=\(file.fileName)"
            return ManualDownload(modName: name, fileName: file.fileName, projectPageURL: page)
        }
    }
}

// MARK: - Wizard pinning metadata

/// Distilled view of a CurseForge manifest for the Add Server wizard: pinned Minecraft
/// version + loader flavor/version, mirroring `MrpackMetadata` so the wizard's pinning
/// path (P7.2) is reused unchanged.
struct CurseForgeMetadata {
    let manifest: CurseForgeManifest
    let name: String
    let versionId: String
    let minecraftVersion: String?
    let loaderFlavor: JavaServerFlavor?
    let loaderVersion: String?

    /// Shared with the .mrpack path — produces the "1.20.1 — Forge 47.4.1" picker entry.
    var versionEntry: ServerVersionEntry? {
        ModpackVersionEntry.make(
            minecraftVersion: minecraftVersion,
            loaderFlavor: loaderFlavor,
            loaderVersion: loaderVersion
        )
    }

    /// Maps a decoded CurseForge manifest onto pinning metadata. Picks the `primary`
    /// mod loader (else the first) and parses its id. Throws on unknown/malformed loaders
    /// so the wizard shows a clear error instead of pinning a guess.
    static func from(manifest: CurseForgeManifest) throws -> CurseForgeMetadata {
        let loaderEntry = manifest.minecraft.modLoaders.first(where: { $0.primary == true })
            ?? manifest.minecraft.modLoaders.first

        var flavor: JavaServerFlavor?
        var loaderVersion: String?
        if let loaderEntry {
            let parsed = try CurseForgeModpack.parseLoaderId(loaderEntry.id)
            flavor = parsed.flavor
            loaderVersion = parsed.loaderVersion
        }

        let mc = manifest.minecraft.version.trimmingCharacters(in: .whitespacesAndNewlines)
        return CurseForgeMetadata(
            manifest: manifest,
            name: manifest.name?.isEmpty == false ? manifest.name! : "CurseForge Modpack",
            versionId: manifest.version ?? "",
            minecraftVersion: mc.isEmpty ? nil : mc,
            loaderFlavor: flavor,
            loaderVersion: loaderVersion
        )
    }
}

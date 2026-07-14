//
//  ModpackClientOnlyClassifier.swift
//  MinecraftServerController
//
//  P7.4: auto-disable client-only mods during .mrpack import.
//
//  BMC4 (and packs like it) mark every manifest file `server=required` even though
//  ~56 of them are client-only (continuity, BadOptimizations, ParticleEffects…), each
//  of which crashes or degrades a dedicated server. The manifest alone cannot be trusted,
//  so the importer classifies each mod jar through three tiers and disables the client-only
//  ones (rename `.jar` → `.jar.disabled`, the app's existing convention).
//
//  Everything here is network-free and filesystem-only so it is fully unit-testable:
//  the AppViewModel importer does the fetching and feeds this already-resolved metadata.
//

import Foundation

enum ModpackClientOnlyClassifier {

    // MARK: - Tier 1 — manifest env

    /// The `.mrpack` manifest's own signal: a file whose `env.server == "unsupported"`
    /// is client-only. (These files are filtered out before download; they never land
    /// on disk.) Pure so the filter itself is unit-testable.
    static func isManifestServerUnsupported(_ env: MrpackEnv?) -> Bool {
        env?.server?.lowercased() == "unsupported"
    }

    // MARK: - Tier 2 — Modrinth project id extraction

    /// Extracts a Modrinth project ID from a file's download URLs. Modrinth CDN URLs
    /// look like `https://cdn.modrinth.com/data/<projectId>/versions/<versionId>/<file>.jar`,
    /// so the segment right after `data/` is the project ID. Returns nil for non-Modrinth
    /// or malformed URLs.
    static func modrinthProjectId(fromDownloadURLs urls: [String]) -> String? {
        for download in urls {
            guard let url = URL(string: download),
                  url.host?.lowercased().contains("modrinth.com") == true else { continue }
            let components = url.pathComponents        // e.g. ["/", "data", "<id>", "versions", …]
            guard let dataIndex = components.firstIndex(of: "data") else { continue }
            let idIndex = components.index(after: dataIndex)
            guard components.indices.contains(idIndex) else { continue }
            let candidate = components[idIndex]
            if !candidate.isEmpty, candidate != "/", candidate != "versions" { return candidate }
        }
        return nil
    }

    // MARK: - Tiers 2 + 3 — the decision table

    /// Resolves whether a mod is client-only, and why. Modrinth is authoritative when its
    /// metadata is present:
    ///   • `server_side == "unsupported"` → client-only (disable), reason names Modrinth.
    ///   • `server_side` present and *not* unsupported → server-usable, keep enabled —
    ///     Modrinth wins over the jar's embedded env (many single-jar mods ship a
    ///     client-facing `fabric.mod.json` yet run fine server-side).
    /// Only when Modrinth metadata is absent/unknown (unlisted project, or the network
    /// call failed) do we fall back to Tier 3, the jar's embedded `fabric.mod.json`:
    ///   • `environment == "client"` → client-only (disable), reason names the jar.
    /// Returns a human-readable reason when the mod should be disabled, else nil.
    static func clientOnlyReason(
        modrinthServerSide serverSide: String?,
        modrinthProjectTitle title: String?,
        jarEnvironment: String?
    ) -> String? {
        if let side = serverSide?.lowercased(), !side.isEmpty {
            if side == "unsupported" {
                return "Modrinth marks \(title ?? "this mod") as client-only (server_side=unsupported)"
            }
            // Modrinth explicitly says it works server-side — trust it over the jar env.
            return nil
        }
        // Tier 3 fallback: no Modrinth data for this jar.
        if jarEnvironment?.lowercased() == "client" {
            return "Embedded fabric.mod.json marks it environment=client"
        }
        return nil
    }

    // MARK: - Disabling (filesystem, never-clobber)

    /// True when a manifest file path points at a jar inside the `mods/` folder.
    static func isModsJar(path: String) -> Bool {
        let lower = path.lowercased()
        return lower.hasPrefix("mods/") && lower.hasSuffix(".jar")
    }

    /// The `.jar.disabled` sibling for an active `.jar` URL.
    static func disabledURL(forActiveJar jarURL: URL) -> URL {
        jarURL.appendingPathExtension("disabled")
    }

    /// Renames an active `.jar` to `.jar.disabled`, honoring the never-clobber rule: if a
    /// `.jar.disabled` already exists (a prior import already disabled this mod), the freshly
    /// present active jar is removed rather than overwriting the existing disabled copy — we
    /// never re-enable or clobber a `.jar.disabled`. Returns the disabled filename on success,
    /// or nil if there was nothing to disable or the rename failed.
    @discardableResult
    static func disableJar(at jarURL: URL, fm: FileManager = .default) -> String? {
        let disabledURL = disabledURL(forActiveJar: jarURL)
        do {
            if fm.fileExists(atPath: disabledURL.path) {
                // Never clobber an existing .jar.disabled — drop the redundant active jar.
                if fm.fileExists(atPath: jarURL.path) { try fm.removeItem(at: jarURL) }
                return disabledURL.lastPathComponent
            }
            guard fm.fileExists(atPath: jarURL.path) else { return nil }
            try fm.moveItem(at: jarURL, to: disabledURL)
            return disabledURL.lastPathComponent
        } catch {
            return nil
        }
    }
}

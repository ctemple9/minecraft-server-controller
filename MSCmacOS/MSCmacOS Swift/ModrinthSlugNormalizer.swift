//
//  ModrinthSlugNormalizer.swift
//  MinecraftServerController
//
//  P7.5: maps a loader mod-id (as it appears in a Forge/Fabric crash log) to the Modrinth
//  project slug it actually lives under. Forge internal ids are NOT Modrinth slugs — e.g.
//  a crash names `connectormod`, but the project is `connector`; `kotlinforforge` →
//  `kotlin-for-forge`.
//
//  The Fabric-API alias is loader-conditional: on a Forge/NeoForge server (running Fabric
//  mods through Sinytra Connector) the server-usable project is `forgified-fabric-api`, but
//  on a real Fabric/Quilt server `fabric-api` is already correct and must NOT be rewritten.
//  Callers pass `forgeFamily` so the same offender resolves correctly per server type.
//

import Foundation

enum ModrinthSlugNormalizer {

    /// Aliases that hold regardless of server loader.
    private static let commonAliases: [String: String] = [
        "connectormod": "connector",
        "connector-mod": "connector",
        "kotlinforforge": "kotlin-for-forge",
        "kotlin-for-forge": "kotlin-for-forge",
    ]

    /// Aliases that apply ONLY on Forge-family servers (Forge/NeoForge). On Fabric/Quilt
    /// these must be left alone — `fabric-api` is the correct project there.
    private static let forgeFamilyAliases: [String: String] = [
        "fabric-api": "forgified-fabric-api",
        "fabricapi": "forgified-fabric-api",
        "fabric-api-base": "forgified-fabric-api",
        "forgified-fabric-api": "forgified-fabric-api",
    ]

    /// Lowercases and collapses every run of non-alphanumerics to a single dash, trimming
    /// leading/trailing dashes. "Fabric API" → "fabric-api"; "connector_mod" → "connector-mod".
    static func normalizedSlug(_ raw: String) -> String {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var result = ""
        var previousWasDash = false
        for scalar in lower.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
                previousWasDash = false
            } else if !previousWasDash {
                result.append("-")
                previousWasDash = true
            }
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// The best-known Modrinth slug for a raw mod-id/name. Applies the common alias table
    /// unconditionally, then the Forge-family alias table only when `forgeFamily` is true.
    /// Returns the plain normalized slug when no alias matches.
    static func canonicalSlug(for raw: String, forgeFamily: Bool) -> String {
        let normalized = normalizedSlug(raw)
        if let alias = commonAliases[normalized] { return alias }
        if forgeFamily, let alias = forgeFamilyAliases[normalized] { return alias }
        return normalized
    }

    /// The search-query form: the canonical slug, or the raw text when normalization empties it.
    static func searchQuery(for raw: String, forgeFamily: Bool) -> String {
        let canonical = canonicalSlug(for: raw, forgeFamily: forgeFamily)
        return canonical.isEmpty ? raw : canonical
    }

    /// True when a slug was rewritten by an alias (i.e. the canonical form is a *known*
    /// project, not just a normalized guess) — the identity ladder trusts these directly.
    static func isKnownAlias(_ raw: String, forgeFamily: Bool) -> Bool {
        canonicalSlug(for: raw, forgeFamily: forgeFamily) != normalizedSlug(raw)
    }
}

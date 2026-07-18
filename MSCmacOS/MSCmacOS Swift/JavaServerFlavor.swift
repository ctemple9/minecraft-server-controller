//
//  JavaServerFlavor.swift
//  MinecraftServerController
//
//  M0 foundation for multi-server-type support. Describes the specific Java
//  server software a server runs (Paper, Purpur, Fabric, NeoForge, …), the
//  category it belongs to (Standard vs Modded), how it is provisioned, and what
//  kind of add-ons it accepts. Consumed by the Create Server flow and the
//  add-ons manager. See the working-notes design doc, milestone M0.
//

import Foundation

// MARK: - Java Server Category

/// The two top-level categories a Java server falls into. Surfaced as the
/// visible Level-1 choice in the Create Server flow.
enum JavaServerCategory: String, Codable, CaseIterable {
    case standard   // plugin servers — players join with a normal client
    case modded     // mod loaders — every player needs the same mods

    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .modded:   return "Modded"
        }
    }

    /// One-line subtitle shown under the category card. (Wording is locked.)
    var subtitle: String {
        switch self {
        case .standard: return "Players join normally · add plugins"
        case .modded:   return "Adds new content · players need the mods"
        }
    }
}

// MARK: - Provisioning Kind

/// How a server flavor is provisioned. Drives the "Creating" screen and effort.
/// - `downloadAndGo`: fetch one jar, accept EULA, launch. No install step.
/// - `installStep`:   a separate, fallible install/build phase (progress + log + retry).
enum ServerProvisioningKind {
    case downloadAndGo
    case installStep
}

// MARK: - Add-on Kind

/// What kind of add-on a server accepts, and where those files live.
enum AddOnKind {
    case plugin   // Bukkit/Paper plugins → plugins/ ; server-side only
    case mod      // Fabric/NeoForge mods → mods/ ; server + every client

    /// Folder (relative to serverDir) where these add-ons are installed.
    var folderName: String {
        switch self {
        case .plugin: return "plugins"
        case .mod:    return "mods"
        }
    }

    var displayName: String {
        switch self {
        case .plugin: return "Plugins"
        case .mod:    return "Mods"
        }
    }
}

// MARK: - Java Server Flavor

/// The specific Java server software a server runs. Persisted as a string.
/// Defaults to `.paper` everywhere so existing servers are unaffected.
enum JavaServerFlavor: String, Codable, CaseIterable {
    // Standard (plugin) servers
    case paper
    case purpur
    case pufferfish
    case vanilla
    // Modded (loader) servers
    case fabric
    case neoforge
    // Known to the model but not yet surfaced in the Create flow (future milestones)
    case spigot
    case forge
    case quilt

    var displayName: String {
        switch self {
        case .paper:      return "Paper"
        case .purpur:     return "Purpur"
        case .pufferfish: return "Pufferfish"
        case .vanilla:    return "Vanilla"
        case .fabric:     return "Fabric"
        case .neoforge:   return "NeoForge"
        case .spigot:     return "Spigot"
        case .forge:      return "Forge"
        case .quilt:      return "Quilt"
        }
    }

    /// One-line purpose shown on the Level-2 selection card in the Create flow.
    var shortDescription: String {
        switch self {
        case .paper:      return "Performance and bug fixes; the standard plugin server"
        case .purpur:     return "Paper plus hundreds of gameplay config options"
        case .pufferfish: return "Paper fork tuned for raw performance"
        case .vanilla:    return "Mojang's unmodified server"
        case .fabric:     return "Lightweight mod loader; great for performance mods"
        case .neoforge:   return "Heavyweight loader for big content modpacks"
        case .spigot:     return "Classic plugin server (legacy)"
        case .forge:      return "Original loader; huge library of mods and modpacks"
        case .quilt:      return "Community Fabric fork"
        }
    }

    var category: JavaServerCategory {
        switch self {
        case .paper, .purpur, .pufferfish, .vanilla, .spigot:
            return .standard
        case .fabric, .neoforge, .forge, .quilt:
            return .modded
        }
    }

    /// Forge/NeoForge run Fabric mods through Sinytra Connector, which changes which
    /// Modrinth project a Fabric-side dependency maps to (e.g. fabric-api →
    /// forgified-fabric-api). Used by ModrinthSlugNormalizer to alias conditionally.
    var isForgeFamily: Bool { self == .forge || self == .neoforge }

    /// What add-ons this flavor accepts. Vanilla has no plugin/mod API
    /// (datapacks only), so it returns nil — the add-on browser is hidden for it.
    var addOnKind: AddOnKind? {
        switch self {
        case .vanilla: return nil
        default:       return category == .standard ? .plugin : .mod
        }
    }

    /// How this flavor is provisioned. Spigot looks like a download to the user
    /// but actually needs a local BuildTools compile, so it's an install step.
    var provisioningKind: ServerProvisioningKind {
        switch self {
        case .neoforge, .forge, .spigot: return .installStep
        default:                         return .downloadAndGo
        }
    }

    /// Modrinth `project_type` facet for this flavor's add-on catalog.
    var modrinthProjectType: String {
        category == .standard ? "plugin" : "mod"
    }

    /// Modrinth `loaders` facet values used when searching add-ons for this flavor.
    /// Empty when the flavor has no add-on catalog (Vanilla).
    var modrinthLoaderFacets: [String] {
        switch self {
        case .paper, .purpur, .pufferfish, .spigot: return ["paper", "spigot", "bukkit"]
        case .fabric:                               return ["fabric"]
        case .quilt:                                return ["quilt", "fabric"]
        case .neoforge:                             return ["neoforge"]
        case .forge:                                return ["forge"]
        case .vanilla:                              return []
        }
    }

    /// SF Symbol used to represent this flavor in the UI (create cards, lists).
    var iconName: String {
        switch self {
        case .paper:      return "cup.and.saucer.fill"
        case .purpur:     return "wand.and.stars"
        case .pufferfish: return "bolt.fill"
        case .vanilla:    return "cube"
        case .fabric:     return "puzzlepiece.fill"
        case .neoforge:   return "hammer.fill"
        case .spigot:     return "cup.and.saucer.fill"
        case .forge:      return "hammer.fill"
        case .quilt:      return "puzzlepiece.extension.fill"
        }
    }

    /// Flavor-specific console command MSC can send to request a TPS sample.
    /// Paper-family servers expose a bare `tps`; Forge and NeoForge nest it under
    /// their loader root command (`forge tps` / `neoforge tps`). Vanilla, Fabric,
    /// and Quilt have no stable built-in TPS command, so this is nil for them and
    /// MSC skips the poll rather than spamming "Unknown or incomplete command".
    var autoTpsCommand: String? {
        switch self {
        case .paper, .purpur, .pufferfish, .spigot:
            return "tps"
        case .forge:
            return "forge tps"
        case .neoforge:
            return "neoforge tps"
        case .vanilla, .fabric, .quilt:
            return nil
        }
    }

    /// The console command MSC should poll for a live TPS sample, given the
    /// server's Minecraft version. Loader-native commands (Paper `tps`, Forge /
    /// NeoForge `… tps`) are version-independent, so they come straight from
    /// `autoTpsCommand`. Vanilla, Fabric, and Quilt have no loader TPS command,
    /// but Minecraft 1.20.3+ ships the vanilla `/tick query`, whose "Average time
    /// per tick" line `TpsLineParser` converts into a TPS figure. Older versions
    /// (and unknown versions) return nil so MSC skips the poll rather than
    /// spamming "Unknown or incomplete command".
    func tpsPollCommand(minecraftVersion: String?) -> String? {
        if let native = autoTpsCommand { return native }
        switch self {
        case .vanilla, .fabric, .quilt:
            return Self.supportsVanillaTickQuery(minecraftVersion) ? "tick query" : nil
        default:
            return nil
        }
    }

    /// Whether the running server exposes the vanilla `/tick query` command,
    /// added in Minecraft 1.20.3. Uses a numeric string compare so multi-digit
    /// components order correctly (e.g. "1.20.10" > "1.20.3"). Unknown/empty
    /// versions are treated as unsupported to avoid console spam.
    static func supportsVanillaTickQuery(_ minecraftVersion: String?) -> Bool {
        guard let v = minecraftVersion?.trimmingCharacters(in: .whitespaces),
              !v.isEmpty else { return false }
        return v.compare("1.20.3", options: .numeric) != .orderedAscending
    }

    /// Highlighted as the recommended default within its category.
    var isRecommended: Bool { self == .paper || self == .fabric }

    /// Whether this flavor is offered in the Create Server flow today.
    var isAvailableInCreateFlow: Bool {
        switch self {
        case .spigot, .quilt, .pufferfish: return false
        default:                            return true
        }
    }

    /// Flavors offered for a given category in the Create flow, recommended first.
    static func createFlowChoices(in category: JavaServerCategory) -> [JavaServerFlavor] {
        allCases
            .filter { $0.category == category && $0.isAvailableInCreateFlow }
            .sorted { ($0.isRecommended ? 0 : 1) < ($1.isRecommended ? 0 : 1) }
    }
}

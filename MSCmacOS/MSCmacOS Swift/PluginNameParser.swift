//
//  PluginNameParser.swift
//  MinecraftServerController
//
//  Extracts a human-readable plugin name and version from a JAR filename stem.
//
//  Common patterns handled:
//    Geyser-Spigot-2.4.3-b375   → name: "Geyser-Spigot",    version: "2.4.3-b375"
//    LuckPerms-Bukkit-5.4.141   → name: "LuckPerms-Bukkit",  version: "5.4.141"
//    EssentialsX-2.21.0         → name: "EssentialsX",       version: "2.21.0"
//    WorldEdit                  → name: "WorldEdit",          version: nil
//    VaultAPI                   → name: "VaultAPI",           version: nil
//

import Foundation

enum PluginNameParser {

    // MARK: - Public API

    /// Returns the plugin name portion of a JAR stem (strips trailing version numbers).
    static func extractDisplayName(from stem: String) -> String {
        let parts = stem.components(separatedBy: "-")
        var nameParts: [String] = []
        for part in parts {
            // Stop accumulating name parts once we hit something that looks like a version
            if looksLikeVersionComponent(part) { break }
            nameParts.append(part)
        }
        let name = nameParts.joined(separator: "-")
        return name.isEmpty ? stem : name
    }

    /// Returns the version string portion of a JAR stem, or nil if none found.
    static func extractVersion(from stem: String) -> String? {
        let parts = stem.components(separatedBy: "-")
        var versionParts: [String] = []
        var collecting = false
        for part in parts {
            if looksLikeVersionComponent(part) { collecting = true }
            if collecting { versionParts.append(part) }
        }
        let version = versionParts.joined(separator: "-")
        return version.isEmpty ? nil : version
    }

    // MARK: - Helpers

    /// Returns true if the string looks like a version component.
    /// Matches: "1.21.4", "5.4.141", "b375", "v2.1.0", "2", "374" etc.
    private static func looksLikeVersionComponent(_ s: String) -> Bool {
        guard !s.isEmpty else { return false }
        // Starts with a digit or a 'v'/'b' followed by digits
        let lower = s.lowercased()
        if lower.first?.isNumber == true { return true }
        if (lower.hasPrefix("v") || lower.hasPrefix("b")),
           lower.dropFirst().first?.isNumber == true { return true }
        return false
    }
}

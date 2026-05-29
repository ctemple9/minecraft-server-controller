//
//  PluginSourceDetector.swift
//  MinecraftServerController
//
//  Detects plugin source type from a URL string and parses the structured
//  identifiers needed to call the appropriate API.
//

import Foundation

enum PluginSourceDetector {

    // MARK: - Type detection

    /// Infers the source type from a URL string.
    /// Returns nil if the URL is blank or unrecognisable.
    static func detect(url: String) -> PluginSourceType? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains("github.com")          { return .github }
        if trimmed.contains("modrinth.com")        { return .modrinth }
        if trimmed.contains("hangar.papermc.io")   { return .hangar }
        // Anything with a scheme or a .jar suffix is treated as a direct download
        if trimmed.hasSuffix(".jar") || trimmed.hasPrefix("http") { return .direct }
        return nil
    }

    // MARK: - GitHub

    /// Parses `github.com/owner/repo` (with or without https://) into owner + repo.
    static func parseGitHub(url: String) -> (owner: String, repo: String)? {
        let clean = stripScheme(url)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // Expect: github.com/owner/repo[/anything]
        let parts = clean.components(separatedBy: "/")
        guard parts.count >= 3,
              parts[0].lowercased() == "github.com",
              !parts[1].isEmpty,
              !parts[2].isEmpty
        else { return nil }
        return (parts[1], parts[2])
    }

    // MARK: - Modrinth

    /// Parses `modrinth.com/plugin/slug` (or /mod/slug) into slug.
    static func parseModrinth(url: String) -> String? {
        let clean = stripScheme(url)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = clean.components(separatedBy: "/")
        // modrinth.com / (plugin|mod|project) / slug
        guard parts.count >= 3,
              parts[0].lowercased() == "modrinth.com",
              !parts[2].isEmpty
        else { return nil }
        return parts[2]
    }

    // MARK: - Hangar

    /// Parses `hangar.papermc.io/Author/PluginName` into author + slug.
    static func parseHangar(url: String) -> (author: String, slug: String)? {
        let clean = stripScheme(url)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = clean.components(separatedBy: "/")
        guard parts.count >= 3,
              parts[0].lowercased() == "hangar.papermc.io",
              !parts[1].isEmpty,
              !parts[2].isEmpty
        else { return nil }
        return (parts[1], parts[2])
    }

    // MARK: - Helpers

    private static func stripScheme(_ url: String) -> String {
        var s = url.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://"] {
            if s.lowercased().hasPrefix(prefix) {
                s = String(s.dropFirst(prefix.count))
                break
            }
        }
        return s
    }
}

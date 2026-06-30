//
//  ModJarMetadataParser.swift
//  MinecraftServerController
//
//  Extracts mod metadata from .jar files (which are ZIPs).
//  Fabric mods carry fabric.mod.json; NeoForge/Forge mods carry META-INF/mods.toml.
//  Falls back to filename heuristics (PluginNameParser) when no recognized manifest exists.
//

import Foundation

enum ModJarMetadataParser {

    struct ModMetadata: Equatable {
        let modId: String?
        let displayName: String?
        let version: String?
        /// Author/team string when the manifest provides one (used for name-based
        /// Modrinth matching). Nil when unknown.
        var author: String? = nil
        /// For Fabric mods: "client", "server", or "*" from fabric.mod.json "environment".
        /// Nil for Forge/NeoForge mods and unrecognised jars.
        var environment: String? = nil
    }

    /// Tries to extract mod metadata from a JAR file.
    /// Returns nil if the jar has no recognizable mod manifest.
    static func parse(jarURL: URL) -> ModMetadata? {
        if let meta = parseFabric(jarURL: jarURL) { return meta }
        if let meta = parseForge(jarURL: jarURL)  { return meta }
        return nil
    }

    /// Tries every known manifest format — Fabric, NeoForge/Forge, and Bukkit/Paper
    /// plugin descriptors — returning the first that yields an identity. Use this when
    /// the jar could be either a mod or a plugin (the add-on update resolver).
    static func parseAny(jarURL: URL) -> ModMetadata? {
        if let meta = parseFabric(jarURL: jarURL) { return meta }
        if let meta = parseForge(jarURL: jarURL)  { return meta }
        if let meta = parsePlugin(jarURL: jarURL) { return meta }
        return nil
    }

    // MARK: - Bukkit / Spigot / Paper: plugin.yml or paper-plugin.yml

    private static func parsePlugin(jarURL: URL) -> ModMetadata? {
        // paper-plugin.yml takes precedence on Paper, but both share the same keys.
        for entry in ["plugin.yml", "paper-plugin.yml"] {
            guard let data = extractFromZip(jarURL: jarURL, entryPath: entry),
                  let text = String(data: data, encoding: .utf8) else { continue }
            if let meta = parsePluginYml(text) { return meta }
        }
        return nil
    }

    /// Parses the top-level `name`, `version`, and `author`/`authors` keys from a
    /// Bukkit-style plugin.yml. Only top-level (non-indented) keys are considered so
    /// nested mappings (commands, permissions) can't shadow them. Internal for testing.
    static func parsePluginYml(_ text: String) -> ModMetadata? {
        var name: String?
        var version: String?
        var author: String?

        for raw in text.components(separatedBy: .newlines) {
            // Only top-level keys (no leading whitespace). Skip comments/blank lines.
            guard let first = raw.first, first != " ", first != "\t", first != "#" else { continue }
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let v = ymlScalar(line: line, key: "name")    { name = v }
            if let v = ymlScalar(line: line, key: "version") { version = v.hasPrefix("${") ? nil : v }
            if let v = ymlScalar(line: line, key: "author")  { author = v }
            if author == nil, let v = ymlInlineListFirst(line: line, key: "authors") { author = v }
        }

        guard name != nil || version != nil else { return nil }
        // Plugins have no stable machine ID like mods; use the lowercased name as modId
        // so downstream "already installed?" checks have something to match on.
        let modId = name.map { $0.lowercased().replacingOccurrences(of: " ", with: "-") }
        return ModMetadata(modId: modId, displayName: name, version: version, author: author)
    }

    /// Parses `key: value` from a YAML line, stripping optional surrounding quotes.
    private static func ymlScalar(line: String, key: String) -> String? {
        guard line.hasPrefix(key) else { return nil }
        let after = line.dropFirst(key.count)
        guard let colon = after.first, colon == ":" else { return nil }
        var value = after.dropFirst().trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
           (value.hasPrefix("'") && value.hasSuffix("'")), value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        return value.isEmpty ? nil : value
    }

    /// Parses the first element of an inline YAML list, e.g. `authors: [Alice, Bob]` → "Alice".
    private static func ymlInlineListFirst(line: String, key: String) -> String? {
        guard let raw = ymlScalar(line: line, key: key) else { return nil }
        guard raw.hasPrefix("[") else { return raw }  // not a list — return as-is
        let inner = raw.dropFirst().drop(while: { $0 == " " })
        let trimmed = inner.hasSuffix("]") ? inner.dropLast() : inner
        let firstElem = trimmed.split(separator: ",").first.map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
        }
        return firstElem?.isEmpty == false ? firstElem : nil
    }

    // MARK: - Fabric: fabric.mod.json

    private static func parseFabric(jarURL: URL) -> ModMetadata? {
        guard let data = extractFromZip(jarURL: jarURL, entryPath: "fabric.mod.json"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let modId = json["id"] as? String
        let name  = json["name"] as? String
        let ver   = (json["version"] as? String).flatMap { $0.hasPrefix("${") ? nil : $0 }
        let env   = json["environment"] as? String
        guard modId != nil || name != nil else { return nil }
        return ModMetadata(modId: modId, displayName: name, version: ver, environment: env)
    }

    // MARK: - NeoForge / Forge: META-INF/mods.toml

    private static func parseForge(jarURL: URL) -> ModMetadata? {
        guard let data = extractFromZip(jarURL: jarURL, entryPath: "META-INF/mods.toml"),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        return parseModsToml(text)
    }

    // MARK: - TOML line scanner (internal for testing)

    static func parseModsToml(_ text: String) -> ModMetadata? {
        var inModsSection = false
        var modId: String?
        var displayName: String?
        var version: String?

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[[") {
                // Leaving a [[mods]] section — stop if we have data
                if inModsSection && (modId != nil || displayName != nil) { break }
                inModsSection = (trimmed == "[[mods]]")
                continue
            }
            guard inModsSection else { continue }
            if let v = tomlStringValue(line: trimmed, key: "modId")      { modId = v }
            if let v = tomlStringValue(line: trimmed, key: "displayName") { displayName = v }
            if let v = tomlStringValue(line: trimmed, key: "version") {
                version = v.hasPrefix("${") ? nil : v
            }
        }

        guard modId != nil || displayName != nil else { return nil }
        return ModMetadata(modId: modId, displayName: displayName, version: version)
    }

    // MARK: - ZIP extraction via unzip -p

    /// Runs `unzip -p <jar> <entryPath>` and returns the file's bytes, or nil on failure.
    private static func extractFromZip(jarURL: URL, entryPath: String) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-p", jarURL.path, entryPath]
        let out = Pipe()
        p.standardOutput = out
        p.standardError  = Pipe()   // suppress unzip warnings
        do { try p.run(); p.waitUntilExit() } catch { return nil }
        guard p.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return data.isEmpty ? nil : data
    }

    // MARK: - TOML key="value" helper

    /// Parses a simple TOML assignment: `key = "value"` or `key = 'value'`.
    private static func tomlStringValue(line: String, key: String) -> String? {
        let candidates = [key + " = ", key + "="]
        var rest: Substring? = nil
        for prefix in candidates where line.hasPrefix(prefix) {
            rest = line[line.index(line.startIndex, offsetBy: prefix.count)...]
            break
        }
        guard var r = rest else { return nil }
        // Strip leading/trailing whitespace after the equals sign
        r = r.drop(while: { $0 == " " })
        let quoteChar: Character
        if r.hasPrefix("\"")      { quoteChar = "\"" }
        else if r.hasPrefix("'") { quoteChar = "'" }
        else { return nil }
        r = r.dropFirst()
        if let end = r.firstIndex(of: quoteChar) { return String(r[..<end]) }
        return nil
    }
}

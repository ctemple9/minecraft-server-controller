//
//  PurpurConfigManager.swift
//  MinecraftServerController
//
//  Reads and patches purpur.yml using indentation-aware path walking.
//  Uses the same "patch in place, preserve comments" approach as GeyserConfigManager.
//

import Foundation

struct PurpurConfig: Equatable {
    /// `world-settings.default.mobs.creeper.grief-radius`  (-1 = no limit, 0 = no grief)
    var creeperGriefRadius: Int = 3
    /// `world-settings.default.gameplay-mechanics.disable-ice-and-snow`
    var disableIceAndSnow: Bool = false
    /// `world-settings.default.gameplay-mechanics.disable-thunder`
    var disableThunder: Bool = false
    /// `world-settings.default.gameplay-mechanics.tick-fluids`
    var tickFluids: Bool = true
}

struct PurpurConfigManager {

    static func configURL(for serverDir: String) -> URL {
        URL(fileURLWithPath: serverDir, isDirectory: true)
            .appendingPathComponent("purpur.yml")
    }

    static func isAvailable(serverDir: String) -> Bool {
        FileManager.default.fileExists(atPath: configURL(for: serverDir).path)
    }

    static func readConfig(serverDir: String) -> PurpurConfig? {
        let url = configURL(for: serverDir)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: .newlines)
        var cfg = PurpurConfig()
        if let v = walkPath(["world-settings", "default", "mobs", "creeper", "grief-radius"], in: lines) {
            cfg.creeperGriefRadius = Int(v) ?? 3
        }
        if let v = walkPath(["world-settings", "default", "gameplay-mechanics", "disable-ice-and-snow"], in: lines) {
            cfg.disableIceAndSnow = v == "true"
        }
        if let v = walkPath(["world-settings", "default", "gameplay-mechanics", "disable-thunder"], in: lines) {
            cfg.disableThunder = v == "true"
        }
        if let v = walkPath(["world-settings", "default", "gameplay-mechanics", "tick-fluids"], in: lines) {
            cfg.tickFluids = v != "false"
        }
        return cfg
    }

    static func writeConfig(serverDir: String, config: PurpurConfig) throws {
        let url = configURL(for: serverDir)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let original = try String(contentsOf: url, encoding: .utf8)
        var patched = original
        patched = patchPath(["world-settings", "default", "mobs", "creeper", "grief-radius"],
                            value: String(config.creeperGriefRadius), in: patched)
        patched = patchPath(["world-settings", "default", "gameplay-mechanics", "disable-ice-and-snow"],
                            value: config.disableIceAndSnow ? "true" : "false", in: patched)
        patched = patchPath(["world-settings", "default", "gameplay-mechanics", "disable-thunder"],
                            value: config.disableThunder ? "true" : "false", in: patched)
        patched = patchPath(["world-settings", "default", "gameplay-mechanics", "tick-fluids"],
                            value: config.tickFluids ? "true" : "false", in: patched)
        guard patched != original else { return }
        try patched.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Private helpers

    /// Walks a YAML path (2-space indents assumed, matching Purpur defaults).
    /// Returns the string value of the leaf key, or nil if the path is not found.
    private static func walkPath(_ path: [String], in lines: [String]) -> String? {
        var pathIndex = 0
        var parentIndent = -2

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let indent = line.prefix(while: { $0 == " " }).count

            // Exited the parent block without finding the next key
            if pathIndex > 0, indent <= parentIndent { return nil }

            let expectedKey = path[pathIndex]
            guard trimmed.hasPrefix(expectedKey + ":") else { continue }

            // Each nesting level adds 2 spaces
            let expectedIndent = pathIndex * 2
            guard indent == expectedIndent else { continue }

            if pathIndex == path.count - 1 {
                let after = String(trimmed.dropFirst(expectedKey.count + 1))
                    .trimmingCharacters(in: .whitespaces)
                return bareValue(after)
            }
            parentIndent = indent
            pathIndex += 1
        }
        return nil
    }

    /// Finds the line index of the leaf key in path, or nil.
    private static func lineIndex(for path: [String], in lines: [String]) -> Int? {
        var pathIndex = 0
        var parentIndent = -2

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let indent = line.prefix(while: { $0 == " " }).count

            if pathIndex > 0, indent <= parentIndent { return nil }

            let expectedKey = path[pathIndex]
            guard trimmed.hasPrefix(expectedKey + ":") else { continue }

            let expectedIndent = pathIndex * 2
            guard indent == expectedIndent else { continue }

            if pathIndex == path.count - 1 { return i }
            parentIndent = indent
            pathIndex += 1
        }
        return nil
    }

    /// Patches the leaf of a YAML path in-place, preserving indentation and trailing comments.
    private static func patchPath(_ path: [String], value: String, in text: String) -> String {
        var lines = text.components(separatedBy: .newlines)
        guard let idx = lineIndex(for: path, in: lines) else { return text }
        let line = lines[idx]
        let indent = String(line.prefix(while: { $0 == " " }))
        let key = path.last!
        let trailingComment: String
        if let commentRange = line.range(of: " #") {
            trailingComment = " " + String(line[commentRange.lowerBound...]).trimmingCharacters(in: .init(charactersIn: " "))
        } else {
            trailingComment = ""
        }
        lines[idx] = "\(indent)\(key): \(value)\(trailingComment.isEmpty ? "" : "  \(trailingComment)")"
        return lines.joined(separator: "\n")
    }

    private static func bareValue(_ raw: String) -> String {
        let noComment = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? raw
        return noComment
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }
}

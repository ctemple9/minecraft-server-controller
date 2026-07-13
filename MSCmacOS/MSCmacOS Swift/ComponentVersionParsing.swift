//  ComponentVersionParsing.swift
//  MinecraftServerController
//
//  Small helpers for extracting human-friendly version strings from filenames.

import Foundation

struct PaperJarVersion: Equatable {
    let mcVersion: String
    let build: Int

    var displayString: String {
        "\(mcVersion) (build \(build))"
    }

    /// Convenience string for compact comparisons/display.
    var compactString: String {
        "\(mcVersion)-\(build)"
    }
}

enum ComponentVersionParsing {

    /// Parses common Paper template patterns:
    /// - paper-<mc>-build<build>.jar
    /// - paper-<mc>-<build>.jar
    static func parsePaperJarFilename(_ filename: String) -> PaperJarVersion? {
        let base = (filename as NSString).deletingPathExtension
        guard base.lowercased().hasPrefix("paper-") else { return nil }

        let rest = String(base.dropFirst("paper-".count))
        let parts = rest.split(separator: "-")
        guard parts.count >= 2 else { return nil }

        let mcVersion = String(parts[0])
        let buildPart = String(parts[1])

        if buildPart.lowercased().hasPrefix("build") {
            let b = buildPart.dropFirst("build".count)
            if let build = Int(b) {
                return PaperJarVersion(mcVersion: mcVersion, build: build)
            }
        }

        if let build = Int(buildPart) {
            return PaperJarVersion(mcVersion: mcVersion, build: build)
        }

        return nil
    }

    /// Extracts a trailing integer from names like:
    /// - Geyser-spigot-1004.jar
    /// - floodgate-spigot-121.jar
    static func parseTrailingBuildNumber(fromJarFilename filename: String) -> Int? {
        let base = (filename as NSString).deletingPathExtension
        let parts = base.split(separator: "-")
        guard let last = parts.last else { return nil }
        return Int(last)
    }

    /// A very small helper for comparing optional build numbers.
    static func buildDisplayString(_ build: Int?) -> String? {
        guard let build else { return nil }
        return "build \(build)"
    }
}

// MARK: - MC version comparison (U4b)

/// Pure semantic-version comparator for Minecraft version strings.
/// Handles dotted-integer forms used by both Java (e.g. "1.21.4") and
/// Bedrock (e.g. "1.21.30.03"). Non-numeric or "LATEST" strings are
/// treated as unresolvable, meaning no backup is forced.
struct MCVersionComparator {

    /// Returns `true` if `target` is a strict version downgrade from `current`.
    /// Returns `false` whenever comparison is impossible (blank, "LATEST", or any
    /// non-integer dot-separated segment such as a snapshot like "24w14a").
    static func isDowngrade(from current: String?, to target: String) -> Bool {
        guard let current, !current.isEmpty else { return false }
        let c = current.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let t = target.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard c != "latest", !t.isEmpty, t != "latest" else { return false }
        guard let cv = parseComponents(c), let tv = parseComponents(t) else { return false }
        return compareComponents(tv, cv) == .orderedAscending
    }

    private static func parseComponents(_ s: String) -> [Int]? {
        let parts = s.split(separator: ".")
        guard !parts.isEmpty else { return nil }
        var result: [Int] = []
        for part in parts {
            guard let n = Int(part) else { return nil }
            result.append(n)
        }
        return result
    }

    private static func compareComponents(_ a: [Int], _ b: [Int]) -> ComparisonResult {
        let count = max(a.count, b.count)
        for i in 0..<count {
            let av = i < a.count ? a[i] : 0
            let bv = i < b.count ? b[i] : 0
            if av < bv { return .orderedAscending }
            if av > bv { return .orderedDescending }
        }
        return .orderedSame
    }
}

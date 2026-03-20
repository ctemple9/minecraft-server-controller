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

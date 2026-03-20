//  TemplateItemDisplay.swift
//  MinecraftServerController
//
//  Helpers for showing human-friendly names + versions for template JARs.
//

import Foundation

extension PluginTemplateItem {
    /// Human-friendly display title for plugin templates.
    ///
    /// Examples:
    /// - "Geyser-Spigot-2.4.2.jar" -> "Geyser-Spigot (2.4.2)"
    /// - "floodgate-2.2.0.jar"     -> "floodgate (2.2.0)"
    /// - "Geyser.jar"              -> "Geyser"
    var displayTitle: String {
        let rawBase = url.deletingPathExtension().lastPathComponent
        // Hide noisy "-latest" suffixes like "Geyser-latest-spigot"
        let base = rawBase.replacingOccurrences(of: "-latest",
                                                with: "",
                                                options: [.caseInsensitive])

        // Split on "-" and try to treat the last part as a version if it has digits.
        let parts = base.split(separator: "-")
        guard parts.count >= 2 else {
            return base
        }

        let last = parts.last!
        let hasDigits = last.rangeOfCharacter(from: .decimalDigits) != nil

        if hasDigits {
            let name = parts.dropLast().joined(separator: "-")
            return "\(name) (\(last))"
        } else {
            // e.g. "Geyser-Spigot" – no obvious version at the end
            return base
        }
    }
}

extension PaperTemplateItem {
    /// Human-friendly display title for Paper templates.
    ///
    /// Handles common patterns:
    /// - "paper-1.21.1-120.jar"        -> "Paper 1.21.1 (build 120)"
    /// - "paper-1.20.4-build120.jar"   -> "Paper 1.20.4 (build 120)"
    /// Falls back to the base name if pattern is unknown.
    var displayTitle: String {
        let base = url.deletingPathExtension().lastPathComponent

        guard base.hasPrefix("paper-") else {
            // Some manually-added JAR with a custom name – just show the base.
            return base
        }

        let rest = base.dropFirst("paper-".count)
        let components = rest.split(separator: "-")

        // Pattern 1: paper-<version>-<build>
        //   e.g. "paper-1.21.1-120"
        if components.count == 2 {
            let version = components[0]
            let second = components[1]

            // Pattern 1a: paper-<version>-build<build>
            //   e.g. "paper-1.20.4-build120"
            let secondLower = second.lowercased()
            if secondLower.hasPrefix("build") {
                let buildStr = second.dropFirst("build".count)
                if !buildStr.isEmpty {
                    return "Paper \(version) (build \(buildStr))"
                }
            }

            // Pattern 1b: paper-<version>-<build>
            return "Paper \(version) (build \(second))"
        }

        // Fallback for unusual names, but still nicer than raw filename.
        return "Paper \(rest)"
    }
}


//
//  StartupCrashAnalyzer.swift
//  MinecraftServerController
//
//  Turns a failed modded-server start into structured, mod-attributed problems the UI
//  can act on (delete / disable / view on Modrinth). Pure service — no AppViewModel
//  dependency. This slice handles Fabric/Quilt, whose loader prints a clean, parseable
//  dependency-resolution block; other loaders return [] and fall back to the generic
//  "stopped unexpectedly" alert. Defensive by design: when nothing parses confidently,
//  it returns nothing rather than guessing.
//

import Foundation

// MARK: - Model

enum StartupProblemKind: String, Codable, Equatable {
    case missingDependency   // offender needs something that isn't installed
    case incompatibleVersion // offender is built for a different MC/loader/mod version
    case duplicate           // same mod present twice
    case loadError           // threw while loading
    case unknown

    var title: String {
        switch self {
        case .missingDependency:   return "Missing dependency"
        case .incompatibleVersion: return "Incompatible version"
        case .duplicate:           return "Duplicate mod"
        case .loadError:           return "Failed to load"
        case .unknown:             return "Problem"
        }
    }
    var symbol: String {
        switch self {
        case .missingDependency:   return "puzzlepiece.extension"
        case .incompatibleVersion: return "exclamationmark.triangle.fill"
        case .duplicate:           return "doc.on.doc"
        case .loadError:           return "xmark.octagon.fill"
        case .unknown:             return "questionmark.circle"
        }
    }
}

/// One parsed startup problem, attributed to an installed add-on when we can map it.
struct StartupProblem: Codable, Identifiable, Equatable {
    var id: String { "\(kind.rawValue)|\(offenderId ?? offenderName)|\(requirement ?? "")" }

    var kind: StartupProblemKind
    /// Display name of the mod that has the problem (the one we can delete/disable).
    var offenderName: String
    /// The loader mod-id, when known (used to map back to a file on disk).
    var offenderId: String?
    /// The offender's jar filename on disk, when matched to an installed mod.
    var installedFile: String?
    var installedJarStem: String?
    /// Plain-English requirement, e.g. "requires version 1.21 of minecraft".
    var requirement: String?
    /// For `.missingDependency`: the name of the absent dependency to install
    /// (e.g. "fabric-api"). Nil for non-installable targets (minecraft/java/loader).
    var missingDependency: String?
    /// The raw log line(s), shown in the row's details disclosure.
    var rawExcerpt: String
}

// MARK: - Analyzer

enum StartupCrashAnalyzer {

    /// Parses a failed start into structured problems. `consoleExcerpt` is recent console
    /// output captured this run (a fallback when the log file isn't readable).
    static func analyze(
        serverDir: String,
        flavor: JavaServerFlavor,
        consoleExcerpt: [String],
        installedMods: [ModEntry]
    ) -> [StartupProblem] {
        let text = combinedLog(serverDir: serverDir, consoleExcerpt: consoleExcerpt)
        guard !text.isEmpty else { return [] }
        switch flavor {
        case .fabric, .quilt:   return parseFabric(text, installedMods: installedMods)
        case .neoforge, .forge: return parseForge(text, installedMods: installedMods)
        default:                return []
        }
    }

    /// Prefers the authoritative logs/latest.log, also folds in the newest crash report
    /// (Forge/NeoForge write dependency errors there) and the console excerpt as backup.
    private static func combinedLog(serverDir: String, consoleExcerpt: [String]) -> String {
        var parts: [String] = []
        let base = URL(fileURLWithPath: serverDir)
        if let log = try? String(contentsOf: base.appendingPathComponent("logs/latest.log"), encoding: .utf8) {
            parts.append(log)
        }
        if let crash = newestCrashReport(in: base) { parts.append(crash) }
        if !consoleExcerpt.isEmpty { parts.append(consoleExcerpt.joined(separator: "\n")) }
        return parts.joined(separator: "\n")
    }

    /// Contents of the most-recently-modified crash-reports/*.txt, if any.
    private static func newestCrashReport(in serverDir: URL) -> String? {
        let dir = serverDir.appendingPathComponent("crash-reports", isDirectory: true)
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
        else { return nil }
        let txts = files.filter { $0.pathExtension.lowercased() == "txt" }
        let newest = txts.max { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return da < db
        }
        guard let newest else { return nil }
        return try? String(contentsOf: newest, encoding: .utf8)
    }

    // MARK: Fabric / Quilt

    /// Fabric Loader prints canonical lines like:
    ///   - Mod 'Sodium' (sodium) 0.4.0 requires version 1.21 of minecraft, but only … is present!
    ///   - Mod 'X' (x) 1.0 requires any version of fabric api, which is missing!
    /// We parse those (ignoring the "potential solution" lines, which restate the same facts).
    private static func parseFabric(_ text: String, installedMods: [ModEntry]) -> [StartupProblem] {
        var problems: [StartupProblem] = []
        var seen = Set<String>()
        let trimSet = CharacterSet(charactersIn: " \t-–•\u{00A0}")

        for raw in text.components(separatedBy: .newlines) {
            let bullet = raw.trimmingCharacters(in: trimSet)
            // 1. Dependency-resolver failures: "Mod 'Name' (id) ver requires …".
            if bullet.hasPrefix("Mod '"), bullet.contains("requires"), !bullet.contains("recommends") {
                if let problem = parseRequiresLine(bullet, installedMods: installedMods),
                   seen.insert(problem.id).inserted {
                    problems.append(problem)
                }
                continue
            }
            // 2. Runtime/launch failures that name a mod (it loaded, then exploded —
            //    usually built for a different Minecraft version). Stack-trace format.
            let plain = raw.trimmingCharacters(in: .whitespaces)
            if let problem = parseRuntimeFailure(plain, installedMods: installedMods),
               seen.insert(problem.id).inserted {
                problems.append(problem)
            }
        }
        return problems
    }

    /// Catches Fabric runtime/launch crashes that name an offending mod, e.g.
    ///   "Failed to read classTweaker file from mod cloth-config"  (mappings mismatch)
    ///   "Mixin apply for mod X failed"                            (load error)
    /// Classifies mapping/namespace mismatches as incompatibleVersion so "Update" is offered.
    private static func parseRuntimeFailure(_ line: String, installedMods: [ModEntry]) -> StartupProblem? {
        guard line.contains("from mod ") || line.contains("for mod ") else { return nil }
        let isFailure = line.contains("Failed to") || line.contains("Mixin")
            || line.contains("classTweaker") || line.contains("Exception")
        guard isFailure else { return nil }

        guard let modId = tokenAfter("from mod ", in: line) ?? tokenAfter("for mod ", in: line) else { return nil }
        if ["minecraft", "java", "fabricloader", "quilt_loader"].contains(modId.lowercased()) { return nil }

        let isMappingMismatch = line.contains("classTweaker") || line.contains("Namespace")
        let kind: StartupProblemKind = isMappingMismatch ? .incompatibleVersion : .loadError
        let requirement = isMappingMismatch
            ? "Built for a different Minecraft version (mappings mismatch)."
            : "Failed to load at startup — it may be built for a different version."

        let match = installedMods.first { $0.modId == modId }
            ?? installedMods.first { $0.jarStem.lowercased().contains(modId.lowercased()) }

        return StartupProblem(
            kind: kind,
            offenderName: match?.displayName ?? modId,
            offenderId: modId,
            installedFile: match?.filename,
            installedJarStem: match?.jarStem,
            requirement: requirement,
            missingDependency: nil,
            rawExcerpt: line
        )
    }

    /// First identifier-like token following `marker` (letters/digits/-/_), trimmed of
    /// surrounding quotes/punctuation. e.g. tokenAfter("from mod ", "… from mod cloth-config") → "cloth-config".
    private static func tokenAfter(_ marker: String, in line: String) -> String? {
        guard let r = line.range(of: marker) else { return nil }
        let rest = line[r.upperBound...].drop { $0 == " " || $0 == "'" || $0 == "\"" }
        let token = rest.prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        let value = String(token)
        return value.isEmpty ? nil : value
    }

    private static func parseRequiresLine(_ line: String, installedMods: [ModEntry]) -> StartupProblem? {
        // Name between the first pair of single quotes.
        guard let openQuote = line.range(of: "Mod '") else { return nil }
        let afterOpen = line[openQuote.upperBound...]
        guard let closeQuote = afterOpen.range(of: "'") else { return nil }
        let name = String(afterOpen[..<closeQuote.lowerBound])
        guard !name.isEmpty else { return nil }

        // mod-id inside the first parentheses after the name.
        let afterName = afterOpen[closeQuote.upperBound...]
        var modId: String?
        if let pOpen = afterName.range(of: "("), let pClose = afterName.range(of: ")"),
           pOpen.upperBound <= pClose.lowerBound {
            let candidate = String(afterName[pOpen.upperBound..<pClose.lowerBound]).trimmingCharacters(in: .whitespaces)
            if !candidate.isEmpty { modId = candidate }
        }

        guard let reqRange = line.range(of: "requires") else { return nil }
        let isMissing = line.localizedCaseInsensitiveContains("which is missing")
        let kind: StartupProblemKind = isMissing ? .missingDependency : .incompatibleVersion

        // Short requirement clause: from "requires" up to the first comma.
        var clause = String(line[reqRange.lowerBound...])
        if let comma = clause.firstIndex(of: ",") { clause = String(clause[..<comma]) }
        clause = clause.trimmingCharacters(in: CharacterSet(charactersIn: " \t!."))

        // Map offender back to an installed mod (by id, then by display name).
        let match = installedMods.first { m in modId != nil && m.modId == modId }
            ?? installedMods.first { $0.displayName.caseInsensitiveCompare(name) == .orderedSame }

        var requirementText: String? = nil
        if !clause.isEmpty {
            requirementText = clause.prefix(1).uppercased() + String(clause.dropFirst())
        }

        // For a missing dependency, capture the target's name so we can offer to install
        // it. It sits between the last " of " and the comma, e.g.
        // "requires any version of fabric api, which is missing!" → "fabric api".
        var missingDep: String? = nil
        if isMissing, let ofRange = line.range(of: " of ", options: .backwards) {
            var target = String(line[ofRange.upperBound...])
            if let comma = target.firstIndex(of: ",") { target = String(target[..<comma]) }
            target = target.trimmingCharacters(in: .whitespaces)
            let nonInstallable: Set<String> = ["minecraft", "java", "fabricloader",
                                               "fabric loader", "fabric-loader", "quilt_loader"]
            if !target.isEmpty, !nonInstallable.contains(target.lowercased()) {
                missingDep = target
            }
        }

        return StartupProblem(
            kind: kind,
            offenderName: name,
            offenderId: modId,
            installedFile: match?.filename,
            installedJarStem: match?.jarStem,
            requirement: requirementText,
            missingDependency: missingDep,
            rawExcerpt: line
        )
    }

    // MARK: NeoForge / Forge

    /// Modern Forge/NeoForge print (in the log and crash report):
    ///   Mod ID: 'jei', Requested by: 'somemod', Expected range: '[15.2,)', Actual version: '[MISSING]'
    ///   Mod ID: 'minecraft', Requested by: 'othermod', Expected range: '[1.21]', Actual version: '1.21.4'
    /// "Requested by" is the installed mod with the unmet requirement; "Mod ID" is the
    /// dependency. We attribute the actionable offender accordingly (see below).
    private static let loaderModIds: Set<String> = [
        "minecraft", "forge", "neoforge", "fml", "javafml", "java", "lowcodefml", "mcp"
    ]

    private static func parseForge(_ text: String, installedMods: [ModEntry]) -> [StartupProblem] {
        var problems: [StartupProblem] = []
        var seen = Set<String>()

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.contains("Mod ID:"), line.contains("Requested by:"),
                  line.contains("Actual version:") else { continue }
            guard let problem = parseForgeDependencyLine(line, installedMods: installedMods) else { continue }
            if seen.insert(problem.id).inserted { problems.append(problem) }
        }
        return problems
    }

    private static func parseForgeDependencyLine(_ line: String, installedMods: [ModEntry]) -> StartupProblem? {
        guard let depId = quotedValue(after: "Mod ID:", in: line),
              let requestedBy = quotedValue(after: "Requested by:", in: line) else { return nil }
        let expected = quotedValue(after: "Expected range:", in: line)
        let actual = quotedValue(after: "Actual version:", in: line)
        let isMissing = (actual ?? "").uppercased().contains("MISSING")
        let depIsLoader = loaderModIds.contains(depId.lowercased())

        // Offender = the mod we can act on (delete/disable/update).
        //  • missing dep, or the requester needs a different MC/loader version → requester
        //  • a real dependency is the wrong version → that dependency (so "Update" fixes it)
        let offenderId: String
        let kind: StartupProblemKind
        var missingDep: String? = nil
        var requirement: String

        if isMissing {
            kind = .missingDependency
            offenderId = requestedBy
            missingDep = depIsLoader ? nil : depId
            requirement = "Requires \(depId) \(expected ?? "")".trimmingCharacters(in: .whitespaces)
        } else if depIsLoader {
            kind = .incompatibleVersion
            offenderId = requestedBy
            requirement = "Needs \(depId) \(expected ?? "") (have \(actual ?? "?"))"
        } else {
            kind = .incompatibleVersion
            offenderId = depId
            requirement = "Needs version \(expected ?? "?") (have \(actual ?? "?")); required by \(requestedBy)"
        }

        let match = installedMods.first { $0.modId == offenderId }
            ?? installedMods.first { $0.displayName.caseInsensitiveCompare(offenderId) == .orderedSame }

        return StartupProblem(
            kind: kind,
            offenderName: match?.displayName ?? offenderId,
            offenderId: offenderId,
            installedFile: match?.filename,
            installedJarStem: match?.jarStem,
            requirement: requirement,
            missingDependency: missingDep,
            rawExcerpt: line
        )
    }

    /// Extracts the first `'…'`-quoted value following `label` in `line`.
    private static func quotedValue(after label: String, in line: String) -> String? {
        guard let lr = line.range(of: label) else { return nil }
        let after = line[lr.upperBound...]
        guard let q1 = after.range(of: "'") else { return nil }
        let rest = after[q1.upperBound...]
        guard let q2 = rest.range(of: "'") else { return nil }
        let value = String(rest[..<q2.lowerBound]).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    // MARK: - Paper / Spigot plugins (soft fail)

    /// Scans a *running* Paper-family server's output for plugins that failed to load —
    /// these don't stop the server, so they surface as a non-blocking signal rather than
    /// the crash sheet's hard-fail flow. Recognizes missing-dependency and enable-error
    /// messages. Returns problems attributed to installed plugins.
    static func analyzePaperPlugins(
        serverDir: String,
        consoleExcerpt: [String],
        installedPlugins: [PluginEntry]
    ) -> [StartupProblem] {
        let text = combinedLog(serverDir: serverDir, consoleExcerpt: consoleExcerpt)
        guard !text.isEmpty else { return [] }

        var problems: [StartupProblem] = []
        var seen = Set<String>()

        func matchPlugin(_ name: String) -> PluginEntry? {
            installedPlugins.first { $0.displayName.caseInsensitiveCompare(name) == .orderedSame }
                ?? installedPlugins.first { $0.jarStem.lowercased().contains(name.lowercased()) }
        }

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)

            // Missing dependency: "Unknown/missing dependency plugins: [Vault, X]. … to run 'Foo'."
            if line.contains("Unknown/missing dependency plugins:") {
                let plugin = quotedValue(after: "to run", in: line) ?? "A plugin"
                let deps = bracketedList(in: line)
                for dep in deps {
                    let match = matchPlugin(plugin)
                    let p = StartupProblem(
                        kind: .missingDependency,
                        offenderName: match?.displayName ?? plugin,
                        offenderId: nil,
                        installedFile: match?.filename,
                        installedJarStem: match?.jarStem,
                        requirement: "Requires \(dep)",
                        missingDependency: dep,
                        rawExcerpt: line)
                    if seen.insert(p.id).inserted { problems.append(p) }
                }
                continue
            }

            // Enable error: "Error occurred while enabling Foo v1.2 (Is it up to date?)"
            if let r = line.range(of: "Error occurred while enabling ") {
                var rest = String(line[r.upperBound...])
                // Trim at " v<version>" or " (" — whichever comes first.
                if let vr = rest.range(of: " v") { rest = String(rest[..<vr.lowerBound]) }
                else if let pr = rest.range(of: " (") { rest = String(rest[..<pr.lowerBound]) }
                let pluginName = rest.trimmingCharacters(in: .whitespaces)
                guard !pluginName.isEmpty else { continue }
                let match = matchPlugin(pluginName)
                let p = StartupProblem(
                    kind: .loadError,
                    offenderName: match?.displayName ?? pluginName,
                    offenderId: nil,
                    installedFile: match?.filename,
                    installedJarStem: match?.jarStem,
                    requirement: "Failed to enable — the plugin errored on startup (it may be outdated).",
                    missingDependency: nil,
                    rawExcerpt: line)
                if seen.insert(p.id).inserted { problems.append(p) }
            }
        }
        return problems
    }

    /// Returns the comma-separated entries inside the first `[ … ]` in a line.
    private static func bracketedList(in line: String) -> [String] {
        guard let open = line.range(of: "["), let close = line.range(of: "]"),
              open.upperBound <= close.lowerBound else { return [] }
        return line[open.upperBound..<close.lowerBound]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

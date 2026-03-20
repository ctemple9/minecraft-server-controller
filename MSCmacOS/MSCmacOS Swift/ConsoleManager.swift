//
//  ConsoleManager.swift
//  MinecraftServerController
//

import Foundation
import Combine

@MainActor
/// Owns console state, filtering, and structured line parsing for the UI.
final class ConsoleManager: ObservableObject {

    // MARK: - Published state (mirrors the original @Published vars on AppViewModel)

    @Published var entries: [ConsoleEntry] = []
    @Published var tab: ConsoleTab = .all
    @Published var searchText: String = ""
    @Published var selectedSources: Set<ConsoleSource> = []
    @Published var selectedLevels: Set<ConsoleLevel> = []
    @Published var selectedTags: Set<String> = []
    @Published var hideAuto: Bool = false

    // MARK: - Auto-attribution window (used during line parsing)

    /// Timestamp of the most recent auto command. Responses arriving within
    /// `autoAttributionWindowSeconds` of this timestamp are also marked auto.
    private(set) var lastAutoCommandAt: Date? = nil
    private let autoAttributionWindowSeconds: TimeInterval = 2.0

    // MARK: - Derived / computed

    /// All distinct tags observed so far, sorted case-insensitively.
    var knownTags: [String] {
        let tags = entries
            .compactMap { $0.tag?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { isDisplayableTag($0) }
        return Array(Set(tags)).sorted { $0.lowercased() < $1.lowercased() }
    }

    /// True when any advanced filter is active (used to decide tab auto-selection).
    private var isAnyAdvancedFilterActive: Bool {
        if !selectedSources.isEmpty { return true }
        if !selectedLevels.isEmpty { return true }
        if !selectedTags.isEmpty { return true }
        if hideAuto { return true }
        return !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Entries after applying the active tab preset + advanced filters + search text.
    var filteredEntries: [ConsoleEntry] {
        var items = entries

        // 1) Tab preset
        items = items.filter { matchesTabPreset($0, tab: tab) }

        // 2) Advanced filters (AND logic)
        if !selectedSources.isEmpty {
            items = items.filter { selectedSources.contains($0.source) }
        }
        if !selectedLevels.isEmpty {
            items = items.filter { selectedLevels.contains($0.level) }
        }
        if !selectedTags.isEmpty {
            items = items.filter { entry in
                guard let tag = entry.tag else { return false }
                return selectedTags.contains(tag)
            }
        }
        if hideAuto {
            items = items.filter { !$0.isAuto }
        }

        // 3) Search
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !term.isEmpty {
            items = items.filter { $0.raw.lowercased().contains(term) }
        }

        return items
    }

    // MARK: - Filter controls

    /// Clear all advanced filters and return to the closest matching preset tab.
    func resetFilters() {
        selectedSources = []
        selectedLevels = []
        selectedTags = []
        hideAuto = false
        autoSelectTab()
    }

    func setSource(_ source: ConsoleSource, enabled: Bool) {
        if enabled { selectedSources.insert(source) } else { selectedSources.remove(source) }
        autoSelectTab()
    }

    func setLevel(_ level: ConsoleLevel, enabled: Bool) {
        if enabled { selectedLevels.insert(level) } else { selectedLevels.remove(level) }
        autoSelectTab()
    }

    func setTag(_ tag: String, enabled: Bool) {
        if enabled { selectedTags.insert(tag) } else { selectedTags.remove(tag) }
        autoSelectTab()
    }

    /// Switches to a preset tab when the current advanced filter set exactly matches one;
    /// otherwise switches to `.custom` to indicate a non-standard view is active.
    func autoSelectTab() {
        guard isAnyAdvancedFilterActive else { return }

        if selectedSources == [.controller],
           selectedLevels.isEmpty,
           selectedTags.isEmpty,
           hideAuto == false,
           searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            tab = .controller
            return
        }

        tab = .custom
    }

    // MARK: - Entry appending

    /// Parse a raw output line and append it as a structured ConsoleEntry.
    /// Parse a raw output line and append it as a structured entry.
    func appendRaw(_ raw: String, source: ConsoleSource) {
        let parsed = parseLine(raw, source: source)
        entries.append(parsed)
    }

    /// Remove all entries (does not touch the remote API buffer; AppViewModel handles that).
    /// Remove all console entries.
    func clearEntries() {
        entries.removeAll()
    }

    /// Record that an auto command was just sent, so the attribution window starts now.
    func markAutoCommand() {
        lastAutoCommandAt = Date()
    }

    // MARK: - Line parsing (private)

    private func parseLine(_ raw: String, source: ConsoleSource) -> ConsoleEntry {
        let level = inferLevel(from: raw)
        let tag   = inferTag(from: raw, source: source)

        var isAuto = false

        if raw.contains("[Auto →") || raw.contains("[Auto ->") {
            isAuto = true
        } else if isLikelyAutoResponseLine(raw), let t = lastAutoCommandAt {
            if Date().timeIntervalSince(t) <= autoAttributionWindowSeconds {
                isAuto = true
            }
        }

        return ConsoleEntry(raw: raw, source: source, level: level, tag: tag, isAuto: isAuto)
    }

    private func inferLevel(from raw: String) -> ConsoleLevel {
        let upper = raw.uppercased()
        if upper.contains(" ERROR") || upper.contains(" SEVERE") { return .error }
        if upper.contains(" WARN")                               { return .warn  }
        if upper.contains(" INFO")                               { return .info  }
        if upper.contains("EXCEPTION") || upper.contains("JAVA.LANG.") { return .error }
        return .other
    }

    private func inferTag(from raw: String, source: ConsoleSource) -> String? {
        let tokens = extractBracketTokens(raw)

        if source == .controller {
            let candidate = tokens.first(where: { !looksLikeTimestampToken($0) })
            if let c = candidate,
               c.lowercased().hasPrefix("you →")  || c.lowercased().hasPrefix("auto →") ||
               c.lowercased().hasPrefix("you ->") || c.lowercased().hasPrefix("auto ->") {
                return "Command"
            }
            return sanitizeTag(candidate, source: source)
        }

        let filtered = tokens.filter { tok in
            if looksLikeTimestampToken(tok) { return false }
            let lower = tok.lowercased()
            return lower != "info" && lower != "warn" && lower != "error"
        }

        for token in filtered {
            if let sanitized = sanitizeTag(token, source: source) {
                return sanitized
            }
        }

        return nil
    }

    private func sanitizeTag(_ rawTag: String?, source: ConsoleSource) -> String? {
        guard var tag = rawTag?.trimmingCharacters(in: .whitespacesAndNewlines), !tag.isEmpty else {
            return nil
        }

        if source == .controller {
            let lower = tag.lowercased()
            if lower.hasPrefix("you →") || lower.hasPrefix("auto →") ||
               lower.hasPrefix("you ->") || lower.hasPrefix("auto ->") {
                return "Command"
            }
        }

        if !isDisplayableTag(tag) {
            return nil
        }

        if looksLikePackageIdentifier(tag) {
            let components = tag.split(separator: ".").map(String.init)
            let domainLikePrefixes: Set<String> = ["com", "org", "net", "io", "gg", "dev", "app", "co", "ca", "me"]
            let genericComponents: Set<String> = [
                "github", "papermc", "papermc", "minecraft", "mojang", "java", "javax", "server"
            ]

            if let chosen = components.first(where: { part in
                let lower = part.lowercased()
                return !domainLikePrefixes.contains(lower) && !genericComponents.contains(lower)
            }) {
                tag = humanizeTagComponent(chosen)
            }
        }

        if tag.count > 28 {
            tag = String(tag.prefix(28))
        }

        guard isDisplayableTag(tag) else { return nil }
        return tag
    }

    private func isDisplayableTag(_ tag: String) -> Bool {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let lower = trimmed.lowercased()
        if ["info", "warn", "error", "debug", "trace", "??", "?", "unknown", "null", "nil"].contains(lower) {
            return false
        }

        let punctuationOnly = trimmed.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.inverted.contains($0) }
        if punctuationOnly { return false }

        return true
    }

    private func looksLikePackageIdentifier(_ tag: String) -> Bool {
        tag.contains(".") && !tag.contains(" ")
    }

    private func humanizeTagComponent(_ component: String) -> String {
        let cleaned = component
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        if cleaned.uppercased() == cleaned {
            return cleaned
        }

        let separated = cleaned.replacingOccurrences(
            of: "([a-z0-9])([A-Z])",
            with: "$1 $2",
            options: .regularExpression
        )

        return separated
            .split(separator: " ")
            .map { word in
                let lower = word.lowercased()
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }
            .joined(separator: " ")
    }

    private func extractBracketTokens(_ raw: String) -> [String] {
        var out: [String] = []
        var current = ""
        var inBracket = false

        for ch in raw {
            if ch == "[" {
                inBracket = true
                current = ""
                continue
            }
            if ch == "]" {
                if inBracket { out.append(current) }
                inBracket = false
                current = ""
                continue
            }
            if inBracket { current.append(ch) }
        }

        return out.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private func looksLikeTimestampToken(_ tok: String) -> Bool {
        tok.contains(":") && tok.rangeOfCharacter(from: .decimalDigits) != nil
    }

    private func isLikelyAutoResponseLine(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        if lower.contains("tps from last 1m, 5m, 15m") { return true }
        if lower.contains("there are") && lower.contains("players online") { return true }
        return false
    }

    // MARK: - Tab preset matching

    private func matchesTabPreset(_ entry: ConsoleEntry, tab: ConsoleTab) -> Bool {
        switch tab {
        case .all, .custom:
            return true

        case .controller:
            return entry.source == .controller

        case .commands:
            return entry.tag?.lowercased() == "command"

        case .warnings:
            if entry.level == .warn || entry.level == .error { return true }
            let lower = entry.raw.lowercased()
            return lower.contains(" exception") || lower.contains("java.lang.") || lower.contains("at ")

        case .server:
            guard entry.source == .server else { return false }
            if let tag = entry.tag?.lowercased() { return isCoreServerTag(tag) }
            return true

        case .plugins:
            guard entry.source == .server else { return false }
            guard let tag = entry.tag?.lowercased() else { return false }
            return !isCoreServerTag(tag)
        }
    }

    private func isCoreServerTag(_ lowerTag: String) -> Bool {
        let core = ["bootstrap", "minecraftserver", "paper", "server", "main"]
        return core.contains(lowerTag)
    }
}


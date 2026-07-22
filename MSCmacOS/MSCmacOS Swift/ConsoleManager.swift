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

    // Raw log store — not @Published. filteredEntries is the single SwiftUI trigger.
    var entries: [ConsoleEntry] = []
    // Cached filtered view of entries. Updated in one shot after each batch or filter
    // change so SwiftUI re-renders at most once per batch (~10×/s) instead of once
    // per incoming line (potentially 1 000+/s during mod-loading bursts).
    @Published private(set) var filteredEntries: [ConsoleEntry] = []

    private let maxEntries = 8_000
    private var isBatching = false

    @Published var tab: ConsoleTab = .all {
        didSet { recomputeFilteredEntries() }
    }
    @Published var searchText: String = "" {
        didSet { recomputeFilteredEntries() }
    }
    @Published var selectedSources: Set<ConsoleSource> = [] {
        didSet { recomputeFilteredEntries() }
    }
    @Published var selectedLevels: Set<ConsoleLevel> = [] {
        didSet { recomputeFilteredEntries() }
    }
    @Published var selectedTags: Set<String> = [] {
        didSet { recomputeFilteredEntries() }
    }
    @Published var hideAuto: Bool = false {
        didSet { recomputeFilteredEntries() }
    }

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

    /// Append a single line. Safe to call at any time; respects batch mode.
    func appendRaw(_ raw: String, source: ConsoleSource) {
        entries.append(parseLine(raw, source: source))
        if !isBatching {
            capIfNeeded()
            recomputeFilteredEntries()
        }
    }

    /// Begin a batch: subsequent `appendRaw` calls accumulate without triggering
    /// a filter recompute or SwiftUI update. Call `endBatch()` to commit.
    func beginBatch() {
        isBatching = true
    }

    /// End the batch: cap the buffer, recompute the filter once, and publish.
    func endBatch() {
        isBatching = false
        capIfNeeded()
        recomputeFilteredEntries()
    }

    /// Remove all entries (does not touch the remote API buffer; AppViewModel handles that).
    func clearEntries() {
        entries.removeAll()
        recomputeFilteredEntries()
    }

    /// Record that an auto command was just sent, so the attribution window starts now.
    func markAutoCommand() {
        lastAutoCommandAt = Date()
    }

    // MARK: - Buffer management

    private func capIfNeeded() {
        let overflow = entries.count - maxEntries
        if overflow > 0 { entries.removeFirst(overflow) }
    }

    private func recomputeFilteredEntries() {
        var items = entries
        items = items.filter { matchesTabPreset($0, tab: tab) }
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
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !term.isEmpty {
            items = items.filter { $0.raw.lowercased().contains(term) }
        }
        filteredEntries = items
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
        // Legacy Forge/NeoForge `forge tps` reply: "Overall: … Mean tick time: X ms. Mean TPS: Y"
        if lower.contains("mean tick time") && lower.contains("mean tps") { return true }
        // Modern NeoForge (MC 1.21+) reply: "Overall: 20.000 TPS (0.354 ms/tick)"
        if lower.contains("tps (") && lower.contains("ms/tick") { return true }
        // Vanilla `tick query` reply (Fabric/Quilt/Vanilla 1.20.3+), sent as three
        // lines: "Target tick rate: …", "Average time per tick: …", "Percentiles: …"
        if lower.contains("average time per tick") { return true }
        if lower.contains("target tick rate") { return true }
        if lower.contains("percentiles: p50") { return true }
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


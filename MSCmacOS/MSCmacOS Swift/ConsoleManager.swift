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
    // Cached filtered view of entries. Extended incrementally (append-only) as batches
    // arrive, and fully recomputed only when a filter/tab/search changes. This is the
    // single SwiftUI trigger, so the console re-renders at most once per batch (~10×/s)
    // instead of once per incoming line (potentially 1 000+/s during mod-loading bursts).
    @Published private(set) var filteredEntries: [ConsoleEntry] = []

    // Parsed in-game chat feed (chat / advancements / join-leave) for the Overview card.
    // Built incrementally as batches arrive — parsed off the main thread and appended here —
    // so the card never re-scans the whole entries buffer on every render.
    @Published private(set) var chatFeed: [ChatFeedMessage] = []
    private let maxChatFeed = 80

    // The buffer is trimmed back to `maxEntries` only once it grows past
    // `maxEntries + trimSlack`, so the O(n) front-shift runs once per `trimSlack` lines
    // instead of on every batch during a burst.
    private let maxEntries = 8_000
    private let trimSlack  = 2_000

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

    /// Sendable snapshot of the state `ConsoleLineParser` needs, captured on the main
    /// actor so a whole batch can be parsed off the main thread. See
    /// `AppViewModel.drainConsoleBatch`.
    var parseContext: ConsoleParseContext {
        ConsoleParseContext(lastAutoCommandAt: lastAutoCommandAt,
                            windowSeconds: autoAttributionWindowSeconds)
    }

    // MARK: - Derived / computed

    /// All distinct tags observed so far, sorted case-insensitively.
    var knownTags: [String] {
        let tags = entries
            .compactMap { $0.tag?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { ConsoleLineParser.isDisplayableTag($0) }
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

    /// Append a single raw line (used for controller/app messages, which arrive one at a
    /// time and are low-frequency). Parses on the calling actor.
    func appendRaw(_ raw: String, source: ConsoleSource) {
        let entry = ConsoleLineParser.parse(raw: raw, source: source,
                                            lastAutoCommandAt: lastAutoCommandAt,
                                            windowSeconds: autoAttributionWindowSeconds)
        entries.append(entry)
        appendMatchingToFiltered([entry])
        trimIfNeeded()
    }

    /// Append a batch of entries that were parsed off the main thread. Appends them to the
    /// store, extends the filtered view with any that pass the active filter, and trims the
    /// buffer if it grew past its slack ceiling — all in one pass, so SwiftUI publishes at
    /// most once for the whole batch.
    func appendParsedBatch(_ parsed: [ConsoleEntry]) {
        guard !parsed.isEmpty else { return }
        entries.append(contentsOf: parsed)
        appendMatchingToFiltered(parsed)
        trimIfNeeded()
    }

    /// Append chat-feed messages parsed off-main for this batch, capped to the most recent
    /// `maxChatFeed`. Publishes once for the batch; no-op (no publish) when empty — so a
    /// burst of non-chat log lines doesn't re-render the Overview chat card.
    func appendChatMessages(_ messages: [ChatFeedMessage]) {
        guard !messages.isEmpty else { return }
        chatFeed.append(contentsOf: messages)
        if chatFeed.count > maxChatFeed {
            chatFeed.removeFirst(chatFeed.count - maxChatFeed)
        }
    }

    /// Remove all entries (does not touch the remote API buffer; AppViewModel handles that).
    func clearEntries() {
        entries.removeAll()
        if !filteredEntries.isEmpty { filteredEntries.removeAll() }
        if !chatFeed.isEmpty { chatFeed.removeAll() }
    }

    /// Record that an auto command was just sent, so the attribution window starts now.
    func markAutoCommand() {
        lastAutoCommandAt = Date()
    }

    // MARK: - Buffer management & filtering

    /// Trim the oldest entries once the buffer exceeds its slack ceiling, keeping the
    /// O(n) front-shift amortized. Also drops the matching leading entries from the
    /// filtered view — which is an in-order subsequence of `entries`, so the trimmed
    /// ones are always a prefix of it.
    private func trimIfNeeded() {
        guard entries.count > maxEntries + trimSlack else { return }
        let removeCount = entries.count - maxEntries
        let trimmedIDs = Set(entries.prefix(removeCount).map(\.id))
        entries.removeFirst(removeCount)

        var filteredRemove = 0
        for entry in filteredEntries {
            if trimmedIDs.contains(entry.id) { filteredRemove += 1 } else { break }
        }
        if filteredRemove > 0 { filteredEntries.removeFirst(filteredRemove) }
    }

    /// Extend `filteredEntries` with the subset of `newEntries` that pass the active
    /// filter. No-op (and no @Published fire) when none match — which is exactly the
    /// hideAuto + live-monitoring case, keeping the list steady while the user reads.
    private func appendMatchingToFiltered(_ newEntries: [ConsoleEntry]) {
        let term = normalizedSearchTerm()
        let matching = newEntries.filter { passesFilter($0, term: term) }
        guard !matching.isEmpty else { return }
        filteredEntries.append(contentsOf: matching)
    }

    /// Full rescan — used only when a filter/tab/search control changes (user-driven and
    /// infrequent), never on the per-batch append path.
    private func recomputeFilteredEntries() {
        let term = normalizedSearchTerm()
        let items = entries.filter { passesFilter($0, term: term) }
        // Only republish when the visible result actually changed, so filter toggles that
        // don't alter the view don't churn the LazyVStack.
        guard items != filteredEntries else { return }
        filteredEntries = items
    }

    private func normalizedSearchTerm() -> String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Single-entry predicate combining the tab preset, advanced filters (AND logic), and
    /// search term. `term` is passed in pre-normalized so a full rescan doesn't re-trim and
    /// re-lowercase it for every entry.
    private func passesFilter(_ entry: ConsoleEntry, term: String) -> Bool {
        if !matchesTabPreset(entry, tab: tab) { return false }
        if !selectedSources.isEmpty, !selectedSources.contains(entry.source) { return false }
        if !selectedLevels.isEmpty, !selectedLevels.contains(entry.level) { return false }
        if !selectedTags.isEmpty {
            guard let tag = entry.tag, selectedTags.contains(tag) else { return false }
        }
        if hideAuto, entry.isAuto { return false }
        if !term.isEmpty, !entry.raw.lowercased().contains(term) { return false }
        return true
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

// MARK: - ConsoleParseContext

/// Immutable, Sendable snapshot of the auto-attribution state a line needs to be parsed.
/// Captured on the main actor, then handed to `ConsoleLineParser` on a background queue.
struct ConsoleParseContext: Sendable {
    let lastAutoCommandAt: Date?
    let windowSeconds: TimeInterval
}

// MARK: - ConsoleLineParser

/// Pure, non-isolated line parser. Holds no state and touches no main-actor data, so it
/// can run on a background queue to keep the heavy regex/tokenizing work off the RunLoop
/// during mod-loading bursts. All inputs and outputs are Sendable value types.
enum ConsoleLineParser {

    static func parse(raw: String,
                      source: ConsoleSource,
                      lastAutoCommandAt: Date?,
                      windowSeconds: TimeInterval) -> ConsoleEntry {
        let level = inferLevel(from: raw)
        let tag   = inferTag(from: raw, source: source)

        var isAuto = false

        if raw.contains("[Auto →") || raw.contains("[Auto ->") {
            isAuto = true
        } else if isLikelyAutoResponseLine(raw), let t = lastAutoCommandAt {
            if Date().timeIntervalSince(t) <= windowSeconds {
                isAuto = true
            }
        }

        return ConsoleEntry(raw: raw, source: source, level: level, tag: tag, isAuto: isAuto)
    }

    static func inferLevel(from raw: String) -> ConsoleLevel {
        let upper = raw.uppercased()
        if upper.contains(" ERROR") || upper.contains(" SEVERE") { return .error }
        if upper.contains(" WARN")                               { return .warn  }
        if upper.contains(" INFO")                               { return .info  }
        if upper.contains("EXCEPTION") || upper.contains("JAVA.LANG.") { return .error }
        return .other
    }

    static func inferTag(from raw: String, source: ConsoleSource) -> String? {
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

    static func sanitizeTag(_ rawTag: String?, source: ConsoleSource) -> String? {
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

    static func isDisplayableTag(_ tag: String) -> Bool {
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

    static func looksLikePackageIdentifier(_ tag: String) -> Bool {
        tag.contains(".") && !tag.contains(" ")
    }

    static func humanizeTagComponent(_ component: String) -> String {
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

    static func extractBracketTokens(_ raw: String) -> [String] {
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

    static func looksLikeTimestampToken(_ tok: String) -> Bool {
        tok.contains(":") && tok.rangeOfCharacter(from: .decimalDigits) != nil
    }

    static func isLikelyAutoResponseLine(_ raw: String) -> Bool {
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
}

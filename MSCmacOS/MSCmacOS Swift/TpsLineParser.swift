//
//  TpsLineParser.swift
//  Minecraft Server Controller
//
//  Pure, side-effect-free parsing of server TPS console lines. Extracted from
//  AppViewModel+OutputHandling so the two console formats (Paper vs Forge/NeoForge)
//  can be unit-tested without an AppViewModel instance or its @Published state.
//
//  Two shapes are recognized:
//    • Paper family: "TPS from last 1m, 5m, 15m: 20.0, 20.0, 20.0" — three rolling
//      averages.
//    • Forge / NeoForge `forge tps` / `neoforge tps`:
//      "Overall: Mean tick time: 3.456 ms. Mean TPS: 20.000" — one overall value,
//      no 1m/5m/15m breakdown, so t5/t15 are nil.
//

import Foundation

enum TpsLineParser {

    /// A parsed TPS sample. `t5`/`t15` are nil for single-value flavors (Forge)
    /// so downstream UI renders one number instead of stale trio values.
    struct Sample: Equatable {
        let t1: Double
        let t5: Double?
        let t15: Double?
    }

    /// Parse an already-sanitized console line. Paper format is tried first, then
    /// Forge; returns nil when the line is neither (the caller records nothing).
    static func parse(_ clean: String) -> Sample? {
        if let paper = parsePaper(clean) { return paper }
        return parseForge(clean)
    }

    static func parsePaper(_ clean: String) -> Sample? {
        guard clean.contains("TPS from last 1m, 5m, 15m:") else { return nil }
        guard let colonIndex = clean.lastIndex(of: ":") else { return nil }
        let numbersPart = clean[clean.index(after: colonIndex)...]
            .trimmingCharacters(in: .whitespaces)
        let parts = numbersPart.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 3 else { return nil }
        guard let t1 = Double(parts[0]),
              let t5 = Double(parts[1]),
              let t15 = Double(parts[2]) else { return nil }
        return Sample(t1: t1, t5: t5, t15: t15)
    }

    static func parseForge(_ clean: String) -> Sample? {
        let pattern = #"Overall:\s*Mean tick time:\s*[0-9.]+\s*ms\.?\s*Mean TPS:\s*([0-9.]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let fullRange = NSRange(clean.startIndex..<clean.endIndex, in: clean)
        guard let match = regex.firstMatch(in: clean, options: [], range: fullRange),
              match.numberOfRanges > 1,
              let tpsRange = Range(match.range(at: 1), in: clean),
              let tps = Double(clean[tpsRange]) else {
            return nil
        }
        // Forge reports one overall rolling mean, not Paper's 1m/5m/15m trio.
        return Sample(t1: tps, t5: nil, t15: nil)
    }
}

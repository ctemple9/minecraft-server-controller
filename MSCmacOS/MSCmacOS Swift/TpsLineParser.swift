//
//  TpsLineParser.swift
//  Minecraft Server Controller
//
//  Pure, side-effect-free parsing of server TPS console lines. Extracted from
//  AppViewModel+OutputHandling so the two console formats (Paper vs Forge/NeoForge)
//  can be unit-tested without an AppViewModel instance or its @Published state.
//
//  Three shapes are recognized:
//    • Paper family: "TPS from last 1m, 5m, 15m: 20.0, 20.0, 20.0" — three rolling
//      averages.
//    • Legacy Forge / NeoForge (MC ≤1.20) `forge tps` / `neoforge tps`:
//      "Overall: Mean tick time: 3.456 ms. Mean TPS: 20.000" — one overall value,
//      no 1m/5m/15m breakdown, so t5/t15 are nil.
//    • Modern NeoForge (MC ≥1.21) `neoforge tps`:
//      "Overall: 20.000 TPS (0.354 ms/tick)" — NeoForge reworded its output at 1.21
//      (Forge/LexForge kept the legacy wording). Same single-value shape as above.
//    • Vanilla `/tick query` (MC ≥1.20.3, used for Vanilla/Fabric/Quilt which have
//      no loader TPS command): "Average time per tick: 0.7ms (Target: 50.0ms)".
//      There is no TPS figure in the output, so it is derived from the mean tick
//      time as min(20, 1000 / mspt). Single value, so t5/t15 are nil.
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
    /// legacy Forge, then modern NeoForge, then the vanilla `/tick query` line;
    /// returns nil when the line is none of them (the caller records nothing).
    static func parse(_ clean: String) -> Sample? {
        if let paper = parsePaper(clean) { return paper }
        if let forge = parseForge(clean) { return forge }
        if let neo = parseNeoForge(clean) { return neo }
        return parseVanillaTick(clean)
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
        // Cheap pre-guard: the regex requires this literal, so skip the compile+match on
        // the overwhelming majority of (non-TPS) lines during a burst.
        guard clean.contains("Mean tick time") else { return nil }
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

    /// Modern NeoForge (MC 1.21+) reworded its `neoforge tps` reply to
    /// "Overall: 20.000 TPS (0.354 ms/tick)" — no "Mean tick time"/"Mean TPS"
    /// text, so `parseForge` can't see it. Anchoring on "Overall:" avoids matching
    /// the per-dimension lines ("minecraft:overworld: 20.000 TPS (…)").
    static func parseNeoForge(_ clean: String) -> Sample? {
        // Cheap pre-guard: the regex anchors on "Overall:" … "TPS", so skip the compile+
        // match on lines that can't match (all non-TPS burst lines, and per-dimension lines).
        guard clean.contains("Overall:"), clean.contains("TPS") else { return nil }
        let pattern = #"Overall:\s*([0-9.]+)\s*TPS\b"#
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
        // Single overall value, same shape as legacy Forge.
        return Sample(t1: tps, t5: nil, t15: nil)
    }

    /// Vanilla `/tick query` (MC 1.20.3+) reports mean tick time, not TPS:
    /// "Average time per tick: 0.7ms (Target: 50.0ms)". We derive TPS as
    /// min(20, 1000 / mspt) — 20 is the vanilla target rate, and a server that
    /// beats the tick budget still caps at 20. Matches the "Average time per
    /// tick:" line specifically so the "Percentiles:" and "Target tick rate:"
    /// lines from the same command are ignored.
    static func parseVanillaTick(_ clean: String) -> Sample? {
        // Cheap pre-guard: the regex requires this literal, so skip the compile+match on
        // every line that isn't the vanilla tick-query reply.
        guard clean.contains("Average time per tick") else { return nil }
        let pattern = #"Average time per tick:\s*([0-9.]+)\s*ms"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let fullRange = NSRange(clean.startIndex..<clean.endIndex, in: clean)
        guard let match = regex.firstMatch(in: clean, options: [], range: fullRange),
              match.numberOfRanges > 1,
              let msptRange = Range(match.range(at: 1), in: clean),
              let mspt = Double(clean[msptRange]),
              mspt > 0 else {
            return nil
        }
        let tps = min(20.0, 1000.0 / mspt)
        return Sample(t1: tps, t5: nil, t15: nil)
    }

    // MARK: - spark `/spark tps` (Fabric/Quilt/Vanilla with the spark mod)

    /// True for spark's TPS section header: "TPS from last 5s, 10s, 1m, 5m, 15m:".
    /// spark prints the five values on the FOLLOWING line, so the caller arms on the
    /// header and parses the next line with `parseSparkValues`.
    static func isSparkTpsHeader(_ clean: String) -> Bool {
        clean.contains("TPS from last 5s, 10s, 1m, 5m, 15m")
    }

    /// Parses spark's TPS values line ("20.0, 20.0, 20.0, 20.0, 20.0" — possibly with
    /// colour codes or a leading "*"), extracting the five decimals for the 5s, 10s,
    /// 1m, 5m, 15m windows. Maps 1m/5m/15m onto t1/t5/t15 so the UI renders the same
    /// trio as Paper. Requires decimals, so a log timestamp ("[11:48:55]") can't be
    /// mistaken for a value. Returns nil if fewer than five values are present.
    static func parseSparkValues(_ clean: String) -> Sample? {
        guard let regex = try? NSRegularExpression(pattern: #"[0-9]+\.[0-9]+"#) else { return nil }
        let ns = clean as NSString
        let matches = regex.matches(in: clean, range: NSRange(location: 0, length: ns.length))
        let nums = matches.compactMap { Double(ns.substring(with: $0.range)) }
        guard nums.count >= 5 else { return nil }
        // spark order: 5s, 10s, 1m, 5m, 15m.
        return Sample(t1: nums[2], t5: nums[3], t15: nums[4])
    }
}

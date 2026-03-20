import Foundation

/// Router identification and matching engine. Scores guide candidates against user input and returns ranked results with confidence metadata.
///
/// This layer stays fully deterministic and independent from UI.
/// It consumes repository data, normalizes freeform user input, infers likely
/// router/provider families, ranks candidate guides, and suggests a fallback when
/// there is no exact family guide in the current catalog.
final class RouterPortForwardGuideMatcher {

    struct MatchCandidate: Equatable {
        let guide: RouterPortForwardGuide
        let score: Int
        let reasons: [String]
    }

    struct MatchResult: Equatable {
        let originalQuery: String
        let normalizedQuery: String
        let normalizedTokens: [String]
        let inferredFamilies: [RouterGuideFamily]
        let candidates: [MatchCandidate]
        let suggestedFallbackGuide: RouterPortForwardGuide?
        let isAmbiguous: Bool
        let matchedDirectGuide: Bool

        var topCandidate: MatchCandidate? { candidates.first }
    }

    private struct FamilyAliasRule: Equatable {
        let family: RouterGuideFamily
        let aliases: [String]
    }

    private let repository: RouterPortForwardGuideRepository

    init(repository: RouterPortForwardGuideRepository = RouterPortForwardGuideRepository()) {
        self.repository = repository
    }

    func match(_ rawQuery: String) -> MatchResult {
        let normalizedQuery = Self.normalize(rawQuery)
        let normalizedTokens = Self.tokens(fromNormalized: normalizedQuery)
        let inferredFamilies = inferFamilies(from: normalizedQuery, tokens: normalizedTokens)
        let intent = inferredIntent(from: normalizedQuery, tokens: normalizedTokens, inferredFamilies: inferredFamilies)

        let rankedCandidates = repository.allGuides
            .map { scoreCandidate($0, normalizedQuery: normalizedQuery, normalizedTokens: normalizedTokens, inferredFamilies: inferredFamilies, intent: intent) }
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.guide.displayName.localizedCaseInsensitiveCompare(rhs.guide.displayName) == .orderedAscending
            }

        let fallbackGuide = suggestedFallbackGuide(
            normalizedQuery: normalizedQuery,
            tokens: normalizedTokens,
            inferredFamilies: inferredFamilies,
            intent: intent,
            excluding: rankedCandidates.first?.guide.id
        )

        let isAmbiguous: Bool
        if rankedCandidates.count >= 2 {
            let first = rankedCandidates[0].score
            let second = rankedCandidates[1].score
            isAmbiguous = first > 0 && (first - second) <= 12
        } else {
            isAmbiguous = false
        }

        let matchedDirectGuide = rankedCandidates.first.map { candidate in
            inferredFamilies.contains(candidate.guide.family) || candidate.reasons.contains("exact keyword")
        } ?? false

        return MatchResult(
            originalQuery: rawQuery,
            normalizedQuery: normalizedQuery,
            normalizedTokens: normalizedTokens,
            inferredFamilies: inferredFamilies,
            candidates: rankedCandidates,
            suggestedFallbackGuide: fallbackGuide,
            isAmbiguous: isAmbiguous,
            matchedDirectGuide: matchedDirectGuide
        )
    }

    func bestMatch(for rawQuery: String) -> RouterPortForwardGuide? {
        match(rawQuery).topCandidate?.guide ?? match(rawQuery).suggestedFallbackGuide
    }

    // MARK: - Scoring

    private enum MatchIntent {
        case guideLookup
        case troubleshooting
        case mesh
        case unknown
    }

    private func scoreCandidate(
        _ guide: RouterPortForwardGuide,
        normalizedQuery: String,
        normalizedTokens: [String],
        inferredFamilies: [RouterGuideFamily],
        intent: MatchIntent
    ) -> MatchCandidate {
        var score = 0
        var reasons: [String] = []

        let guideKeywords = guide.searchKeywords.map(Self.normalize)
        let providerName = Self.normalize(guide.providerDisplayName ?? "")
        let deviceName = Self.normalize(guide.deviceDisplayName ?? "")
        let displayName = Self.normalize(guide.displayName)

        if !normalizedQuery.isEmpty {
            if guideKeywords.contains(normalizedQuery) || providerName == normalizedQuery || deviceName == normalizedQuery || displayName == normalizedQuery {
                score += 120
                reasons.append("exact keyword")
            }

            if guideKeywords.contains(where: { $0.hasPrefix(normalizedQuery) && $0 != normalizedQuery }) {
                score += 48
                reasons.append("keyword prefix")
            }

            if guideKeywords.contains(where: { $0.contains(normalizedQuery) && $0 != normalizedQuery }) {
                score += 28
                reasons.append("keyword substring")
            }
        }

        let guideTokenSet = Set((guide.searchKeywords + [guide.displayName, guide.providerDisplayName ?? "", guide.deviceDisplayName ?? ""]).flatMap {
            Self.tokens(fromNormalized: Self.normalize($0))
        })

        let queryTokenSet = Set(normalizedTokens)
        let tokenOverlap = queryTokenSet.intersection(guideTokenSet)
        if !tokenOverlap.isEmpty {
            score += min(40, tokenOverlap.count * 14)
            reasons.append("token overlap")
        }

        if inferredFamilies.contains(guide.family) {
            score += 70
            reasons.append("family alias")
        }

        switch intent {
        case .troubleshooting:
            if guide.family == .advancedTroubleshooting {
                score += 55
                reasons.append("troubleshooting intent")
            }
        case .mesh:
            if score > 0 && guide.category == .meshSystem {
                score += 22
                reasons.append("mesh intent")
            }
        case .unknown:
            if guide.family == .genericRouter || guide.family == .unknownRouter {
                score += 20
                reasons.append("unknown router fallback")
            }
        case .guideLookup:
            break
        }

        if score > 0 && (normalizedQuery.contains("isp") || normalizedQuery.contains("gateway") || normalizedQuery.contains("modem")) {
            if guide.category == .ispGateway {
                score += 12
                reasons.append("isp/gateway hint")
            }
        }

        if score > 0 && (normalizedQuery.contains("app") || normalizedQuery.contains("mesh")) {
            if guide.adminSurface == .mobileApp || guide.adminSurface == .either {
                score += 10
                reasons.append("app-managed hint")
            }
        }

        score = min(score, 250)
        return MatchCandidate(guide: guide, score: score, reasons: reasons)
    }

    // MARK: - Intent / fallback

    private func inferredIntent(
        from normalizedQuery: String,
        tokens: [String],
        inferredFamilies: [RouterGuideFamily]
    ) -> MatchIntent {
        let tokenSet = Set(tokens)
        let troubleshootingTerms: Set<String> = [
            "double", "nat", "cgnat", "firewall", "blocked", "wrong", "router", "device",
            "reboot", "passthrough", "bridge", "stuck", "failing", "failed", "working"
        ]

        if tokenSet.contains("mesh") || tokenSet.contains("deco") || tokenSet.contains("eero") || tokenSet.contains("nest") {
            return .mesh
        }

        if !tokenSet.intersection(troubleshootingTerms).isEmpty && (normalizedQuery.contains("not working") || normalizedQuery.contains("trouble") || normalizedQuery.contains("fail") || inferredFamilies.contains(.advancedTroubleshooting)) {
            return .troubleshooting
        }

        if normalizedQuery.isEmpty || normalizedQuery == "router" || normalizedQuery == "generic router" || normalizedQuery.contains("dont know") || normalizedQuery.contains("don't know") || normalizedQuery.contains("unknown") {
            return .unknown
        }

        return .guideLookup
    }

    private func suggestedFallbackGuide(
        normalizedQuery: String,
        tokens: [String],
        inferredFamilies: [RouterGuideFamily],
        intent: MatchIntent,
        excluding excludedGuideID: String?
    ) -> RouterPortForwardGuide? {
        let availableFamilies = Set(repository.allGuides.map(\ .family))

        if intent == .troubleshooting,
           let guide = repository.guides(family: .advancedTroubleshooting).first,
           guide.id != excludedGuideID {
            return guide
        }

        for family in inferredFamilies {
            if availableFamilies.contains(family),
               let guide = repository.guides(family: family).first,
               guide.id != excludedGuideID {
                return guide
            }
        }

        if intent == .mesh,
           let guide = repository.guides(family: .genericMesh).first,
           guide.id != excludedGuideID {
            return guide
        }

        if let guide = repository.guides(family: .genericRouter).first,
           guide.id != excludedGuideID {
            return guide
        }

        return repository.allGuides.first { $0.id != excludedGuideID }
    }

    // MARK: - Family inference

    private func inferFamilies(from normalizedQuery: String, tokens: [String]) -> [RouterGuideFamily] {
        var inferred: [RouterGuideFamily] = []

        for rule in Self.familyAliasRules {
            let matched = rule.aliases.contains { alias in
                let normalizedAlias = Self.normalize(alias)
                guard !normalizedAlias.isEmpty else { return false }
                if normalizedQuery == normalizedAlias { return true }
                if normalizedQuery.contains(normalizedAlias) { return true }
                let aliasTokens = Set(Self.tokens(fromNormalized: normalizedAlias))
                return !aliasTokens.isEmpty && aliasTokens.isSubset(of: Set(tokens))
            }

            if matched && !inferred.contains(rule.family) {
                inferred.append(rule.family)
            }
        }

        return inferred
    }

    private static let familyAliasRules: [FamilyAliasRule] = [
        FamilyAliasRule(family: .xfinityGateway, aliases: ["xfinity", "comcast", "comcast xfinity", "xfi", "xb6", "xb7", "xb8", "xfinity gateway", "comcast gateway"]),
        FamilyAliasRule(family: .spectrumGateway, aliases: ["spectrum", "charter", "charter spectrum", "spectrum router", "spectrum gateway", "sax1v1k", "rac2v1k"]),
        FamilyAliasRule(family: .attGateway, aliases: ["att", "at&t", "at and t", "uverse", "u verse", "bgw210", "bgw320", "5268ac", "att gateway", "at&t gateway"]),
        FamilyAliasRule(family: .fiosRouter, aliases: ["fios", "verizon", "verizon fios", "verizon router", "fios router", "g3100", "cr1000a", "cr1000b"]),
        FamilyAliasRule(family: .coxGateway, aliases: ["cox", "panoramic wifi", "cox panoramic", "cox gateway", "pw3", "pw6"]),
        FamilyAliasRule(family: .asus, aliases: ["asus", "asus router", "rt ax", "rt ac", "rog router", "zenwifi"]),
        FamilyAliasRule(family: .tpLink, aliases: ["tp link", "tplink", "deco", "archer", "omada"]),
        FamilyAliasRule(family: .netgear, aliases: ["netgear", "nighthawk", "orbi"]),
        FamilyAliasRule(family: .linksys, aliases: ["linksys", "velop"]),
        FamilyAliasRule(family: .eero, aliases: ["eero", "eero pro", "eero mesh"]),
        FamilyAliasRule(family: .googleNest, aliases: ["google wifi", "google nest", "nest wifi", "nest pro"]),
        FamilyAliasRule(family: .advancedTroubleshooting, aliases: ["double nat", "cgnat", "wrong router", "firewall", "port forwarding not working"]),
        FamilyAliasRule(family: .genericMesh, aliases: ["mesh", "mesh wifi", "app managed router", "app managed"]),
        FamilyAliasRule(family: .unknownRouter, aliases: ["unknown router", "dont know my router", "don't know my router", "not sure what router"])
    ]

    // MARK: - Normalization

    static func normalize(_ raw: String) -> String {
        let folded = raw
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return folded
    }

    static func tokens(from raw: String) -> [String] {
        tokens(fromNormalized: normalize(raw))
    }

    private static func tokens(fromNormalized normalized: String) -> [String] {
        guard !normalized.isEmpty else { return [] }
        let stopWords: Set<String> = ["the", "a", "an", "my", "i", "have", "wifi"]
        return normalized
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty && !stopWords.contains($0) }
    }
}


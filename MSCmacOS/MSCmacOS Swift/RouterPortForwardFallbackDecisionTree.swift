import Foundation

/// Decision-tree logic for unknown and unmatched routers. Drives the step-by-step router identification funnel and surfaces appropriate fallback guides.
///
/// This file intentionally stays independent from SwiftUI and view state.
/// It models a deterministic decision tree plus a resolver that can route a user
/// toward the best available guide, an honest fallback, or an unknown-router help path.

// MARK: - Decision tree model

enum RouterPortForwardDecisionNodeID: String, Codable, CaseIterable {
    case start
    case ispProviderChoice
    case ownRouterBrandChoice
    case meshBrandChoice
    case ispVsRouterClarifier
    case unknownRouterHelp
    case optionalSearch
    case advancedTroubleshooting
}

enum RouterPortForwardDecisionNodeKind: String, Codable, CaseIterable {
    case singleChoice
    case freeTextSearch
    case info
}

enum RouterPortForwardNetworkType: String, Codable, CaseIterable {
    case ispGateway = "isp_gateway"
    case ownRouter = "own_router"
    case meshSystem = "mesh_system"
    case notSure = "not_sure"
}

struct RouterPortForwardDecisionChoice: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var nextNodeID: RouterPortForwardDecisionNodeID?
    var impliedNetworkType: RouterPortForwardNetworkType?
    var suggestedSearchTerms: [String]
}

struct RouterPortForwardDecisionNode: Codable, Equatable, Identifiable {
    var id: RouterPortForwardDecisionNodeID
    var kind: RouterPortForwardDecisionNodeKind
    var title: String
    var body: String?
    var bullets: [String]
    var choices: [RouterPortForwardDecisionChoice]
}

enum RouterPortForwardFallbackDecisionTree {

    static func makeTree(detectedGatewayIPAddress: String?) -> [RouterPortForwardDecisionNode] {
        [
            RouterPortForwardDecisionNode(
                id: .start,
                kind: .singleChoice,
                title: "What are you configuring?",
                body: "Choose the device type first. The internet provider and the router you configure are not always the same thing.",
                bullets: [],
                choices: [
                    RouterPortForwardDecisionChoice(
                        id: "start-isp",
                        title: "ISP router / gateway",
                        nextNodeID: .ispProviderChoice,
                        impliedNetworkType: .ispGateway,
                        suggestedSearchTerms: ["Xfinity", "Spectrum", "AT&T", "Fios"]
                    ),
                    RouterPortForwardDecisionChoice(
                        id: "start-own",
                        title: "Your own router",
                        nextNodeID: .ownRouterBrandChoice,
                        impliedNetworkType: .ownRouter,
                        suggestedSearchTerms: ["ASUS", "TP-Link", "Netgear", "Linksys"]
                    ),
                    RouterPortForwardDecisionChoice(
                        id: "start-mesh",
                        title: "Mesh Wi‑Fi system",
                        nextNodeID: .meshBrandChoice,
                        impliedNetworkType: .meshSystem,
                        suggestedSearchTerms: ["eero", "Deco", "Nest"]
                    ),
                    RouterPortForwardDecisionChoice(
                        id: "start-unsure",
                        title: "Not sure",
                        nextNodeID: .unknownRouterHelp,
                        impliedNetworkType: .notSure,
                        suggestedSearchTerms: []
                    )
                ]
            ),
            RouterPortForwardDecisionNode(
                id: .ispProviderChoice,
                kind: .freeTextSearch,
                title: "Which provider gateway are you using?",
                body: "Search by provider or gateway line. Example terms: Xfinity, Spectrum, AT&T, Fios, XB7, BGW320.",
                bullets: [
                    "Choose the gateway only if that is the device doing routing.",
                    "If your provider modem is in bridge mode and your own router handles routing, use the router path instead."
                ],
                choices: []
            ),
            RouterPortForwardDecisionNode(
                id: .ownRouterBrandChoice,
                kind: .freeTextSearch,
                title: "Which router brand or line are you using?",
                body: "Search by brand or product line. Example terms: ASUS, TP-Link, Netgear, Linksys, Nighthawk, Archer.",
                bullets: [
                    "Use the router brand if you bought the router yourself.",
                    "If the router sits behind ISP equipment, you may still need bridge mode or upstream forwarding."
                ],
                choices: []
            ),
            RouterPortForwardDecisionNode(
                id: .meshBrandChoice,
                kind: .freeTextSearch,
                title: "Which mesh system or app are you using?",
                body: "Search by mesh brand or app. Example terms: eero, Deco, Google Wi‑Fi, Nest.",
                bullets: [
                    "Mesh systems are often identified by app name rather than router model.",
                    "If the mesh is in bridge mode, forwarding may need to happen on another router."
                ],
                choices: []
            ),
            RouterPortForwardDecisionNode(
                id: .ispVsRouterClarifier,
                kind: .info,
                title: "Make sure you are configuring the right device",
                body: "Your provider name and the router you configure are not always the same device.",
                bullets: [
                    "Spectrum could mean a Spectrum gateway or a Spectrum modem feeding your own ASUS router.",
                    "A mesh system can sit behind ISP hardware and still be the device doing routing.",
                    "If one device is in bridge mode, the other device usually holds the forwarding settings."
                ],
                choices: [
                    RouterPortForwardDecisionChoice(
                        id: "clarifier-search",
                        title: "Continue with search",
                        nextNodeID: .optionalSearch,
                        impliedNetworkType: nil,
                        suggestedSearchTerms: []
                    )
                ]
            ),
            RouterPortForwardDecisionNode(
                id: .unknownRouterHelp,
                kind: .info,
                title: "I don’t know my router",
                body: "Use these checks to identify the device or at least find the right fallback path.",
                bullets: unknownRouterBullets(detectedGatewayIPAddress: detectedGatewayIPAddress),
                choices: [
                    RouterPortForwardDecisionChoice(
                        id: "unknown-search",
                        title: "I found a name to search",
                        nextNodeID: .optionalSearch,
                        impliedNetworkType: nil,
                        suggestedSearchTerms: []
                    ),
                    RouterPortForwardDecisionChoice(
                        id: "unknown-advanced",
                        title: "Skip to advanced troubleshooting",
                        nextNodeID: .advancedTroubleshooting,
                        impliedNetworkType: nil,
                        suggestedSearchTerms: ["double NAT", "CGNAT"]
                    )
                ]
            ),
            RouterPortForwardDecisionNode(
                id: .optionalSearch,
                kind: .freeTextSearch,
                title: "Search by provider, brand, model line, or app",
                body: "Try provider names, brand names, mesh app names, or model lines like XB7, BGW320, Deco, or Nighthawk.",
                bullets: [
                    "The matcher can route broad terms to family guides when exact model coverage is not available.",
                    "If nothing looks right, you can still continue with a generic guide or advanced troubleshooting."
                ],
                choices: []
            ),
            RouterPortForwardDecisionNode(
                id: .advancedTroubleshooting,
                kind: .info,
                title: "Advanced networking path",
                body: "Use this when forwarding still fails, when you suspect double NAT or CGNAT, or when no exact router path is available.",
                bullets: [
                    "Check whether another upstream router is doing routing.",
                    "Check whether your ISP or apartment network blocks inbound connections.",
                    "Verify that the correct device, IP, port, and protocol were used."
                ],
                choices: []
            )
        ]
    }

    private static func unknownRouterBullets(detectedGatewayIPAddress: String?) -> [String] {
        var bullets: [String] = [
            "Look for the model name on the sticker on the router, gateway, or mesh node.",
            "Check which router or mesh apps are already installed on your phone or Mac.",
            "Identify whether the ISP device or your own router is actually doing routing.",
            "Common gateway addresses include 192.168.1.1, 192.168.0.1, and 10.0.0.1.",
            "Port forwarding may also be labeled NAT Forwarding, Virtual Server, Applications & Gaming, Port Rules, Firewall Rules, or Advanced NAT."
        ]

        if let detectedGatewayIPAddress,
           !detectedGatewayIPAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            bullets.insert("Detected gateway IP from the app: \(detectedGatewayIPAddress)", at: 3)
        }

        return bullets
    }
}

// MARK: - Resolution engine

struct RouterPortForwardFallbackState: Equatable {
    var networkType: RouterPortForwardNetworkType?
    var searchQuery: String
    var onlyKnowsISP: Bool
    var onlyKnowsMeshSystem: Bool
    var unsureWhetherISPOrOwnRouter: Bool
    var wantsAdvancedTroubleshooting: Bool

    init(
        networkType: RouterPortForwardNetworkType? = nil,
        searchQuery: String = "",
        onlyKnowsISP: Bool = false,
        onlyKnowsMeshSystem: Bool = false,
        unsureWhetherISPOrOwnRouter: Bool = false,
        wantsAdvancedTroubleshooting: Bool = false
    ) {
        self.networkType = networkType
        self.searchQuery = searchQuery
        self.onlyKnowsISP = onlyKnowsISP
        self.onlyKnowsMeshSystem = onlyKnowsMeshSystem
        self.unsureWhetherISPOrOwnRouter = unsureWhetherISPOrOwnRouter
        self.wantsAdvancedTroubleshooting = wantsAdvancedTroubleshooting
    }
}

enum RouterPortForwardResolutionKind: String, Equatable {
    case exactGuide
    case familyGuide
    case genericRouterGuide
    case genericMeshGuide
    case troubleshootingGuide
    case unknownRouterHelp
    case needsMoreInfo
}

enum RouterPortForwardGuideAvailability: String, Equatable {
    case exactMatch
    case familyMatch
    case fallbackUsed
    case desiredGuideNotSeededYet
}

struct RouterPortForwardFallbackResolution: Equatable {
    var kind: RouterPortForwardResolutionKind
    var availability: RouterPortForwardGuideAvailability
    var matchedGuide: RouterPortForwardGuide?
    var fallbackGuide: RouterPortForwardGuide?
    var desiredFamily: RouterGuideFamily?
    var inferredFamilies: [RouterGuideFamily]
    var explanationBullets: [String]
    var recommendedNextNodeID: RouterPortForwardDecisionNodeID?
    var suggestedSearchTerms: [String]
    var matchedQuery: String?
}

final class RouterPortForwardFallbackRouter {

    private let repository: RouterPortForwardGuideRepository
    private let matcher: RouterPortForwardGuideMatcher

    init(
        repository: RouterPortForwardGuideRepository = RouterPortForwardGuideRepository(),
        matcher: RouterPortForwardGuideMatcher? = nil
    ) {
        self.repository = repository
        self.matcher = matcher ?? RouterPortForwardGuideMatcher(repository: repository)
    }

    func decisionTree(detectedGatewayIPAddress: String?) -> [RouterPortForwardDecisionNode] {
        RouterPortForwardFallbackDecisionTree.makeTree(detectedGatewayIPAddress: detectedGatewayIPAddress)
    }

    func resolve(
        state: RouterPortForwardFallbackState,
        runtimeContext: RouterPortForwardGuideRuntimeContext? = nil
    ) -> RouterPortForwardFallbackResolution {
        let query = state.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        if state.wantsAdvancedTroubleshooting {
            return troubleshootingResolution(
                inferredFamilies: [.advancedTroubleshooting],
                query: query,
                explanationBullets: [
                    "Advanced troubleshooting is the right path when forwarding still fails or when the network may be blocked by double NAT, CGNAT, or ISP restrictions."
                ]
            )
        }

        if !query.isEmpty {
            let match = matcher.match(query)

            if let topCandidate = match.topCandidate {
                if topCandidate.guide.family == .advancedTroubleshooting {
                    return troubleshootingResolution(
                        inferredFamilies: match.inferredFamilies,
                        query: query,
                        explanationBullets: [
                            "Your search looks like a networking failure or restriction rather than a router identification request."
                        ]
                    )
                }

                if match.matchedDirectGuide {
                    let kind: RouterPortForwardResolutionKind = topCandidate.reasons.contains("exact keyword") ? .exactGuide : .familyGuide
                    let availability: RouterPortForwardGuideAvailability = topCandidate.reasons.contains("exact keyword") ? .exactMatch : .familyMatch
                    return RouterPortForwardFallbackResolution(
                        kind: kind,
                        availability: availability,
                        matchedGuide: topCandidate.guide,
                        fallbackGuide: nil,
                        desiredFamily: topCandidate.guide.family,
                        inferredFamilies: match.inferredFamilies,
                        explanationBullets: explanationBullets(for: state, match: match, guide: topCandidate.guide),
                        recommendedNextNodeID: nil,
                        suggestedSearchTerms: [],
                        matchedQuery: query
                    )
                }
            }

            if let firstRecognizedFamily = match.inferredFamilies.first {
                if firstRecognizedFamily == .advancedTroubleshooting {
                    return troubleshootingResolution(
                        inferredFamilies: match.inferredFamilies,
                        query: query,
                        explanationBullets: [
                            "The matcher recognized an advanced networking problem rather than a supported router family."
                        ]
                    )
                }

                if let directFamilyGuide = repository.guides(family: firstRecognizedFamily).first {
                    return RouterPortForwardFallbackResolution(
                        kind: .familyGuide,
                        availability: .familyMatch,
                        matchedGuide: directFamilyGuide,
                        fallbackGuide: nil,
                        desiredFamily: firstRecognizedFamily,
                        inferredFamilies: match.inferredFamilies,
                        explanationBullets: explanationBullets(for: state, match: match, guide: directFamilyGuide),
                        recommendedNextNodeID: nil,
                        suggestedSearchTerms: [],
                        matchedQuery: query
                    )
                }

                return recognizedFamilyFallbackResolution(
                    desiredFamily: firstRecognizedFamily,
                    inferredFamilies: match.inferredFamilies,
                    query: query,
                    state: state
                )
            }
        }

        switch state.networkType {
        case .meshSystem:
            return genericMeshResolution(query: query, runtimeContext: runtimeContext)

        case .ispGateway:
            return RouterPortForwardFallbackResolution(
                kind: .needsMoreInfo,
                availability: .fallbackUsed,
                matchedGuide: nil,
                fallbackGuide: nil,
                desiredFamily: nil,
                inferredFamilies: [],
                explanationBullets: [
                    "Choose the provider gateway family next, or search by gateway line such as XB7 or BGW320.",
                    "If your own router is behind the provider modem, use the router path instead."
                ],
                recommendedNextNodeID: state.unsureWhetherISPOrOwnRouter ? .ispVsRouterClarifier : .ispProviderChoice,
                suggestedSearchTerms: ["Xfinity", "Spectrum", "AT&T", "Fios", "XB7", "BGW320"],
                matchedQuery: nil
            )

        case .ownRouter:
            return RouterPortForwardFallbackResolution(
                kind: .needsMoreInfo,
                availability: .fallbackUsed,
                matchedGuide: nil,
                fallbackGuide: nil,
                desiredFamily: nil,
                inferredFamilies: [],
                explanationBullets: [
                    "Search by router brand or product line next.",
                    "Common examples include ASUS, TP-Link, Netgear, Linksys, Nighthawk, and Archer."
                ],
                recommendedNextNodeID: .ownRouterBrandChoice,
                suggestedSearchTerms: ["ASUS", "TP-Link", "Netgear", "Linksys", "Nighthawk", "Archer"],
                matchedQuery: nil
            )

        case .notSure, nil:
            break
        }

        if state.onlyKnowsMeshSystem {
            return genericMeshResolution(query: query, runtimeContext: runtimeContext)
        }

        if state.onlyKnowsISP || state.unsureWhetherISPOrOwnRouter || state.networkType == .notSure || query.isEmpty {
            return RouterPortForwardFallbackResolution(
                kind: .unknownRouterHelp,
                availability: .fallbackUsed,
                matchedGuide: nil,
                fallbackGuide: bestAvailableGenericRouterGuide(),
                desiredFamily: .unknownRouter,
                inferredFamilies: [],
                explanationBullets: unknownRouterExplanationBullets(runtimeContext: runtimeContext),
                recommendedNextNodeID: state.unsureWhetherISPOrOwnRouter ? .ispVsRouterClarifier : .unknownRouterHelp,
                suggestedSearchTerms: ["Xfinity", "Spectrum", "ASUS", "eero", "Deco", "Nighthawk"],
                matchedQuery: nil
            )
        }

        return genericRouterResolution(query: query)
    }

    // MARK: - Helpers

    private func explanationBullets(
        for state: RouterPortForwardFallbackState,
        match: RouterPortForwardGuideMatcher.MatchResult,
        guide: RouterPortForwardGuide
    ) -> [String] {
        var bullets: [String] = []

        if let topCandidate = match.topCandidate, !topCandidate.reasons.isEmpty {
            bullets.append("Matched this guide because: \(topCandidate.reasons.joined(separator: ", ")).")
        }

        if state.unsureWhetherISPOrOwnRouter {
            bullets.append("Verify that this is the device doing routing before you make changes.")
        }

        if let provider = guide.providerDisplayName, let device = guide.deviceDisplayName, provider.caseInsensitiveCompare(device) != .orderedSame {
            bullets.append("Provider: \(provider). Device family: \(device). Do not treat those as interchangeable.")
        }

        return bullets
    }

    private func recognizedFamilyFallbackResolution(
        desiredFamily: RouterGuideFamily,
        inferredFamilies: [RouterGuideFamily],
        query: String,
        state: RouterPortForwardFallbackState
    ) -> RouterPortForwardFallbackResolution {
        if desiredFamily == .advancedTroubleshooting {
            return troubleshootingResolution(inferredFamilies: inferredFamilies, query: query, explanationBullets: [])
        }

        let kind: RouterPortForwardResolutionKind = isMeshFamily(desiredFamily) ? .genericMeshGuide : .genericRouterGuide
        let availability: RouterPortForwardGuideAvailability = .desiredGuideNotSeededYet
        let fallbackGuide: RouterPortForwardGuide? = isMeshFamily(desiredFamily) ? bestAvailableGenericMeshOrRouterGuide() : bestAvailableGenericRouterGuide()

        var bullets = [
            "The matcher recognized the family \(desiredFamily.rawValue), but that family guide is not seeded in the current project yet.",
            "Use the fallback guide for the general flow, then continue to advanced troubleshooting if the router labels differ too much."
        ]
        if state.unsureWhetherISPOrOwnRouter {
            bullets.append("Before changing settings, confirm whether the ISP hardware or your own router is actually doing routing.")
        }

        return RouterPortForwardFallbackResolution(
            kind: kind,
            availability: availability,
            matchedGuide: nil,
            fallbackGuide: fallbackGuide,
            desiredFamily: desiredFamily,
            inferredFamilies: inferredFamilies,
            explanationBullets: bullets,
            recommendedNextNodeID: nil,
            suggestedSearchTerms: [],
            matchedQuery: query.isEmpty ? nil : query
        )
    }

    private func genericRouterResolution(query: String) -> RouterPortForwardFallbackResolution {
        let guide = bestAvailableGenericRouterGuide()
        return RouterPortForwardFallbackResolution(
            kind: .genericRouterGuide,
            availability: .fallbackUsed,
            matchedGuide: guide,
            fallbackGuide: nil,
            desiredFamily: .genericRouter,
            inferredFamilies: [],
            explanationBullets: [
                "No exact family match was found, so the generic router guide is the safest fallback.",
                "Use menu aliases such as NAT Forwarding, Virtual Server, Applications & Gaming, Port Rules, Firewall Rules, or Advanced NAT while you search the router interface."
            ],
            recommendedNextNodeID: nil,
            suggestedSearchTerms: [],
            matchedQuery: query.isEmpty ? nil : query
        )
    }

    private func genericMeshResolution(
        query: String,
        runtimeContext: RouterPortForwardGuideRuntimeContext?
    ) -> RouterPortForwardFallbackResolution {
        if let genericMesh = repository.guides(family: .genericMesh).first {
            return RouterPortForwardFallbackResolution(
                kind: .genericMeshGuide,
                availability: .familyMatch,
                matchedGuide: genericMesh,
                fallbackGuide: nil,
                desiredFamily: .genericMesh,
                inferredFamilies: [.genericMesh],
                explanationBullets: [
                    "A mesh-specific fallback guide is available for app-managed or mesh-first systems."
                ],
                recommendedNextNodeID: nil,
                suggestedSearchTerms: [],
                matchedQuery: query.isEmpty ? nil : query
            )
        }

        return RouterPortForwardFallbackResolution(
            kind: .genericMeshGuide,
            availability: .desiredGuideNotSeededYet,
            matchedGuide: nil,
            fallbackGuide: bestAvailableGenericRouterGuide(),
            desiredFamily: .genericMesh,
            inferredFamilies: [.genericMesh],
            explanationBullets: [
                "The current seed catalog does not include a dedicated generic mesh guide yet.",
                "Use the generic router guide as the fallback, but expect more app-based wording and bridge-mode edge cases for mesh systems.",
                runtimeContext?.detectedGatewayIPAddress == nil ? "If the mesh is in bridge mode, forwarding may need to happen on another router." : "If the mesh is in bridge mode, forwarding may need to happen on the gateway at \(runtimeContext?.detectedGatewayIPAddress ?? "the upstream router")."
            ],
            recommendedNextNodeID: nil,
            suggestedSearchTerms: ["eero", "Deco", "Nest"],
            matchedQuery: query.isEmpty ? nil : query
        )
    }

    private func troubleshootingResolution(
        inferredFamilies: [RouterGuideFamily],
        query: String,
        explanationBullets: [String]
    ) -> RouterPortForwardFallbackResolution {
        let guide = repository.guides(family: .advancedTroubleshooting).first
        var bullets = explanationBullets
        bullets.append("Use the advanced troubleshooting path for double NAT, CGNAT, wrong-router configuration, firewall blocks, or ISP restrictions.")

        return RouterPortForwardFallbackResolution(
            kind: .troubleshootingGuide,
            availability: guide == nil ? .desiredGuideNotSeededYet : .familyMatch,
            matchedGuide: guide,
            fallbackGuide: nil,
            desiredFamily: .advancedTroubleshooting,
            inferredFamilies: inferredFamilies,
            explanationBullets: bullets,
            recommendedNextNodeID: .advancedTroubleshooting,
            suggestedSearchTerms: ["double NAT", "CGNAT", "wrong router", "firewall"],
            matchedQuery: query.isEmpty ? nil : query
        )
    }

    private func unknownRouterExplanationBullets(runtimeContext: RouterPortForwardGuideRuntimeContext?) -> [String] {
        var bullets = [
            "Check the sticker on the router, gateway, or mesh node for the brand and model.",
            "Check your phone or Mac for router apps that may already identify the brand.",
            "Separate the provider name from the device doing routing before you continue.",
            "Common local gateway addresses are 192.168.1.1, 192.168.0.1, and 10.0.0.1.",
            "Port forwarding may also be labeled NAT Forwarding, Virtual Server, Applications & Gaming, Port Rules, Firewall Rules, or Advanced NAT."
        ]

        if let detectedGatewayIPAddress = runtimeContext?.detectedGatewayIPAddress,
           !detectedGatewayIPAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            bullets.insert("The app detected a gateway IP of \(detectedGatewayIPAddress).", at: 3)
        }

        return bullets
    }

    private func bestAvailableGenericRouterGuide() -> RouterPortForwardGuide? {
        repository.guides(family: .genericRouter).first ?? repository.allGuides.first
    }

    private func bestAvailableGenericMeshOrRouterGuide() -> RouterPortForwardGuide? {
        repository.guides(family: .genericMesh).first ?? bestAvailableGenericRouterGuide()
    }

    private func isMeshFamily(_ family: RouterGuideFamily) -> Bool {
        switch family {
        case .genericMesh, .eero, .googleNest:
            return true
        case .tpLink:
            return false
        default:
            return false
        }
    }
}

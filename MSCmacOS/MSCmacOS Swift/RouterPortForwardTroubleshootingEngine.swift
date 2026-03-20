import Foundation

/// Rule-based troubleshooting engine for router and port-forwarding failures. Accepts user-reported symptoms and returns prioritised causes and recommended actions.
///
/// This layer stays independent from SwiftUI. It turns user-observed symptoms into
/// likely causes, recommended next steps, and linked troubleshooting topics that the
/// guide repository already owns.

// MARK: - User-observed symptoms

enum RouterPortForwardSymptomID: String, Codable, CaseIterable {
    case cannotConnectExternally = "cannot_connect_externally"
    case localNetworkWorksButInternetFails = "local_network_works_but_internet_fails"
    case routerRulePointsToOldIP = "router_rule_points_to_old_ip"
    case macIPAddressChanged = "mac_ip_address_changed"
    case selectedWrongTargetDevice = "selected_wrong_target_device"
    case forwardedOnProviderButOwnRouterExists = "forwarded_on_provider_but_own_router_exists"
    case forwardedOnOwnRouterButProviderGatewayExists = "forwarded_on_own_router_but_provider_gateway_exists"
    case twoRoutersPresent = "two_routers_present"
    case wanIPDiffersFromPublicIP = "wan_ip_differs_from_public_ip"
    case apartmentDormManagedNetwork = "apartment_dorm_managed_network"
    case noRouterAdminAccess = "no_router_admin_access"
    case javaWorksBedrockFails = "java_works_bedrock_fails"
    case bedrockWorksJavaFails = "bedrock_works_java_fails"
    case firewallPromptSeen = "firewall_prompt_seen"
    case securityToolMayBeBlocking = "security_tool_may_be_blocking"
    case changesSavedButStillFails = "changes_saved_but_still_fails"
    case routerAskedToReboot = "router_asked_to_reboot"
    case usingMeshBridgeOrAPMode = "using_mesh_bridge_or_ap_mode"
}

enum RouterPortForwardTroubleshootingSeverity: String, Codable, CaseIterable {
    case high
    case medium
    case low
}

struct RouterPortForwardSymptom: Codable, Equatable, Identifiable {
    var id: RouterPortForwardSymptomID
    var title: String
    var description: String
}

// MARK: - Rule model

enum RouterPortForwardCauseConfidence: String, Codable, CaseIterable {
    case strong
    case possible
}

struct RouterPortForwardTroubleshootingCause: Equatable, Identifiable {
    let id: RouterGuideTroubleshootingTopicID
    let confidence: RouterPortForwardCauseConfidence
    let score: Int
    let matchedSymptoms: [RouterPortForwardSymptomID]
    let topic: RouterGuideTroubleshootingTopic

    var severity: RouterPortForwardTroubleshootingSeverity {
        switch score {
        case 9...: return .high
        case 5...: return .medium
        default: return .low
        }
    }
}

struct RouterPortForwardTroubleshootingRule: Equatable, Identifiable {
    struct Requirement: Equatable {
        let symptom: RouterPortForwardSymptomID
        let weight: Int
    }

    let id: String
    let topicID: RouterGuideTroubleshootingTopicID
    let title: String
    let allOf: [Requirement]
    let anyOf: [Requirement]
    let excludedSymptoms: Set<RouterPortForwardSymptomID>
    let explanation: String
    let nextActions: [String]
    let escalationBullets: [String]

    var identifier: String { id }
}

struct RouterPortForwardTroubleshootingReport: Equatable {
    let symptoms: [RouterPortForwardSymptomID]
    let likelyCauses: [RouterPortForwardTroubleshootingCause]
    let recommendedActions: [String]
    let escalationBullets: [String]
    let fallbackResolution: RouterPortForwardFallbackResolution?
    let summary: String
}

// MARK: - Engine

final class RouterPortForwardTroubleshootingEngine {

    private let repository: RouterPortForwardGuideRepository
    private let fallbackRouter: RouterPortForwardFallbackRouter

    init(
        repository: RouterPortForwardGuideRepository = RouterPortForwardGuideRepository(),
        fallbackRouter: RouterPortForwardFallbackRouter? = nil
    ) {
        self.repository = repository
        self.fallbackRouter = fallbackRouter ?? RouterPortForwardFallbackRouter(repository: repository)
    }

    var supportedSymptoms: [RouterPortForwardSymptom] {
        RouterPortForwardTroubleshootingKnowledgeBase.supportedSymptoms
    }

    var rules: [RouterPortForwardTroubleshootingRule] {
        RouterPortForwardTroubleshootingKnowledgeBase.makeRules(repository: repository)
    }

    func analyze(
        symptoms: [RouterPortForwardSymptomID],
        fallbackState: RouterPortForwardFallbackState? = nil,
        runtimeContext: RouterPortForwardGuideRuntimeContext? = nil
    ) -> RouterPortForwardTroubleshootingReport {
        let normalizedSymptoms = normalized(symptoms)
        let fallbackResolution = fallbackState.map { fallbackRouter.resolve(state: $0, runtimeContext: runtimeContext) }

        let likelyCauses = rules.compactMap { evaluate(rule: $0, symptoms: normalizedSymptoms) }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.confidence != rhs.confidence {
                    return lhs.confidence == .strong
                }
                return lhs.topic.title < rhs.topic.title
            }

        let recommendedActions = deduplicatedStrings(
            likelyCauses.flatMap { $0.topic.suggestedNextActions } + likelyCauses.flatMap { cause in
                rules.first(where: { $0.topicID == cause.id })?.nextActions ?? []
            }
        )

        var escalationBullets = deduplicatedStrings(
            likelyCauses.flatMap { cause in
                rules.first(where: { $0.topicID == cause.id })?.escalationBullets ?? []
            }
        )

        if let fallbackResolution {
            escalationBullets = deduplicatedStrings(escalationBullets + fallbackResolution.explanationBullets)
        }

        let summary = makeSummary(likelyCauses: likelyCauses, fallbackResolution: fallbackResolution)

        return RouterPortForwardTroubleshootingReport(
            symptoms: normalizedSymptoms,
            likelyCauses: likelyCauses,
            recommendedActions: recommendedActions,
            escalationBullets: escalationBullets,
            fallbackResolution: fallbackResolution,
            summary: summary
        )
    }

    func analyze(
        symptomIDs: Set<RouterPortForwardSymptomID>,
        fallbackState: RouterPortForwardFallbackState? = nil,
        runtimeContext: RouterPortForwardGuideRuntimeContext? = nil
    ) -> RouterPortForwardTroubleshootingReport {
        analyze(symptoms: Array(symptomIDs), fallbackState: fallbackState, runtimeContext: runtimeContext)
    }

    func symptom(id: RouterPortForwardSymptomID) -> RouterPortForwardSymptom? {
        supportedSymptoms.first { $0.id == id }
    }

    private func evaluate(
        rule: RouterPortForwardTroubleshootingRule,
        symptoms: [RouterPortForwardSymptomID]
    ) -> RouterPortForwardTroubleshootingCause? {
        let symptomSet = Set(symptoms)

        if !rule.excludedSymptoms.isDisjoint(with: symptomSet) {
            return nil
        }

        let requiredSymptoms = rule.allOf.map(\ .symptom)
        guard requiredSymptoms.allSatisfy(symptomSet.contains) else {
            return nil
        }

        let anyMatches = rule.anyOf.filter { symptomSet.contains($0.symptom) }
        if !rule.anyOf.isEmpty && anyMatches.isEmpty {
            return nil
        }

        guard let topic = repository.troubleshootingTopic(id: rule.topicID) else {
            return nil
        }

        let requiredScore = rule.allOf.reduce(0) { $0 + $1.weight }
        let optionalScore = anyMatches.reduce(0) { $0 + $1.weight }
        let score = requiredScore + optionalScore
        let matchedSymptoms = rule.allOf.map(\ .symptom) + anyMatches.map(\ .symptom)
        let confidence: RouterPortForwardCauseConfidence = (rule.anyOf.isEmpty || anyMatches.count >= max(1, rule.anyOf.count / 2)) ? .strong : .possible

        return RouterPortForwardTroubleshootingCause(
            id: rule.topicID,
            confidence: confidence,
            score: score,
            matchedSymptoms: matchedSymptoms,
            topic: topic
        )
    }

    private func normalized(_ symptoms: [RouterPortForwardSymptomID]) -> [RouterPortForwardSymptomID] {
        var seen = Set<RouterPortForwardSymptomID>()
        var ordered: [RouterPortForwardSymptomID] = []
        for symptom in symptoms {
            if seen.insert(symptom).inserted {
                ordered.append(symptom)
            }
        }
        return ordered
    }

    private func deduplicatedStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed).inserted {
                result.append(trimmed)
            }
        }
        return result
    }

    private func makeSummary(
        likelyCauses: [RouterPortForwardTroubleshootingCause],
        fallbackResolution: RouterPortForwardFallbackResolution?
    ) -> String {
        if let first = likelyCauses.first {
            if likelyCauses.count == 1 {
                return "Most likely cause: \(first.topic.title)."
            }
            let remaining = likelyCauses.dropFirst().map { $0.topic.title }
            return "Most likely cause: \(first.topic.title). Also check: \(remaining.joined(separator: ", "))."
        }

        if let fallbackResolution, fallbackResolution.kind == .unknownRouterHelp || fallbackResolution.kind == .needsMoreInfo {
            return "No strong failure cause was detected yet. Identify the correct router path first, then re-run troubleshooting with more specific symptoms."
        }

        return "No strong failure cause was detected yet. Use the generic troubleshooting path and verify the router, target device, IP, port, and protocol."
    }
}

// MARK: - Knowledge base

enum RouterPortForwardTroubleshootingKnowledgeBase {

    static let supportedSymptoms: [RouterPortForwardSymptom] = [
        RouterPortForwardSymptom(
            id: .cannotConnectExternally,
            title: "No one can connect from outside your network",
            description: "The server may work locally, but internet players still cannot join."
        ),
        RouterPortForwardSymptom(
            id: .localNetworkWorksButInternetFails,
            title: "It works on the local network but not from the internet",
            description: "This often means the server itself is running, but upstream networking is still wrong."
        ),
        RouterPortForwardSymptom(
            id: .routerRulePointsToOldIP,
            title: "The router rule points to an old local IP",
            description: "The forwarding rule still targets a previous address instead of the host Mac's current address."
        ),
        RouterPortForwardSymptom(
            id: .macIPAddressChanged,
            title: "The Mac's IP changed",
            description: "DHCP may have given the Mac a new local address."
        ),
        RouterPortForwardSymptom(
            id: .selectedWrongTargetDevice,
            title: "The wrong target device was selected",
            description: "The forwarding rule may target another Mac, PC, console, or stale DHCP entry."
        ),
        RouterPortForwardSymptom(
            id: .forwardedOnProviderButOwnRouterExists,
            title: "You forwarded on the provider device, but your own router is also present",
            description: "The upstream provider box may not be the device doing LAN routing."
        ),
        RouterPortForwardSymptom(
            id: .forwardedOnOwnRouterButProviderGatewayExists,
            title: "You forwarded on your own router, but provider gateway hardware is also present",
            description: "The provider gateway may still be doing routing unless bridge mode is enabled."
        ),
        RouterPortForwardSymptom(
            id: .twoRoutersPresent,
            title: "Two routers or router-like devices are present",
            description: "Common examples include ISP gateway + personal router or gateway + mesh system."
        ),
        RouterPortForwardSymptom(
            id: .wanIPDiffersFromPublicIP,
            title: "The router WAN IP does not match the public IP",
            description: "This can indicate CGNAT or another upstream routing layer."
        ),
        RouterPortForwardSymptom(
            id: .apartmentDormManagedNetwork,
            title: "You are on an apartment, dorm, campus, or managed network",
            description: "Those environments often block direct forwarding or do not give router admin access."
        ),
        RouterPortForwardSymptom(
            id: .noRouterAdminAccess,
            title: "You do not have router admin access",
            description: "Without admin access, you may not be allowed to create or edit forwarding rules."
        ),
        RouterPortForwardSymptom(
            id: .javaWorksBedrockFails,
            title: "Java works but Bedrock fails",
            description: "The Bedrock port and protocol are often different from Java."
        ),
        RouterPortForwardSymptom(
            id: .bedrockWorksJavaFails,
            title: "Bedrock works but Java fails",
            description: "The Java side may be missing its TCP rule or using the wrong target."
        ),
        RouterPortForwardSymptom(
            id: .firewallPromptSeen,
            title: "You saw a macOS firewall or permission prompt",
            description: "The host may still be blocking inbound traffic even if the router rule is correct."
        ),
        RouterPortForwardSymptom(
            id: .securityToolMayBeBlocking,
            title: "Another security or network tool may be blocking traffic",
            description: "Third-party security tools can override otherwise correct routing."
        ),
        RouterPortForwardSymptom(
            id: .changesSavedButStillFails,
            title: "You saved the rule, but it still does not work",
            description: "Some routers need Apply, reboot, or a short delay before the rule becomes active."
        ),
        RouterPortForwardSymptom(
            id: .routerAskedToReboot,
            title: "The router asked to reboot or apply changes",
            description: "The new rule may not be active yet."
        ),
        RouterPortForwardSymptom(
            id: .usingMeshBridgeOrAPMode,
            title: "Your mesh or router may be in bridge / AP mode",
            description: "If the device is not routing, forwarding must happen elsewhere."
        )
    ]

    static func makeRules(repository: RouterPortForwardGuideRepository) -> [RouterPortForwardTroubleshootingRule] {
        [
            RouterPortForwardTroubleshootingRule(
                id: "local-ip-changed",
                topicID: .localIPChanged,
                title: "Local IP changed or rule points to old IP",
                allOf: [
                    .init(symptom: .cannotConnectExternally, weight: 3)
                ],
                anyOf: [
                    .init(symptom: .routerRulePointsToOldIP, weight: 4),
                    .init(symptom: .macIPAddressChanged, weight: 4)
                ],
                excludedSymptoms: [],
                explanation: "A stale local IP is one of the most common reasons a previously working port forward stops working.",
                nextActions: [
                    "Re-check the Mac's current local IP in Minecraft Server Controller.",
                    "Update the router rule so it points to the current host Mac address.",
                    "Reserve the Mac's DHCP address later so it stops changing."
                ],
                escalationBullets: [
                    "If the router UI lists multiple copies of the same device, delete stale target entries before re-testing."
                ]
            ),
            RouterPortForwardTroubleshootingRule(
                id: "wrong-device",
                topicID: .wrongDevice,
                title: "Wrong target device selected",
                allOf: [
                    .init(symptom: .cannotConnectExternally, weight: 3)
                ],
                anyOf: [
                    .init(symptom: .selectedWrongTargetDevice, weight: 5),
                    .init(symptom: .bedrockWorksJavaFails, weight: 2),
                    .init(symptom: .javaWorksBedrockFails, weight: 2)
                ],
                excludedSymptoms: [],
                explanation: "A correct port number still fails if the rule targets the wrong machine on the LAN.",
                nextActions: [
                    "Confirm the selected target device is the Mac running Minecraft Server Controller.",
                    "Match the target device entry to the local IP shown in the app.",
                    "Remove duplicate rules that still point to older devices."
                ],
                escalationBullets: []
            ),
            RouterPortForwardTroubleshootingRule(
                id: "wrong-router",
                topicID: .wrongRouter,
                title: "Wrong router configured",
                allOf: [
                    .init(symptom: .cannotConnectExternally, weight: 3)
                ],
                anyOf: [
                    .init(symptom: .forwardedOnProviderButOwnRouterExists, weight: 4),
                    .init(symptom: .forwardedOnOwnRouterButProviderGatewayExists, weight: 4),
                    .init(symptom: .usingMeshBridgeOrAPMode, weight: 3)
                ],
                excludedSymptoms: [],
                explanation: "The provider name is not always the device that actually holds the routing table.",
                nextActions: [
                    "Identify which device is assigning LAN IP addresses and acting as the main router.",
                    "If your mesh or own router is in bridge / AP mode, make the rule on the upstream router instead.",
                    "If your ISP device is bridged, configure forwarding only on your own router."
                ],
                escalationBullets: [
                    "When in doubt, compare the LAN IP ranges and DHCP clients shown by each device."
                ]
            ),
            RouterPortForwardTroubleshootingRule(
                id: "double-nat",
                topicID: .doubleNAT,
                title: "Double NAT or multiple routers",
                allOf: [
                    .init(symptom: .cannotConnectExternally, weight: 3)
                ],
                anyOf: [
                    .init(symptom: .twoRoutersPresent, weight: 5),
                    .init(symptom: .forwardedOnProviderButOwnRouterExists, weight: 3),
                    .init(symptom: .forwardedOnOwnRouterButProviderGatewayExists, weight: 3),
                    .init(symptom: .usingMeshBridgeOrAPMode, weight: 2)
                ],
                excludedSymptoms: [],
                explanation: "Two routing layers often mean forwarding was only done on one layer, so the connection still cannot reach the host Mac.",
                nextActions: [
                    "Check whether both the ISP device and another router or mesh system are routing.",
                    "Put one device into bridge / passthrough mode when possible.",
                    "Otherwise forward on the upstream router as well."
                ],
                escalationBullets: [
                    "If the WAN IP of your own router is private, there is definitely another upstream routing layer."
                ]
            ),
            RouterPortForwardTroubleshootingRule(
                id: "cgnat",
                topicID: .cgnat,
                title: "Carrier-grade NAT or blocked public IPv4",
                allOf: [
                    .init(symptom: .cannotConnectExternally, weight: 3)
                ],
                anyOf: [
                    .init(symptom: .wanIPDiffersFromPublicIP, weight: 6),
                    .init(symptom: .apartmentDormManagedNetwork, weight: 3)
                ],
                excludedSymptoms: [],
                explanation: "If your router never receives a real public IPv4 address, standard inbound forwarding may never work.",
                nextActions: [
                    "Compare the WAN IP on the router to the public IP seen on the internet.",
                    "Ask the ISP whether they offer a real public IP or bridgeable modem mode.",
                    "Use an alternative remote-access method if your network environment blocks direct forwarding."
                ],
                escalationBullets: []
            ),
            RouterPortForwardTroubleshootingRule(
                id: "firewall-blocked",
                topicID: .firewallBlocked,
                title: "Host firewall or security tool blocking traffic",
                allOf: [
                    .init(symptom: .cannotConnectExternally, weight: 3)
                ],
                anyOf: [
                    .init(symptom: .firewallPromptSeen, weight: 5),
                    .init(symptom: .securityToolMayBeBlocking, weight: 5),
                    .init(symptom: .localNetworkWorksButInternetFails, weight: 2)
                ],
                excludedSymptoms: [],
                explanation: "A correct router rule still fails if the host Mac or another security layer rejects the traffic locally.",
                nextActions: [
                    "Verify the server is running and reachable on your LAN first.",
                    "Review macOS firewall permissions and any third-party security tools.",
                    "Re-test externally after confirming the host is accepting local traffic."
                ],
                escalationBullets: []
            ),
            RouterPortForwardTroubleshootingRule(
                id: "wrong-protocol",
                topicID: .wrongProtocol,
                title: "Wrong protocol or wrong service rule",
                allOf: [
                    .init(symptom: .cannotConnectExternally, weight: 3)
                ],
                anyOf: [
                    .init(symptom: .javaWorksBedrockFails, weight: 5),
                    .init(symptom: .bedrockWorksJavaFails, weight: 5)
                ],
                excludedSymptoms: [],
                explanation: "Java and Bedrock often need different protocol choices and sometimes separate rules.",
                nextActions: [
                    "Use TCP for Java unless your specific setup says otherwise.",
                    "Use UDP for Bedrock unless your specific setup says otherwise.",
                    "If both Java and Bedrock need to work, verify that both rules exist and point to the same host Mac."
                ],
                escalationBullets: []
            ),
            RouterPortForwardTroubleshootingRule(
                id: "router-reboot",
                topicID: .routerRebootRequired,
                title: "Router has not applied the rule yet",
                allOf: [
                    .init(symptom: .changesSavedButStillFails, weight: 3)
                ],
                anyOf: [
                    .init(symptom: .routerAskedToReboot, weight: 5),
                    .init(symptom: .cannotConnectExternally, weight: 1)
                ],
                excludedSymptoms: [],
                explanation: "Some firmware does not activate the new forwarding rule immediately after you edit it.",
                nextActions: [
                    "Press Save or Apply in the forwarding page.",
                    "If the router requested a reboot, complete it and wait for the network to come back.",
                    "Run the external test again after the router is fully online."
                ],
                escalationBullets: []
            ),
            RouterPortForwardTroubleshootingRule(
                id: "no-admin-access",
                topicID: .noAdminAccess,
                title: "Admin access or network policy blocks forwarding",
                allOf: [],
                anyOf: [
                    .init(symptom: .noRouterAdminAccess, weight: 6),
                    .init(symptom: .apartmentDormManagedNetwork, weight: 5)
                ],
                excludedSymptoms: [],
                explanation: "Some networks simply do not permit user-managed forwarding.",
                nextActions: [
                    "Check whether you have the router admin credentials.",
                    "Ask the ISP, property manager, or network owner whether inbound forwarding is allowed.",
                    "Use another remote-access path when the network policy blocks direct inbound rules."
                ],
                escalationBullets: [
                    "This is especially common on apartment, dorm, campus, and shared-building networks."
                ]
            )
        ]
    }
}

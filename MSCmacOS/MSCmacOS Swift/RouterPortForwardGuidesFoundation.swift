import Foundation

//
//  RouterPortForwardGuidesFoundation.swift
//  MinecraftServerController
//
//  Foundation layer for the Router Port Forwarding Guides feature.
//  Contains only domain models, validation logic, and V1 seed data.
//  No UI, AppConfig schema changes, or repository wiring live here.
//

// MARK: - Catalog

struct RouterPortForwardGuideCatalog: Codable, Equatable {
    var schemaVersion: Int
    var guides: [RouterPortForwardGuide]
    var troubleshootingTopics: [RouterGuideTroubleshootingTopic]

    static let v1Seed = RouterPortForwardGuideCatalog(
        schemaVersion: 1,
        guides: RouterPortForwardGuideSeedData.v1Guides,
        troubleshootingTopics: RouterPortForwardGuideSeedData.v1TroubleshootingTopics
    )
}

// MARK: - Guide core types

enum RouterGuideCategory: String, Codable, CaseIterable {
    case ispGateway = "isp_gateway"
    case retailRouter = "retail_router"
    case meshSystem = "mesh_system"
    case genericFallback = "generic_fallback"
    case advancedNetworking = "advanced_networking"
}

enum RouterGuideFamily: String, Codable, CaseIterable {
    case genericRouter = "generic_router"
    case genericMesh = "generic_mesh"
    case unknownRouter = "unknown_router"
    case xfinityGateway = "xfinity_gateway"
    case spectrumGateway = "spectrum_gateway"
    case attGateway = "att_gateway"
    case fiosRouter = "fios_router"
    case coxGateway = "cox_gateway"
    case asus = "asus"
    case tpLink = "tp_link"
    case netgear = "netgear"
    case linksys = "linksys"
    case eero = "eero"
    case googleNest = "google_nest"
    case advancedTroubleshooting = "advanced_troubleshooting"
}

enum RouterGuideConfidence: String, Codable, CaseIterable {
    case verifiedRecently = "verified_recently"
    case commonFlow = "common_flow"
    case olderInterfaceMayVary = "older_interface_may_vary"
    case communityBased = "community_based"

    var displayName: String {
        switch self {
        case .verifiedRecently: return "Verified recently"
        case .commonFlow: return "Common flow"
        case .olderInterfaceMayVary: return "Older interface, may vary"
        case .communityBased: return "Community-based guidance"
        }
    }
}

enum RouterGuideAdminSurface: String, Codable, CaseIterable {
    case webBrowser = "web_browser"
    case mobileApp = "mobile_app"
    case either = "either"
}

enum RouterGuideStepKind: String, Codable, CaseIterable {
    case intro = "intro"
    case prerequisite = "prerequisite"
    case navigate = "navigate"
    case input = "input"
    case save = "save"
    case test = "test"
    case warning = "warning"
}

enum RouterGuideToken: String, Codable, CaseIterable {
    case selectedServerName = "selected_server_name"
    case detectedLocalIPAddress = "detected_local_ip_address"
    case detectedGatewayIPAddress = "detected_gateway_ip_address"
    case javaPort = "java_port"
    case bedrockPort = "bedrock_port"
    case recommendedProtocol = "recommended_protocol"
    case bedrockEnabled = "bedrock_enabled"
}

enum RouterGuideTroubleshootingTopicID: String, Codable, CaseIterable {
    case localIPChanged = "local_ip_changed"
    case doubleNAT = "double_nat"
    case cgnat = "cgnat"
    case wrongRouter = "wrong_router"
    case wrongDevice = "wrong_device"
    case firewallBlocked = "firewall_blocked"
    case wrongProtocol = "wrong_protocol"
    case routerRebootRequired = "router_reboot_required"
    case noAdminAccess = "no_admin_access"
}

struct RouterPortForwardGuide: Codable, Equatable, Identifiable {
    var id: String
    var displayName: String
    var category: RouterGuideCategory
    var family: RouterGuideFamily

    /// Search aliases for later matching/ranking phases.
    /// Includes provider names, product lines, model nicknames, and common user phrasing.
    var searchKeywords: [String]

    /// Common admin entry addresses surfaced to the user.
    /// These are guidance hints, not authoritative network discovery results.
    var adminAddresses: [String]

    /// Whether the router is usually configured in a browser, app, or either.
    var adminSurface: RouterGuideAdminSurface

    /// Ordered navigation breadcrumb shown as the likely path to the forwarding page.
    var menuPath: [String]

    /// Alternate labels vendors may use for the same area.
    var alternateMenuNames: [String]

    /// The primary actionable steps for this guide.
    var steps: [RouterGuideStep]

    /// Short notes / caveats / known quirks.
    var notes: [RouterGuideNote]

    /// References into the shared troubleshooting system.
    var troubleshooting: [RouterGuideTroubleshootingTopicID]

    /// Shared content hooks for later composition phases.
    var sharedSections: RouterGuideSharedSections

    /// Source-confidence + review metadata required by the PRD.
    var review: RouterGuideReviewMetadata

    /// Optional provider label shown separately from device family.
    /// This supports the PRD requirement to distinguish ISP from the actual router being configured.
    var providerDisplayName: String?

    /// Optional device / family label for clearer matching and display.
    var deviceDisplayName: String?
}

struct RouterGuideStep: Codable, Equatable, Identifiable {
    var id: String
    var kind: RouterGuideStepKind
    var title: String
    var body: String

    /// Tokens referenced by this step body for future runtime injection.
    var referencedTokens: [RouterGuideToken]

    /// Optional vendor-specific menu aliases relevant to this step.
    var alternateTerms: [String]
}

struct RouterGuideNote: Codable, Equatable, Identifiable {
    var id: String
    var title: String?
    var body: String
}

struct RouterGuideSharedSections: Codable, Equatable {
    var includeSharedIntro: Bool
    var includeSharedPrerequisites: Bool
    var includeSharedValueSummary: Bool
    var includeSharedTroubleshootingFooter: Bool
}

struct RouterGuideReviewMetadata: Codable, Equatable {
    var sourceConfidence: RouterGuideConfidence
    var lastReviewed: String?
    var reviewNotes: String?
}

struct RouterGuideTroubleshootingTopic: Codable, Equatable, Identifiable {
    var id: RouterGuideTroubleshootingTopicID
    var title: String
    var summary: String
    var suggestedNextActions: [String]
}

// MARK: - Validation

enum RouterPortForwardGuideValidationIssue: Equatable {
    case catalogHasNoGuides
    case duplicateGuideID(String)
    case duplicateTroubleshootingID(String)
    case emptyDisplayName(String)
    case emptySearchKeywords(String)
    case duplicateSearchKeyword(guideID: String, keyword: String)
    case invalidAdminAddress(guideID: String, value: String)
    case guideHasNoSteps(String)
    case guideHasNoTroubleshootingReferences(String)
    case invalidStep(guideID: String, stepID: String)
    case duplicateStepID(guideID: String, stepID: String)
    case invalidReviewDate(guideID: String, value: String)
}

enum RouterPortForwardGuideValidator {

    static func validate(_ catalog: RouterPortForwardGuideCatalog) -> [RouterPortForwardGuideValidationIssue] {
        var issues: [RouterPortForwardGuideValidationIssue] = []

        if catalog.guides.isEmpty {
            issues.append(.catalogHasNoGuides)
        }

        var seenGuideIDs = Set<String>()
        for guide in catalog.guides {
            if !seenGuideIDs.insert(guide.id).inserted {
                issues.append(.duplicateGuideID(guide.id))
            }

            if guide.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.emptyDisplayName(guide.id))
            }

            if guide.searchKeywords.isEmpty {
                issues.append(.emptySearchKeywords(guide.id))
            }

            var seenKeywords = Set<String>()
            for keyword in guide.searchKeywords {
                let normalized = keyword.normalizedRouterGuideKeyword
                if normalized.isEmpty {
                    issues.append(.emptySearchKeywords(guide.id))
                    continue
                }
                if !seenKeywords.insert(normalized).inserted {
                    issues.append(.duplicateSearchKeyword(guideID: guide.id, keyword: normalized))
                }
            }

            for address in guide.adminAddresses {
                if !Self.isLikelyAdminAddress(address) {
                    issues.append(.invalidAdminAddress(guideID: guide.id, value: address))
                }
            }

            if guide.steps.isEmpty {
                issues.append(.guideHasNoSteps(guide.id))
            }

            if guide.troubleshooting.isEmpty {
                issues.append(.guideHasNoTroubleshootingReferences(guide.id))
            }

            var seenStepIDs = Set<String>()
            for step in guide.steps {
                let title = step.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let body = step.body.trimmingCharacters(in: .whitespacesAndNewlines)
                if title.isEmpty || body.isEmpty {
                    issues.append(.invalidStep(guideID: guide.id, stepID: step.id))
                }
                if !seenStepIDs.insert(step.id).inserted {
                    issues.append(.duplicateStepID(guideID: guide.id, stepID: step.id))
                }
            }

            if let lastReviewed = guide.review.lastReviewed,
               !lastReviewed.isEmpty,
               ISO8601DateFormatter().date(from: lastReviewed) == nil {
                issues.append(.invalidReviewDate(guideID: guide.id, value: lastReviewed))
            }
        }

        var seenTroubleshootingIDs = Set<String>()
        for topic in catalog.troubleshootingTopics {
            let raw = topic.id.rawValue
            if !seenTroubleshootingIDs.insert(raw).inserted {
                issues.append(.duplicateTroubleshootingID(raw))
            }
        }

        return issues
    }

    private static func isLikelyAdminAddress(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return true
        }
        if trimmed.split(separator: ".").count == 4 {
            return true
        }
        return false
    }
}

private extension String {
    var normalizedRouterGuideKeyword: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
    }
}

// MARK: - V1 seed data

enum RouterPortForwardGuideSeedData {
    static let v1Guides: [RouterPortForwardGuide] = [
        genericRouterGuide,
        genericMeshGuide,
        xfinityGatewayGuide,
        spectrumGatewayGuide,
        attGatewayGuide,
        fiosRouterGuide,
        coxGatewayGuide,
        asusGuide,
        tpLinkGuide,
        netgearGuide,
        linksysGuide,
        eeroGuide,
        googleNestGuide,
        genericTroubleshootingGuide
    ]

    static let v1TroubleshootingTopics: [RouterGuideTroubleshootingTopic] = [
        RouterGuideTroubleshootingTopic(
            id: .localIPChanged,
            title: "Your Mac's local IP changed",
            summary: "Your router may still be forwarding to an old device address.",
            suggestedNextActions: [
                "Check the Mac's current local IP in the app.",
                "Update the router rule so it points to the current local IP.",
                "Reserve the Mac's IP in the router later so it stops changing."
            ]
        ),
        RouterGuideTroubleshootingTopic(
            id: .doubleNAT,
            title: "You may be behind two routers",
            summary: "Port forwarding on the wrong router will not expose the server to the internet.",
            suggestedNextActions: [
                "Check whether your ISP device and your own router are both doing routing.",
                "If possible, put one device into bridge / passthrough mode.",
                "Otherwise forward on the upstream router as well."
            ]
        ),
        RouterGuideTroubleshootingTopic(
            id: .cgnat,
            title: "Your ISP may be using CGNAT",
            summary: "Some internet plans do not give you a public IPv4 address you can forward through.",
            suggestedNextActions: [
                "Compare the router WAN IP with your public IP.",
                "Ask the ISP whether they offer a public IP option.",
                "Use an alternative remote-access method if needed."
            ]
        ),
        RouterGuideTroubleshootingTopic(
            id: .wrongRouter,
            title: "You configured the wrong device",
            summary: "The provider name is not always the router actually doing the routing.",
            suggestedNextActions: [
                "Find which device is acting as the main router.",
                "If you use mesh, open the mesh app first.",
                "If your own router is connected to ISP hardware, configure the router that owns the LAN."
            ]
        ),
        RouterGuideTroubleshootingTopic(
            id: .wrongDevice,
            title: "The port forward may point to the wrong target device",
            summary: "The rule must target the Mac that is hosting Minecraft Server Controller.",
            suggestedNextActions: [
                "Confirm the selected target device matches the host Mac.",
                "Use the detected local IP from the app when possible.",
                "Delete duplicate rules that point to old devices."
            ]
        ),
        RouterGuideTroubleshootingTopic(
            id: .firewallBlocked,
            title: "The Mac firewall or another filter may still be blocking traffic",
            summary: "A correct router rule is not enough if the host still rejects inbound traffic.",
            suggestedNextActions: [
                "Verify the server is running and reachable on the local network first.",
                "Review macOS firewall or security-tool rules.",
                "Re-test from outside your network after confirming local connectivity."
            ]
        ),
        RouterGuideTroubleshootingTopic(
            id: .wrongProtocol,
            title: "The protocol may be wrong",
            summary: "Java usually needs TCP 25565. Bedrock usually needs UDP 19132.",
            suggestedNextActions: [
                "Confirm which game mode you are exposing.",
                "Use TCP for Java and UDP for Bedrock unless your specific setup says otherwise.",
                "Check whether both Java and Bedrock need separate rules."
            ]
        ),
        RouterGuideTroubleshootingTopic(
            id: .routerRebootRequired,
            title: "The router may need a save/apply cycle or reboot",
            summary: "Some firmware does not activate the new rule immediately.",
            suggestedNextActions: [
                "Press Save / Apply in the forwarding page.",
                "If the router asks to reboot, do it.",
                "Re-test after the router is fully back online."
            ]
        ),
        RouterGuideTroubleshootingTopic(
            id: .noAdminAccess,
            title: "You may not have permission to change router settings",
            summary: "Some ISP, dorm, apartment, or managed-network environments lock down forwarding.",
            suggestedNextActions: [
                "Check whether you have the router admin login.",
                "Ask the network owner or ISP whether forwarding is allowed.",
                "Use a fallback remote-access solution if direct forwarding is blocked."
            ]
        )
    ]

    private static let genericRouterGuide = RouterPortForwardGuide(
        id: "generic-router",
        displayName: "Generic Router Guide",
        category: .genericFallback,
        family: .genericRouter,
        searchKeywords: ["generic router", "router", "port forwarding", "nat forwarding", "virtual server", "applications and gaming"],
        adminAddresses: ["192.168.1.1", "192.168.0.1", "10.0.0.1"],
        adminSurface: .webBrowser,
        menuPath: ["Login", "Advanced", "Port Forwarding"],
        alternateMenuNames: ["NAT Forwarding", "Virtual Server", "Applications & Gaming", "Firewall Rules", "Port Rules", "Advanced NAT"],
        steps: [
            RouterGuideStep(
                id: "generic-step-1",
                kind: .intro,
                title: "Get the values you need first",
                body: "Before changing the router, note the host Mac's local IP, the Java port, and the Bedrock port if Bedrock is enabled.",
                referencedTokens: [.detectedLocalIPAddress, .javaPort, .bedrockPort, .bedrockEnabled],
                alternateTerms: []
            ),
            RouterGuideStep(
                id: "generic-step-2",
                kind: .navigate,
                title: "Log into the router",
                body: "Open the router admin page in a browser. Common addresses include 192.168.1.1, 192.168.0.1, and 10.0.0.1. Exact screens vary by firmware.",
                referencedTokens: [],
                alternateTerms: ["Gateway", "Admin", "Router Login"]
            ),
            RouterGuideStep(
                id: "generic-step-3",
                kind: .navigate,
                title: "Find the forwarding section",
                body: "Look for Port Forwarding, NAT Forwarding, Virtual Server, Applications & Gaming, Firewall Rules, or Advanced NAT.",
                referencedTokens: [],
                alternateTerms: ["Port Forwarding", "NAT Forwarding", "Virtual Server", "Applications & Gaming"]
            ),
            RouterGuideStep(
                id: "generic-step-4",
                kind: .input,
                title: "Create the rule",
                body: "Target the host Mac's local IP. For Java, forward TCP on the configured Java port. If Bedrock is enabled, also forward UDP on the configured Bedrock port.",
                referencedTokens: [.detectedLocalIPAddress, .javaPort, .bedrockPort, .recommendedProtocol, .bedrockEnabled],
                alternateTerms: ["Internal IP", "Device", "LAN IP", "Server IP"]
            ),
            RouterGuideStep(
                id: "generic-step-5",
                kind: .save,
                title: "Save or apply the change",
                body: "Save the new rule, apply changes, and reboot the router only if the firmware asks for it.",
                referencedTokens: [],
                alternateTerms: ["Apply", "Submit"]
            ),
            RouterGuideStep(
                id: "generic-step-6",
                kind: .test,
                title: "Test from outside your network",
                body: "After the rule is saved, test from a different network. If it still fails, continue into troubleshooting instead of guessing.",
                referencedTokens: [],
                alternateTerms: []
            )
        ],
        notes: [
            RouterGuideNote(id: "generic-note-1", title: "Transparency", body: "Exact labels and screens vary by firmware version and router vendor."),
            RouterGuideNote(id: "generic-note-2", title: "ISP vs router", body: "Your internet provider name is not always the device you configure. You may have ISP hardware plus your own router.")
        ],
        troubleshooting: [.localIPChanged, .wrongRouter, .wrongDevice, .wrongProtocol, .doubleNAT, .cgnat, .firewallBlocked, .routerRebootRequired],
        sharedSections: RouterGuideSharedSections(
            includeSharedIntro: true,
            includeSharedPrerequisites: true,
            includeSharedValueSummary: true,
            includeSharedTroubleshootingFooter: true
        ),
        review: RouterGuideReviewMetadata(
            sourceConfidence: .commonFlow,
            lastReviewed: "2026-03-17T00:00:00Z",
            reviewNotes: "Fallback family-level guidance. Labels vary widely by vendor."
        ),
        providerDisplayName: nil,
        deviceDisplayName: "Generic Router"
    )

    private static let xfinityGatewayGuide = RouterPortForwardGuide(
        id: "xfinity-gateway",
        displayName: "Xfinity Gateway",
        category: .ispGateway,
        family: .xfinityGateway,
        searchKeywords: ["xfinity", "comcast", "xfi", "xb6", "xb7", "xb8", "xfinity gateway"],
        adminAddresses: ["10.0.0.1", "http://10.0.0.1"],
        adminSurface: .either,
        menuPath: ["xFi app or 10.0.0.1", "Advanced", "Port Forwarding"],
        alternateMenuNames: ["xFi", "Gateway", "Advanced Security"],
        steps: [
            RouterGuideStep(
                id: "xfinity-step-1",
                kind: .prerequisite,
                title: "Confirm you are using the Xfinity gateway itself",
                body: "If you also have your own router or mesh system, the forwarding rule may belong there instead.",
                referencedTokens: [],
                alternateTerms: []
            ),
            RouterGuideStep(
                id: "xfinity-step-2",
                kind: .navigate,
                title: "Open xFi or log in to 10.0.0.1",
                body: "Use the Xfinity app first if that is how your gateway is managed. Otherwise try 10.0.0.1 in a browser.",
                referencedTokens: [],
                alternateTerms: ["xFi", "Gateway"]
            ),
            RouterGuideStep(
                id: "xfinity-step-3",
                kind: .navigate,
                title: "Go to the forwarding area",
                body: "Find the section for advanced network settings and port forwarding. Xfinity labels and availability can vary by gateway generation.",
                referencedTokens: [],
                alternateTerms: ["Advanced", "Port Forwarding", "Gateway Settings"]
            ),
            RouterGuideStep(
                id: "xfinity-step-4",
                kind: .input,
                title: "Select the host Mac and enter the port values",
                body: "Choose the Mac running Minecraft Server Controller. Forward TCP for the Java port. If Bedrock is enabled, also forward UDP for the Bedrock port.",
                referencedTokens: [.javaPort, .bedrockPort, .bedrockEnabled],
                alternateTerms: ["Device", "Connected Device"]
            ),
            RouterGuideStep(
                id: "xfinity-step-5",
                kind: .test,
                title: "Save and test externally",
                body: "Save the rule, then test from a different network. If you cannot find forwarding at all, you may be on a restricted or app-only gateway flow.",
                referencedTokens: [],
                alternateTerms: []
            )
        ],
        notes: [
            RouterGuideNote(id: "xfinity-note-1", title: "Common flow", body: "Xfinity gateway menus vary across XB6, XB7, and XB8 hardware revisions."),
            RouterGuideNote(id: "xfinity-note-2", title: "Restrictions", body: "If the app or gateway firmware hides forwarding, verify you are not in bridge mode and that another router is not actually doing routing.")
        ],
        troubleshooting: [.wrongRouter, .doubleNAT, .cgnat, .wrongProtocol, .noAdminAccess],
        sharedSections: RouterGuideSharedSections(
            includeSharedIntro: true,
            includeSharedPrerequisites: true,
            includeSharedValueSummary: true,
            includeSharedTroubleshootingFooter: true
        ),
        review: RouterGuideReviewMetadata(
            sourceConfidence: .commonFlow,
            lastReviewed: "2026-03-17T00:00:00Z",
            reviewNotes: "Provider gateway family guidance. Exact xFi flow may differ by region and hardware."
        ),
        providerDisplayName: "Xfinity / Comcast",
        deviceDisplayName: "Xfinity Gateway"
    )

    private static let spectrumGatewayGuide = RouterPortForwardGuide(
        id: "spectrum-gateway",
        displayName: "Spectrum Gateway",
        category: .ispGateway,
        family: .spectrumGateway,
        searchKeywords: ["spectrum", "charter", "charter spectrum", "spectrum router", "spectrum gateway", "sax1v1k", "rac2v1k"],
        adminAddresses: ["192.168.1.1", "192.168.0.1", "10.0.0.1", "https://www.spectrum.net"],
        adminSurface: .either,
        menuPath: ["Spectrum Advanced Settings", "Port Forwarding"],
        alternateMenuNames: ["My Spectrum app", "Spectrum.net", "NAT", "Firewall", "Port Forward", "Virtual Server"],
        steps: [
            RouterGuideStep(
                id: "spectrum-step-1",
                kind: .prerequisite,
                title: "Confirm the Spectrum gateway is the router doing the routing",
                body: "If you also use your own router or mesh system, the forwarding rule may belong there instead.",
                referencedTokens: [],
                alternateTerms: []
            ),
            RouterGuideStep(
                id: "spectrum-step-2",
                kind: .navigate,
                title: "Open Spectrum Advanced Settings",
                body: "Start in Spectrum.net or the My Spectrum app and open Advanced Settings before you begin.",
                referencedTokens: [],
                alternateTerms: ["Spectrum.net", "My Spectrum app", "Advanced Settings"]
            ),
            RouterGuideStep(
                id: "spectrum-step-3",
                kind: .navigate,
                title: "Find the forwarding section",
                body: "Look for Port Forwarding first. Depending on the hardware or firmware, you may also see labels such as NAT, Firewall, Port Forward, or Virtual Server.",
                referencedTokens: [],
                alternateTerms: ["Port Forwarding", "NAT", "Firewall", "Virtual Server"]
            ),
            RouterGuideStep(
                id: "spectrum-step-4",
                kind: .input,
                title: "Create the Minecraft rule",
                body: "Target the Mac running Minecraft Server Controller using its local IP. Forward TCP for the Java port. If Bedrock is enabled, also add a separate UDP rule for the Bedrock port.",
                referencedTokens: [.detectedLocalIPAddress, .javaPort, .bedrockPort, .bedrockEnabled],
                alternateTerms: ["Device", "Internal IP", "LAN IP"]
            ),
            RouterGuideStep(
                id: "spectrum-step-5",
                kind: .test,
                title: "Save and test externally",
                body: "Save the changes, then test from outside your network. If forwarding options are missing, verify the Spectrum device is not bridged and that another router is not doing NAT instead.",
                referencedTokens: [],
                alternateTerms: ["Apply", "Save"]
            )
        ],
        notes: [
            RouterGuideNote(id: "spectrum-note-1", title: "Common flow", body: "Spectrum menus vary by hardware revision and firmware, but the overall forwarding process is usually similar."),
            RouterGuideNote(id: "spectrum-note-2", title: "Where to start", body: "Use Spectrum.net or the My Spectrum app for Advanced Settings when available before falling back to local admin addresses.")
        ],
        troubleshooting: [.wrongRouter, .wrongDevice, .doubleNAT, .wrongProtocol, .routerRebootRequired, .noAdminAccess],
        sharedSections: RouterGuideSharedSections(
            includeSharedIntro: true,
            includeSharedPrerequisites: true,
            includeSharedValueSummary: true,
            includeSharedTroubleshootingFooter: true
        ),
        review: RouterGuideReviewMetadata(
            sourceConfidence: .commonFlow,
            lastReviewed: "2026-03-18T00:00:00Z",
            reviewNotes: "Provider gateway family guidance for Spectrum-managed hardware. Exact menus vary by firmware and account management flow."
        ),
        providerDisplayName: "Spectrum / Charter",
        deviceDisplayName: "Spectrum Gateway"
    )

    private static let attGatewayGuide = RouterPortForwardGuide(
        id: "att-gateway",
        displayName: "AT&T Gateway",
        category: .ispGateway,
        family: .attGateway,
        searchKeywords: ["at&t", "att", "at and t", "att gateway", "at&t gateway", "bgw210", "bgw320", "5268ac", "u-verse"],
        adminAddresses: ["192.168.1.254", "http://192.168.1.254"],
        adminSurface: .webBrowser,
        menuPath: ["Gateway settings", "Firewall", "NAT/Gaming or Port Forwarding"],
        alternateMenuNames: ["Applications", "NAT/Gaming", "Firewall", "Custom Service"],
        steps: [
            RouterGuideStep(
                id: "att-step-1",
                kind: .prerequisite,
                title: "Confirm the AT&T gateway is handling routing",
                body: "If you also have a separate personal router behind the AT&T gateway, the forwarding rule may belong on that router instead.",
                referencedTokens: [],
                alternateTerms: []
            ),
            RouterGuideStep(
                id: "att-step-2",
                kind: .navigate,
                title: "Open your AT&T gateway settings in a browser",
                body: "Open the AT&T gateway settings page in a web browser before you begin. BGW210, BGW320, and older AT&T hardware may not present identical screens.",
                referencedTokens: [],
                alternateTerms: ["Gateway settings", "Gateway GUI"]
            ),
            RouterGuideStep(
                id: "att-step-3",
                kind: .navigate,
                title: "Go to Firewall and find the forwarding controls",
                body: "Look for Firewall first, then find NAT/Gaming, Applications, or another Port Forwarding-style section.",
                referencedTokens: [],
                alternateTerms: ["Firewall", "NAT/Gaming", "Applications", "Custom Service"]
            ),
            RouterGuideStep(
                id: "att-step-4",
                kind: .input,
                title: "Create and assign the Minecraft rule",
                body: "Create or select a custom service for Minecraft, then assign it to the Mac running Minecraft Server Controller. Use TCP for the Java port. If Bedrock is enabled, add a separate UDP rule for the Bedrock port.",
                referencedTokens: [.detectedLocalIPAddress, .javaPort, .bedrockPort, .bedrockEnabled],
                alternateTerms: ["Hosted Application", "Needed by Device", "Device List"]
            ),
            RouterGuideStep(
                id: "att-step-5",
                kind: .test,
                title: "Save and retest from outside your network",
                body: "Save the changes and test from a different network. If access still fails, double-check that you forwarded on the AT&T gateway and not only on a downstream router.",
                referencedTokens: [],
                alternateTerms: ["Apply", "Save"]
            )
        ],
        notes: [
            RouterGuideNote(id: "att-note-1", title: "Common flow", body: "AT&T gateways often use Firewall and NAT/Gaming language instead of the simpler labels found on many retail routers."),
            RouterGuideNote(id: "att-note-2", title: "Downstream routers", body: "AT&T setups commonly include a second router. If your own router is doing NAT, configure forwarding there instead.")
        ],
        troubleshooting: [.wrongRouter, .wrongDevice, .doubleNAT, .wrongProtocol, .routerRebootRequired, .noAdminAccess],
        sharedSections: RouterGuideSharedSections(
            includeSharedIntro: true,
            includeSharedPrerequisites: true,
            includeSharedValueSummary: true,
            includeSharedTroubleshootingFooter: true
        ),
        review: RouterGuideReviewMetadata(
            sourceConfidence: .commonFlow,
            lastReviewed: "2026-03-18T00:00:00Z",
            reviewNotes: "Provider gateway family guidance centered on AT&T BGW-family flows and similar gateway terminology."
        ),
        providerDisplayName: "AT&T",
        deviceDisplayName: "AT&T Gateway"
    )

    private static let fiosRouterGuide = RouterPortForwardGuide(
        id: "fios-router",
        displayName: "Fios Router",
        category: .ispGateway,
        family: .fiosRouter,
        searchKeywords: ["fios", "verizon", "verizon fios", "verizon router", "fios router", "g3100", "cr1000a", "cr1000b"],
        adminAddresses: ["192.168.1.1", "http://mynetworksettings.com", "http://192.168.1.1"],
        adminSurface: .webBrowser,
        menuPath: ["Router settings", "Firewall or Advanced", "Port Forwarding"],
        alternateMenuNames: ["Port Forwarding Rules", "Firewall", "NAT", "Applications"],
        steps: [
            RouterGuideStep(
                id: "fios-step-1",
                kind: .prerequisite,
                title: "Confirm the Fios router is the main router",
                body: "If Verizon internet is connected to your own personal router, the forwarding rule may belong on that router instead.",
                referencedTokens: [],
                alternateTerms: []
            ),
            RouterGuideStep(
                id: "fios-step-2",
                kind: .navigate,
                title: "Open your Fios router settings in a browser",
                body: "Open the Fios router settings page in a web browser before you begin. Different Verizon router generations may use different page layouts.",
                referencedTokens: [],
                alternateTerms: ["Router settings", "Admin page"]
            ),
            RouterGuideStep(
                id: "fios-step-3",
                kind: .navigate,
                title: "Find the forwarding area",
                body: "Go to Firewall, Advanced, or a similar settings area and look for Port Forwarding or Port Forwarding Rules.",
                referencedTokens: [],
                alternateTerms: ["Firewall", "Advanced", "Port Forwarding", "Port Forwarding Rules"]
            ),
            RouterGuideStep(
                id: "fios-step-4",
                kind: .input,
                title: "Create the Minecraft rule",
                body: "Target the Mac running Minecraft Server Controller. Add the Java port as TCP. If Bedrock is enabled, add a separate UDP rule for the Bedrock port.",
                referencedTokens: [.detectedLocalIPAddress, .javaPort, .bedrockPort, .bedrockEnabled],
                alternateTerms: ["Device", "IP Address", "Port Range"]
            ),
            RouterGuideStep(
                id: "fios-step-5",
                kind: .test,
                title: "Save, apply, and test externally",
                body: "Save the new rule, apply any pending changes, and test from another network. If forwarding appears unavailable, verify you are on the full router settings page and not a limited status page.",
                referencedTokens: [],
                alternateTerms: ["Apply", "Save"]
            )
        ],
        notes: [
            RouterGuideNote(id: "fios-note-1", title: "Common flow", body: "Fios menu wording varies by router generation and firmware, but Firewall and Port Forwarding labels are common anchors."),
            RouterGuideNote(id: "fios-note-2", title: "Use the actual router", body: "If the Verizon ONT feeds a separate personal router, configure forwarding on that router instead of the Fios-branded hardware.")
        ],
        troubleshooting: [.wrongRouter, .wrongDevice, .doubleNAT, .wrongProtocol, .routerRebootRequired, .noAdminAccess],
        sharedSections: RouterGuideSharedSections(
            includeSharedIntro: true,
            includeSharedPrerequisites: true,
            includeSharedValueSummary: true,
            includeSharedTroubleshootingFooter: true
        ),
        review: RouterGuideReviewMetadata(
            sourceConfidence: .commonFlow,
            lastReviewed: "2026-03-18T00:00:00Z",
            reviewNotes: "Provider router family guidance for Verizon Fios hardware and common web-based forwarding flows."
        ),
        providerDisplayName: "Verizon Fios",
        deviceDisplayName: "Fios Router"
    )

    private static let asusGuide = RouterPortForwardGuide(
        id: "asus-router",
        displayName: "ASUS Router",
        category: .retailRouter,
        family: .asus,
        searchKeywords: ["asus", "asus router", "rt-ax", "rt-ac", "rog router", "zenwifi"],
        adminAddresses: ["192.168.50.1", "http://router.asus.com", "http://192.168.50.1"],
        adminSurface: .either,
        menuPath: ["Login", "WAN", "Virtual Server / Port Forwarding"],
        alternateMenuNames: ["WAN", "Virtual Server", "Port Forwarding"],
        steps: [
            RouterGuideStep(
                id: "asus-step-1",
                kind: .navigate,
                title: "Open the ASUS router interface",
                body: "Use router.asus.com or the router's local IP in a browser. Some ASUS systems also expose these settings in the app.",
                referencedTokens: [],
                alternateTerms: ["ASUS Router app"]
            ),
            RouterGuideStep(
                id: "asus-step-2",
                kind: .navigate,
                title: "Go to WAN → Virtual Server / Port Forwarding",
                body: "ASUS commonly places forwarding under WAN rather than a general firewall section.",
                referencedTokens: [],
                alternateTerms: ["WAN", "Virtual Server"]
            ),
            RouterGuideStep(
                id: "asus-step-3",
                kind: .input,
                title: "Create the Minecraft rule",
                body: "Forward the Java port over TCP to the host Mac's local IP. Add a second UDP rule for the Bedrock port if Bedrock is enabled.",
                referencedTokens: [.detectedLocalIPAddress, .javaPort, .bedrockPort, .bedrockEnabled],
                alternateTerms: ["Local IP", "Port Range", "Internal Port"]
            ),
            RouterGuideStep(
                id: "asus-step-4",
                kind: .save,
                title: "Apply the configuration",
                body: "Click Apply and wait for the ASUS UI to finish saving.",
                referencedTokens: [],
                alternateTerms: ["Apply"]
            ),
            RouterGuideStep(
                id: "asus-step-5",
                kind: .test,
                title: "Test remote access",
                body: "Test from outside your network after the rule is active. If the rule exists but access still fails, check whether the ISP upstream device is still routing.",
                referencedTokens: [],
                alternateTerms: []
            )
        ],
        notes: [
            RouterGuideNote(id: "asus-note-1", title: "Firmware drift", body: "ASUSWRT layouts can differ between older RT models, newer AX models, and ZenWiFi systems."),
            RouterGuideNote(id: "asus-note-2", title: nil, body: "If your ASUS router sits behind ISP hardware, you may still need bridge mode or upstream forwarding.")
        ],
        troubleshooting: [.doubleNAT, .wrongDevice, .wrongProtocol, .firewallBlocked],
        sharedSections: RouterGuideSharedSections(
            includeSharedIntro: true,
            includeSharedPrerequisites: true,
            includeSharedValueSummary: true,
            includeSharedTroubleshootingFooter: true
        ),
        review: RouterGuideReviewMetadata(
            sourceConfidence: .olderInterfaceMayVary,
            lastReviewed: "2026-03-17T00:00:00Z",
            reviewNotes: "Family-level ASUSWRT guidance with known firmware variation."
        ),
        providerDisplayName: nil,
        deviceDisplayName: "ASUS Router"
    )

    private static let tpLinkGuide = RouterPortForwardGuide(
        id: "tp-link-router",
        displayName: "TP-Link Router / Deco",
        category: .retailRouter,
        family: .tpLink,
        searchKeywords: ["tp link", "tplink", "tp link router", "deco", "archer", "omada", "tp link deco", "tp link archer", "tp link omada"],
        adminAddresses: ["192.168.0.1", "192.168.1.1", "http://tplinkwifi.net", "http://192.168.0.1", "http://192.168.1.1"],
        adminSurface: .either,
        menuPath: ["TP-Link app or tplinkwifi.net", "Advanced", "NAT Forwarding / Port Forwarding"],
        alternateMenuNames: ["Deco app", "Archer", "Omada", "Virtual Servers", "Forwarding"],
        steps: [
            RouterGuideStep(
                id: "tp-link-step-1",
                kind: .prerequisite,
                title: "Confirm the TP-Link device is the router doing routing",
                body: "If your TP-Link system is in access point or bridge mode, or if an ISP gateway is still routing above it, the forward belongs on the upstream router instead.",
                referencedTokens: [],
                alternateTerms: ["Access Point Mode", "Bridge Mode"]
            ),
            RouterGuideStep(
                id: "tp-link-step-2",
                kind: .navigate,
                title: "Open the correct TP-Link management surface",
                body: "For Deco systems, start in the Deco app. For Archer routers, use the Tether app or tplinkwifi.net in a browser. For Omada setups, use the Omada controller or gateway interface.",
                referencedTokens: [],
                alternateTerms: ["Deco", "Tether", "tplinkwifi.net", "Omada"]
            ),
            RouterGuideStep(
                id: "tp-link-step-3",
                kind: .navigate,
                title: "Find the forwarding section",
                body: "Look under Advanced first, then find NAT Forwarding, Port Forwarding, Virtual Servers, or a similar forwarding section depending on whether you are in Deco, Archer, or Omada.",
                referencedTokens: [],
                alternateTerms: ["Advanced", "NAT Forwarding", "Virtual Servers", "Port Forwarding"]
            ),
            RouterGuideStep(
                id: "tp-link-step-4",
                kind: .input,
                title: "Create the Minecraft rule",
                body: "Target the Mac running Minecraft Server Controller using its local IP. Forward TCP for the Java port. If Bedrock is enabled, add a separate UDP rule for the Bedrock port.",
                referencedTokens: [.detectedLocalIPAddress, .javaPort, .bedrockPort, .bedrockEnabled],
                alternateTerms: ["Internal IP", "Device", "Client", "LAN IP"]
            ),
            RouterGuideStep(
                id: "tp-link-step-5",
                kind: .test,
                title: "Save and test from another network",
                body: "Save or apply the new rule and test from outside your network. If the port still stays closed, verify that the TP-Link device is not only acting as an access point under another router.",
                referencedTokens: [],
                alternateTerms: ["Save", "Apply"]
            )
        ],
        notes: [
            RouterGuideNote(id: "tp-link-note-1", title: "Family coverage", body: "This guide covers TP-Link Archer routers, Deco systems, and Omada-family forwarding paths at a family level rather than exact-model screenshots."),
            RouterGuideNote(id: "tp-link-note-2", title: "App vs browser", body: "Deco is often app-first, while Archer and Omada commonly expose forwarding in browser-based management as well.")
        ],
        troubleshooting: [.wrongRouter, .doubleNAT, .wrongDevice, .wrongProtocol, .firewallBlocked],
        sharedSections: RouterGuideSharedSections(
            includeSharedIntro: true,
            includeSharedPrerequisites: true,
            includeSharedValueSummary: true,
            includeSharedTroubleshootingFooter: true
        ),
        review: RouterGuideReviewMetadata(
            sourceConfidence: .commonFlow,
            lastReviewed: "2026-03-18T00:00:00Z",
            reviewNotes: "Family-level TP-Link guidance covering Archer, Deco, and Omada forwarding terminology."
        ),
        providerDisplayName: nil,
        deviceDisplayName: "TP-Link Router / Deco"
    )

    private static let netgearGuide = RouterPortForwardGuide(
        id: "netgear-router",
        displayName: "NETGEAR / Nighthawk / Orbi",
        category: .retailRouter,
        family: .netgear,
        searchKeywords: ["netgear", "netgear router", "nighthawk", "orbi", "night hawk", "orbi router", "orbi mesh"],
        adminAddresses: ["192.168.1.1", "192.168.0.1", "http://routerlogin.net", "http://192.168.1.1", "http://192.168.0.1"],
        adminSurface: .either,
        menuPath: ["Nighthawk / Orbi app or routerlogin.net", "Advanced", "Port Forwarding / Port Triggering"],
        alternateMenuNames: ["Nighthawk app", "Orbi app", "Advanced Setup", "Port Triggering", "WAN Setup"],
        steps: [
            RouterGuideStep(
                id: "netgear-step-1",
                kind: .prerequisite,
                title: "Confirm the NETGEAR device is the router doing routing",
                body: "If Orbi or another NETGEAR system is in access point mode, or if an ISP gateway is still routing above it, create the forward on the actual upstream router instead.",
                referencedTokens: [],
                alternateTerms: ["Access Point Mode", "Bridge Mode"]
            ),
            RouterGuideStep(
                id: "netgear-step-2",
                kind: .navigate,
                title: "Open the correct NETGEAR management surface",
                body: "Use the Nighthawk or Orbi app if you manage the network by app, or log in through routerlogin.net or the router's local IP in a browser.",
                referencedTokens: [],
                alternateTerms: ["Nighthawk", "Orbi", "routerlogin.net"]
            ),
            RouterGuideStep(
                id: "netgear-step-3",
                kind: .navigate,
                title: "Go to the forwarding controls",
                body: "Look under Advanced or Advanced Setup for Port Forwarding / Port Triggering. Some models place related WAN options nearby, but you want the actual forwarding page.",
                referencedTokens: [],
                alternateTerms: ["Advanced", "Advanced Setup", "Port Forwarding / Port Triggering", "WAN Setup"]
            ),
            RouterGuideStep(
                id: "netgear-step-4",
                kind: .input,
                title: "Create the Minecraft rule",
                body: "Point the rule to the Mac running Minecraft Server Controller. Forward TCP for the Java port. If Bedrock is enabled, add a separate UDP rule for the Bedrock port.",
                referencedTokens: [.detectedLocalIPAddress, .javaPort, .bedrockPort, .bedrockEnabled],
                alternateTerms: ["Service Name", "Server IP Address", "Internal IP"]
            ),
            RouterGuideStep(
                id: "netgear-step-5",
                kind: .test,
                title: "Apply and test from outside your network",
                body: "Save or apply the new rule, then test from another network. If access still fails, verify that the NETGEAR device is not in access point mode and that no ISP gateway is still doing the real NAT.",
                referencedTokens: [],
                alternateTerms: ["Apply", "Save"]
            )
        ],
        notes: [
            RouterGuideNote(id: "netgear-note-1", title: "Family coverage", body: "This guide covers NETGEAR routers, Nighthawk models, and Orbi systems as a family guide rather than exact-model instructions."),
            RouterGuideNote(id: "netgear-note-2", title: "App vs browser", body: "Nighthawk and Orbi can be app-managed, but many forwarding options are still easiest to confirm in the browser interface.")
        ],
        troubleshooting: [.wrongRouter, .doubleNAT, .wrongDevice, .wrongProtocol, .firewallBlocked],
        sharedSections: RouterGuideSharedSections(
            includeSharedIntro: true,
            includeSharedPrerequisites: true,
            includeSharedValueSummary: true,
            includeSharedTroubleshootingFooter: true
        ),
        review: RouterGuideReviewMetadata(
            sourceConfidence: .commonFlow,
            lastReviewed: "2026-03-18T00:00:00Z",
            reviewNotes: "Family-level NETGEAR guidance covering Nighthawk and Orbi forwarding paths."
        ),
        providerDisplayName: nil,
        deviceDisplayName: "NETGEAR / Nighthawk / Orbi"
    )

    private static let eeroGuide = RouterPortForwardGuide(
        id: "eero-mesh",
        displayName: "eero",
        category: .meshSystem,
        family: .eero,
        searchKeywords: ["eero", "eero pro", "eero mesh", "mesh wifi", "app managed router"],
        adminAddresses: [],
        adminSurface: .mobileApp,
        menuPath: ["eero app", "Settings", "Reservations & Port Forwarding"],
        alternateMenuNames: ["Reservations & Port Forwarding", "Network Settings"],
        steps: [
            RouterGuideStep(
                id: "eero-step-1",
                kind: .prerequisite,
                title: "Confirm eero is the router doing routing",
                body: "If eero is in bridge mode, the forwarding rule belongs on the upstream router instead.",
                referencedTokens: [],
                alternateTerms: ["Bridge mode"]
            ),
            RouterGuideStep(
                id: "eero-step-2",
                kind: .navigate,
                title: "Open the eero app",
                body: "eero is app-managed first. Open the eero app and go to the network settings area.",
                referencedTokens: [],
                alternateTerms: ["eero app"]
            ),
            RouterGuideStep(
                id: "eero-step-3",
                kind: .navigate,
                title: "Find Reservations & Port Forwarding",
                body: "Open Settings, then Network Settings, then Reservations & Port Forwarding.",
                referencedTokens: [],
                alternateTerms: ["Network Settings", "Reservations & Port Forwarding"]
            ),
            RouterGuideStep(
                id: "eero-step-4",
                kind: .input,
                title: "Select the host Mac and enter the port",
                body: "Choose the Mac running Minecraft Server Controller. Add a TCP rule for the Java port and a UDP rule for the Bedrock port if Bedrock is enabled.",
                referencedTokens: [.javaPort, .bedrockPort, .bedrockEnabled],
                alternateTerms: ["Reservation", "Device", "Forward"]
            ),
            RouterGuideStep(
                id: "eero-step-5",
                kind: .test,
                title: "Save and test",
                body: "Save the rule and test from a different network. If nothing works, check whether the ISP modem/router is still doing routing above eero.",
                referencedTokens: [],
                alternateTerms: []
            )
        ],
        notes: [
            RouterGuideNote(id: "eero-note-1", title: "App-first flow", body: "eero users often think of the network by app name rather than router model. Matching should preserve that later."),
            RouterGuideNote(id: "eero-note-2", title: nil, body: "If eero is in bridge mode, port forwarding must be configured elsewhere.")
        ],
        troubleshooting: [.wrongRouter, .doubleNAT, .wrongDevice, .wrongProtocol],
        sharedSections: RouterGuideSharedSections(
            includeSharedIntro: true,
            includeSharedPrerequisites: true,
            includeSharedValueSummary: true,
            includeSharedTroubleshootingFooter: true
        ),
        review: RouterGuideReviewMetadata(
            sourceConfidence: .commonFlow,
            lastReviewed: "2026-03-17T00:00:00Z",
            reviewNotes: "App-first family guidance for eero mesh systems."
        ),
        providerDisplayName: nil,
        deviceDisplayName: "eero"
    )

    private static let genericMeshGuide = RouterPortForwardGuide(
        id: "generic-mesh",
        displayName: "Generic Mesh Wi-Fi System",
        category: .meshSystem,
        family: .genericMesh,
        searchKeywords: ["generic mesh", "mesh", "mesh wifi", "whole home wifi", "app managed router", "mesh system"],
        adminAddresses: [],
        adminSurface: .either,
        menuPath: ["Router app or admin page", "Advanced", "Port Forwarding"],
        alternateMenuNames: ["NAT Forwarding", "Virtual Server", "Reservations & Port Forwarding"],
        steps: [
            RouterGuideStep(
                id: "generic-mesh-step-1",
                kind: .prerequisite,
                title: "Confirm the mesh system is doing routing",
                body: "If the mesh is in bridge mode, access point mode, or passthrough mode, the forwarding rule belongs on the upstream router instead.",
                referencedTokens: [],
                alternateTerms: ["Bridge Mode", "Access Point Mode", "Passthrough"]
            ),
            RouterGuideStep(
                id: "generic-mesh-step-2",
                kind: .navigate,
                title: "Open the mesh app or admin page",
                body: "Most mesh products expose port forwarding in the mobile app first, though some also support a browser admin page.",
                referencedTokens: [],
                alternateTerms: ["App", "Admin Page"]
            ),
            RouterGuideStep(
                id: "generic-mesh-step-3",
                kind: .navigate,
                title: "Find the forwarding section",
                body: "Look for labels such as Port Forwarding, NAT Forwarding, Virtual Server, or Reservations & Port Forwarding.",
                referencedTokens: [],
                alternateTerms: ["Port Forwarding", "NAT Forwarding", "Virtual Server"]
            ),
            RouterGuideStep(
                id: "generic-mesh-step-4",
                kind: .input,
                title: "Target the Mac running the server",
                body: "Choose the Mac running {{selected_server_name}} and point the rule at {{detected_local_ip_address}}. Forward TCP for Java on {{java_port}}. If Bedrock is enabled, also add UDP for {{bedrock_port}}.",
                referencedTokens: [.selectedServerName, .detectedLocalIPAddress, .javaPort, .bedrockPort],
                alternateTerms: ["Device", "Client", "Reservation"]
            ),
            RouterGuideStep(
                id: "generic-mesh-step-5",
                kind: .test,
                title: "Save and test from another network",
                body: "Apply the rule, then test from outside your home network. If it still fails, check for upstream ISP routing or double NAT.",
                referencedTokens: [],
                alternateTerms: []
            )
        ],
        notes: [
            RouterGuideNote(id: "generic-mesh-note-1", title: "App-managed systems", body: "Mesh systems often hide advanced settings until you tap deeper into network or advanced menus."),
            RouterGuideNote(id: "generic-mesh-note-2", title: nil, body: "If your ISP device is still routing above the mesh, forwarding on the mesh alone will not expose the server.")
        ],
        troubleshooting: [.wrongRouter, .doubleNAT, .wrongDevice, .wrongProtocol],
        sharedSections: RouterGuideSharedSections(
            includeSharedIntro: true,
            includeSharedPrerequisites: true,
            includeSharedValueSummary: true,
            includeSharedTroubleshootingFooter: true
        ),
        review: RouterGuideReviewMetadata(
            sourceConfidence: .commonFlow,
            lastReviewed: "2026-03-17T00:00:00Z",
            reviewNotes: "Generic fallback for mesh systems where the exact product guide is unavailable."
        ),
        providerDisplayName: nil,
        deviceDisplayName: "Mesh Wi-Fi System"
    )

    private static let coxGatewayGuide = RouterPortForwardGuide(
        id: "cox-gateway",
        displayName: "Cox Panoramic WiFi Gateway",
        category: .ispGateway,
        family: .coxGateway,
        searchKeywords: ["cox", "cox panoramic", "panoramic wifi", "cox gateway", "pw3", "pw6"],
        adminAddresses: ["http://192.168.0.1", "http://192.168.1.1"],
        adminSurface: .either,
        menuPath: ["Panoramic WiFi app or gateway page", "Advanced", "Port Forwarding"],
        alternateMenuNames: ["Port Management", "Advanced Security", "NAT Forwarding"],
        steps: [
            RouterGuideStep(
                id: "cox-step-1",
                kind: .prerequisite,
                title: "Confirm the Cox gateway is the router",
                body: "If you use your own router or mesh behind the Cox hardware, the forwarding rule may belong there instead.",
                referencedTokens: [],
                alternateTerms: ["Bridge Mode"]
            ),
            RouterGuideStep(
                id: "cox-step-2",
                kind: .navigate,
                title: "Open the Panoramic WiFi app or gateway page",
                body: "Use the Cox app flow when available. Some gateway firmware also exposes forwarding in the local admin page.",
                referencedTokens: [],
                alternateTerms: ["Panoramic WiFi", "Gateway Settings"]
            ),
            RouterGuideStep(
                id: "cox-step-3",
                kind: .navigate,
                title: "Find Port Forwarding",
                body: "Open the advanced network settings and look for Port Forwarding or NAT-related controls.",
                referencedTokens: [],
                alternateTerms: ["Advanced", "NAT", "Port Management"]
            ),
            RouterGuideStep(
                id: "cox-step-4",
                kind: .input,
                title: "Create the Minecraft rule",
                body: "Forward TCP {{java_port}} to {{detected_local_ip_address}} for Java. If Bedrock is enabled, also create a UDP rule for {{bedrock_port}}.",
                referencedTokens: [.javaPort, .detectedLocalIPAddress, .bedrockPort],
                alternateTerms: ["Internal IP", "Device", "Protocol"]
            ),
            RouterGuideStep(
                id: "cox-step-5",
                kind: .test,
                title: "Save and test outside the network",
                body: "Apply the rule and test from another network. If the rule exists but remote access still fails, check upstream NAT, app restrictions, or security features.",
                referencedTokens: [],
                alternateTerms: []
            )
        ],
        notes: [
            RouterGuideNote(id: "cox-note-1", title: "ISP-managed behavior", body: "Cox firmware and app flows may vary by hardware revision and account features."),
            RouterGuideNote(id: "cox-note-2", title: nil, body: "If the forwarding screen is limited or missing, verify that the gateway is not bridged and that another router is not handling your LAN.")
        ],
        troubleshooting: [.wrongRouter, .doubleNAT, .wrongDevice, .wrongProtocol, .firewallBlocked],
        sharedSections: RouterGuideSharedSections(
            includeSharedIntro: true,
            includeSharedPrerequisites: true,
            includeSharedValueSummary: true,
            includeSharedTroubleshootingFooter: true
        ),
        review: RouterGuideReviewMetadata(
            sourceConfidence: .commonFlow,
            lastReviewed: "2026-03-17T00:00:00Z",
            reviewNotes: "Family-level guidance for Cox Panoramic gateways."
        ),
        providerDisplayName: "Cox",
        deviceDisplayName: "Panoramic WiFi Gateway"
    )

    private static let linksysGuide = RouterPortForwardGuide(
        id: "linksys-router",
        displayName: "Linksys / Velop",
        category: .retailRouter,
        family: .linksys,
        searchKeywords: ["linksys", "velop", "linksys velop", "velop mesh"],
        adminAddresses: ["http://192.168.1.1", "http://myrouter.local"],
        adminSurface: .either,
        menuPath: ["Linksys app or admin page", "Security", "Apps and Gaming", "Single Port Forwarding"],
        alternateMenuNames: ["Port Forwarding", "Apps and Gaming", "NAT"],
        steps: [
            RouterGuideStep(
                id: "linksys-step-1",
                kind: .navigate,
                title: "Open the Linksys app or admin page",
                body: "Some Linksys products use the mobile app first, while others expose the setting mainly in the browser admin page.",
                referencedTokens: [],
                alternateTerms: ["Linksys App", "myrouter.local"]
            ),
            RouterGuideStep(
                id: "linksys-step-2",
                kind: .navigate,
                title: "Find the forwarding section",
                body: "Look for Apps and Gaming, Port Forwarding, or Single Port Forwarding depending on model and firmware.",
                referencedTokens: [],
                alternateTerms: ["Apps and Gaming", "Single Port Forwarding"]
            ),
            RouterGuideStep(
                id: "linksys-step-3",
                kind: .input,
                title: "Add the Minecraft rule",
                body: "Forward TCP {{java_port}} to {{detected_local_ip_address}}. If Bedrock is enabled, add a UDP rule for {{bedrock_port}}.",
                referencedTokens: [.javaPort, .detectedLocalIPAddress, .bedrockPort],
                alternateTerms: ["Device IP", "Internal IP", "External Port"]
            ),
            RouterGuideStep(
                id: "linksys-step-4",
                kind: .save,
                title: "Save the changes",
                body: "Apply the rule and wait for the router to finish saving.",
                referencedTokens: [],
                alternateTerms: ["Apply", "Save"]
            ),
            RouterGuideStep(
                id: "linksys-step-5",
                kind: .test,
                title: "Test from outside the LAN",
                body: "Use another network to confirm the port is reachable after the rule is active.",
                referencedTokens: [],
                alternateTerms: []
            )
        ],
        notes: [
            RouterGuideNote(id: "linksys-note-1", title: "Model variation", body: "Classic Linksys routers and Velop systems do not always expose the same menu names."),
            RouterGuideNote(id: "linksys-note-2", title: nil, body: "If Velop is bridged behind ISP hardware, forwarding may need to happen upstream instead.")
        ],
        troubleshooting: [.wrongRouter, .doubleNAT, .wrongDevice, .wrongProtocol],
        sharedSections: RouterGuideSharedSections(
            includeSharedIntro: true,
            includeSharedPrerequisites: true,
            includeSharedValueSummary: true,
            includeSharedTroubleshootingFooter: true
        ),
        review: RouterGuideReviewMetadata(
            sourceConfidence: .olderInterfaceMayVary,
            lastReviewed: "2026-03-17T00:00:00Z",
            reviewNotes: "Family-level Linksys and Velop guidance."
        ),
        providerDisplayName: nil,
        deviceDisplayName: "Linksys / Velop"
    )

    private static let googleNestGuide = RouterPortForwardGuide(
        id: "google-nest",
        displayName: "Google Nest WiFi / Google WiFi",
        category: .meshSystem,
        family: .googleNest,
        searchKeywords: ["google nest", "google wifi", "nest wifi", "nest pro", "google nest wifi"],
        adminAddresses: [],
        adminSurface: .mobileApp,
        menuPath: ["Google Home app", "Wi-Fi", "Settings", "Advanced Networking", "Port Management"],
        alternateMenuNames: ["Advanced Networking", "Port Management", "Port Forwarding"],
        steps: [
            RouterGuideStep(
                id: "google-nest-step-1",
                kind: .prerequisite,
                title: "Confirm Google/Nest is routing",
                body: "If the system is bridged or another router sits upstream, forwarding belongs on the device that owns the LAN.",
                referencedTokens: [],
                alternateTerms: ["Bridge Mode"]
            ),
            RouterGuideStep(
                id: "google-nest-step-2",
                kind: .navigate,
                title: "Open the Google Home app",
                body: "Google WiFi and Nest WiFi forwarding is usually managed in the Google Home app rather than a traditional browser admin page.",
                referencedTokens: [],
                alternateTerms: ["Google Home", "Wi-Fi"]
            ),
            RouterGuideStep(
                id: "google-nest-step-3",
                kind: .navigate,
                title: "Go to Advanced Networking",
                body: "Open Wi-Fi settings, then Advanced Networking, then Port Management or the forwarding section.",
                referencedTokens: [],
                alternateTerms: ["Advanced Networking", "Port Management"]
            ),
            RouterGuideStep(
                id: "google-nest-step-4",
                kind: .input,
                title: "Create the Minecraft rule",
                body: "Choose the device running {{selected_server_name}} and forward TCP {{java_port}} to {{detected_local_ip_address}}. If Bedrock is enabled, also forward UDP {{bedrock_port}}.",
                referencedTokens: [.selectedServerName, .javaPort, .detectedLocalIPAddress, .bedrockPort],
                alternateTerms: ["Device", "Internal IP", "Protocol"]
            ),
            RouterGuideStep(
                id: "google-nest-step-5",
                kind: .test,
                title: "Save and test remotely",
                body: "Apply the rule and test from another network after the Google Home app finishes saving.",
                referencedTokens: [],
                alternateTerms: []
            )
        ],
        notes: [
            RouterGuideNote(id: "google-nest-note-1", title: "App-first flow", body: "Google WiFi and Nest WiFi are commonly identified by ecosystem name rather than exact hardware model."),
            RouterGuideNote(id: "google-nest-note-2", title: nil, body: "If your ISP device is still routing, the Google/Nest rule alone may not expose the server.")
        ],
        troubleshooting: [.wrongRouter, .doubleNAT, .wrongDevice, .wrongProtocol],
        sharedSections: RouterGuideSharedSections(
            includeSharedIntro: true,
            includeSharedPrerequisites: true,
            includeSharedValueSummary: true,
            includeSharedTroubleshootingFooter: true
        ),
        review: RouterGuideReviewMetadata(
            sourceConfidence: .commonFlow,
            lastReviewed: "2026-03-17T00:00:00Z",
            reviewNotes: "Family-level Google/Nest WiFi app flow guidance."
        ),
        providerDisplayName: nil,
        deviceDisplayName: "Google Nest WiFi"
    )

    private static let genericTroubleshootingGuide = RouterPortForwardGuide(
        id: "advanced-troubleshooting",
        displayName: "Advanced Port Forwarding Troubleshooting",
        category: .advancedNetworking,
        family: .advancedTroubleshooting,
        searchKeywords: ["double nat", "cgnat", "wrong router", "firewall", "port forwarding not working"],
        adminAddresses: ["192.168.1.1", "192.168.0.1", "10.0.0.1"],
        adminSurface: .either,
        menuPath: [],
        alternateMenuNames: ["NAT", "Firewall", "Bridge Mode", "Passthrough"],
        steps: [
            RouterGuideStep(
                id: "troubleshooting-step-1",
                kind: .warning,
                title: "Verify the server works locally first",
                body: "Test from the same network before debugging the router. A router rule cannot fix a server that is not reachable on the LAN.",
                referencedTokens: [.detectedLocalIPAddress, .javaPort, .bedrockPort],
                alternateTerms: []
            ),
            RouterGuideStep(
                id: "troubleshooting-step-2",
                kind: .warning,
                title: "Check whether you have two routers",
                body: "If you have ISP hardware plus your own router or mesh system, you may be forwarding on the wrong device.",
                referencedTokens: [],
                alternateTerms: ["Double NAT", "Bridge Mode"]
            ),
            RouterGuideStep(
                id: "troubleshooting-step-3",
                kind: .warning,
                title: "Compare the router WAN IP to your public IP",
                body: "If they do not match, you may be behind CGNAT or another upstream NAT layer.",
                referencedTokens: [],
                alternateTerms: ["WAN IP", "Public IP"]
            ),
            RouterGuideStep(
                id: "troubleshooting-step-4",
                kind: .warning,
                title: "Confirm target device and protocol",
                body: "Make sure the rule points to the host Mac and uses TCP for Java and UDP for Bedrock unless your setup says otherwise.",
                referencedTokens: [.recommendedProtocol],
                alternateTerms: []
            )
        ],
        notes: [
            RouterGuideNote(id: "troubleshooting-note-1", title: "Limitations", body: "Some dorm, apartment, cellular, or ISP-managed networks will not allow direct port forwarding at all."),
            RouterGuideNote(id: "troubleshooting-note-2", title: nil, body: "This guide exists as a fallback path, not as proof that every network can be opened successfully.")
        ],
        troubleshooting: [.localIPChanged, .wrongRouter, .wrongDevice, .doubleNAT, .cgnat, .firewallBlocked, .wrongProtocol, .routerRebootRequired, .noAdminAccess],
        sharedSections: RouterGuideSharedSections(
            includeSharedIntro: true,
            includeSharedPrerequisites: false,
            includeSharedValueSummary: true,
            includeSharedTroubleshootingFooter: false
        ),
        review: RouterGuideReviewMetadata(
            sourceConfidence: .commonFlow,
            lastReviewed: "2026-03-17T00:00:00Z",
            reviewNotes: "Advanced fallback guide for unsupported or failing topologies."
        ),
        providerDisplayName: nil,
        deviceDisplayName: "Advanced Networking"
    )
}


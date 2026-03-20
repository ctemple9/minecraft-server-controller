import Foundation

/// Composes fully ordered logical guide structures from seed data, merging router-specific steps, prerequisites, value summaries, and notes into a renderable section list.
///
/// Produces a fully ordered logical guide structure from:
/// - shared content blocks
/// - guide-specific metadata
/// - router-specific steps/notes
/// - linked troubleshooting topics
///
/// This file intentionally contains no UI code. It is a pure composition layer that
/// later phases can feed into runtime token resolution and shared rendering.
final class RouterPortForwardGuideComposer {

    struct ComposedGuide: Equatable {
        let guide: RouterPortForwardGuide
        let sections: [ComposedSection]

        var id: String { guide.id }
    }

    struct ComposedSection: Equatable, Identifiable {
        let id: String
        let kind: SectionKind
        let title: String
        let items: [SectionItem]
        let origin: SectionOrigin

        var referencedTokens: [RouterGuideToken] {
            let all = items.flatMap(\ .referencedTokens)
            var seen = Set<RouterGuideToken>()
            return all.filter { seen.insert($0).inserted }
        }
    }

    enum SectionKind: String, Equatable {
        case intro
        case prerequisites
        case valueSummary
        case menuPath
        case routerSpecificSteps
        case notes
        case troubleshootingFooter
    }

    enum SectionOrigin: Equatable {
        case shared
        case guideSpecific
        case mixed
    }

    enum SectionItem: Equatable {
        case paragraph(title: String?, body: String, referencedTokens: [RouterGuideToken])
        case bulletList(title: String?, bullets: [String], referencedTokens: [RouterGuideToken])
        case menuPath(title: String?, path: [String], alternateMenuNames: [String])
        case step(RouterGuideStep)
        case note(RouterGuideNote)
        case troubleshootingTopic(RouterGuideTroubleshootingTopic)

        var referencedTokens: [RouterGuideToken] {
            switch self {
            case .paragraph(_, _, let referencedTokens):
                return referencedTokens
            case .bulletList(_, _, let referencedTokens):
                return referencedTokens
            case .menuPath:
                return []
            case .step(let step):
                return step.referencedTokens
            case .note:
                return []
            case .troubleshootingTopic:
                return []
            }
        }
    }

    private let repository: RouterPortForwardGuideRepository

    init(repository: RouterPortForwardGuideRepository = RouterPortForwardGuideRepository()) {
        self.repository = repository
    }

    func composeGuide(id: String) -> ComposedGuide? {
        guard let guide = repository.guide(id: id) else { return nil }
        return composeGuide(guide)
    }

    func composeGuide(_ guide: RouterPortForwardGuide) -> ComposedGuide {
        ComposedGuide(guide: guide, sections: composeSections(for: guide))
    }

    func composeBestMatch(for query: String, matcher: RouterPortForwardGuideMatcher? = nil) -> ComposedGuide? {
        let matcher = matcher ?? RouterPortForwardGuideMatcher(repository: repository)
        guard let guide = matcher.bestMatch(for: query) else { return nil }
        return composeGuide(guide)
    }

    // MARK: - Internal composition

    private func composeSections(for guide: RouterPortForwardGuide) -> [ComposedSection] {
        var sections: [ComposedSection] = []

        if guide.sharedSections.includeSharedIntro {
            sections.append(sharedIntroSection(for: guide))
        }

        if guide.sharedSections.includeSharedPrerequisites {
            sections.append(sharedPrerequisitesSection(for: guide))
        }

        if guide.sharedSections.includeSharedValueSummary {
            sections.append(sharedValueSummarySection(for: guide))
        }

        if let menuPathSection = menuPathSection(for: guide) {
            sections.append(menuPathSection)
        }

        sections.append(routerSpecificStepsSection(for: guide))

        if let notesSection = notesSection(for: guide) {
            sections.append(notesSection)
        }

        if guide.sharedSections.includeSharedTroubleshootingFooter,
           let troubleshootingSection = troubleshootingFooterSection(for: guide) {
            sections.append(troubleshootingSection)
        }

        return sections
    }

    private func sharedIntroSection(for guide: RouterPortForwardGuide) -> ComposedSection {
        let body = introBody(for: guide)
        return ComposedSection(
            id: "\(guide.id).intro",
            kind: .intro,
            title: "What you are doing",
            items: [
                .paragraph(title: nil, body: body, referencedTokens: []),
                .paragraph(
                    title: "Confidence",
                    body: guide.review.sourceConfidence.displayName,
                    referencedTokens: []
                )
            ],
            origin: .shared
        )
    }

    private func sharedPrerequisitesSection(for guide: RouterPortForwardGuide) -> ComposedSection {
        let bullets = prerequisitesBullets(for: guide)
        return ComposedSection(
            id: "\(guide.id).prerequisites",
            kind: .prerequisites,
            title: "Before you start",
            items: [
                .bulletList(title: nil, bullets: bullets, referencedTokens: [.detectedLocalIPAddress, .javaPort, .bedrockPort, .bedrockEnabled])
            ],
            origin: .shared
        )
    }

    private func sharedValueSummarySection(for guide: RouterPortForwardGuide) -> ComposedSection {
        let bullets = valueSummaryBullets(for: guide)
        return ComposedSection(
            id: "\(guide.id).value-summary",
            kind: .valueSummary,
            title: "Values you will enter",
            items: [
                .bulletList(title: nil, bullets: bullets, referencedTokens: [.detectedLocalIPAddress, .javaPort, .bedrockPort, .recommendedProtocol, .bedrockEnabled])
            ],
            origin: .shared
        )
    }

    private func menuPathSection(for guide: RouterPortForwardGuide) -> ComposedSection? {
        let hasMenuPath = !guide.menuPath.isEmpty
        let hasAlternates = !guide.alternateMenuNames.isEmpty
        guard hasMenuPath || hasAlternates else { return nil }

        return ComposedSection(
            id: "\(guide.id).menu-path",
            kind: .menuPath,
            title: "Where to look",
            items: [
                .menuPath(title: nil, path: guide.menuPath, alternateMenuNames: guide.alternateMenuNames)
            ],
            origin: .mixed
        )
    }

    private func routerSpecificStepsSection(for guide: RouterPortForwardGuide) -> ComposedSection {
        ComposedSection(
            id: "\(guide.id).steps",
            kind: .routerSpecificSteps,
            title: "Steps",
            items: guide.steps.map { .step($0) },
            origin: .guideSpecific
        )
    }

    private func notesSection(for guide: RouterPortForwardGuide) -> ComposedSection? {
        guard !guide.notes.isEmpty else { return nil }
        return ComposedSection(
            id: "\(guide.id).notes",
            kind: .notes,
            title: "Notes and quirks",
            items: guide.notes.map { .note($0) },
            origin: .guideSpecific
        )
    }

    private func troubleshootingFooterSection(for guide: RouterPortForwardGuide) -> ComposedSection? {
        let topics = repository.troubleshootingTopics(for: guide)
        guard !topics.isEmpty else { return nil }

        let items: [SectionItem] = [
            .paragraph(
                title: nil,
                body: "If the rule still does not work after you save and test from another network, continue with the matching troubleshooting topics below instead of guessing.",
                referencedTokens: []
            )
        ] + topics.map { .troubleshootingTopic($0) }

        return ComposedSection(
            id: "\(guide.id).troubleshooting",
            kind: .troubleshootingFooter,
            title: "Still not working?",
            items: items,
            origin: .mixed
        )
    }

    // MARK: - Shared block content

    private func introBody(for guide: RouterPortForwardGuide) -> String {
        let surfaceDescription: String
        switch guide.adminSurface {
        case .webBrowser:
            surfaceDescription = "in your router's browser-based admin page"
        case .mobileApp:
            surfaceDescription = "in the router's mobile app"
        case .either:
            surfaceDescription = "in either the router app or its browser-based admin page"
        }

        if let provider = cleaned(guide.providerDisplayName),
           let device = cleaned(guide.deviceDisplayName),
           provider.caseInsensitiveCompare(device) != .orderedSame {
            return "This guide helps you create a port-forward rule \(surfaceDescription) for \(device). Keep the provider name (\(provider)) separate from the actual device where settings are changed."
        }

        if let device = cleaned(guide.deviceDisplayName) {
            return "This guide helps you create a port-forward rule \(surfaceDescription) for \(device)."
        }

        return "This guide helps you create a port-forward rule \(surfaceDescription)."
    }

    private func prerequisitesBullets(for guide: RouterPortForwardGuide) -> [String] {
        var bullets: [String] = [
            "Confirm the host Mac is the device that will receive the forward.",
            "Keep the router login open so you can return to the forwarding page if the firmware hides advanced settings.",
            "Have the host Mac's local IP ready: {{detected_local_ip_address}}."
        ]

        if !guide.adminAddresses.isEmpty {
            bullets.append("Common admin addresses for this guide: \(guide.adminAddresses.joined(separator: ", ")).")
        }

        switch guide.category {
        case .ispGateway:
            bullets.append("Verify you are configuring the ISP gateway itself and not a separate downstream router or mesh system.")
        case .meshSystem:
            bullets.append("Check whether management happens in the router app first; some mesh systems hide forwarding outside the app.")
        default:
            break
        }

        return bullets
    }

    private func valueSummaryBullets(for guide: RouterPortForwardGuide) -> [String] {
        var bullets: [String] = [
            "Target device / internal IP: {{detected_local_ip_address}}",
            "Java port: {{java_port}} (usually TCP)",
            "Recommended protocol guidance: {{recommended_protocol}}"
        ]

        let mentionsBedrock = guide.steps.contains { $0.referencedTokens.contains(.bedrockPort) || $0.referencedTokens.contains(.bedrockEnabled) }
        if mentionsBedrock {
            bullets.append("Bedrock port: {{bedrock_port}} (usually UDP, when Bedrock/Geyser is enabled)")
            bullets.append("Bedrock enabled: {{bedrock_enabled}}")
        }

        return bullets
    }

    private func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

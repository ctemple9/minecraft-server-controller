import Foundation

/// Runtime value injection engine for composed router port-forwarding guides. Resolves dynamic tokens against the selected server's live context.
///
/// This layer resolves guide tokens against the currently selected server's state
/// without coupling the guide content model to SwiftUI. It consumes the
/// composed-guide output from RouterPortForwardGuideComposer and produces
/// a fully resolved logical structure that later
/// UI code can render directly.
struct RouterPortForwardGuideRuntimeContext: Equatable {
    var selectedServerID: String?
    var selectedServerName: String?
    var detectedLocalIPAddress: String?
    var detectedGatewayIPAddress: String?
    var javaPort: Int?
    var bedrockPort: Int?
    var recommendedProtocol: String?
    var bedrockEnabled: Bool?

    func resolvedString(for token: RouterGuideToken) -> String? {
        switch token {
        case .selectedServerName:
            return cleaned(selectedServerName)
        case .detectedLocalIPAddress:
            return cleaned(detectedLocalIPAddress)
        case .detectedGatewayIPAddress:
            return cleaned(detectedGatewayIPAddress)
        case .javaPort:
            return javaPort.map(String.init)
        case .bedrockPort:
            return bedrockPort.map(String.init)
        case .recommendedProtocol:
            return cleaned(recommendedProtocol)
        case .bedrockEnabled:
            guard let bedrockEnabled else { return nil }
            return bedrockEnabled ? "Yes" : "No"
        }
    }

    func fallbackString(for token: RouterGuideToken) -> String {
        switch token {
        case .selectedServerName:
            return "Current Server"
        case .detectedLocalIPAddress:
            return "Unavailable on this Mac right now"
        case .detectedGatewayIPAddress:
            return "Look up your router or gateway address manually"
        case .javaPort:
            return "Unknown"
        case .bedrockPort:
            return "Not enabled"
        case .recommendedProtocol:
            return "Forward TCP for Java. Add UDP only when Bedrock or Geyser is enabled."
        case .bedrockEnabled:
            return "Unknown"
        }
    }

    static func makeRecommendedProtocol(javaPort: Int?, bedrockPort: Int?, bedrockEnabled: Bool) -> String {
        if bedrockEnabled, let bedrockPort {
            if let javaPort {
                return "Forward TCP for the Java server on port \(javaPort). Also forward UDP for Bedrock or Geyser on port \(bedrockPort)."
            }
            return "Forward UDP for Bedrock or Geyser on port \(bedrockPort)."
        }

        if let javaPort {
            return "Forward TCP for the Java server on port \(javaPort)."
        }

        return "Forward TCP for Java. Add UDP only when Bedrock or Geyser is enabled."
    }

    private func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

final class RouterPortForwardGuideRuntimeResolver {

    struct ResolvedGuide: Equatable {
        let baseGuide: RouterPortForwardGuideComposer.ComposedGuide
        let sections: [ResolvedSection]
        let unresolvedTokens: [UnresolvedToken]

        var id: String { baseGuide.id }
        var guide: RouterPortForwardGuide { baseGuide.guide }
    }

    struct ResolvedSection: Equatable, Identifiable {
        let id: String
        let kind: RouterPortForwardGuideComposer.SectionKind
        let title: String
        let items: [ResolvedItem]
        let origin: RouterPortForwardGuideComposer.SectionOrigin
    }

    enum ResolvedItem: Equatable {
        case paragraph(title: String?, body: String)
        case bulletList(title: String?, bullets: [String])
        case menuPath(title: String?, path: [String], alternateMenuNames: [String])
        case step(ResolvedStep)
        case note(RouterGuideNote)
        case troubleshootingTopic(RouterGuideTroubleshootingTopic)
    }

    struct ResolvedStep: Equatable, Identifiable {
        let id: String
        let kind: RouterGuideStepKind
        let title: String
        let body: String
        let alternateTerms: [String]
    }

    struct UnresolvedToken: Equatable, Hashable, Identifiable {
        let sectionID: String
        let token: RouterGuideToken

        var id: String { "\(sectionID).\(token.rawValue)" }
    }

    func resolve(
        _ composedGuide: RouterPortForwardGuideComposer.ComposedGuide,
        context: RouterPortForwardGuideRuntimeContext
    ) -> ResolvedGuide {
        var unresolved = Set<UnresolvedToken>()

        let sections = composedGuide.sections.map { section in
            ResolvedSection(
                id: section.id,
                kind: section.kind,
                title: section.title,
                items: section.items.map { resolveItem($0, context: context, sectionID: section.id, unresolved: &unresolved) },
                origin: section.origin
            )
        }

        return ResolvedGuide(
            baseGuide: composedGuide,
            sections: sections,
            unresolvedTokens: unresolved.sorted {
                if $0.sectionID != $1.sectionID { return $0.sectionID < $1.sectionID }
                return $0.token.rawValue < $1.token.rawValue
            }
        )
    }

    func resolveGuide(
        id: String,
        composer: RouterPortForwardGuideComposer = RouterPortForwardGuideComposer(),
        context: RouterPortForwardGuideRuntimeContext
    ) -> ResolvedGuide? {
        guard let composed = composer.composeGuide(id: id) else { return nil }
        return resolve(composed, context: context)
    }

    func resolveBestMatch(
        for query: String,
        composer: RouterPortForwardGuideComposer = RouterPortForwardGuideComposer(),
        matcher: RouterPortForwardGuideMatcher? = nil,
        context: RouterPortForwardGuideRuntimeContext
    ) -> ResolvedGuide? {
        guard let composed = composer.composeBestMatch(for: query, matcher: matcher) else { return nil }
        return resolve(composed, context: context)
    }

    private func resolveItem(
        _ item: RouterPortForwardGuideComposer.SectionItem,
        context: RouterPortForwardGuideRuntimeContext,
        sectionID: String,
        unresolved: inout Set<UnresolvedToken>
    ) -> ResolvedItem {
        switch item {
        case .paragraph(let title, let body, _):
            return .paragraph(title: title, body: resolveText(body, context: context, sectionID: sectionID, unresolved: &unresolved))

        case .bulletList(let title, let bullets, _):
            return .bulletList(
                title: title,
                bullets: bullets.map { resolveText($0, context: context, sectionID: sectionID, unresolved: &unresolved) }
            )

        case .menuPath(let title, let path, let alternateMenuNames):
            return .menuPath(title: title, path: path, alternateMenuNames: alternateMenuNames)

        case .step(let step):
            return .step(
                ResolvedStep(
                    id: step.id,
                    kind: step.kind,
                    title: step.title,
                    body: resolveText(step.body, context: context, sectionID: sectionID, unresolved: &unresolved),
                    alternateTerms: step.alternateTerms
                )
            )

        case .note(let note):
            return .note(note)

        case .troubleshootingTopic(let topic):
            return .troubleshootingTopic(topic)
        }
    }

    private func resolveText(
        _ text: String,
        context: RouterPortForwardGuideRuntimeContext,
        sectionID: String,
        unresolved: inout Set<UnresolvedToken>
    ) -> String {
        var resolved = text

        for token in RouterGuideToken.allCases {
            let placeholder = "{{\(token.rawValue)}}"
            guard resolved.contains(placeholder) else { continue }

            if let replacement = context.resolvedString(for: token) {
                resolved = resolved.replacingOccurrences(of: placeholder, with: replacement)
            } else {
                unresolved.insert(UnresolvedToken(sectionID: sectionID, token: token))
                resolved = resolved.replacingOccurrences(of: placeholder, with: context.fallbackString(for: token))
            }
        }

        return resolved
    }
}

@MainActor
extension AppViewModel {

    func routerPortForwardGuideRuntimeContext(for configServer: ConfigServer) -> RouterPortForwardGuideRuntimeContext {
        let localIP = AppUtilities.localIPAddress()
        let propertiesModel = loadServerPropertiesModel(for: configServer)
        let javaPort = propertiesModel.serverPort
        let bedrockPort = effectiveBedrockPort(for: configServer)

        let bedrockEnabled = configServer.isBedrock || configServer.bedrockEnabled || bedrockPort != nil
        let recommendedProtocol = RouterPortForwardGuideRuntimeContext.makeRecommendedProtocol(
            javaPort: javaPort,
            bedrockPort: bedrockPort,
            bedrockEnabled: bedrockEnabled
        )

        return RouterPortForwardGuideRuntimeContext(
            selectedServerID: configServer.id,
            selectedServerName: configServer.displayName,
            detectedLocalIPAddress: localIP,
            detectedGatewayIPAddress: AppUtilities.defaultGatewayIPAddress(),
            javaPort: javaPort,
            bedrockPort: bedrockPort,
            recommendedProtocol: recommendedProtocol,
            bedrockEnabled: bedrockEnabled
        )
    }

    func routerPortForwardGuideRuntimeContextForSelectedServer() -> RouterPortForwardGuideRuntimeContext? {
        guard let server = selectedServer,
              let configServer = configServer(for: server) else {
            return nil
        }
        return routerPortForwardGuideRuntimeContext(for: configServer)
    }

    func resolvedRouterPortForwardGuide(
        id: String,
        composer: RouterPortForwardGuideComposer = RouterPortForwardGuideComposer(),
        resolver: RouterPortForwardGuideRuntimeResolver = RouterPortForwardGuideRuntimeResolver()
    ) -> RouterPortForwardGuideRuntimeResolver.ResolvedGuide? {
        guard let context = routerPortForwardGuideRuntimeContextForSelectedServer(),
              let composed = composer.composeGuide(id: id) else {
            return nil
        }
        return resolver.resolve(composed, context: context)
    }

    func resolvedBestMatchRouterPortForwardGuide(
        for query: String,
        composer: RouterPortForwardGuideComposer = RouterPortForwardGuideComposer(),
        matcher: RouterPortForwardGuideMatcher? = nil,
        resolver: RouterPortForwardGuideRuntimeResolver = RouterPortForwardGuideRuntimeResolver()
    ) -> RouterPortForwardGuideRuntimeResolver.ResolvedGuide? {
        guard let context = routerPortForwardGuideRuntimeContextForSelectedServer(),
              let composed = composer.composeBestMatch(for: query, matcher: matcher) else {
            return nil
        }
        return resolver.resolve(composed, context: context)
    }
}

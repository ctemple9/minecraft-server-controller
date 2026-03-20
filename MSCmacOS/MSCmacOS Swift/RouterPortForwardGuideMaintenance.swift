import Foundation

/// Maintainer-focused validation and authoring helpers for the router port-forwarding guide system. Used during guide authoring and catalog integrity checks.
///
/// This file is intentionally additive and independent from SwiftUI.
/// It does not replace the hard validation already present in
/// `RouterPortForwardGuideValidator`; instead it layers on project-hygiene
/// checks so the guide system does not drift into one-off content blobs.

enum RouterPortForwardGuideMaintenanceSeverity: String, CaseIterable {
    case error
    case warning
    case info
}

struct RouterPortForwardGuideMaintenanceIssue: Equatable, Identifiable {
    let id: String
    let severity: RouterPortForwardGuideMaintenanceSeverity
    let guideID: String?
    let title: String
    let message: String
    let suggestedFix: String?
}

struct RouterPortForwardGuideMaintenanceReport: Equatable {
    let issues: [RouterPortForwardGuideMaintenanceIssue]

    var errors: [RouterPortForwardGuideMaintenanceIssue] {
        issues.filter { $0.severity == .error }
    }

    var warnings: [RouterPortForwardGuideMaintenanceIssue] {
        issues.filter { $0.severity == .warning }
    }

    var infos: [RouterPortForwardGuideMaintenanceIssue] {
        issues.filter { $0.severity == .info }
    }

    var isPassing: Bool {
        errors.isEmpty
    }

    func summaryLines() -> [String] {
        [
            "Errors: \(errors.count)",
            "Warnings: \(warnings.count)",
            "Info: \(infos.count)"
        ]
    }
}

enum RouterPortForwardGuideMaintenanceLinter {

    static func audit(
        catalog: RouterPortForwardGuideCatalog,
        referenceDate: Date = Date(),
        staleAfterDays: Int = 180
    ) -> RouterPortForwardGuideMaintenanceReport {
        var issues: [RouterPortForwardGuideMaintenanceIssue] = []

        issues += RouterPortForwardGuideValidator.validate(catalog).map(makeErrorIssue)

        let troubleshootingIDs = Set(catalog.troubleshootingTopics.map(\ .id))

        for guide in catalog.guides {
            issues += missingTroubleshootingReferenceIssues(for: guide, knownTopicIDs: troubleshootingIDs)
            issues += providerAndDeviceMetadataIssues(for: guide)
            issues += adminAddressIssues(for: guide)
            issues += menuPathIssues(for: guide)
            issues += reviewMetadataIssues(for: guide, referenceDate: referenceDate, staleAfterDays: staleAfterDays)
            issues += sharedSectionDisciplineIssues(for: guide)
            issues += keywordCoverageIssues(for: guide)
            issues += noteCoverageIssues(for: guide)
        }

        return RouterPortForwardGuideMaintenanceReport(issues: issues)
    }

    private static func makeErrorIssue(
        from validationIssue: RouterPortForwardGuideValidationIssue
    ) -> RouterPortForwardGuideMaintenanceIssue {
        switch validationIssue {
        case .catalogHasNoGuides:
            return RouterPortForwardGuideMaintenanceIssue(
                id: "error.catalog.empty",
                severity: .error,
                guideID: nil,
                title: "Catalog has no guides",
                message: "The guide catalog is empty.",
                suggestedFix: "Add at least one guide before shipping the catalog."
            )
        case .duplicateGuideID(let id):
            return RouterPortForwardGuideMaintenanceIssue(
                id: "error.guide.duplicate.\(id)",
                severity: .error,
                guideID: id,
                title: "Duplicate guide id",
                message: "Two or more guides share the id '\(id)'.",
                suggestedFix: "Make every guide id unique and stable."
            )
        case .duplicateTroubleshootingID(let id):
            return RouterPortForwardGuideMaintenanceIssue(
                id: "error.troubleshooting.duplicate.\(id)",
                severity: .error,
                guideID: nil,
                title: "Duplicate troubleshooting topic id",
                message: "Two or more troubleshooting topics share the id '\(id)'.",
                suggestedFix: "Give each troubleshooting topic a unique id."
            )
        case .emptyDisplayName(let guideID):
            return RouterPortForwardGuideMaintenanceIssue(
                id: "error.guide.displayName.\(guideID)",
                severity: .error,
                guideID: guideID,
                title: "Missing display name",
                message: "Guide '\(guideID)' has an empty displayName.",
                suggestedFix: "Set a short human-readable displayName."
            )
        case .emptySearchKeywords(let guideID):
            return RouterPortForwardGuideMaintenanceIssue(
                id: "error.guide.searchKeywords.\(guideID)",
                severity: .error,
                guideID: guideID,
                title: "Missing search keywords",
                message: "Guide '\(guideID)' must have at least one search keyword.",
                suggestedFix: "Add provider names, family names, model nicknames, and common user phrasing."
            )
        case .duplicateSearchKeyword(let guideID, let keyword):
            return RouterPortForwardGuideMaintenanceIssue(
                id: "error.guide.duplicateKeyword.\(guideID).\(keyword)",
                severity: .error,
                guideID: guideID,
                title: "Duplicate normalized keyword",
                message: "Guide '\(guideID)' repeats the normalized keyword '\(keyword)'.",
                suggestedFix: "Remove duplicate aliases after normalization."
            )
        case .invalidAdminAddress(let guideID, let value):
            return RouterPortForwardGuideMaintenanceIssue(
                id: "error.guide.adminAddress.\(guideID).\(value)",
                severity: .error,
                guideID: guideID,
                title: "Invalid admin address",
                message: "Guide '\(guideID)' contains an invalid admin address '\(value)'.",
                suggestedFix: "Use a likely local admin IP or full local URL."
            )
        case .guideHasNoSteps(let guideID):
            return RouterPortForwardGuideMaintenanceIssue(
                id: "error.guide.steps.\(guideID)",
                severity: .error,
                guideID: guideID,
                title: "Guide has no steps",
                message: "Guide '\(guideID)' does not include any actionable steps.",
                suggestedFix: "Add compact, action-oriented steps."
            )
        case .guideHasNoTroubleshootingReferences(let guideID):
            return RouterPortForwardGuideMaintenanceIssue(
                id: "error.guide.troubleshooting.\(guideID)",
                severity: .error,
                guideID: guideID,
                title: "Guide has no troubleshooting references",
                message: "Guide '\(guideID)' is missing troubleshooting topic references.",
                suggestedFix: "Link every guide to the shared troubleshooting system."
            )
        case .invalidStep(let guideID, let stepID):
            return RouterPortForwardGuideMaintenanceIssue(
                id: "error.guide.step.invalid.\(guideID).\(stepID)",
                severity: .error,
                guideID: guideID,
                title: "Invalid step content",
                message: "Guide '\(guideID)' contains an invalid step '\(stepID)'.",
                suggestedFix: "Give every step a non-empty title and body."
            )
        case .duplicateStepID(let guideID, let stepID):
            return RouterPortForwardGuideMaintenanceIssue(
                id: "error.guide.step.duplicate.\(guideID).\(stepID)",
                severity: .error,
                guideID: guideID,
                title: "Duplicate step id",
                message: "Guide '\(guideID)' repeats the step id '\(stepID)'.",
                suggestedFix: "Make step ids unique within the guide."
            )
        case .invalidReviewDate(let guideID, let value):
            return RouterPortForwardGuideMaintenanceIssue(
                id: "error.guide.reviewDate.\(guideID).\(value)",
                severity: .error,
                guideID: guideID,
                title: "Invalid review date",
                message: "Guide '\(guideID)' has an invalid ISO-8601 review date '\(value)'.",
                suggestedFix: "Use a full ISO-8601 timestamp, for example 2026-03-17T00:00:00Z."
            )
        }
    }

    private static func missingTroubleshootingReferenceIssues(
        for guide: RouterPortForwardGuide,
        knownTopicIDs: Set<RouterGuideTroubleshootingTopicID>
    ) -> [RouterPortForwardGuideMaintenanceIssue] {
        guide.troubleshooting.compactMap { topicID in
            guard !knownTopicIDs.contains(topicID) else { return nil }
            return RouterPortForwardGuideMaintenanceIssue(
                id: "warning.guide.missingTopic.\(guide.id).\(topicID.rawValue)",
                severity: .warning,
                guideID: guide.id,
                title: "Guide references missing troubleshooting topic",
                message: "Guide '\(guide.id)' references troubleshooting topic '\(topicID.rawValue)', but that topic is not present in the catalog.",
                suggestedFix: "Add the missing troubleshooting topic or remove the stale reference."
            )
        }
    }

    private static func providerAndDeviceMetadataIssues(
        for guide: RouterPortForwardGuide
    ) -> [RouterPortForwardGuideMaintenanceIssue] {
        var issues: [RouterPortForwardGuideMaintenanceIssue] = []

        let deviceName = guide.deviceDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if deviceName.isEmpty {
            issues.append(
                RouterPortForwardGuideMaintenanceIssue(
                    id: "warning.guide.deviceName.\(guide.id)",
                    severity: .warning,
                    guideID: guide.id,
                    title: "Missing deviceDisplayName",
                    message: "Guide '\(guide.id)' has no deviceDisplayName.",
                    suggestedFix: "Set deviceDisplayName so provider and device labeling stay distinct."
                )
            )
        }

        if guide.category == .ispGateway {
            let providerName = guide.providerDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if providerName.isEmpty {
                issues.append(
                    RouterPortForwardGuideMaintenanceIssue(
                        id: "warning.guide.providerName.\(guide.id)",
                        severity: .warning,
                        guideID: guide.id,
                        title: "ISP gateway guide missing providerDisplayName",
                        message: "ISP gateway guide '\(guide.id)' does not set providerDisplayName.",
                        suggestedFix: "Set providerDisplayName so the app can keep provider and device concepts separate."
                    )
                )
            }
        }

        return issues
    }

    private static func adminAddressIssues(
        for guide: RouterPortForwardGuide
    ) -> [RouterPortForwardGuideMaintenanceIssue] {
        var issues: [RouterPortForwardGuideMaintenanceIssue] = []

        let normalizedAddresses = guide.adminAddresses.map(normalizeAddress)
        let duplicates = Dictionary(grouping: normalizedAddresses, by: { $0 })
            .filter { !$0.key.isEmpty && $0.value.count > 1 }
            .keys
            .sorted()

        for duplicate in duplicates {
            issues.append(
                RouterPortForwardGuideMaintenanceIssue(
                    id: "warning.guide.duplicateAddress.\(guide.id).\(duplicate)",
                    severity: .warning,
                    guideID: guide.id,
                    title: "Duplicate admin address after normalization",
                    message: "Guide '\(guide.id)' repeats the admin address '\(duplicate)' after normalization.",
                    suggestedFix: "Keep only one normalized version of each admin address hint."
                )
            )
        }

        let shouldHaveAdminHints = guide.category == .ispGateway || guide.category == .retailRouter || guide.category == .meshSystem
        if shouldHaveAdminHints && guide.adminAddresses.isEmpty {
            issues.append(
                RouterPortForwardGuideMaintenanceIssue(
                    id: "warning.guide.adminAddresses.missing.\(guide.id)",
                    severity: .warning,
                    guideID: guide.id,
                    title: "Guide is missing admin address hints",
                    message: "Guide '\(guide.id)' has no adminAddresses hints.",
                    suggestedFix: "Add likely local admin IPs or app entry points when they are known."
                )
            )
        }

        return issues
    }

    private static func menuPathIssues(
        for guide: RouterPortForwardGuide
    ) -> [RouterPortForwardGuideMaintenanceIssue] {
        let needsMenuPath = guide.family != .advancedTroubleshooting
        guard needsMenuPath && guide.menuPath.isEmpty else { return [] }

        return [
            RouterPortForwardGuideMaintenanceIssue(
                id: "warning.guide.menuPath.missing.\(guide.id)",
                severity: .warning,
                guideID: guide.id,
                title: "Guide is missing menu path guidance",
                message: "Guide '\(guide.id)' has no menuPath values.",
                suggestedFix: "Add the most likely navigation path, even if the labels may vary."
            )
        ]
    }

    private static func reviewMetadataIssues(
        for guide: RouterPortForwardGuide,
        referenceDate: Date,
        staleAfterDays: Int
    ) -> [RouterPortForwardGuideMaintenanceIssue] {
        var issues: [RouterPortForwardGuideMaintenanceIssue] = []

        let reviewString = guide.review.lastReviewed?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if reviewString.isEmpty {
            issues.append(
                RouterPortForwardGuideMaintenanceIssue(
                    id: "warning.guide.review.missing.\(guide.id)",
                    severity: .warning,
                    guideID: guide.id,
                    title: "Missing review date",
                    message: "Guide '\(guide.id)' has no lastReviewed date.",
                    suggestedFix: "Set lastReviewed whenever a guide is verified or materially revised."
                )
            )
            return issues
        }

        guard let reviewedAt = ISO8601DateFormatter().date(from: reviewString) else {
            return issues
        }

        let ageDays = Calendar(identifier: .gregorian).dateComponents([.day], from: reviewedAt, to: referenceDate).day ?? 0
        if ageDays >= staleAfterDays {
            issues.append(
                RouterPortForwardGuideMaintenanceIssue(
                    id: "warning.guide.review.stale.\(guide.id)",
                    severity: .warning,
                    guideID: guide.id,
                    title: "Review date is stale",
                    message: "Guide '\(guide.id)' was last reviewed \(ageDays) days ago.",
                    suggestedFix: "Re-check the flow against the current router UI or downgrade sourceConfidence if certainty has slipped."
                )
            )
        }

        if guide.review.sourceConfidence == .verifiedRecently && ageDays >= 90 {
            issues.append(
                RouterPortForwardGuideMaintenanceIssue(
                    id: "info.guide.review.verifyAgain.\(guide.id)",
                    severity: .info,
                    guideID: guide.id,
                    title: "Verified-recently confidence may need refresh",
                    message: "Guide '\(guide.id)' still claims verifiedRecently but the recorded review is \(ageDays) days old.",
                    suggestedFix: "Either verify the flow again or lower the confidence level to keep trust signals honest."
                )
            )
        }

        return issues
    }

    private static func sharedSectionDisciplineIssues(
        for guide: RouterPortForwardGuide
    ) -> [RouterPortForwardGuideMaintenanceIssue] {
        var issues: [RouterPortForwardGuideMaintenanceIssue] = []

        if !guide.sharedSections.includeSharedIntro {
            issues.append(
                RouterPortForwardGuideMaintenanceIssue(
                    id: "info.guide.sharedIntro.disabled.\(guide.id)",
                    severity: .info,
                    guideID: guide.id,
                    title: "Shared intro disabled",
                    message: "Guide '\(guide.id)' disables the shared intro block.",
                    suggestedFix: "Only disable shared intro when the guide truly needs a different opening structure."
                )
            )
        }

        if !guide.sharedSections.includeSharedPrerequisites {
            issues.append(
                RouterPortForwardGuideMaintenanceIssue(
                    id: "info.guide.sharedPrereqs.disabled.\(guide.id)",
                    severity: .info,
                    guideID: guide.id,
                    title: "Shared prerequisites disabled",
                    message: "Guide '\(guide.id)' disables the shared prerequisites block.",
                    suggestedFix: "Keep shared prerequisites enabled unless the guide would become misleading."
                )
            )
        }

        if !guide.sharedSections.includeSharedValueSummary {
            issues.append(
                RouterPortForwardGuideMaintenanceIssue(
                    id: "info.guide.sharedValueSummary.disabled.\(guide.id)",
                    severity: .info,
                    guideID: guide.id,
                    title: "Shared value summary disabled",
                    message: "Guide '\(guide.id)' disables the shared value summary block.",
                    suggestedFix: "Disable it only when the guide genuinely cannot benefit from auto-filled server values."
                )
            )
        }

        if !guide.sharedSections.includeSharedTroubleshootingFooter {
            issues.append(
                RouterPortForwardGuideMaintenanceIssue(
                    id: "warning.guide.sharedTroubleshooting.disabled.\(guide.id)",
                    severity: .warning,
                    guideID: guide.id,
                    title: "Shared troubleshooting footer disabled",
                    message: "Guide '\(guide.id)' disables the shared troubleshooting footer.",
                    suggestedFix: "Keep the shared troubleshooting footer enabled so guides do not drift apart."
                )
            )
        }

        return issues
    }

    private static func keywordCoverageIssues(
        for guide: RouterPortForwardGuide
    ) -> [RouterPortForwardGuideMaintenanceIssue] {
        let normalizedKeywords = Set(guide.searchKeywords.map(normalizeKeyword).filter { !$0.isEmpty })
        let normalizedDisplayName = normalizeKeyword(guide.displayName)

        guard !normalizedDisplayName.isEmpty, !normalizedKeywords.contains(normalizedDisplayName) else {
            return []
        }

        return [
            RouterPortForwardGuideMaintenanceIssue(
                id: "info.guide.keyword.displayName.\(guide.id)",
                severity: .info,
                guideID: guide.id,
                title: "Display name is not present in search keywords",
                message: "Guide '\(guide.id)' does not include its displayName as a normalized keyword.",
                suggestedFix: "Add the displayName or an equivalent normalized alias to improve maintainability."
            )
        ]
    }

    private static func noteCoverageIssues(
        for guide: RouterPortForwardGuide
    ) -> [RouterPortForwardGuideMaintenanceIssue] {
        guard guide.notes.isEmpty else { return [] }

        return [
            RouterPortForwardGuideMaintenanceIssue(
                id: "info.guide.notes.empty.\(guide.id)",
                severity: .info,
                guideID: guide.id,
                title: "Guide has no notes",
                message: "Guide '\(guide.id)' has no note entries for quirks, transparency, or caveats.",
                suggestedFix: "Add at least one concise note when the guide has vendor-specific caveats or important limitations."
            )
        ]
    }

    private static func normalizeKeyword(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeAddress(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/$", with: "", options: .regularExpression)
    }
}

enum RouterPortForwardGuideAuthoringTemplate {

    static func makeGuideStub(
        id: String,
        displayName: String,
        category: RouterGuideCategory,
        family: RouterGuideFamily,
        adminSurface: RouterGuideAdminSurface
    ) -> RouterPortForwardGuide {
        RouterPortForwardGuide(
            id: id,
            displayName: displayName,
            category: category,
            family: family,
            searchKeywords: [displayName],
            adminAddresses: [],
            adminSurface: adminSurface,
            menuPath: ["Login", "Advanced", "Port Forwarding"],
            alternateMenuNames: ["NAT Forwarding", "Virtual Server"],
            steps: [
                RouterGuideStep(
                    id: "\(id)-step-1",
                    kind: .navigate,
                    title: "Log in to the router",
                    body: "Open the router app or admin page and sign in.",
                    referencedTokens: [],
                    alternateTerms: []
                ),
                RouterGuideStep(
                    id: "\(id)-step-2",
                    kind: .navigate,
                    title: "Find the forwarding section",
                    body: "Look for Port Forwarding, NAT Forwarding, Virtual Server, or a similar menu.",
                    referencedTokens: [],
                    alternateTerms: ["NAT Forwarding", "Virtual Server"]
                ),
                RouterGuideStep(
                    id: "\(id)-step-3",
                    kind: .input,
                    title: "Create the rule",
                    body: "Target {{detected_local_ip_address}} and enter the correct ports and protocol.",
                    referencedTokens: [.detectedLocalIPAddress, .javaPort, .bedrockPort, .recommendedProtocol],
                    alternateTerms: ["LAN IP", "Internal IP"]
                )
            ],
            notes: [
                RouterGuideNote(
                    id: "\(id)-note-1",
                    title: "Transparency",
                    body: "Exact labels and screens may vary by firmware version."
                )
            ],
            troubleshooting: [.localIPChanged, .wrongRouter, .wrongDevice, .wrongProtocol],
            sharedSections: RouterGuideSharedSections(
                includeSharedIntro: true,
                includeSharedPrerequisites: true,
                includeSharedValueSummary: true,
                includeSharedTroubleshootingFooter: true
            ),
            review: RouterGuideReviewMetadata(
                sourceConfidence: .commonFlow,
                lastReviewed: nil,
                reviewNotes: "Replace this note after verifying the flow."
            ),
            providerDisplayName: nil,
            deviceDisplayName: displayName
        )
    }
}

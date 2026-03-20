//
//  RouterPortForwardGuideTroubleshootingScreen.swift
//  MinecraftServerController
//
//  Phase UI-4: Symptom-driven troubleshooting screen.
//  Visual: dark windowBackgroundColor base. Section cards use Welcome Guide
//  tint pattern (color.opacity(0.06) fill / color.opacity(0.18) stroke).
//    symptom rows   → accent selection tint
//    summary card   → secondary/neutral
//    likely causes  → neutral (severity accent on left-edge bar)
//    actions card   → blue
//    escalation     → orange (unchanged)
//    fallback card  → accentColor tint
//

import SwiftUI

// MARK: - Top-level screen

struct RouterPortForwardGuideTroubleshootingScreen: View {
    @ObservedObject var sheetViewModel: RouterPortForwardGuideSheetViewModel
    @State private var expandedCauseIDs: Set<RouterGuideTroubleshootingTopicID> = []

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: MSC.Spacing.xl) {
                    SymptomChecklistSection(sheetViewModel: sheetViewModel)
                    AnalyzeControlSection(sheetViewModel: sheetViewModel)
                    if let report = sheetViewModel.troubleshootingReport {
                        TroubleshootingResultsSection(report: report, sheetViewModel: sheetViewModel, expandedCauseIDs: $expandedCauseIDs)
                    }
                }
                .padding(MSC.Spacing.xl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            TroubleshootingNavBar(sheetViewModel: sheetViewModel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Bottom nav bar

private struct TroubleshootingNavBar: View {
    @ObservedObject var sheetViewModel: RouterPortForwardGuideSheetViewModel

    private var hasActiveState: Bool { !sheetViewModel.selectedSymptoms.isEmpty || sheetViewModel.troubleshootingReport != nil }
    private var backLabel: String { sheetViewModel.selectedGuideID != nil ? "← Back to guide" : "← Back to picker" }

    var body: some View {
        HStack {
            Button(backLabel) { sheetViewModel.navigateBackFromTroubleshooting() }
                .font(.system(size: 12)).foregroundStyle(.secondary).buttonStyle(.plain)
            Spacer()
            if hasActiveState {
                Button("Clear and restart") { sheetViewModel.resetTroubleshooting() }
                    .font(.system(size: 12)).foregroundStyle(.secondary).buttonStyle(.plain)
            }
        }
        .padding(.horizontal, MSC.Spacing.xl).padding(.vertical, MSC.Spacing.md)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Symptom checklist section

private struct SymptomChecklistSection: View {
    @ObservedObject var sheetViewModel: RouterPortForwardGuideSheetViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {
            MSCOverline("What are you seeing?")
            VStack(spacing: MSC.Spacing.xs) {
                ForEach(sheetViewModel.supportedSymptoms) { symptom in
                    SymptomRow(
                        symptom: symptom,
                        isSelected: sheetViewModel.selectedSymptoms.contains(symptom.id)
                    ) {
                        if sheetViewModel.selectedSymptoms.contains(symptom.id) {
                            sheetViewModel.selectedSymptoms.remove(symptom.id)
                        } else {
                            sheetViewModel.selectedSymptoms.insert(symptom.id)
                        }
                        sheetViewModel.troubleshootingReport = nil
                    }
                }
            }
        }
    }
}

// MARK: - Symptom row — accent tint on selection

private struct SymptomRow: View {
    let symptom: RouterPortForwardSymptom
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: MSC.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: 1)
                    if isSelected {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                    }
                }
                .frame(width: 16, height: 16).padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(symptom.title)
                        .font(MSC.Typography.cardTitle)
                        .foregroundStyle(.primary).multilineTextAlignment(.leading)
                    Text(symptom.description)
                        .font(MSC.Typography.caption)
                        .foregroundStyle(.secondary).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, MSC.Spacing.md).padding(.vertical, MSC.Spacing.sm + 2)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Analyze control

private struct AnalyzeControlSection: View {
    @ObservedObject var sheetViewModel: RouterPortForwardGuideSheetViewModel

    private var hasSelection: Bool { !sheetViewModel.selectedSymptoms.isEmpty }
    private var hasResult: Bool { sheetViewModel.troubleshootingReport != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {
            if !hasSelection && !hasResult {
                Text("Select the symptoms above to get a diagnosis.")
                    .font(MSC.Typography.caption).foregroundStyle(.secondary)
            }
            if hasSelection || hasResult {
                Button("Analyze") { sheetViewModel.runAnalysis() }
                    .buttonStyle(MSCPrimaryButtonStyle()).disabled(!hasSelection)
            }
        }
    }
}

// MARK: - Results section

private struct TroubleshootingResultsSection: View {
    let report: RouterPortForwardTroubleshootingReport
    @ObservedObject var sheetViewModel: RouterPortForwardGuideSheetViewModel
    @Binding var expandedCauseIDs: Set<RouterGuideTroubleshootingTopicID>

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.xl) {
            SummaryCard(summary: report.summary)

            if report.likelyCauses.isEmpty {
                NoCausesCard(sheetViewModel: sheetViewModel)
            } else {
                LikelyCausesSection(causes: report.likelyCauses, sheetViewModel: sheetViewModel, expandedCauseIDs: $expandedCauseIDs)
            }

            if !report.recommendedActions.isEmpty {
                RecommendedActionsCard(actions: report.recommendedActions)
            }

            if !report.escalationBullets.isEmpty {
                EscalationCard(bullets: report.escalationBullets)
            }

            if let resolution = report.fallbackResolution {
                FallbackResolutionCard(resolution: resolution, sheetViewModel: sheetViewModel)
            }
        }
    }
}

// MARK: - Summary card — neutral

private struct SummaryCard: View {
    let summary: String
    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
            MSCOverline("Diagnosis")
            Text(summary).font(MSC.Typography.cardTitle).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MSC.Spacing.lg)
        .background(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).fill(Color.secondary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
    }
}

// MARK: - No causes card — neutral

private struct NoCausesCard: View {
    @ObservedObject var sheetViewModel: RouterPortForwardGuideSheetViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {
            HStack(spacing: MSC.Spacing.sm) {
                Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
                Text("No specific cause matched").font(MSC.Typography.cardTitle).foregroundStyle(.primary)
            }
            Text("Try the advanced troubleshooting guide for deeper diagnostics.")
                .font(MSC.Typography.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Open Advanced Troubleshooting") {
                if let guide = sheetViewModel.advancedTroubleshootingGuide { sheetViewModel.navigateToGuide(id: guide.id) }
                else { sheetViewModel.navigateToGenericGuide() }
            }
            .font(.system(size: 13, weight: .medium)).foregroundStyle(Color.accentColor).buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MSC.Spacing.lg)
        .background(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).fill(Color.secondary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
    }
}

// MARK: - Likely causes section

private struct LikelyCausesSection: View {
    let causes: [RouterPortForwardTroubleshootingCause]
    @ObservedObject var sheetViewModel: RouterPortForwardGuideSheetViewModel
    @Binding var expandedCauseIDs: Set<RouterGuideTroubleshootingTopicID>

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
            MSCOverline("Likely causes")
            ForEach(causes) { cause in
                CauseCard(cause: cause, isExpanded: expandedCauseIDs.contains(cause.id), sheetViewModel: sheetViewModel) {
                    if expandedCauseIDs.contains(cause.id) { expandedCauseIDs.remove(cause.id) } else { expandedCauseIDs.insert(cause.id) }
                }
            }
        }
    }
}

// MARK: - Cause card — neutral with severity left-edge bar

private struct CauseCard: View {
    let cause: RouterPortForwardTroubleshootingCause
    let isExpanded: Bool
    @ObservedObject var sheetViewModel: RouterPortForwardGuideSheetViewModel
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: MSC.Spacing.sm) {
                    RoundedRectangle(cornerRadius: 2).fill(severityColor(cause.severity))
                        .frame(width: 3).padding(.vertical, 2)
                    SeverityBadge(severity: cause.severity)
                    Text(cause.topic.title)
                        .font(MSC.Typography.cardTitle).foregroundStyle(.primary)
                        .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }
                .padding(.vertical, MSC.Spacing.sm + 2)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Rectangle().fill(Color.secondary.opacity(0.12)).frame(height: 1)
                VStack(alignment: .leading, spacing: MSC.Spacing.md) {
                    if !cause.matchedSymptoms.isEmpty {
                        VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                            Text("Matched because of:").font(MSC.Typography.caption).foregroundStyle(.secondary)
                            FlowChipRow(labels: cause.matchedSymptoms.map { sheetViewModel.symptomTitle(for: $0) })
                        }
                    }
                    if !cause.topic.suggestedNextActions.isEmpty {
                        VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                            Text("Suggested actions:").font(MSC.Typography.caption).foregroundStyle(.secondary)
                            ForEach(cause.topic.suggestedNextActions, id: \.self) { action in BulletRow(text: action) }
                        }
                    }
                }
                .padding(.top, MSC.Spacing.sm).padding(.leading, MSC.Spacing.xs + 3).padding(.bottom, MSC.Spacing.sm)
            }
        }
        .padding(.horizontal, MSC.Spacing.md).padding(.vertical, MSC.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).fill(Color.secondary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
        .animation(.easeInOut(duration: 0.18), value: isExpanded)
    }
}

// MARK: - Severity badge

private struct SeverityBadge: View {
    let severity: RouterPortForwardTroubleshootingSeverity
    var body: some View {
        Text(severityLabel(severity))
            .font(.system(size: 10, weight: .semibold)).foregroundStyle(severityColor(severity))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(severityColor(severity).opacity(0.12)))
            .overlay(Capsule().stroke(severityColor(severity).opacity(0.25), lineWidth: 0.5))
    }
}

// MARK: - Recommended actions card — blue, like InAppBox

private struct RecommendedActionsCard: View {
    let actions: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.right.circle").font(.system(size: 11)).foregroundStyle(.blue)
                MSCOverline("Recommended actions")
            }
            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                ForEach(actions, id: \.self) { action in BulletRow(text: action, bulletColor: .blue) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MSC.Spacing.lg)
        .background(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).fill(Color.blue.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).stroke(Color.blue.opacity(0.18), lineWidth: 1))
    }
}

// MARK: - Escalation card — orange, matches Welcome Guide warning style

private struct EscalationCard: View {
    let bullets: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {
            HStack(spacing: MSC.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 13)).foregroundStyle(.orange)
                Text("Important").font(MSC.Typography.cardTitle).foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                ForEach(bullets, id: \.self) { bullet in BulletRow(text: bullet, bulletColor: .orange) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MSC.Spacing.lg)
        .background(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).fill(Color.orange.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).stroke(Color.orange.opacity(0.20), lineWidth: 1))
    }
}

// MARK: - Fallback resolution card — accent tint

private struct FallbackResolutionCard: View {
    let resolution: RouterPortForwardFallbackResolution
    @ObservedObject var sheetViewModel: RouterPortForwardGuideSheetViewModel

    private var targetGuide: RouterPortForwardGuide? { resolution.matchedGuide ?? resolution.fallbackGuide }

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {
            MSCOverline("Suggested path")
            HStack(spacing: MSC.Spacing.sm) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 12)).foregroundStyle(Color.accentColor)
                Text(resolutionKindLabel(resolution.kind)).font(MSC.Typography.cardTitle).foregroundStyle(.primary)
            }
            if !resolution.explanationBullets.isEmpty {
                VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                    ForEach(resolution.explanationBullets, id: \.self) { bullet in BulletRow(text: bullet) }
                }
            }
            if let guide = targetGuide {
                Button { sheetViewModel.navigateToGuide(id: guide.id) }
                label: { Label("Open guide: \(guide.displayName)", systemImage: "arrow.right") }
                .buttonStyle(MSCPrimaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MSC.Spacing.lg)
        .background(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).fill(Color.accentColor.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).stroke(Color.accentColor.opacity(0.18), lineWidth: 1))
    }
}

// MARK: - Shared helpers

private func severityColor(_ severity: RouterPortForwardTroubleshootingSeverity) -> Color {
    switch severity { case .high: return .red; case .medium: return .orange; case .low: return Color(nsColor: .systemGray) }
}

private func severityLabel(_ severity: RouterPortForwardTroubleshootingSeverity) -> String {
    switch severity { case .high: return "High"; case .medium: return "Medium"; case .low: return "Low" }
}

private func resolutionKindLabel(_ kind: RouterPortForwardResolutionKind) -> String {
    switch kind {
    case .exactGuide:           return "Matched guide available"
    case .familyGuide:          return "Family guide available"
    case .genericRouterGuide:   return "Generic router guide recommended"
    case .genericMeshGuide:     return "Generic mesh guide recommended"
    case .troubleshootingGuide: return "Advanced troubleshooting guide recommended"
    case .unknownRouterHelp:    return "Unknown router help path"
    case .needsMoreInfo:        return "More information needed"
    }
}

// MARK: - Bullet row

private struct BulletRow: View {
    let text: String
    var bulletColor: Color = Color(nsColor: .secondaryLabelColor)

    var body: some View {
        HStack(alignment: .top, spacing: MSC.Spacing.sm) {
            Circle().fill(bulletColor.opacity(0.6)).frame(width: 4, height: 4).padding(.top, 5)
            Text(text).font(MSC.Typography.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Flow chip row (matched symptoms)

private struct FlowChipRow: View {
    let labels: [String]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MSC.Spacing.xs) {
                ForEach(labels, id: \.self) { label in
                    Text(label)
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.secondary.opacity(0.08)))
                        .overlay(Capsule().stroke(Color.secondary.opacity(0.18), lineWidth: 0.5))
                }
            }
        }
    }
}

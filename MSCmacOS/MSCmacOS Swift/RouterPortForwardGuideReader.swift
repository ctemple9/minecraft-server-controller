//
//  RouterPortForwardGuideReader.swift
//  MinecraftServerController
//
//  Phase UI-3 (revised): Full guide reader screen.
//  Visual: dark windowBackgroundColor base. Each section kind gets a colored
//  tint card matching Welcome Guide pattern:
//    intro        → purple   (like AnalogyBox)
//    prerequisites → blue    (like InAppBox)
//    valueSummary  → green
//    menuPath      → secondary/neutral
//    steps         → neutral card, accent number badge retained
//    notes         → secondary/neutral
//

import SwiftUI

// MARK: - Top-level reader

struct RouterPortForwardGuideReader: View {
    let guideID: String
    @EnvironmentObject var viewModel: AppViewModel
    @ObservedObject var sheetViewModel: RouterPortForwardGuideSheetViewModel

    @State private var completedStepIDs: Set<String> = []
    @State private var expandedStepDetailIDs: Set<String> = []
    @State private var introExpanded: Bool = true
    @State private var notesExpanded: Bool = false
    @State private var expandedTopicIDs: Set<String> = []

    var body: some View {
        let resolved = viewModel.resolvedRouterPortForwardGuide(id: guideID)

        VStack(spacing: 0) {

            if let r = resolved, !r.unresolvedTokens.isEmpty {
                UnresolvedTokensWarningStrip()
            }

            if resolved != nil, let ctx = sheetViewModel.runtimeContext {
                StickyValuesStrip(context: ctx)
            }

            if let r = resolved {
                ScrollView {
                    VStack(alignment: .leading, spacing: MSC.Spacing.xl) {
                        ReaderGuideHeader(resolved: r)

                        ForEach(r.sections) { section in
                            SectionDispatcher(
                                section: section,
                                resolvedGuide: r,
                                completedStepIDs: $completedStepIDs,
                                expandedStepDetailIDs: $expandedStepDetailIDs,
                                introExpanded: $introExpanded,
                                notesExpanded: $notesExpanded,
                                expandedTopicIDs: $expandedTopicIDs,
                                sheetViewModel: sheetViewModel,
                                accentColor: viewModel.resolvedAccentColor
                            )
                        }

                        InlineTroubleshootingNudge(sheetViewModel: sheetViewModel)
                        FirmwareVarianceFooter()
                    }
                    .padding(MSC.Spacing.xl)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GuideNotFoundView(sheetViewModel: sheetViewModel)
            }

            Divider()
            ReaderNavigationBar(sheetViewModel: sheetViewModel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Not found state

private struct GuideNotFoundView: View {
    @ObservedObject var sheetViewModel: RouterPortForwardGuideSheetViewModel
    var body: some View {
        VStack(spacing: MSC.Spacing.lg) {
            Spacer()
            Image(systemName: "exclamationmark.magnifyingglass")
                .font(.system(size: 36, weight: .thin)).foregroundStyle(.secondary)
            Text("This guide could not be loaded. Return to picker.")
                .font(MSC.Typography.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("← Return to Picker") { sheetViewModel.navigateToPicker() }
                .font(.system(size: 13)).foregroundStyle(Color.accentColor).buttonStyle(.plain)
            Spacer()
        }
        .padding(MSC.Spacing.xxl).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Unresolved tokens warning strip

private struct UnresolvedTokensWarningStrip: View {
    var body: some View {
        HStack(spacing: MSC.Spacing.sm) {
            Image(systemName: "info.circle").font(.system(size: 12)).foregroundStyle(.orange)
            Text("Some server values could not be auto-detected. Check the app's network tab.")
                .font(MSC.Typography.caption).foregroundStyle(.orange)
            Spacer()
        }
        .padding(.horizontal, MSC.Spacing.xl).padding(.vertical, MSC.Spacing.sm)
        .background(MSC.Colors.guideWarningFill)
        .overlay(alignment: .bottom) { Rectangle().fill(MSC.Colors.guideWarningBorder).frame(height: 0.5) }
    }
}

// MARK: - Sticky values strip

private struct StickyValuesStrip: View {
    let context: RouterPortForwardGuideRuntimeContext

    private var localIP: String? { context.detectedLocalIPAddress }
    private var javaPort: String? { context.javaPort.map(String.init) }
    private var bedrockPort: String? { context.bedrockPort.map(String.init) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                StickyValueCell(label: "Your IP",      value: localIP ?? "Not detected", isMissing: localIP == nil,  copyable: localIP)
                Divider().frame(height: 28)
                StickyValueCell(label: "Java port",    value: javaPort ?? "—",           isMissing: javaPort == nil, copyable: javaPort)
                if let bp = bedrockPort {
                    Divider().frame(height: 28)
                    StickyValueCell(label: "Bedrock port", value: bp, isMissing: false, copyable: bp)
                }
                Spacer()
                if localIP == nil {
                    HStack(spacing: MSC.Spacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundStyle(.orange)
                        Text("IP missing — see below").font(.system(size: 10, weight: .medium)).foregroundStyle(.orange)
                    }
                    .padding(.trailing, MSC.Spacing.md)
                }
            }
            .padding(.horizontal, MSC.Spacing.xl).padding(.vertical, MSC.Spacing.sm)
            .background(Color(nsColor: .controlBackgroundColor))
            Divider()
        }
    }
}

private struct StickyValueCell: View {
    let label: String; let value: String; let isMissing: Bool; let copyable: String?
    @State private var copied = false

    var body: some View {
        HStack(spacing: MSC.Spacing.xs) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased())
                    .font(.system(size: 8, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
                Text(value)
                    .font(MSC.Typography.mono).foregroundStyle(isMissing ? .secondary : .primary).lineLimit(1)
            }
            if let copyable {
                Button {
                    let pb = NSPasteboard.general; pb.clearContents(); pb.setString(copyable, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9)).foregroundStyle(copied ? Color.green : Color.secondary)
                }
                .buttonStyle(.plain).help("Copy \(label)").animation(MSC.Animation.buttonPress, value: copied)
            }
        }
        .padding(.horizontal, MSC.Spacing.md)
    }
}

// MARK: - Guide header

private struct ReaderGuideHeader: View {
    let resolved: RouterPortForwardGuideRuntimeResolver.ResolvedGuide
    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
            HStack(alignment: .center) {
                MSCOverline(resolved.guide.category.readerLabel)
                Spacer()
                ReaderConfidenceBadge(confidence: resolved.guide.review.sourceConfidence)
            }
            Text(resolved.guide.displayName)
                .font(MSC.Typography.pageTitle).foregroundStyle(.primary)
        }
    }
}

// MARK: - Navigation bar

private struct ReaderNavigationBar: View {
    @ObservedObject var sheetViewModel: RouterPortForwardGuideSheetViewModel
    var body: some View {
        HStack(spacing: MSC.Spacing.sm) {
            Button("← Back to picker") { sheetViewModel.navigateToPicker() }
                .font(.system(size: 12)).foregroundStyle(.secondary).buttonStyle(.plain)
            Spacer()
            Button("Troubleshooting →") { sheetViewModel.navigateToTroubleshooting() }
                .font(.system(size: 12)).foregroundStyle(.secondary).buttonStyle(.plain)
        }
        .padding(.horizontal, MSC.Spacing.xl).padding(.vertical, MSC.Spacing.md)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Inline troubleshooting nudge

private struct InlineTroubleshootingNudge: View {
    @ObservedObject var sheetViewModel: RouterPortForwardGuideSheetViewModel
    var body: some View {
        HStack(spacing: MSC.Spacing.sm) {
            Image(systemName: "questionmark.circle").font(.system(size: 13)).foregroundStyle(.secondary)
            Text("Still not working after following the steps?")
                .font(MSC.Typography.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Troubleshooting →") { sheetViewModel.navigateToTroubleshooting() }
                .font(.system(size: 11, weight: .medium)).foregroundStyle(Color.accentColor).buttonStyle(.plain)
        }
        .padding(MSC.Spacing.md)
        .background(RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous).fill(MSC.Colors.guideNeutralFill))
        .overlay(RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous).stroke(MSC.Colors.guideNeutralBorder, lineWidth: 1))
    }
}

// MARK: - Section dispatcher

private struct SectionDispatcher: View {
    let section: RouterPortForwardGuideRuntimeResolver.ResolvedSection
    let resolvedGuide: RouterPortForwardGuideRuntimeResolver.ResolvedGuide
    @Binding var completedStepIDs: Set<String>
    @Binding var expandedStepDetailIDs: Set<String>
    @Binding var introExpanded: Bool
    @Binding var notesExpanded: Bool
    @Binding var expandedTopicIDs: Set<String>
    @ObservedObject var sheetViewModel: RouterPortForwardGuideSheetViewModel
    var accentColor: Color = .accentColor

    var body: some View {
        switch section.kind {
        case .intro:
            IntroSectionView(section: section, confidence: resolvedGuide.guide.review.sourceConfidence, isExpanded: $introExpanded)
        case .prerequisites:
            PrerequisitesSectionView(section: section)
        case .valueSummary:
            ValueSummarySectionView(section: section, resolvedGuide: resolvedGuide)
        case .menuPath:
            MenuPathSectionView(section: section)
        case .routerSpecificSteps:
            RouterSpecificStepsSectionView(section: section, completedStepIDs: $completedStepIDs, expandedDetailIDs: $expandedStepDetailIDs, accentColor: accentColor)
        case .notes:
            NotesSectionView(section: section, isExpanded: $notesExpanded)
        case .troubleshootingFooter:
            TroubleshootingFooterSectionView(section: section, expandedTopicIDs: $expandedTopicIDs, sheetViewModel: sheetViewModel)
        }
    }
}

// MARK: - Intro section — purple, like AnalogyBox

private struct IntroSectionView: View {
    let section: RouterPortForwardGuideRuntimeResolver.ResolvedSection
    let confidence: RouterGuideConfidence
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(MSC.Animation.tabSwitch) { isExpanded.toggle() }
            } label: {
                HStack(spacing: MSC.Spacing.sm) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 11)).foregroundStyle(.purple)
                    MSCOverline("What you are doing")
                    Spacer()
                    ReaderConfidenceBadge(confidence: confidence)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, MSC.Spacing.md).padding(.vertical, MSC.Spacing.sm + 2)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Rectangle().fill(MSC.Colors.guideMenuPath.opacity(0.12)).frame(height: 1)
                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                    ForEach(section.items.indices, id: \.self) { i in
                        if case .paragraph(_, let body) = section.items[i] {
                            Text(body)
                                .font(.system(size: 12)).foregroundStyle(.primary.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, MSC.Spacing.md).padding(.vertical, MSC.Spacing.md)
            }
        }
        .background(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).fill(MSC.Colors.guideMenuPathFill))
        .overlay(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).stroke(MSC.Colors.guideMenuPathBorder, lineWidth: 1))
    }
}

// MARK: - Prerequisites section — blue, like InAppBox

private struct PrerequisitesSectionView: View {
    let section: RouterPortForwardGuideRuntimeResolver.ResolvedSection

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "checklist").font(.system(size: 11)).foregroundStyle(.blue)
                MSCOverline("Before you start")
            }
            .padding(.horizontal, MSC.Spacing.md).padding(.top, MSC.Spacing.md)

            ForEach(section.items.indices, id: \.self) { i in
                if case .bulletList(_, let bullets) = section.items[i] {
                    VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                        ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                            HStack(alignment: .top, spacing: MSC.Spacing.sm) {
                                Circle().fill(MSC.Colors.guideInfo.opacity(0.5)).frame(width: 4, height: 4).padding(.top, 5)
                                Text(bullet)
                                    .font(.system(size: 12)).foregroundStyle(.primary.opacity(0.85))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.horizontal, MSC.Spacing.md).padding(.bottom, MSC.Spacing.md)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).fill(MSC.Colors.guideInfoFill))
        .overlay(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).stroke(MSC.Colors.guideInfoBorder, lineWidth: 1))
    }
}

// MARK: - Value summary section — green

private struct ValueSummarySectionView: View {
    let section: RouterPortForwardGuideRuntimeResolver.ResolvedSection
    let resolvedGuide: RouterPortForwardGuideRuntimeResolver.ResolvedGuide

    private var unresolvedForSection: Set<RouterGuideToken> {
        Set(resolvedGuide.unresolvedTokens.filter { $0.sectionID == section.id }.map { $0.token })
    }

    var body: some View {
        let unresolved = unresolvedForSection
        let localIPUnresolved = unresolved.contains(.detectedLocalIPAddress)

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.and.pencil.and.ellipsis").font(.system(size: 11)).foregroundStyle(.green)
                MSCOverline("Values you will enter")
            }
            .padding(.horizontal, MSC.Spacing.md).padding(.top, MSC.Spacing.md).padding(.bottom, MSC.Spacing.sm)

            if localIPUnresolved {
                LocalIPFailureCallout()
                    .padding(.horizontal, MSC.Spacing.md).padding(.bottom, MSC.Spacing.sm)
            }

            ForEach(section.items.indices, id: \.self) { i in
                if case .bulletList(_, let bullets) = section.items[i] {
                    VStack(spacing: 0) {
                        ForEach(Array(bullets.enumerated()), id: \.offset) { idx, bullet in
                            ValueSummaryRow(bullet: bullet, isUnresolved: isUnresolved(bullet: bullet, unresolvedTokens: unresolved))
                            if idx < bullets.count - 1 {
                                Rectangle().fill(MSC.Colors.guideStep.opacity(0.12)).frame(height: 1).padding(.leading, MSC.Spacing.md)
                            }
                        }
                    }
                    .padding(.bottom, MSC.Spacing.xs)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).fill(MSC.Colors.guideStepFill))
        .overlay(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).stroke(MSC.Colors.guideStepBorder, lineWidth: 1))
    }

    private func isUnresolved(bullet: String, unresolvedTokens: Set<RouterGuideToken>) -> Bool {
        guard let token = tokenForBullet(bullet) else { return false }
        return unresolvedTokens.contains(token)
    }

    private func tokenForBullet(_ bullet: String) -> RouterGuideToken? {
        let label: String
        if let range = bullet.range(of: ": ") { label = String(bullet[..<range.lowerBound]) } else { label = bullet }
        if label.hasPrefix("Target device")        { return .detectedLocalIPAddress }
        if label.hasPrefix("Java port")            { return .javaPort }
        if label.hasPrefix("Recommended protocol") { return .recommendedProtocol }
        if label.hasPrefix("Bedrock port")         { return .bedrockPort }
        if label.hasPrefix("Bedrock enabled")      { return .bedrockEnabled }
        return nil
    }
}

// MARK: - Local IP failure callout

private struct LocalIPFailureCallout: View {
    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
            HStack(spacing: MSC.Spacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(.orange)
                Text("Your Mac's local IP could not be detected").font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
            }
            Text("This is the most important value you'll enter. To find it manually:")
                .font(MSC.Typography.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                ManualIPStep(number: "1", text: "Open System Settings")
                ManualIPStep(number: "2", text: "Go to Network")
                ManualIPStep(number: "3", text: "Select your active connection (Wi-Fi or Ethernet)")
                ManualIPStep(number: "4", text: "Your IP address is shown — it usually starts with 192.168 or 10.0")
            }
            Text("Enter that address wherever the router asks for Device IP, Internal IP, or Target Device.")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(MSC.Spacing.md)
        .background(RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous).fill(MSC.Colors.guideWarningFill))
        .overlay(RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous).stroke(MSC.Colors.guideWarningBorder, lineWidth: 1))
    }
}

private struct ManualIPStep: View {
    let number: String; let text: String
    var body: some View {
        HStack(alignment: .top, spacing: MSC.Spacing.sm) {
            Text(number + ".").font(MSC.Typography.mono).foregroundStyle(.secondary).frame(width: 14, alignment: .leading)
            Text(text).font(MSC.Typography.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Value summary row

private struct ValueSummaryRow: View {
    let bullet: String; let isUnresolved: Bool
    @State private var copied = false

    private var label: String { bullet.range(of: ": ").map { String(bullet[..<$0.lowerBound]) } ?? bullet }
    private var value: String { bullet.range(of: ": ").map { String(bullet[$0.upperBound...]) } ?? "" }

    var body: some View {
        HStack(alignment: .top, spacing: MSC.Spacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(MSC.Typography.caption).foregroundStyle(.secondary)
                if isUnresolved {
                    Text(value).font(.system(size: 12).italic()).foregroundStyle(.secondary)
                } else {
                    Text(value).font(MSC.Typography.mono).foregroundStyle(.primary)
                }
            }
            Spacer()
            if isUnresolved {
                HStack(spacing: MSC.Spacing.xxs) {
                    Image(systemName: "info.circle").font(.system(size: 10))
                    Text("Could not detect").font(.system(size: 10))
                }
                .foregroundStyle(.secondary).padding(.top, MSC.Spacing.xs)
            } else {
                Button {
                    let pb = NSPasteboard.general; pb.clearContents(); pb.setString(value, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11)).foregroundStyle(copied ? Color.green : Color.secondary)
                }
                .buttonStyle(.plain).help("Copy \(label)").animation(MSC.Animation.buttonPress, value: copied)
            }
        }
        .padding(.horizontal, MSC.Spacing.md).padding(.vertical, MSC.Spacing.sm)
    }
}

// MARK: - Menu path section — neutral

private struct MenuPathSectionView: View {
    let section: RouterPortForwardGuideRuntimeResolver.ResolvedSection

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
            MSCOverline("Where to look")
                .padding(.horizontal, MSC.Spacing.md).padding(.top, MSC.Spacing.md)

            ForEach(section.items.indices, id: \.self) { i in
                if case .menuPath(_, let path, let alternates) = section.items[i] {
                    VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                        if !path.isEmpty {
                            HStack(spacing: MSC.Spacing.xs) {
                                ForEach(Array(path.enumerated()), id: \.offset) { idx, step in
                                    if idx > 0 { Text("›").font(MSC.Typography.mono).foregroundStyle(.secondary) }
                                    Text(step).font(MSC.Typography.mono).foregroundStyle(.primary)
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        if !alternates.isEmpty {
                            AlternateNameSummary(terms: alternates)
                        }
                    }
                    .padding(.horizontal, MSC.Spacing.md).padding(.bottom, MSC.Spacing.md)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).fill(MSC.Colors.guideNeutralFill))
        .overlay(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).stroke(MSC.Colors.guideNeutralBorder, lineWidth: 1))
    }
}

private struct AlternateNameSummary: View {
    let terms: [String]

    private var summaryText: String {
        terms.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Similar labels may include")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(summaryText)
                .font(MSC.Typography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Router-specific steps section

private struct RouterSpecificStepsSectionView: View {
    let section: RouterPortForwardGuideRuntimeResolver.ResolvedSection
    @Binding var completedStepIDs: Set<String>
    @Binding var expandedDetailIDs: Set<String>
    var accentColor: Color = .accentColor

    private var orderedSteps: [(stepNumber: Int, step: RouterPortForwardGuideRuntimeResolver.ResolvedStep)] {
        var result: [(Int, RouterPortForwardGuideRuntimeResolver.ResolvedStep)] = []
        var num = 1
        for item in section.items {
            if case .step(let s) = item { result.append((num, s)); num += 1 }
        }
        return result
    }

    private var allStepIDs: [String] { orderedSteps.map { $0.step.id } }
    private var allDone: Bool { let ids = allStepIDs; return !ids.isEmpty && ids.allSatisfy { completedStepIDs.contains($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
            HStack {
                Text("\(allStepIDs.count) \(allStepIDs.count == 1 ? "step" : "steps")")
                    .font(MSC.Typography.caption).foregroundStyle(.secondary)
                Spacer()
                Button(allDone ? "Reset" : "Mark all done") {
                    withAnimation(MSC.Animation.tabSwitch) {
                        if allDone { allStepIDs.forEach { completedStepIDs.remove($0) } }
                        else { allStepIDs.forEach { completedStepIDs.insert($0) } }
                    }
                }
                .font(.system(size: 11)).foregroundStyle(Color.accentColor).buttonStyle(.plain)
            }

            ForEach(orderedSteps, id: \.step.id) { entry in
                StepCard(
                    step: entry.step, stepNumber: entry.stepNumber,
                    isCompleted: completedStepIDs.contains(entry.step.id),
                    isDetailExpanded: expandedDetailIDs.contains(entry.step.id),
                    accentColor: accentColor,
                    onToggleComplete: {
                        withAnimation(MSC.Animation.tabSwitch) {
                            if completedStepIDs.contains(entry.step.id) { completedStepIDs.remove(entry.step.id) }
                            else { completedStepIDs.insert(entry.step.id) }
                        }
                    },
                    onToggleDetail: {
                        withAnimation(MSC.Animation.tabSwitch) {
                            if expandedDetailIDs.contains(entry.step.id) { expandedDetailIDs.remove(entry.step.id) }
                            else { expandedDetailIDs.insert(entry.step.id) }
                        }
                    }
                )
            }
        }
    }
}

// MARK: - Step card — neutral card, accent number badge retained

private struct StepCard: View {
    let step: RouterPortForwardGuideRuntimeResolver.ResolvedStep
    let stepNumber: Int
    let isCompleted: Bool
    let isDetailExpanded: Bool
    var accentColor: Color = .accentColor
    let onToggleComplete: () -> Void
    let onToggleDetail: () -> Void

    private var hasLongBody: Bool { step.body.count > 100 }

    var body: some View {
        HStack(alignment: .top, spacing: MSC.Spacing.md) {
            // Accent-colored number badge — retained per user preference
            ZStack {
                Circle()
                    .fill(isCompleted ? accentColor.opacity(0.15) : accentColor)
                    .frame(width: 26, height: 26)
                if isCompleted {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(accentColor)
                } else {
                    Text("\(stepNumber)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                }
            }
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                HStack(alignment: .center, spacing: MSC.Spacing.xs) {
                    Image(systemName: step.kind.readerIconName)
                        .font(.system(size: 11)).foregroundStyle(step.kind.readerIconColor)
                    Text(step.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isCompleted ? .secondary : .primary)
                }

                Text(step.body)
                    .font(.system(size: 12))
                    .foregroundStyle(isCompleted ? .secondary : Color(nsColor: .secondaryLabelColor))
                    .lineLimit(hasLongBody && !isDetailExpanded ? 2 : nil)
                    .fixedSize(horizontal: false, vertical: true)

                if hasLongBody {
                    Button(isDetailExpanded ? "Less" : "Details") { onToggleDetail() }
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Color.accentColor).buttonStyle(.plain)
                }

                if !step.alternateTerms.isEmpty {
                    HStack(spacing: MSC.Spacing.xs) {
                        Text("Also called:").font(.system(size: 10)).foregroundStyle(.secondary)
                        ForEach(step.alternateTerms, id: \.self) { term in
                            Text(term)
                                .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                                .padding(.horizontal, MSC.Spacing.xs + 2).padding(.vertical, 2)
                                .background(Capsule().fill(MSC.Colors.guideNeutralChip))
                                .overlay(Capsule().stroke(MSC.Colors.guideNeutralChipBorder, lineWidth: 0.5))
                        }
                    }
                }
            }

            Spacer()

            Button(action: onToggleComplete) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isCompleted ? accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(isCompleted ? "Mark incomplete" : "Mark complete")
            .padding(.top, 2)
        }
        .padding(MSC.Spacing.md)
        .background(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).fill(MSC.Colors.guideNeutralFill))
        .overlay(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).stroke(MSC.Colors.guideNeutralBorder, lineWidth: 1))
    }
}

// MARK: - Notes section — neutral

private struct NotesSectionView: View {
    let section: RouterPortForwardGuideRuntimeResolver.ResolvedSection
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(MSC.Animation.tabSwitch) { isExpanded.toggle() }
            } label: {
                HStack {
                    MSCOverline("Notes and quirks")
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, MSC.Spacing.md).padding(.vertical, MSC.Spacing.sm + 2)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Rectangle().fill(MSC.Colors.guideNeutralDivider).frame(height: 1)
                VStack(alignment: .leading, spacing: MSC.Spacing.md) {
                    ForEach(section.items.indices, id: \.self) { i in
                        if case .note(let note) = section.items[i] { NoteRow(note: note) }
                    }
                }
                .padding(.horizontal, MSC.Spacing.md).padding(.vertical, MSC.Spacing.md)
            }
        }
        .background(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).fill(MSC.Colors.guideNeutralFill))
        .overlay(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).stroke(MSC.Colors.guideNeutralBorder, lineWidth: 1))
    }
}

private struct NoteRow: View {
    let note: RouterGuideNote
    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
            if let title = note.title { MSCOverline(title) }
            Text(note.body).font(MSC.Typography.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Troubleshooting footer section

private struct TroubleshootingFooterSectionView: View {
    let section: RouterPortForwardGuideRuntimeResolver.ResolvedSection
    @Binding var expandedTopicIDs: Set<String>
    @ObservedObject var sheetViewModel: RouterPortForwardGuideSheetViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {
            Divider()
            Text("Still not working?").font(MSC.Typography.sectionHeader).foregroundStyle(.primary)

            ForEach(section.items.indices, id: \.self) { i in
                switch section.items[i] {
                case .paragraph(_, let body):
                    Text(body).font(MSC.Typography.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                case .troubleshootingTopic(let topic):
                    TroubleshootingTopicRow(
                        topic: topic,
                        isExpanded: expandedTopicIDs.contains(topic.id.rawValue),
                        onToggle: {
                            withAnimation(MSC.Animation.tabSwitch) {
                                let key = topic.id.rawValue
                                if expandedTopicIDs.contains(key) { expandedTopicIDs.remove(key) } else { expandedTopicIDs.insert(key) }
                            }
                        }
                    )
                default: EmptyView()
                }
            }

//            Button("See full troubleshooting →") { sheetViewModel.navigateToTroubleshooting() }
//                .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.accentColor).buttonStyle(.plain)
//                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

private struct TroubleshootingTopicRow: View {
    let topic: RouterGuideTroubleshootingTopic
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack {
                    Text(topic.title).font(.system(size: 13, weight: .medium)).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, MSC.Spacing.md).padding(.vertical, MSC.Spacing.sm + 2)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Rectangle().fill(MSC.Colors.guideNeutralDivider).frame(height: 1)
                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                    Text(topic.summary).font(MSC.Typography.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if !topic.suggestedNextActions.isEmpty {
                        VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                            ForEach(Array(topic.suggestedNextActions.enumerated()), id: \.offset) { _, action in
                                HStack(alignment: .top, spacing: MSC.Spacing.sm) {
                                    Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(.secondary).padding(.top, 3)
                                    Text(action).font(MSC.Typography.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, MSC.Spacing.md).padding(.bottom, MSC.Spacing.md)
            }
        }
        .background(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).fill(MSC.Colors.guideNeutralFill))
        .overlay(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).stroke(MSC.Colors.guideNeutralBorder, lineWidth: 1))
    }
}

// MARK: - Firmware variance footer

private struct FirmwareVarianceFooter: View {
    var body: some View {
        Text("Screen layouts vary by firmware version. Menu paths and labels may differ.")
            .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).padding(.vertical, MSC.Spacing.md)
    }
}

// MARK: - Confidence badge

private struct ReaderConfidenceBadge: View {
    let confidence: RouterGuideConfidence

    private var color: Color {
        switch confidence {
        case .verifiedRecently:      return .green
        case .commonFlow:            return .blue
        case .olderInterfaceMayVary: return .orange
        case .communityBased:        return Color(nsColor: .systemGray)
        }
    }

    var body: some View {
        Text(confidence.displayName)
            .font(.system(size: 9, weight: .semibold)).foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
            .overlay(Capsule().stroke(color.opacity(0.30), lineWidth: 0.5))
    }
}

// MARK: - RouterGuideStepKind UI helpers

private extension RouterGuideStepKind {
    var readerIconName: String {
        switch self {
        case .warning: return "exclamationmark.triangle"; case .test: return "checkmark"
        case .input: return "pencil"; case .navigate: return "chevron.right"
        case .save: return "checkmark.circle"; case .intro: return "info.circle"
        case .prerequisite: return "info.circle"
        }
    }
    var readerIconColor: Color {
        switch self {
        case .warning: return .orange; case .test: return .green; case .input: return .accentColor
        case .navigate: return Color(nsColor: .secondaryLabelColor); case .save: return .accentColor
        case .intro: return Color(nsColor: .secondaryLabelColor); case .prerequisite: return Color(nsColor: .secondaryLabelColor)
        }
    }
}

// MARK: - RouterGuideCategory reader label

private extension RouterGuideCategory {
    var readerLabel: String {
        switch self {
        case .ispGateway: return "ISP GATEWAY"; case .retailRouter: return "RETAIL ROUTER"
        case .meshSystem: return "MESH SYSTEM"; case .genericFallback: return "GENERIC FALLBACK"
        case .advancedNetworking: return "ADVANCED NETWORKING"
        }
    }
}


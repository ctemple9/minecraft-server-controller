//
//  RouterPortForwardGuidePicker.swift
//  MinecraftServerController
//
//  Phase UI-2: global router guide browser.
//  Uses one global search field plus grouped dedicated-guide inventory,
//  while keeping the existing matcher, repository, and generic fallback wiring.
//

import SwiftUI

// MARK: - Top-level picker

struct RouterPortForwardGuidePicker: View {
    @ObservedObject var sheetViewModel: RouterPortForwardGuideSheetViewModel

    var body: some View {
        VStack(spacing: 0) {
            if sheetViewModel.allGuides.isEmpty {
                PickerEmptyRepositoryView()
            } else {
                ScrollView {
                    GlobalGuideBrowserView(sheetViewModel: sheetViewModel)
                        .padding(MSC.Spacing.xl)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()
                PickerBottomBar(sheetViewModel: sheetViewModel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Bottom bar

private struct PickerBottomBar: View {
    @ObservedObject var sheetViewModel: RouterPortForwardGuideSheetViewModel

    var body: some View {
        HStack(spacing: MSC.Spacing.sm) {
            Spacer()
            Button("Use generic guide") { sheetViewModel.navigateToGenericGuide() }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, MSC.Spacing.xl)
        .padding(.vertical, MSC.Spacing.md)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Empty repository error

private struct PickerEmptyRepositoryView: View {
    var body: some View {
        VStack(spacing: MSC.Spacing.lg) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .thin))
                .foregroundStyle(.orange)
            Text("Guides unavailable. Check app installation.")
                .font(MSC.Typography.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Global guide browser

private struct GlobalGuideBrowserView: View {
    @ObservedObject var sheetViewModel: RouterPortForwardGuideSheetViewModel
    @FocusState private var isSearchFocused: Bool

    private var dedicatedGuides: [RouterPortForwardGuide] {
        sheetViewModel.allGuides.filter { guide in
            switch guide.category {
            case .ispGateway, .retailRouter, .meshSystem:
                return true
            case .genericFallback, .advancedNetworking:
                return false
            }
        }
    }

    private var ispGuides: [RouterPortForwardGuide] {
        guides(in: .ispGateway)
    }

    private var routerGuides: [RouterPortForwardGuide] {
        guides(in: .retailRouter)
    }

    private var meshGuides: [RouterPortForwardGuide] {
        guides(in: .meshSystem)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.xl) {
            NodeHeader(
                title: "Find your router guide",
                bodyText: "Search across all supported providers, routers, and mesh systems, or browse the available guide inventory below."
            )

            IKnowDontKnowCard(sheetViewModel: sheetViewModel)

            searchField

            if let results = activeResults {
                SearchResultsBlock(results: results, sheetViewModel: sheetViewModel)
            } else {
                GuideInventorySection(
                    title: "Provider Gateways",
                    bodyText: "Provider-supplied internet equipment such as Xfinity, Spectrum, AT&T, and Fios.",
                    guides: ispGuides,
                    sheetViewModel: sheetViewModel
                )

                GuideInventorySection(
                    title: "Routers",
                    bodyText: "Standalone router brands and product lines you bought yourself.",
                    guides: routerGuides,
                    sheetViewModel: sheetViewModel
                )

                GuideInventorySection(
                    title: "Mesh Systems",
                    bodyText: "Whole-home Wi-Fi systems and app-managed mesh products.",
                    guides: meshGuides,
                    sheetViewModel: sheetViewModel
                )
            }
        }
        .onAppear {
            if sheetViewModel.pickerQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                isSearchFocused = true
            }
        }
    }

    private var searchField: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
            Text("Search supported guides")
                .font(MSC.Typography.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: MSC.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                TextField(
                    "Search by provider, brand, model, or product line…",
                    text: Binding(
                        get: { sheetViewModel.pickerQuery },
                        set: { sheetViewModel.runSearch($0) }
                    )
                )
                .textFieldStyle(.plain)
                .font(MSC.Typography.body)
                .focused($isSearchFocused)

                if !sheetViewModel.pickerQuery.isEmpty {
                    Button {
                        sheetViewModel.runSearch("")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, MSC.Spacing.md)
            .padding(.vertical, MSC.Spacing.sm + 2)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                    .fill(Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                    .stroke(
                        isSearchFocused ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.15),
                        lineWidth: 1
                    )
            )
            .animation(MSC.Animation.tabSwitch, value: isSearchFocused)
        }
    }

    private var activeResults: RouterPortForwardGuideMatcher.MatchResult? {
        let trimmed = sheetViewModel.pickerQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return sheetViewModel.searchResults
    }

    private func guides(in category: RouterGuideCategory) -> [RouterPortForwardGuide] {
        dedicatedGuides
            .filter { $0.category == category }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}

private struct IKnowDontKnowCard: View {
    @ObservedObject var sheetViewModel: RouterPortForwardGuideSheetViewModel
    @State private var isHovered = false

    var body: some View {
        Button {
            sheetViewModel.navigateToGenericGuide()
        } label: {
            HStack(spacing: MSC.Spacing.md) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text("I don’t know my router")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Open the generic guide and continue with the broadest supported path.")
                        .font(MSC.Typography.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(isHovered ? 1.0 : 0.6))
            }
            .padding(MSC.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                    .fill(isHovered ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                    .stroke(
                        isHovered ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.15),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(MSC.Animation.tabSwitch, value: isHovered)
        .onHover { isHovered = $0 }
    }
}

private struct GuideInventorySection: View {
    let title: String
    let bodyText: String
    let guides: [RouterPortForwardGuide]
    @ObservedObject var sheetViewModel: RouterPortForwardGuideSheetViewModel

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: MSC.Spacing.md),
        GridItem(.flexible(), spacing: MSC.Spacing.md)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {
            NodeHeader(title: title, bodyText: bodyText)

            LazyVGrid(columns: columns, alignment: .leading, spacing: MSC.Spacing.md) {
                ForEach(guides, id: \.id) { guide in
                    InventoryGuideCard(guide: guide) {
                        sheetViewModel.navigateToGuide(id: guide.id)
                    }
                }
            }
        }
    }
}

private struct InventoryGuideCard: View {
    let guide: RouterPortForwardGuide
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                Text(guide.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                if let provider = guide.providerDisplayName, !provider.isEmpty {
                    Text(provider)
                        .font(MSC.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let device = guide.deviceDisplayName, !device.isEmpty {
                    Text(device)
                        .font(MSC.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(guide.category.pickerLabel)
                        .font(MSC.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                HStack(spacing: MSC.Spacing.xs) {
                    ConfidenceBadge(confidence: guide.review.sourceConfidence)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.secondary.opacity(isHovered ? 1.0 : 0.6))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .padding(MSC.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                    .fill(isHovered ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                    .stroke(
                        isHovered ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.15),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(MSC.Animation.tabSwitch, value: isHovered)
        .onHover { isHovered = $0 }
    }
}

private struct SearchResultsBlock: View {
    let results: RouterPortForwardGuideMatcher.MatchResult
    @ObservedObject var sheetViewModel: RouterPortForwardGuideSheetViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {
            NodeHeader(
                title: "Search results",
                bodyText: "Matching guides across provider gateways, routers, and mesh systems."
            )

            if results.candidates.isEmpty {
                NoResultsView(fallbackGuide: results.suggestedFallbackGuide, sheetViewModel: sheetViewModel)
            } else if results.isAmbiguous {
                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                    MSCOverline("Closest available guides")
                    ForEach(results.candidates.prefix(8), id: \.guide.id) { candidate in
                        CandidateRow(candidate: candidate) { sheetViewModel.navigateToGuide(id: candidate.guide.id) }
                    }
                }
            } else if !results.matchedDirectGuide, let fallback = results.suggestedFallbackGuide {
                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                    FamilyNotSeededBanner()
                    GuideCard(guide: fallback) { sheetViewModel.navigateToGuide(id: fallback.id) }
                    MSCOverline("Closest available guides")
                    ForEach(results.candidates.prefix(8), id: \.guide.id) { candidate in
                        CandidateRow(candidate: candidate) { sheetViewModel.navigateToGuide(id: candidate.guide.id) }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                    ForEach(results.candidates.prefix(8), id: \.guide.id) { candidate in
                        CandidateRow(candidate: candidate) { sheetViewModel.navigateToGuide(id: candidate.guide.id) }
                    }
                }
            }
        }
    }
}

// MARK: - Shared node header

private struct NodeHeader: View {
    let title: String
    let bodyText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
            Text(title)
                .font(MSC.Typography.pageTitle)
                .foregroundStyle(.primary)
            if let text = bodyText, !text.isEmpty {
                Text(text)
                    .font(MSC.Typography.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - No results

private struct NoResultsView: View {
    let fallbackGuide: RouterPortForwardGuide?
    @ObservedObject var sheetViewModel: RouterPortForwardGuideSheetViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {
            Text("No supported guide matched that search.")
                .font(MSC.Typography.caption).foregroundStyle(.secondary)
            if let guide = fallbackGuide {
                Text("You can still continue with the closest generic guide:")
                    .font(MSC.Typography.caption).foregroundStyle(.secondary)
                GuideCard(guide: guide) { sheetViewModel.navigateToGuide(id: guide.id) }
            }
        }
    }
}

// MARK: - Family not seeded banner

private struct FamilyNotSeededBanner: View {
    var body: some View {
        HStack(spacing: MSC.Spacing.sm) {
            Image(systemName: "info.circle").font(.system(size: 12)).foregroundStyle(.orange)
            Text("No specific guide for this family yet — showing the closest match")
                .font(MSC.Typography.caption).foregroundStyle(.orange)
        }
        .padding(.horizontal, MSC.Spacing.md)
        .padding(.vertical, MSC.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous).fill(Color.orange.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous).stroke(Color.orange.opacity(0.20), lineWidth: 1))
    }
}

// MARK: - Candidate row

private struct CandidateRow: View {
    let candidate: RouterPortForwardGuideMatcher.MatchCandidate
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(candidate.guide.displayName)
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(.primary)
                    Text(candidate.guide.category.pickerLabel)
                        .font(MSC.Typography.overline).tracking(0.6).foregroundStyle(.secondary)
                }
                Spacer()
                ConfidenceBadge(confidence: candidate.guide.review.sourceConfidence)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(isHovered ? 1.0 : 0.5))
            }
            .padding(.horizontal, MSC.Spacing.md)
            .padding(.vertical, MSC.Spacing.sm + 1)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                    .fill(isHovered ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                    .stroke(isHovered ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(MSC.Animation.tabSwitch, value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Guide card

private struct GuideCard: View {
    let guide: RouterPortForwardGuide
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(guide.displayName)
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
                    Text(guide.category.pickerLabel)
                        .font(MSC.Typography.overline).tracking(0.6).foregroundStyle(.secondary)
                }
                Spacer()
                ConfidenceBadge(confidence: guide.review.sourceConfidence)
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.accentColor.opacity(isHovered ? 1.0 : 0.7))
            }
            .padding(MSC.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                    .fill(isHovered ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                    .stroke(isHovered ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(MSC.Animation.tabSwitch, value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Confidence badge

private struct ConfidenceBadge: View {
    let confidence: RouterGuideConfidence

    private var color: Color {
        switch confidence {
        case .verifiedRecently:      return .green
        case .commonFlow:            return .blue
        case .olderInterfaceMayVary: return .orange
        case .communityBased:        return Color(nsColor: .systemGray)
        }
    }

    private var shortLabel: String {
        switch confidence {
        case .verifiedRecently:      return "Verified recently"
        case .commonFlow:            return "Common flow"
        case .olderInterfaceMayVary: return "May vary"
        case .communityBased:        return "Community"
        }
    }

    var body: some View {
        Text(shortLabel)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
            .overlay(Capsule().stroke(color.opacity(0.30), lineWidth: 0.5))
    }
}

// MARK: - RouterGuideCategory display name

private extension RouterGuideCategory {
    var pickerLabel: String {
        switch self {
        case .ispGateway:         return "PROVIDER GATEWAY"
        case .retailRouter:       return "ROUTER"
        case .meshSystem:         return "MESH SYSTEM"
        case .genericFallback:    return "GENERIC FALLBACK"
        case .advancedNetworking: return "ADVANCED NETWORKING"
        }
    }
}


//
//  MSCTabBar.swift
//  MinecraftServerController
//
//  Premium tab rail used in DetailsView.
//
//  Finish pass:
//  - Keeps the existing 7-tab structure intact
//  - Refines the rail into a darker floating chrome surface
//  - Gives the selected tab a more lifted capsule with better rim/highlight depth
//  - Adds tactile press compression without changing behavior
//

import SwiftUI

struct MSCTabBar<Tab: Hashable>: View {
    let tabs: [MSCTabItem<Tab>]
    @Binding var selection: Tab

    // Server accent color drives the selected pill tint.
    // Defaults to system accentColor so existing callers without this param still compile.
    var accentColor: Color = .accentColor

    @Namespace private var pillNamespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs) { item in
                tabButton(item)
            }
        }
        .padding(4)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: MSC.Radius.lg, style: .continuous)
                    .fill(.ultraThinMaterial)

                RoundedRectangle(cornerRadius: MSC.Radius.lg, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.025),
                                MSC.Colors.tierChrome.opacity(0.84)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                RoundedRectangle(cornerRadius: MSC.Radius.lg, style: .continuous)
                    .fill(MSC.Colors.accent(from: accentColor, opacity: 0.05))

                RoundedRectangle(cornerRadius: MSC.Radius.lg, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.13),
                                Color.white.opacity(0.035),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.58)
                        )
                    )
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: MSC.Radius.lg, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.24), radius: 12, x: 0, y: 8)
    }

    @ViewBuilder
    private func tabButton(_ item: MSCTabItem<Tab>) -> some View {
        let isSelected = selection == item.id

        Button {
            withAnimation(MSC.Animation.chromeSpring) {
                selection = item.id
            }
        } label: {
            tabLabel(item, isSelected: isSelected)
        }
        .buttonStyle(MSCTabPressButtonStyle())
        .modifier(OptionalOnboardingAnchor(anchorID: item.onboardingAnchorID))
        .contextualHelpAnchor(item.contextualHelpAnchorID)
    }

    @ViewBuilder
    private func tabLabel(_ item: MSCTabItem<Tab>, isSelected: Bool) -> some View {
        HStack(spacing: MSC.Spacing.xs) {
            if let icon = item.icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
            }
            Text(item.label)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
        }
        .foregroundStyle(isSelected ? Color.white.opacity(0.97) : Color.white.opacity(0.64))
        .padding(.horizontal, MSC.Spacing.sm + 1)
        .padding(.vertical, MSC.Spacing.xs + 1)
        .frame(maxWidth: .infinity)
        .background {
            if isSelected {
                ZStack {
                    RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                        .fill(.regularMaterial)

                    RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                        .fill(Color.white.opacity(0.05))

                    RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                        .fill(MSC.Colors.accent(from: accentColor, opacity: 0.18))

                    RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.16), Color.clear],
                                startPoint: .top,
                                endPoint: UnitPoint(x: 0.5, y: 0.68)
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
                }
                .shadow(color: accentColor.opacity(0.18), radius: 10, x: 0, y: 5)
                .shadow(color: .black.opacity(0.20), radius: 8, x: 0, y: 4)
                .matchedGeometryEffect(id: "tabSelectionPill", in: pillNamespace)
            }
        }
    }
}

struct MSCTabItem<Tab: Hashable>: Identifiable {
    let id: Tab
    let label: String
    let icon: String?
    let onboardingAnchorID: OnboardingAnchorID?
    let contextualHelpAnchorID: String?

    init(
        _ id: Tab,
        label: String,
        icon: String? = nil,
        onboardingAnchorID: OnboardingAnchorID? = nil,
        contextualHelpAnchorID: String? = nil
    ) {
        self.id = id
        self.label = label
        self.icon = icon
        self.onboardingAnchorID = onboardingAnchorID
        self.contextualHelpAnchorID = contextualHelpAnchorID
    }
}

private struct OptionalOnboardingAnchor: ViewModifier {
    let anchorID: OnboardingAnchorID?

    func body(content: Content) -> some View {
        if let id = anchorID {
            content.onboardingAnchor(id)
        } else {
            content
        }
    }
}

private struct MSCTabPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(MSC.Animation.buttonPress, value: configuration.isPressed)
    }
}

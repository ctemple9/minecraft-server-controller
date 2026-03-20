//
//  OverviewAlertBannersView.swift
//  MinecraftServerController
//

import SwiftUI

struct OverviewAlertBannersView: View {
    @EnvironmentObject var viewModel: AppViewModel

    @Binding var hasSavedDuckDNS: Bool
    @Binding var isEditingDuckDNS: Bool

    var body: some View {
        overviewAlertBanners
    }

    // MARK: - Overview: Alert Banners

    /// Surfaces conditions that need user attention. Each banner disappears once resolved.
    @ViewBuilder
    private var overviewAlertBanners: some View {
        VStack(spacing: MSC.Spacing.sm) {
            if viewModel.eulaAccepted == false {
                            overviewAlertBanner(
                                icon: "doc.text.fill",
                                color: MSC.Colors.warning,
                                message: "EULA not accepted — the server cannot start until you accept it.",
                                actionLabel: "Accept EULA"
                            ) {
                                viewModel.acceptEULA()
                                if OnboardingManager.shared.isActive,
                                   OnboardingManager.shared.currentStep == .acceptEula {
                                    OnboardingManager.shared.advance()
                                }
                            }
                            .onboardingAnchor(.acceptEulaButton)
                        }

            let trimmedDuck = viewModel.duckdnsInput
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !hasSavedDuckDNS && trimmedDuck.isEmpty {
                overviewAlertBanner(
                    icon: "network",
                    color: MSC.Colors.info,
                    message: "No external hostname set. Friends connecting over the internet will need your IP address.",
                    actionLabel: "Set Hostname"
                ) {
                    isEditingDuckDNS = true
                }
            }
        }
    }

    @ViewBuilder
    private func overviewAlertBanner(
        icon: String,
        color: Color,
        message: String,
        actionLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: MSC.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)

            Text(message)
                .font(MSC.Typography.caption)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(actionLabel, action: action)
                .buttonStyle(MSCSecondaryButtonStyle())
                .controlSize(.small)
        }
        .padding(.horizontal, MSC.Spacing.md)
        .padding(.vertical, MSC.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}

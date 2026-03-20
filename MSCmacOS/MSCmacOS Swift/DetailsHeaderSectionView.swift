//
//  DetailsHeaderSectionView.swift
//  MinecraftServerController
//
//  Premium finish pass:
//  - Keeps the existing header layout and actions intact
//  - Refines the header into a darker glass shelf with a cleaner rim/highlight
//  - Upgrades small controls so the chrome feels more deliberate without redesigning the workspace
//

import SwiftUI

struct DetailsHeaderSectionView: View {
    @EnvironmentObject var viewModel: AppViewModel

    @Binding var isShowingManageServers: Bool
    let bannerColor: Color

    var body: some View {
        HStack(spacing: MSC.Spacing.md) {
            HStack(spacing: MSC.Spacing.md) {
                VStack(alignment: .leading, spacing: 3) {

                    HStack(alignment: .center, spacing: MSC.Spacing.sm) {
                        Text(viewModel.selectedServer?.name ?? "No server selected")
                            .font(.system(size: 25, weight: .semibold))
                            .foregroundStyle(.primary)

                        if let server = viewModel.selectedServer,
                           let cfgServer = viewModel.configServer(for: server) {
                            ServerTypeBadge(serverType: cfgServer.serverType)
                        }
                    }

                    if let server = viewModel.selectedServer {
                        HStack(spacing: MSC.Spacing.md) {
                            Text(server.directory)
                                .font(.system(size: 10))
                                .foregroundStyle(MSC.Colors.tertiary)
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            if let activeSlotName = viewModel.activeWorldSlotName(for: server) {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(MSC.Colors.success)
                                        .frame(width: 5, height: 5)
                                    Text(activeSlotName)
                                        .font(.system(size: 10))
                                        .foregroundStyle(MSC.Colors.tertiary)
                                }
                            }
                        }
                    }
                }

                Spacer(minLength: MSC.Spacing.md)
            }
            .padding(.horizontal, MSC.Spacing.lg)
            .padding(.vertical, MSC.Spacing.md)
            .background {
                ZStack {
                    Rectangle()
                        .fill(.regularMaterial)

                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.025),
                                    MSC.Colors.tierChrome.opacity(0.82)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    Rectangle()
                        .fill(MSC.Colors.accent(from: bannerColor, opacity: 0.06))

                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.11),
                                    Color.white.opacity(0.03),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: UnitPoint(x: 0.5, y: 0.62)
                            )
                        )
                }
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 0.5)
            }
            .shadow(color: .black.opacity(0.16), radius: 8, x: 0, y: 4)
        }
    }
}

// MARK: - Server Type Badge

private struct ServerTypeBadge: View {
    let serverType: ServerType

    private var label: String {
        switch serverType {
        case .java:    return "Java"
        case .bedrock: return "Bedrock"
        }
    }

    private var color: Color {
        switch serverType {
        case .java:    return .blue
        case .bedrock: return MSC.Colors.success
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.94))
            .padding(.horizontal, MSC.Spacing.sm)
            .padding(.vertical, 4)
            .background {
                ZStack {
                    Capsule()
                        .fill(.ultraThinMaterial)

                    Capsule()
                        .fill(color.opacity(0.22))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.15), Color.clear],
                                startPoint: .top,
                                endPoint: UnitPoint(x: 0.5, y: 0.72)
                            )
                        )
                }
            }
            .overlay {
                Capsule()
                    .stroke(color.opacity(0.45), lineWidth: 0.7)
            }
    }
}

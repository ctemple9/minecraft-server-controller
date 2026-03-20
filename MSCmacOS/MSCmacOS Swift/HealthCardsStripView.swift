//
//  HealthCardsStripView.swift
//  MinecraftServerController
//
//  Horizontal scrolling strip of diagnostic cards with 3D flip mechanic.
//  Placed in DetailsOverviewTabView between the connection card and Players section.
//
//  Card backs upgraded from cardBackground to tierContent.
//

import SwiftUI
import AppKit

// MARK: - Strip container

struct HealthCardsStripView: View {
    @EnvironmentObject var viewModel: AppViewModel

    /// ID of the currently-flipped card. Only one card flipped at a time.
    @State private var flippedCardID: String? = nil

    /// Whether to show the console sheet (passed in from parent if needed)
    var onOpenConsoleLog: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {

            // Strip label
            MSCOverline("Server Health")

            if viewModel.healthCards.isEmpty {
                // Loading state
                HStack(spacing: MSC.Spacing.sm) {
                    ForEach(0..<6, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                            .fill(MSC.Colors.tierContent.opacity(0.6))
                            .frame(width: 110, height: 130)
                            .overlay(
                                ProgressView()
                                    .controlSize(.small)
                            )
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: MSC.Spacing.sm) {
                        ForEach(Array(viewModel.healthCards.enumerated()), id: \.element.id) { index, card in
                            let isDimmed = shouldDimCard(at: index)
                            HealthCardTileView(
                                card: card,
                                isFlipped: flippedCardID == card.id,
                                onTap: {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                        if flippedCardID == card.id {
                                            flippedCardID = nil
                                        } else {
                                            flippedCardID = card.id
                                        }
                                    }
                                },
                                onAction: { action in
                                    handleAction(action, for: card)
                                }
                            )
                            .opacity(isDimmed ? 0.4 : 1.0)
                            .help(isDimmed ? "Address earlier issues first" : "")
                            .animation(.easeInOut(duration: 0.2), value: isDimmed)
                        }
                    }
                    .padding(.vertical, MSC.Spacing.xs)
                }
            }
        }
        .onAppear {
            viewModel.refreshHealthCardsForSelectedServer()
        }
        .onChange(of: viewModel.selectedServer) { _ in
            flippedCardID = nil
            viewModel.refreshHealthCardsForSelectedServer()
        }
    }

    // MARK: - Dim logic

    /// A card is dimmed when any card to its LEFT is red.
    private func shouldDimCard(at index: Int) -> Bool {
        guard index > 0 else { return false }
        let prior = viewModel.healthCards.prefix(index)
        return prior.contains(where: { $0.status == .red })
    }

    // MARK: - Action handler

    private func handleAction(_ action: HealthCardAction, for card: HealthCardResult) {
        switch action {
        case .openURL(let urlString):
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        case .openDockerDesktop:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Docker.app"))
        case .pullDockerImage:
            viewModel.updateBedrockImageAndRestart()
        case .openConsoleLog:
            onOpenConsoleLog?()
        case .locateFolder:
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.prompt = "Select Folder"
            panel.runModal()
        case .triggerDownload:
            viewModel.logAppMessage("[Health] User triggered JAR download from health card. See the Components tab to update or download the JAR.")
        case .openComponentsTab:
            viewModel.logAppMessage("[Health] Go to the Components tab to manage server components.")
        case .openRouterPortForwardGuide:
            viewModel.isShowingRouterPortForwardGuide = true
        }
    }
}

// MARK: - Individual card tile

private struct HealthCardTileView: View {
    let card: HealthCardResult
    let isFlipped: Bool
    let onTap: () -> Void
    let onAction: (HealthCardAction) -> Void

    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            // Front
            HealthCardFrontView(card: card)
                .opacity(isFlipped ? 0 : 1)
                .rotation3DEffect(.degrees(rotation), axis: (x: 0, y: 1, z: 0))
                .frame(width: 110, height: 130)

            // Back
            HealthCardBackView(card: card, onAction: onAction)
                .opacity(isFlipped ? 1 : 0)
                .rotation3DEffect(.degrees(rotation - 180), axis: (x: 0, y: 1, z: 0))
                .frame(width: 120, height: 145)  // slightly larger on back (~10%)
                .zIndex(isFlipped ? 1 : 0)
        }
        .frame(width: isFlipped ? 120 : 110, height: isFlipped ? 145 : 130)
        .onTapGesture(perform: onTap)
        .onChange(of: isFlipped) { flipped in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                rotation = flipped ? 180 : 0
            }
        }
    }
}

// MARK: - Card front
//
// Tier C fill + status left-accent bar for diagnostic identity at a glance.

private struct HealthCardFrontView: View {
    let card: HealthCardResult

    var body: some View {
        VStack(spacing: MSC.Spacing.xs) {
            Spacer()

            // Icon
            Image(systemName: iconName)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(iconColor)

            // Short label
            Text(shortLabel)
                .font(MSC.Typography.captionBold)
                .foregroundStyle(MSC.Colors.heading)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            // Status dot
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(MSC.Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .fill(MSC.Colors.tierContent)
        }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(statusColor.opacity(0.85))
                .frame(width: 3)
                .padding(.vertical, MSC.Spacing.sm)
        }
        .overlay {
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .stroke(MSC.Colors.contentBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous))
    }

    private var statusColor: Color {
        switch card.status {
        case .green:  return MSC.Colors.success
        case .yellow: return MSC.Colors.warning
        case .red:    return MSC.Colors.error
        case .gray:   return MSC.Colors.neutral
        }
    }

    private var iconColor: Color {
        switch card.status {
        case .green:  return MSC.Colors.success
        case .yellow: return MSC.Colors.warning
        case .red:    return MSC.Colors.error
        case .gray:   return MSC.Colors.tertiary
        }
    }

    private var iconName: String {
        switch card.id {
        case "directory":  return "folder.fill"
        case "java":       return "cup.and.saucer.fill"
        case "docker":     return "shippingbox.fill"
        case "jar":        return "doc.fill"
        case "bdsImage":   return "arrow.down.circle.fill"
        case "ram":        return "memorychip"
        case "worldData":  return "globe"
        case "port":       return "network"
        case "lastStartup":
            switch card.status {
            case .green:  return "checkmark.seal.fill"
            case .yellow: return "exclamationmark.seal.fill"
            case .red:    return "exclamationmark.seal.fill"
            case .gray:   return "seal"
            }
        default: return "questionmark.circle"
        }
    }

    private var shortLabel: String {
        switch card.id {
        case "directory":  return "Directory"
        case "java":       return "Java"
        case "docker":     return "Docker"
        case "jar":        return "Paper JAR"
        case "bdsImage":   return "BDS Image"
        case "ram":        return "RAM"
        case "worldData":  return "World Data"
        case "port":       return "Port"
        case "lastStartup": return "Last Start"
        default: return card.id
        }
    }
}

// MARK: - Card back

private struct HealthCardBackView: View {
    let card: HealthCardResult
    let onAction: (HealthCardAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.xs) {

            // Header row
            HStack(spacing: MSC.Spacing.xs) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(fullLabel)
                    .font(MSC.Typography.captionBold)
                    .foregroundStyle(MSC.Colors.heading)
            }

            Divider().opacity(0.3)

            // Detected value / description
            if let value = card.detectedValue {
                Text(value)
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.caption)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(statusDescription)
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.caption)
                    .lineLimit(4)
            }

            Spacer(minLength: 0)

            // Action button
            if let label = card.actionLabel, let action = card.actionType {
                Button {
                    onAction(action)
                } label: {
                    Text(label)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .buttonStyle(MSCSecondaryButtonStyle())
                .controlSize(.mini)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(MSC.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .fill(MSC.Colors.tierContent)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .stroke(statusColor.opacity(0.4), lineWidth: 1.5)
        )
    }

    private var statusColor: Color {
        switch card.status {
        case .green:  return MSC.Colors.success
        case .yellow: return MSC.Colors.warning
        case .red:    return MSC.Colors.error
        case .gray:   return MSC.Colors.neutral
        }
    }

    private var fullLabel: String {
        switch card.id {
        case "directory":   return "Server Directory"
        case "java":        return "Java Runtime"
        case "docker":      return "Docker Runtime"
        case "jar":         return "Paper JAR"
        case "bdsImage":    return "BDS Image"
        case "ram":         return "RAM Allocation"
        case "worldData":   return "World Data"
        case "port":        return "Port Reachability"
        case "lastStartup": return "Last Startup"
        default:            return card.id
        }
    }

    private var statusDescription: String {
        switch card.status {
        case .green:  return "Check passed."
        case .yellow: return "Inconclusive or attention recommended."
        case .red:    return "Action required before the server will work reliably."
        case .gray:   return "Not yet checked."
        }
    }
}

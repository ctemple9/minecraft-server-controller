//
//  HealthCardsGridView.swift
//  MinecraftServerController
//
//  Extracted from DetailsOverviewTabView so it can be referenced
//  by any tab view without being re-defined.
//
//  Contains: HealthCardsGridView, HealthGridCardTile,
//            HealthGridCardFront, HealthGridCardBack
//
//
//  Card Back Polish: Value blocks rendered as styled inset chips with
//  status-color left bars. Key/value rows use structured layout.
//  Action button uses filled pill treatment.
//

import SwiftUI

// MARK: - Zone 4: Health Cards Grid

/// 2-row × 3-column fixed grid. No horizontal scroll.
struct HealthCardsGridView: View {
    @EnvironmentObject var viewModel: AppViewModel

    /// Called when user taps "Go to Components" action on a health card.
    var onOpenComponentsTab: (() -> Void)? = nil

    @State private var flippedCardID: String? = nil

    private let columns = [
        GridItem(.flexible(), spacing: MSC.Spacing.sm),
        GridItem(.flexible(), spacing: MSC.Spacing.sm),
        GridItem(.flexible(), spacing: MSC.Spacing.sm)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {

            HStack {
                MSCOverline("Server Health")

                Spacer()
            }

            if viewModel.healthCards.isEmpty {
                LazyVGrid(columns: columns, spacing: MSC.Spacing.sm) {
                    ForEach(0..<6, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                            .fill(MSC.Colors.tierContent.opacity(0.6))
                            .frame(height: 95)
                            .overlay(ProgressView().controlSize(.small))
                    }
                }
            } else {
                LazyVGrid(columns: columns, spacing: MSC.Spacing.sm) {
                    ForEach(Array(viewModel.healthCards.enumerated()), id: \.element.id) { index, card in
                        let isDimmed = shouldDimCard(at: index)

                        HealthGridCardTile(
                            card: card,
                            isFlipped: flippedCardID == card.id,
                            onTap: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                    flippedCardID = flippedCardID == card.id ? nil : card.id
                                }
                            },
                            onAction: { action in handleAction(action) }
                        )
                        .opacity(isDimmed ? 0.4 : 1.0)
                        .help(isDimmed ? "Address earlier issues first" : "")
                        .animation(.easeInOut(duration: 0.2), value: isDimmed)
                    }
                }
            }
        }
        .onAppear { viewModel.refreshHealthCardsForSelectedServer() }
        .onChange(of: viewModel.selectedServer) { _ in
            flippedCardID = nil
            viewModel.refreshHealthCardsForSelectedServer()
        }
        .onChange(of: viewModel.onlinePlayers.count) { _ in
            // Re-check port card when player count changes — Bedrock UDP turns green
            // the moment a player successfully connects, without a manual refresh.
            viewModel.refreshHealthCardsForSelectedServer()
        }
    }

    private func shouldDimCard(at index: Int) -> Bool {
        guard index > 0 else { return false }
        return viewModel.healthCards.prefix(index).contains(where: { $0.status == .red })
    }

    private func handleAction(_ action: HealthCardAction) {
        switch action {
        case .openURL(let urlString):
            if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
        case .openDockerDesktop:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Docker.app"))
        case .pullDockerImage:
            viewModel.updateBedrockImageAndRestart()
        case .openConsoleLog:
            viewModel.logAppMessage("[Health] See the Console below for full startup log.")
        case .locateFolder:
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.prompt = "Select Folder"
            panel.runModal()
        case .triggerDownload:
            viewModel.logAppMessage("[Health] To update the Paper JAR, go to the Components tab.")
        case .openComponentsTab:
            onOpenComponentsTab?()
        case .openRouterPortForwardGuide:
            viewModel.isShowingRouterPortForwardGuide = true
        }
    }
}

// MARK: - Grid card tile (flip mechanic)

fileprivate struct HealthGridCardTile: View {
    let card: HealthCardResult
    let isFlipped: Bool
    let onTap: () -> Void
    let onAction: (HealthCardAction) -> Void

    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            HealthGridCardFront(card: card)
                .opacity(isFlipped ? 0 : 1)
                .rotation3DEffect(.degrees(rotation), axis: (x: 0, y: 1, z: 0))

            HealthGridCardBack(card: card, onAction: onAction)
                .opacity(isFlipped ? 1 : 0)
                .rotation3DEffect(.degrees(rotation - 180), axis: (x: 0, y: 1, z: 0))
        }
        .frame(height: isFlipped ? 130 : 95)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onChange(of: isFlipped) { flipped in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                rotation = flipped ? 180 : 0
            }
        }
    }
}

// MARK: - Grid card front
//
// Visual treatment: Tier C fill + colored left-accent bar showing
// status at a glance. Cleaner than full status-tint background.

fileprivate struct HealthGridCardFront: View {
    let card: HealthCardResult

    var body: some View {
        HStack(spacing: MSC.Spacing.sm) {

            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: MSC.Spacing.xxs) {
                Text(shortLabel)
                    .font(MSC.Typography.captionBold)
                    .foregroundStyle(MSC.Colors.heading)
                    .lineLimit(1)

                HStack(spacing: MSC.Spacing.xs) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(statusLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(statusColor)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(MSC.Colors.tertiary)
        }
        .padding(.horizontal, MSC.Spacing.md)
        .padding(.vertical, MSC.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .fill(MSC.Colors.tierContent)
        }
        .overlay(alignment: .leading) {
            // Status left-accent bar — 3pt wide, meaningful status signal, kept intentionally.
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(statusColor.opacity(0.85))
                .frame(width: 3)
                .padding(.vertical, MSC.Spacing.sm)
        }
        // Outer 1pt stroke omitted intentionally — accent bar + Tier C fill provide sufficient card identity.
        .clipShape(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 5, x: 0, y: 2)
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

    private var statusLabel: String {
        switch card.status {
        case .green:  return "OK"
        case .yellow: return "Warn"
        case .red:    return "Error"
        case .gray:   return "N/A"
        }
    }

    private var iconName: String {
        switch card.id {
        case "directory":  return "folder.fill"
        case "java":       return "cup.and.saucer.fill"
        case "docker":     return "shippingbox.fill"
        case "jar":        return "puzzlepiece.extension.fill"
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
        case "directory":   return "Directory"
        case "java":        return "Java"
        case "docker":      return "Docker"
        case "jar":         return "Components"
        case "bdsImage":    return "BDS Image"
        case "ram":         return "RAM"
        case "worldData":   return "World Data"
        case "port":        return "Port"
        case "lastStartup": return "Last Start"
        default: return card.id
        }
    }
}

// MARK: - Grid card back
//
// Visual treatment: Tier C fill. Status color on header strip + border.
// Values rendered as styled inset blocks; key/value rows use structured
// layout with status-color left accent. Action button is a filled pill.
//
//   ┌─────────────────────────────────────────┐
//   │ [icon] Full Label              [BADGE ←] │  ← status header strip
//   ├─────────────────────────────────────────┤
//   │ ▌ /path/to/value  OR                    │
//   │   KEY        value                       │
//   │   KEY        value                       │
//   ├─────────────────────────────────────────┤
//   │          [  Action Button  ]             │  ← filled pill
//   └─────────────────────────────────────────┘

fileprivate struct HealthGridCardBack: View {
    let card: HealthCardResult
    let onAction: (HealthCardAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header strip ──────────────────────────────────────────────
            HStack(spacing: MSC.Spacing.xs) {
                Image(systemName: headerIcon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(statusColor)

                Text(fullLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MSC.Colors.heading)
                    .lineLimit(1)

                Spacer()

                // Status badge pill
                Text(statusBadgeLabel)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(statusColor.opacity(0.18)))

                // Dismiss chevron
                Image(systemName: "chevron.left")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(MSC.Colors.tertiary)
            }
            .padding(.horizontal, MSC.Spacing.sm)
            .padding(.vertical, 7)
            .background(
                statusColor.opacity(0.08)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(statusColor.opacity(0.12))
                            .frame(height: 0.5)
                    }
            )

            // ── Detail body ───────────────────────────────────────────────
            Group {
                if let value = card.detectedValue {
                    detailBody(value: value)
                } else {
                    emptyBody
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // ── Action button ─────────────────────────────────────────────
            if let label = card.actionLabel, let action = card.actionType {
                Rectangle()
                    .fill(statusColor.opacity(0.12))
                    .frame(height: 0.5)

                Button {
                    onAction(action)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: actionIcon(for: action))
                            .font(.system(size: 9, weight: .semibold))
                        Text(label)
                            .font(.system(size: 9, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(statusColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(statusColor.opacity(0.12))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, MSC.Spacing.sm)
                .padding(.vertical, 5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .fill(MSC.Colors.tierContent)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .stroke(statusColor.opacity(0.35), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous))
    }

    // MARK: Detail body

    /// Renders the detectedValue string into structured visual rows.
    /// - Lines with a colon within the first 25 chars → key : value row
    /// - Everything else → styled plain value block
    @ViewBuilder
    private func detailBody(value: String) -> some View {
        let lines = value.components(separatedBy: "\n").filter { !$0.isEmpty }
        let kvLines = lines.filter {
            if let idx = $0.firstIndex(of: ":") {
                return $0.distance(from: $0.startIndex, to: idx) < 25
            }
            return false
        }
        let isKVLayout = !kvLines.isEmpty

        if isKVLayout {
            kvBody(lines: lines)
        } else {
            singleValueBody(value: value)
        }
    }

    /// Styled inset block for single-value items (paths, versions, etc.)
    private func singleValueBody(value: String) -> some View {
        HStack(spacing: 0) {
            // Status accent bar
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(statusColor.opacity(0.7))
                .frame(width: 2.5)

            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(MSC.Colors.body)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .padding(MSC.Spacing.sm)
    }

    /// Structured key/value rows with accent dots
    private func kvBody(lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.prefix(4).enumerated()), id: \.offset) { idx, line in
                if let colonIdx = line.firstIndex(of: ":"),
                   line.distance(from: line.startIndex, to: colonIdx) < 25 {
                    let key = String(line[..<colonIdx])
                    let val = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)

                    HStack(alignment: .top, spacing: 5) {
                        // Status accent dot
                        Circle()
                            .fill(statusColor.opacity(0.5))
                            .frame(width: 4, height: 4)
                            .padding(.top, 3)

                        Text(key.uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(MSC.Colors.tertiary)
                            .frame(width: 72, alignment: .leading)
                            .lineLimit(1)

                        Text(val)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(MSC.Colors.body)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, MSC.Spacing.sm)
                    .padding(.vertical, 5)
                    .background(
                        idx % 2 == 0
                        ? Color.clear
                        : Color.white.opacity(0.02)
                    )
                } else {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(statusColor.opacity(0.4))
                            .frame(width: 4, height: 4)
                        Text(line)
                            .font(.system(size: 11))
                            .foregroundStyle(MSC.Colors.body)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, MSC.Spacing.sm)
                    .padding(.vertical, 5)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Fallback when there is no detectedValue
    private var emptyBody: some View {
        HStack(spacing: 5) {
            Image(systemName: genericIcon)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(statusColor.opacity(0.6))
            Text(genericDescription)
                .font(.system(size: 9))
                .foregroundStyle(MSC.Colors.caption)
        }
        .padding(MSC.Spacing.sm)
    }

    // MARK: Computed props

    private var statusColor: Color {
        switch card.status {
        case .green:  return MSC.Colors.success
        case .yellow: return MSC.Colors.warning
        case .red:    return MSC.Colors.error
        case .gray:   return Color.secondary
        }
    }

    private var statusBadgeLabel: String {
        switch card.status {
        case .green:  return "OK"
        case .yellow: return "WARN"
        case .red:    return "ERR"
        case .gray:   return "N/A"
        }
    }

    private var headerIcon: String {
        switch card.id {
        case "directory":   return "folder.fill"
        case "java":        return "cup.and.saucer.fill"
        case "docker":      return "shippingbox.fill"
        case "jar":         return "puzzlepiece.extension.fill"
        case "ram":         return "memorychip"
        case "worldData":   return "globe"
        case "port":        return "network"
        case "lastStartup":
            switch card.status {
            case .green:         return "checkmark.seal.fill"
            case .yellow, .red:  return "exclamationmark.seal.fill"
            case .gray:          return "seal"
            }
        default: return "questionmark.circle"
        }
    }

    private var fullLabel: String {
        switch card.id {
        case "directory":   return "Server Directory"
        case "java":        return "Java Runtime"
        case "docker":      return "Docker Runtime"
        case "jar":         return "Components"
        case "ram":         return "RAM Allocation"
        case "worldData":   return "World Data"
        case "port":        return "Port Reachability"
        case "lastStartup": return "Last Startup"
        default:            return card.id
        }
    }

    private var genericDescription: String {
        switch card.status {
        case .green:  return "Check passed."
        case .yellow: return "Attention recommended."
        case .red:    return "Action required."
        case .gray:   return "Not yet checked."
        }
    }

    private var genericIcon: String {
        switch card.status {
        case .green:  return "checkmark.circle"
        case .yellow: return "exclamationmark.triangle"
        case .red:    return "xmark.circle"
        case .gray:   return "clock"
        }
    }

    private func actionIcon(for action: HealthCardAction) -> String {
        switch action {
        case .openURL:                   return "arrow.up.right.square"
        case .openDockerDesktop:         return "shippingbox"
        case .pullDockerImage:           return "arrow.down.circle"
        case .openConsoleLog:            return "terminal"
        case .locateFolder:              return "folder"
        case .triggerDownload:           return "arrow.down.circle"
        case .openComponentsTab:         return "cpu"
        case .openRouterPortForwardGuide:return "network"
        }
    }
}


//
//  OverviewPlayersStripView.swift
//  MinecraftServerController
//
//  Overview tab — "Players" card. Left: a 2-row, horizontally-scrolling grid of
//  player head tiles (online players, or recently-joined when off). Right: a
//  featured full-body render of the selected player with live hearts (health)
//  underneath. Bottom: a stats line (Online / Peak / Unique / Ops).
//
//  Tapping a head features that player (swaps the render + hearts). Tapping the
//  featured character opens the quick-actions popover (message, kick, op,
//  gamemode, teleport, whitelist).
//

import SwiftUI

struct OverviewPlayersStripView: View {
    @EnvironmentObject var viewModel: AppViewModel

    @Binding var messageTarget: OnlinePlayer?
    @Binding var messageText: String

    /// The player shown in the featured full-body render (and whose hearts show).
    @State private var featuredName: String? = nil
    @State private var showFeaturedActions = false

    /// Head grid rows: 1 (fewer, bigger heads) or 2 (more heads). Persisted.
    @AppStorage("msc.overview.playerGridRows") private var playerGridRows: Int = 2

    private var isSingleRow: Bool { playerGridRows == 1 }
    private var gridHeadSize: CGFloat { isSingleRow ? 72 : 44 }
    private var gridRowHeight: CGFloat { isSingleRow ? 104 : 70 }

    private var isBedrock: Bool {
        guard let s = viewModel.selectedServer else { return false }
        return viewModel.configServer(for: s)?.isBedrock ?? false
    }

    /// When the server is running we show live online players; otherwise the
    /// most-recently-seen saved profiles act as a "recently joined" list.
    private var showingOnline: Bool { viewModel.isServerRunning }

    /// Names to render as heads, with their resolved head identifier + op flag.
    private var entries: [PlayerStripEntry] {
        if showingOnline {
            return viewModel.onlinePlayers.map { p in
                let isOp = opFlag(for: p.name)
                return PlayerStripEntry(
                    name: p.name,
                    isOnline: true,
                    identifier: headIdentifier(for: p.name),
                    isOp: isOp,
                    subtitle: isOp ? "Operator" : "Online"
                )
            }
        } else {
            // Recently joined: saved profiles, newest-seen first, capped, hidden excluded.
            return viewModel.playerProfiles
                .filter { !isHidden($0) }
                .sorted { $0.lastModified > $1.lastModified }
                .prefix(24)
                .map { profile in
                    PlayerStripEntry(
                        name: profile.displayName,
                        isOnline: false,
                        identifier: profile.imageIdentifier,
                        isOp: profile.isOp,
                        subtitle: Self.relativeString(profile.lastModified)
                    )
                }
        }
    }

    /// Hidden players (Java by UUID, Bedrock by XUID) — mirrors the Players-tab feature.
    private func isHidden(_ profile: PlayerProfile) -> Bool {
        viewModel.isProfileHidden(profile)
    }

    private var hiddenProfiles: [PlayerProfile] {
        viewModel.playerProfiles.filter { isHidden($0) }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private static func relativeString(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    /// Currently featured player (full body + hearts). Falls back to the first
    /// entry when unset or when the selected name leaves the list.
    private var featuredEntry: PlayerStripEntry? {
        if let name = featuredName, let match = entries.first(where: { $0.name == name }) {
            return match
        }
        return entries.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {

            // Header
            HStack(spacing: MSC.Spacing.xs) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(MSC.Colors.tertiary)
                MSCOverline(showingOnline ? "Players" : "Recently Joined")
                Spacer()
                if showingOnline {
                    Text("\(viewModel.onlinePlayers.count) / \(viewModel.serverMaxPlayersForOverview) online")
                        .font(MSC.Typography.metaCaption)
                        .foregroundStyle(MSC.Colors.tertiary)
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        playerGridRows = isSingleRow ? 2 : 1
                    }
                } label: {
                    Image(systemName: isSingleRow ? "rectangle.grid.1x2" : "rectangle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MSC.Colors.tertiary)
                }
                .buttonStyle(.plain)
                .help(isSingleRow ? "Show two rows of heads" : "Show one larger row of heads")
            }

            if entries.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .center, spacing: MSC.Spacing.lg) {
                    headGrid
                        .frame(maxWidth: .infinity)
                    if let featured = featuredEntry {
                        featuredPanel(featured)
                            .frame(width: 150)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                statsLine
            }
        }
        .padding(MSC.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .fill(MSC.Colors.tierContent)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .stroke(MSC.Colors.contentBorder, lineWidth: 1)
        )
        .contextMenu {
            // Right-clicking empty space: restore hidden players.
            if hiddenProfiles.isEmpty {
                Text("No hidden players")
            } else {
                ForEach(hiddenProfiles) { profile in
                    Button {
                        viewModel.unhideProfile(profile)
                    } label: {
                        Label("Show \(profile.displayName)", systemImage: "eye")
                    }
                }
            }
        }
        .onAppear {
            viewModel.featuredPlayerName = featuredEntry?.name
            ensureFeaturedStatsLoaded()
        }
        .onChange(of: featuredEntry?.id) { id in
            viewModel.featuredPlayerName = id
            ensureFeaturedStatsLoaded()
        }
    }

    /// Player health lives in `PlayerStats`, which is loaded lazily (per profile).
    /// Trigger that load for the featured Java player so its saved hearts appear.
    private func ensureFeaturedStatsLoaded() {
        guard let featured = featuredEntry,
              let profile = matchedProfile(for: featured.name),
              profile.stats == nil,
              !profile.isBedrockPlayer else { return }
        viewModel.loadProfileNBT(uuid: profile.uuid)
    }

    // MARK: - Head grid (2-row horizontal scroll)

    private var headGrid: some View {
        let rows = Array(
            repeating: GridItem(.fixed(gridRowHeight), spacing: MSC.Spacing.sm),
            count: playerGridRows
        )
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: rows, spacing: MSC.Spacing.md) {
                ForEach(entries) { entry in
                    PlayerHeadTile(
                        entry: entry,
                        headSize: gridHeadSize,
                        isFeatured: entry.id == featuredEntry?.id,
                        onTap: { featuredName = entry.name }
                    )
                    .contextMenu { tileContextMenu(for: entry) }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
    }

    /// Right-click menu for a head: hide (recently-joined players, Java or Bedrock)
    /// plus an unhide submenu so hidden players can be restored from anywhere.
    @ViewBuilder
    private func tileContextMenu(for entry: PlayerStripEntry) -> some View {
        if !entry.isOnline, let profile = matchedProfile(for: entry.name) {
            Button {
                viewModel.hideProfile(profile)
            } label: {
                Label("Hide \(entry.name)", systemImage: "eye.slash")
            }
        }
        unhideMenuItems()
    }

    /// Shared unhide items (used by both the tile menu and the empty-space menu).
    @ViewBuilder
    private func unhideMenuItems() -> some View {
        let hidden = hiddenProfiles
        if !hidden.isEmpty {
            Divider()
            Menu("Show hidden player") {
                ForEach(hidden) { profile in
                    Button {
                        viewModel.unhideProfile(profile)
                    } label: {
                        Label(profile.displayName, systemImage: "eye")
                    }
                }
            }
        }
    }

    // MARK: - Featured player panel

    private func featuredPanel(_ featured: PlayerStripEntry) -> some View {
        GeometryReader { geo in
            VStack(spacing: 5) {
                Button { showFeaturedActions = true } label: {
                    PlayerBodyView(
                        identifier: featured.identifier,
                        height: max(72, geo.size.height - 62)
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .help("Quick actions for \(featured.name)")
                .popover(isPresented: $showFeaturedActions, arrowEdge: .leading) {
                    PlayerQuickActionsPopover(
                        entry: featured,
                        isBedrock: isBedrock,
                        dismiss: { showFeaturedActions = false },
                        messageTarget: $messageTarget,
                        messageText: $messageText
                    )
                    .environmentObject(viewModel)
                }

                Text(featured.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MSC.Colors.heading)
                    .lineLimit(1)
                    .truncationMode(.tail)

                heartsBlock(for: featured)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    @ViewBuilder
    private func heartsBlock(for featured: PlayerStripEntry) -> some View {
        let saved = matchedProfile(for: featured.name)?.stats
        let savedHealth = saved.map { Double($0.health) }
        let maxHealth = saved.map { Double($0.maxHealth) } ?? 20
        let live = featured.isOnline ? viewModel.featuredPlayerHealth : nil
        let health = live ?? savedHealth
        let isLive = featured.isOnline && viewModel.featuredPlayerHealth != nil

        if let health {
            VStack(spacing: 2) {
                HeartsRowView(health: health, maxHealth: maxHealth)
                HStack(spacing: 4) {
                    Circle()
                        .fill(isLive ? MSC.Colors.success : MSC.Colors.neutral)
                        .frame(width: 4, height: 4)
                    Text(isLive ? "Live" : "Last saved")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(MSC.Colors.tertiary)
                }
            }
        } else {
            Text("Health unavailable")
                .font(.system(size: 9))
                .foregroundStyle(MSC.Colors.tertiary)
        }
    }

    // MARK: - Stats line

    private var statsLine: some View {
        HStack(spacing: MSC.Spacing.sm) {
            statChip(dot: MSC.Colors.success, icon: nil,
                     label: "Online", value: "\(viewModel.onlinePlayers.count)")
            if let peak = viewModel.playerCountHistory.max(), peak > 0 {
                statChip(dot: nil, icon: "chart.line.uptrend.xyaxis",
                         label: "Peak", value: "\(peak)")
            }
            statChip(dot: nil, icon: "person",
                     label: "Unique", value: "\(viewModel.playerProfiles.count)")
            statChip(dot: nil, icon: "star",
                     label: "Ops", value: "\(viewModel.playerProfiles.filter { $0.isOp }.count)")
            Spacer()
        }
    }

    private func statChip(dot: Color?, icon: String?, label: String, value: String) -> some View {
        HStack(spacing: 5) {
            if let dot {
                Circle().fill(dot).frame(width: 5, height: 5)
            } else if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(MSC.Colors.tertiary)
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(MSC.Colors.tertiary)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MSC.Colors.body)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
    }

    // MARK: - Helpers

    /// Resolves the mc-heads identifier for an online player name by matching a
    /// saved profile (handles Bedrock floodgate UUIDs); falls back to the raw
    /// name, which mc-heads accepts as a Java username.
    private func headIdentifier(for name: String) -> String {
        if let p = matchedProfile(for: name) { return p.imageIdentifier }
        return name
    }

    private func opFlag(for name: String) -> Bool {
        if isBedrock { return viewModel.isBedrockOperator(named: name) }
        return matchedProfile(for: name)?.isOp ?? false
    }

    private func matchedProfile(for name: String) -> PlayerProfile? {
        viewModel.playerProfiles.first {
            $0.displayName.caseInsensitiveCompare(name) == .orderedSame
            || ($0.username?.caseInsensitiveCompare(name) == .orderedSame)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        HStack(spacing: MSC.Spacing.sm) {
            Image(systemName: showingOnline ? "person.2.slash" : "clock.arrow.circlepath")
                .font(.system(size: 16))
                .foregroundStyle(MSC.Colors.tertiary)
            Text(showingOnline
                 ? "No players online."
                 : "No one has joined yet.")
                .font(MSC.Typography.caption)
                .foregroundStyle(MSC.Colors.caption)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, MSC.Spacing.sm)
    }
}

// MARK: - Strip entry model

struct PlayerStripEntry: Identifiable {
    let name: String
    let isOnline: Bool
    let identifier: String
    let isOp: Bool
    /// Small line under the name: "Online" / "Operator" when live, or a relative
    /// last-seen ("2h ago") for the recently-joined list.
    let subtitle: String
    var id: String { name }
}

// MARK: - Head tile (tap to feature)

private struct PlayerHeadTile: View {
    let entry: PlayerStripEntry
    var headSize: CGFloat = 46
    let isFeatured: Bool
    let onTap: () -> Void

    private var ringColor: Color {
        if isFeatured { return MSC.Colors.accent }
        return entry.isOnline ? MSC.Colors.success.opacity(0.8) : MSC.Colors.contentBorder
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    PlayerHeadView(identifier: entry.identifier, size: headSize)
                        .opacity(entry.isOnline ? 1.0 : 0.6)
                        .overlay(
                            RoundedRectangle(cornerRadius: headSize * 0.15, style: .continuous)
                                .stroke(ringColor, lineWidth: isFeatured ? 2.5 : (entry.isOnline ? 2 : 1))
                        )

                    if entry.isOp {
                        Image(systemName: "star.fill")
                            .font(.system(size: headSize * 0.2))
                            .foregroundStyle(Color.yellow.opacity(0.9))
                            .padding(headSize * 0.05)
                            .background(Circle().fill(MSC.Colors.tierContent))
                            .offset(x: 4, y: -4)
                    }
                }

                VStack(spacing: 0) {
                    Text(entry.name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(entry.isOnline ? MSC.Colors.body : MSC.Colors.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(entry.subtitle)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(entry.isOnline ? MSC.Colors.success : MSC.Colors.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: headSize + 30)
            }
        }
        .buttonStyle(.plain)
        .help(entry.name)
    }
}

// MARK: - Hearts row (health)

/// Renders Minecraft-style hearts: 1 heart = 2 HP, with half-hearts.
private struct HeartsRowView: View {
    let health: Double
    let maxHealth: Double

    var body: some View {
        let containers = min(10, max(1, Int((maxHealth / 2).rounded(.up))))
        HStack(spacing: 2) {
            ForEach(0..<containers, id: \.self) { i in
                heart(forContainer: i)
            }
        }
    }

    private func heart(forContainer i: Int) -> some View {
        let lower = Double(i * 2)
        let symbol: String
        let color: Color
        if health >= lower + 2 {
            symbol = "heart.fill";            color = .red
        } else if health > lower {
            symbol = "heart.lefthalf.filled"; color = .red
        } else {
            symbol = "heart";                 color = MSC.Colors.tertiary
        }
        return Image(systemName: symbol)
            .font(.system(size: 10))
            .foregroundStyle(color)
    }
}

// MARK: - Quick actions popover

private struct PlayerQuickActionsPopover: View {
    @EnvironmentObject var viewModel: AppViewModel

    let entry: PlayerStripEntry
    let isBedrock: Bool
    let dismiss: () -> Void
    @Binding var messageTarget: OnlinePlayer?
    @Binding var messageText: String

    private var isRunning: Bool { viewModel.isServerRunning }
    private var isOnline: Bool { entry.isOnline && isRunning }

    private var knownBedrockXUID: String? {
        isBedrock ? viewModel.bedrockXUID(forPlayerNamed: entry.name) : nil
    }

    /// Other online players that this player can teleport to.
    private var teleportTargets: [String] {
        viewModel.onlinePlayers
            .map(\.name)
            .filter { $0.caseInsensitiveCompare(entry.name) != .orderedSame }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {

            // Header
            HStack(spacing: MSC.Spacing.sm) {
                PlayerHeadView(identifier: entry.identifier, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.name)
                        .font(MSC.Typography.captionBold)
                        .foregroundStyle(MSC.Colors.heading)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isOnline ? MSC.Colors.success : MSC.Colors.neutral)
                            .frame(width: 6, height: 6)
                        Text(isOnline ? "Online" : "Offline")
                            .font(.system(size: 10))
                            .foregroundStyle(MSC.Colors.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }

            Divider()

            // Primary actions
            HStack(spacing: MSC.Spacing.sm) {
                Button {
                    messageTarget = viewModel.onlinePlayers.first { $0.name == entry.name }
                        ?? OnlinePlayer(name: entry.name)
                    messageText = ""
                    dismiss()
                } label: {
                    Label("Message", systemImage: "bubble.left")
                }
                .controlSize(.small)
                .disabled(!isOnline)

                Button(role: .destructive) {
                    viewModel.kickPlayer(named: entry.name)
                    dismiss()
                } label: {
                    Label("Kick", systemImage: "door.left.hand.open")
                }
                .controlSize(.small)
                .disabled(!isOnline)

                Spacer()
            }

            // Operator row
            HStack(spacing: MSC.Spacing.sm) {
                if isBedrock {
                    let isOp = viewModel.isBedrockOperator(named: entry.name)
                    Button(isOp ? "Operator" : "Promote to Op") {
                        viewModel.opPlayer(named: entry.name)
                        dismiss()
                    }
                    .controlSize(.small)
                    .disabled(knownBedrockXUID == nil || isOp)

                    Button("Remove Op") {
                        viewModel.deopPlayer(named: entry.name)
                        dismiss()
                    }
                    .controlSize(.small)
                    .disabled(knownBedrockXUID == nil || !viewModel.isBedrockOperator(named: entry.name))
                } else {
                    Button("Op") { viewModel.opPlayer(named: entry.name); dismiss() }
                        .controlSize(.small)
                        .disabled(!isRunning)
                    Button("Deop") { viewModel.deopPlayer(named: entry.name); dismiss() }
                        .controlSize(.small)
                        .disabled(!isRunning)
                }
                Spacer()
            }

            if isBedrock, knownBedrockXUID == nil {
                Text("Operator changes need an XUID — have this player join once so MSC can capture it.")
                    .font(.system(size: 10))
                    .foregroundStyle(MSC.Colors.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // Gamemode
            VStack(alignment: .leading, spacing: 4) {
                Text("GAMEMODE")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(MSC.Colors.tertiary)
                HStack(spacing: 4) {
                    ForEach(["survival", "creative", "adventure", "spectator"], id: \.self) { mode in
                        Button(mode.prefix(1).uppercased()) {
                            viewModel.setGamemode(mode, forPlayer: entry.name)
                            dismiss()
                        }
                        .controlSize(.small)
                        .disabled(!isOnline)
                        .help(mode.capitalized)
                    }
                    Spacer()
                }
            }

            // Quick commands
            HStack(spacing: MSC.Spacing.sm) {
                Menu {
                    if teleportTargets.isEmpty {
                        Text("No other players online")
                    } else {
                        ForEach(teleportTargets, id: \.self) { target in
                            Button("To \(target)") {
                                viewModel.teleportPlayer(named: entry.name, toPlayer: target)
                                dismiss()
                            }
                        }
                    }
                } label: {
                    Label("Teleport", systemImage: "figure.walk.motion")
                }
                .menuStyle(.borderlessButton)
                .controlSize(.small)
                .disabled(!isOnline || teleportTargets.isEmpty)
                .fixedSize()

                Button {
                    viewModel.whitelistPlayer(named: entry.name, add: true)
                    dismiss()
                } label: {
                    Label("Whitelist", systemImage: "checkmark.shield")
                }
                .controlSize(.small)

                Spacer()
            }
        }
        .padding(MSC.Spacing.md)
        .frame(width: 250)
    }
}

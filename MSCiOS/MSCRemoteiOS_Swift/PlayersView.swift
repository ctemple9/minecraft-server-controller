import SwiftUI

// MARK: - PlayersView
//
// Shows online player count and a list of connected players.
// Tapping a player expands an inline action panel — no sheet or navigation
// push needed. This "expand-in-place" pattern keeps context clear: you
// can see the player you're acting on throughout the interaction.
//
// All player actions translate directly into server commands sent via
// the existing sendCommand path. This is the correct architecture here —
// the macOS API doesn't expose player-specific REST endpoints, so commands
// are the universal interface, exactly as they are on the Commands tab.

struct PlayersView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var vm: DashboardViewModel

    // The currently expanded player, if any.
    // Only one player can be expanded at a time — expanding another
    // collapses the previous one automatically.
    @State private var expandedPlayerName: String? = nil

    private var isPaired: Bool {
        settings.resolvedBaseURL() != nil && settings.resolvedToken() != nil
    }

    /// Resolved type of the active server — used to gate Java-only player actions.
    private var activeServerType: ServerType {
        if let fromServers = vm.servers.first(where: { $0.id == (vm.status?.activeServerId ?? "") })?.resolvedServerType {
            return fromServers
        }
        return vm.status?.resolvedServerType ?? .java
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MSCRemoteStyle.bgBase.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: MSCRemoteStyle.spaceLG) {
                        playerCountCard
                        playerListCard
                        footerText
                    }
                    .padding(.horizontal, MSCRemoteStyle.spaceLG)
                    .padding(.top, MSCRemoteStyle.spaceMD)
                    .padding(.bottom, MSCRemoteStyle.space2XL)
                }
            }
            .navigationTitle("Players")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(MSCRemoteStyle.bgBase, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    // MARK: - Player Count Card

    private var playerCountCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            MSCSectionHeader(title: "Online")
                .padding(.bottom, MSCRemoteStyle.spaceMD)

            HStack(spacing: MSCRemoteStyle.spaceMD) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(vm.performanceLatest?.playersOnline.map(String.init) ?? "—")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(MSCRemoteStyle.textPrimary)
                    Text("players online")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(MSCRemoteStyle.textTertiary)
                }
                Spacer()
                MSCStatusDot(isActive: vm.status?.running == true, size: 14)
            }
        }
        .mscCard()
    }

    // MARK: - Player List Card

    private var playerListCard: some View {
        let list = vm.players?.players ?? []
        let isRunning = vm.status?.running == true

        return VStack(alignment: .leading, spacing: 0) {
            MSCSectionHeader(title: "Online Now")
                .padding(.bottom, MSCRemoteStyle.spaceMD)

            if !isPaired {
                Text("Pair with your Mac to see players.")
                    .font(.system(size: 13))
                    .foregroundStyle(MSCRemoteStyle.textTertiary)
            } else if !isRunning || list.isEmpty {
                HStack(spacing: MSCRemoteStyle.spaceSM) {
                    Image(systemName: "person.slash")
                        .font(.system(size: 13))
                        .foregroundStyle(MSCRemoteStyle.textTertiary)
                    Text("No players online")
                        .font(.system(size: 13))
                        .foregroundStyle(MSCRemoteStyle.textTertiary)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(list) { player in
                        ExpandablePlayerRow(
                            player: player,
                            serverType: activeServerType,
                            isExpanded: expandedPlayerName == player.name,
                            onToggle: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    if expandedPlayerName == player.name {
                                        expandedPlayerName = nil
                                    } else {
                                        expandedPlayerName = player.name
                                    }
                                }
                            },
                            onAction: { command in
                                Task { await sendCommand(command) }
                            }
                        )

                        if player.id != list.last?.id {
                            Divider()
                                .background(MSCRemoteStyle.borderSubtle)
                                .padding(.leading, 44)
                        }
                    }
                }
            }
        }
        .mscCard()
    }

    // MARK: - Footer

    private var footerText: some View {
        Text("TempleTech · MSC REMOTE")
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .foregroundStyle(MSCRemoteStyle.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Command dispatch
    //
    // Delegates to DashboardViewModel.sendCommand, which is the same path
    // used by CommandsView. Player actions are just server commands with
    // the player name interpolated — there's no separate player API.

    private func sendCommand(_ command: String) async {
        guard let baseURL = settings.resolvedBaseURL(),
              let token = settings.resolvedToken() else { return }
        _ = await vm.sendCommand(baseURL: baseURL, token: token, command: command)
    }
}

// MARK: - ExpandablePlayerRow
//
// Composes PlayerRow (avatar + name) with an animated inline action panel.
// The panel appears below the name row with a spring animation — it feels
// physical and intentional, not like a sheet materialising from nowhere.
//
// Why inline expansion vs. a sheet?
// Sheets on iOS draw focus away from the list and require an extra dismiss
// tap. Inline expansion keeps the player name visible throughout the action,
// so there's no ambiguity about who you're acting on.

struct ExpandablePlayerRow: View {
    let player: PlayerDTO
    let serverType: ServerType
    let isExpanded: Bool
    let onToggle: () -> Void
    let onAction: (String) -> Void

    // Tracks the confirm state for destructive actions.
    // Only one confirmation prompt can be active at a time per row.
    @State private var pendingConfirmCommand: String? = nil
    @State private var pendingConfirmLabel: String? = nil
    @State private var showConfirm: Bool = false

    // Message field state — shown when the message action is tapped.
    @State private var showMessageField: Bool = false
    @State private var messageText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Tappable header row
            Button(action: onToggle) {
                HStack(spacing: MSCRemoteStyle.spaceMD) {
                    playerAvatar
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                    Text(player.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(MSCRemoteStyle.textPrimary)

                    Spacer()

                    // Chevron indicates expandability
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MSCRemoteStyle.textTertiary)
                }
                .padding(.vertical, MSCRemoteStyle.spaceSM)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded action panel — hidden by default, animated in on expand.
            // `clipped()` ensures the panel doesn't bleed outside the card
            // during the height animation.
            if isExpanded {
                VStack(spacing: MSCRemoteStyle.spaceSM) {
                    Divider()
                        .background(MSCRemoteStyle.borderSubtle)
                        .padding(.horizontal, -MSCRemoteStyle.spaceLG)

                    // Message player (non-destructive)
                    if showMessageField {
                        messageInputRow
                    } else {
                        actionGrid
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .padding(.bottom, MSCRemoteStyle.spaceSM)
            }
        }
        .alert("Confirm Action", isPresented: $showConfirm) {
            Button("Cancel", role: .cancel) {
                pendingConfirmCommand = nil
                pendingConfirmLabel = nil
            }
            Button(pendingConfirmLabel ?? "Confirm", role: .destructive) {
                if let cmd = pendingConfirmCommand {
                    onAction(cmd)
                }
                pendingConfirmCommand = nil
                pendingConfirmLabel = nil
            }
        } message: {
            Text("Send \"\(pendingConfirmLabel ?? "this command")\" for \(player.name)?")
        }
    }

    // MARK: - Action Grid
    //
    // Two-column grid of labeled action buttons. Each action maps to a
    // specific Minecraft server command with the player name interpolated.
    //
    // Destructive actions (kick, ban, deop) require a confirmation tap
    // before the command is sent. This mirrors the CommandsView danger-check
    // and protects against accidental taps in a list.

    private var actionGrid: some View {
        VStack(spacing: MSCRemoteStyle.spaceSM) {
            // Row 1: Message (Java only — /tell not supported on BDS stdin) + TP to spawn
            HStack(spacing: MSCRemoteStyle.spaceSM) {
                if serverType == .java {
                    playerActionButton(
                        title: "Message",
                        icon: "bubble.left.fill",
                        tint: MSCRemoteStyle.accent,
                        destructive: false
                    ) {
                        withAnimation { showMessageField = true }
                    }
                }

                playerActionButton(
                    title: "TP to Spawn",
                    icon: "location.fill",
                    tint: MSCRemoteStyle.actionMessage,
                    destructive: false
                ) {
                    // /tp works on both Java and BDS
                    onAction("/tp \(player.name) 0 64 0")
                }
            }

            // Row 2: Gamemode survival + creative
            HStack(spacing: MSCRemoteStyle.spaceSM) {
                playerActionButton(
                    title: "Survival",
                    icon: "shield.fill",
                    tint: MSCRemoteStyle.actionKick,
                    destructive: false
                ) {
                    onAction("/gamemode survival \(player.name)")
                }

                playerActionButton(
                    title: "Creative",
                    icon: "wand.and.stars",
                    tint: MSCRemoteStyle.actionBan,
                    destructive: false
                ) {
                    onAction("/gamemode creative \(player.name)")
                }
            }

            // Row 3: OP + Kick
            HStack(spacing: MSCRemoteStyle.spaceSM) {
                playerActionButton(
                    title: "Make OP",
                    icon: "star.fill",
                    tint: MSCRemoteStyle.actionKick,
                    destructive: true
                ) {
                    // Both Java and BDS use /op <name>
                    triggerConfirm(command: "/op \(player.name)", label: "Make OP")
                }

                playerActionButton(
                    title: "Kick",
                    icon: "person.fill.xmark",
                    tint: MSCRemoteStyle.danger,
                    destructive: true
                ) {
                    // Both Java and BDS use /kick <name>
                    triggerConfirm(command: "/kick \(player.name)", label: "Kick")
                }
            }
        }
        .padding(.top, MSCRemoteStyle.spaceSM)
    }

    // MARK: - Message Input Row

    private var messageInputRow: some View {
        VStack(alignment: .leading, spacing: MSCRemoteStyle.spaceSM) {
            HStack(spacing: MSCRemoteStyle.spaceSM) {
                Text(">")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(MSCRemoteStyle.accent)

                TextField("Message to \(player.name)…", text: $messageText)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(MSCRemoteStyle.textPrimary)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.send)
                    .onSubmit { sendMessage() }
            }
            .padding(MSCRemoteStyle.spaceSM)
            .background(MSCRemoteStyle.bgDeep)
            .clipShape(RoundedRectangle(cornerRadius: MSCRemoteStyle.radiusSM, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MSCRemoteStyle.radiusSM, style: .continuous)
                    .strokeBorder(MSCRemoteStyle.borderMid, lineWidth: 1)
            )

            HStack(spacing: MSCRemoteStyle.spaceSM) {
                Button {
                    withAnimation { showMessageField = false }
                    messageText = ""
                } label: {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .foregroundStyle(MSCRemoteStyle.textSecondary)
                        .background(MSCRemoteStyle.bgElevated)
                        .clipShape(RoundedRectangle(cornerRadius: MSCRemoteStyle.radiusSM, style: .continuous))
                }

                Button {
                    sendMessage()
                } label: {
                    Text("Send")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .foregroundStyle(messageText.trimmingCharacters(in: .whitespaces).isEmpty ? MSCRemoteStyle.textTertiary : MSCRemoteStyle.bgBase)
                        .background(messageText.trimmingCharacters(in: .whitespaces).isEmpty ? MSCRemoteStyle.bgElevated : MSCRemoteStyle.accent)
                        .clipShape(RoundedRectangle(cornerRadius: MSCRemoteStyle.radiusSM, style: .continuous))
                }
                .disabled(messageText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.top, MSCRemoteStyle.spaceSM)
    }

    // MARK: - Sub-components

    /// A square action button used in the player action grid.
    private func playerActionButton(
        title: String,
        icon: String,
        tint: Color,
        destructive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(destructive ? MSCRemoteStyle.danger : tint)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(destructive ? MSCRemoteStyle.danger : MSCRemoteStyle.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                destructive
                    ? MSCRemoteStyle.danger.opacity(0.10)
                    : tint.opacity(0.10)
            )
            .clipShape(RoundedRectangle(cornerRadius: MSCRemoteStyle.radiusSM, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MSCRemoteStyle.radiusSM, style: .continuous)
                    .strokeBorder(
                        destructive
                            ? MSCRemoteStyle.danger.opacity(0.25)
                            : tint.opacity(0.25),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var playerAvatar: some View {
        Group {
            if let uuid = player.uuid, !uuid.isEmpty,
               let url = URL(string: "https://crafatar.com/avatars/\(uuid)?size=32&overlay=true") {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                    case .failure:
                        genericAvatarIcon
                    case .empty:
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(MSCRemoteStyle.bgElevated)
                    @unknown default:
                        genericAvatarIcon
                    }
                }
            } else {
                genericAvatarIcon
            }
        }
    }

    private var genericAvatarIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(MSCRemoteStyle.bgElevated)
            Image(systemName: "person.fill")
                .font(.system(size: 14))
                .foregroundStyle(MSCRemoteStyle.textTertiary)
        }
    }

    // MARK: - Helpers

    private func triggerConfirm(command: String, label: String) {
        hapticLight()
        pendingConfirmCommand = command
        pendingConfirmLabel = label
        showConfirm = true
    }

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        hapticLight()
        // /tell is the private message command in vanilla/Paper Minecraft.
        // /msg and /w are aliases — /tell is most universally supported.
        onAction("/tell \(player.name) \(text)")
        messageText = ""
        withAnimation { showMessageField = false }
    }
}



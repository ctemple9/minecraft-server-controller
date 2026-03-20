//
//  DetailsPlayersTabView.swift
//  MinecraftServerController
//
//  Players tab — combines:
//    - Online Now / Session History columns (from OverviewPlayersCardView)
//    - Bedrock allowlist manager
//    - Full session log timeline (formerly a sheet)
//

import SwiftUI

struct DetailsPlayersTabView: View {
    @EnvironmentObject var viewModel: AppViewModel

    @State private var filterText: String = ""
    @State private var showClearConfirm: Bool = false
    @State private var newAllowlistEntry: String = ""
    @State private var messageTarget: OnlinePlayer?
    @State private var messageText: String = ""

    private var isBedrock: Bool {
        guard let s = viewModel.selectedServer else { return false }
        return viewModel.configServer(for: s)?.isBedrock ?? false
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: MSC.Spacing.md) {

                // Online Now card
                onlineNowCard

                // Bedrock allowlist (Bedrock only)
                if isBedrock {
                    bedrockAllowlistCard
                }

                // Session log
                sessionLogCard
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, MSC.Spacing.md)
        }
        .sheet(item: $messageTarget) { player in
            MessagePlayerSheetView(
                player: player,
                messageTarget: $messageTarget,
                messageText: $messageText
            )
        }
        .onAppear {
            if isBedrock { viewModel.loadBedrockAllowlistIfNeeded() }
        }
        .confirmationDialog(
            "Clear session log for this server?",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear Log", role: .destructive) {
                viewModel.clearSessionLog()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all recorded join and leave events. This cannot be undone.")
        }
    }

    // MARK: - Online Now card

    private var onlineNowCard: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {

            HStack {
                Label("Players", systemImage: "person.2")
                    .font(MSC.Typography.cardTitle)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(viewModel.onlinePlayers.count) online")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(.secondary)
                if !isBedrock {
                    Button("Refresh") {
                        viewModel.refreshPlayersAndTps()
                    }
                    .controlSize(.small)
                    .disabled(!viewModel.isServerRunning)
                }
            }

            Divider()

            HStack(alignment: .top, spacing: MSC.Spacing.lg) {

                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                    Text("Online Now")
                        .font(MSC.Typography.captionBold)
                        .foregroundStyle(.secondary)
                    if viewModel.onlinePlayers.isEmpty {
                        Text("No players online.")
                            .font(MSC.Typography.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    } else {
                        ForEach(viewModel.onlinePlayers) { player in
                            PlayerOnlineRow(player: player, messageTarget: $messageTarget)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                Divider()

                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                    Text("Seen This Session")
                        .font(MSC.Typography.captionBold)
                        .foregroundStyle(.secondary)
                    if viewModel.playerSessionHistory.isEmpty {
                        Text("No history yet.")
                            .font(MSC.Typography.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    } else {
                        ForEach(viewModel.playerSessionHistory, id: \.self) { name in
                            HStack(spacing: MSC.Spacing.sm) {
                                let isOnline = viewModel.onlinePlayers.contains { $0.name == name }
                                Circle()
                                    .fill(isOnline ? Color.green : Color.secondary.opacity(0.4))
                                    .frame(width: 6, height: 6)
                                Text(name)
                                    .font(MSC.Typography.caption)
                                    .foregroundStyle(isOnline ? .primary : .secondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(MSC.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .fill(MSC.Colors.tierContent)
        )
    }

    // MARK: - Bedrock Allowlist card

    private var bedrockAllowlistCard: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {

            HStack {
                Label("Allowlist", systemImage: "list.bullet.clipboard")
                    .font(MSC.Typography.cardTitle)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(viewModel.bedrockAllowlist.count) entries")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.caption)
                Button {
                    viewModel.loadBedrockAllowlistIfNeeded()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .font(MSC.Typography.caption)
                .help("Reload allowlist from disk")
            }

            Divider()

            // Add row
            HStack(spacing: MSC.Spacing.sm) {
                TextField("Gamertag", text: $newAllowlistEntry)
                    .textFieldStyle(.roundedBorder)
                    .font(MSC.Typography.caption)
                    .onSubmit { commitAllowlistAdd() }
                Button("Add") { commitAllowlistAdd() }
                    .controlSize(.small)
                    .disabled(newAllowlistEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if viewModel.bedrockAllowlist.isEmpty {
                Text("Allowlist is empty. All players can join.")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.caption)
                    .padding(.top, 2)
            } else {
                ForEach(viewModel.bedrockAllowlist) { entry in
                    HStack(spacing: MSC.Spacing.sm) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(MSC.Colors.success)
                        Text(entry.name)
                            .font(MSC.Typography.caption)
                        Spacer()
                        Button {
                            viewModel.removeFromBedrockAllowlist(gamertag: entry.name)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(MSC.Colors.error)
                        }
                        .buttonStyle(.plain)
                        .help("Remove \(entry.name) from allowlist")
                    }
                }
            }

            Text("Note: allowlist is only enforced when online-mode is enabled in server properties.")
                .font(MSC.Typography.caption)
                .foregroundStyle(MSC.Colors.caption)
                .padding(.top, MSC.Spacing.xxs)
        }
        .padding(MSC.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .fill(MSC.Colors.tierContent)
        )
    }

    private func commitAllowlistAdd() {
        let trimmed = newAllowlistEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.addToBedrockAllowlist(gamertag: trimmed)
        newAllowlistEntry = ""
    }

    // MARK: - Session log card (full timeline inline)

    private var sessionLogCard: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {

            HStack {
                Label("Session Log", systemImage: "clock")
                    .font(MSC.Typography.cardTitle)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Clear Log") {
                    showClearConfirm = true
                }
                .foregroundStyle(MSC.Colors.error)
                .font(MSC.Typography.caption)
                .buttonStyle(.plain)
                .disabled(viewModel.sessionEvents.isEmpty)
            }

            Divider()

            // Filter bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(MSC.Colors.tertiary)
                TextField("Filter by player name", text: $filterText)
                    .textFieldStyle(.plain)
                    .font(MSC.Typography.caption)
                if !filterText.isEmpty {
                    Button {
                        filterText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(MSC.Colors.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, MSC.Spacing.sm)
            .padding(.vertical, MSC.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.sm)
                    .fill(MSC.Colors.subtleBackground)
            )

            if viewModel.sessionEvents.isEmpty {
                VStack(spacing: MSC.Spacing.sm) {
                    Image(systemName: "clock.badge.xmark")
                        .font(.system(size: 28))
                        .foregroundStyle(MSC.Colors.tertiary)
                    Text("No session events recorded yet.")
                        .font(MSC.Typography.caption)
                        .foregroundStyle(MSC.Colors.caption)
                    Text("Player join and leave events will appear here once the server has run.")
                        .font(MSC.Typography.caption)
                        .foregroundStyle(MSC.Colors.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(MSC.Spacing.lg)
            } else {
                let filteredDays = filteredSessionDays
                if filteredDays.isEmpty {
                    Text("No events match \"\(filterText)\".")
                        .font(MSC.Typography.caption)
                        .foregroundStyle(MSC.Colors.caption)
                        .padding(MSC.Spacing.md)
                } else {
                    ForEach(filteredDays, id: \.day) { section in
                        VStack(alignment: .leading, spacing: 0) {
                            // Day header
                            HStack {
                                Text(section.day, style: .date)
                                    .font(MSC.Typography.captionBold)
                                    .foregroundStyle(MSC.Colors.tertiary)
                                Spacer()
                            }
                            .padding(.vertical, MSC.Spacing.xs)
                            .padding(.horizontal, MSC.Spacing.sm)
                            .background(MSC.Colors.subtleBackground.opacity(0.5))

                            ForEach(section.events) { event in
                                InlineSessionEventRow(
                                    event: event,
                                    duration: viewModel.sessionDuration(after: event)
                                )
                            }
                        }
                    }
                }
            }
        }
        .padding(MSC.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .fill(MSC.Colors.tierContent)
        )
    }

    private var filteredSessionDays: [(day: Date, events: [SessionEvent])] {
        let trim = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trim.isEmpty else { return viewModel.sessionEventsByDay }
        return viewModel.sessionEventsByDay.compactMap { section in
            let filtered = section.events.filter {
                $0.playerName.lowercased().contains(trim)
            }
            return filtered.isEmpty ? nil : (day: section.day, events: filtered)
        }
    }
}

// MARK: - Player online row

private struct PlayerOnlineRow: View {
    let player: OnlinePlayer
    @Binding var messageTarget: OnlinePlayer?

    var body: some View {
        HStack(spacing: MSC.Spacing.sm) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
            Text(player.name)
                .font(MSC.Typography.caption)
            Spacer()
            Button {
                messageTarget = player
            } label: {
                Image(systemName: "message")
                    .font(.system(size: 11))
                    .foregroundStyle(MSC.Colors.caption)
            }
            .buttonStyle(.plain)
            .help("Send message to \(player.name)")
        }
    }
}

// MARK: - Inline session event row

private struct InlineSessionEventRow: View {
    let event: SessionEvent
    let duration: String?

    private var isJoin: Bool { event.eventType == .joined }

    var body: some View {
        HStack(spacing: MSC.Spacing.sm) {
            Image(systemName: isJoin ? "arrow.right.circle.fill" : "arrow.left.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(isJoin ? MSC.Colors.success : MSC.Colors.caption)
                .frame(width: 16)

            Text(event.playerName)
                .font(MSC.Typography.caption)
                .lineLimit(1)

            Text(isJoin ? "joined" : "left")
                .font(MSC.Typography.caption)
                .foregroundStyle(isJoin ? MSC.Colors.success : MSC.Colors.caption)

            Spacer()

            if let duration, isJoin {
                Text(duration)
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(MSC.Colors.cardBorder.opacity(0.4))
                    )
            }

            Text(event.timestamp, style: .time)
                .font(MSC.Typography.caption)
                .foregroundStyle(MSC.Colors.tertiary)
                .monospacedDigit()
        }
        .padding(.vertical, 3)
        .padding(.horizontal, MSC.Spacing.sm)
    }
}

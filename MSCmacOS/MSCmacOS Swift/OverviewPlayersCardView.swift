//
//  OverviewPlayersCardView.swift
//  MinecraftServerController
//
//  Java behaviour is unchanged.
//
//

import SwiftUI

struct OverviewPlayersCardView: View {
    @EnvironmentObject var viewModel: AppViewModel

    @Binding var selectedPlayerName: String?
    @Binding var messageTarget: OnlinePlayer?
    @Binding var messageText: String

    // Local state for the allowlist add field.
    @State private var newAllowlistEntry: String = ""

    // Convenience
    private var isBedrock: Bool {
        guard let s = viewModel.selectedServer else { return false }
        return viewModel.configServer(for: s)?.isBedrock ?? false
    }

    var body: some View {
        overviewPlayersCard
    }

    // MARK: - Card

    private var overviewPlayersCard: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {

            // ── Header ──────────────────────────────────────────────────
            HStack {
                HStack(spacing: MSC.Spacing.xs) {
                    Image(systemName: "person.2")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(MSC.Colors.tertiary)
                    MSCOverline("Players")
                }
                Spacer()
                Text("\(viewModel.onlinePlayers.count) online")
                    .font(MSC.Typography.metaCaption)
                    .foregroundStyle(MSC.Colors.tertiary)
                // Bedrock: online list comes from log parsing — polling via "list" is Java-only.
                if !isBedrock {
                    Button("Refresh") {
                        viewModel.refreshPlayersAndTps()
                    }
                    .controlSize(.small)
                    .disabled(!viewModel.isServerRunning)
                }
            }

            // ── Online Now / Session History columns ─────────────────────
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
                            playerRowOnline(player)
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
                            playerRowHistory(name: name)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            // ── Bedrock-only: Allowlist manager ──────────────────────────
            if isBedrock {
                Divider().opacity(0.5)
                bedrockAllowlistSection
            }
        }
        .padding(MSC.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .fill(MSC.Colors.tierContent)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .stroke(MSC.Colors.contentBorder, lineWidth: 1)
        )
        .onAppear {
            if isBedrock { viewModel.loadBedrockAllowlistIfNeeded() }
        }
    }

    // MARK: - Bedrock Allowlist Section

    private var bedrockAllowlistSection: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {

            HStack {
                Label("Allowlist", systemImage: "list.bullet.clipboard")
                    .font(MSC.Typography.captionBold)
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
                .help("Reload allowlist from disk")
                .font(MSC.Typography.caption)
            }

            // Add row
            HStack(spacing: MSC.Spacing.sm) {
                TextField("Gamertag", text: $newAllowlistEntry)
                    .textFieldStyle(.roundedBorder)
                    .font(MSC.Typography.caption)
                    .onSubmit { commitAdd() }
                Button("Add") { commitAdd() }
                    .controlSize(.small)
                    .disabled(newAllowlistEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            // List of current entries
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
                            .foregroundStyle(MSC.Colors.body)
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

            // Contextual note: allowlist only enforced when online-mode=true in server.properties.
            Text("Note: allowlist is only enforced when online-mode is enabled in server properties.")
                .font(MSC.Typography.caption)
                .foregroundStyle(MSC.Colors.caption)
                .padding(.top, MSC.Spacing.xxs)
        }
    }

    private func commitAdd() {
        let trimmed = newAllowlistEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.addToBedrockAllowlist(gamertag: trimmed)
        newAllowlistEntry = ""
    }
}

//
//  OverviewPlayerRowHelpers.swift
//  MinecraftServerController
//

import SwiftUI

extension OverviewPlayersCardView {

    // MARK: - Player Row Helpers (used by overviewPlayersCard)

    @ViewBuilder
    func playerRowOnline(_ player: OnlinePlayer) -> some View {
        let isSelected = selectedPlayerName == player.name
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedPlayerName = isSelected ? nil : player.name
                }
            } label: {
                HStack(spacing: 6) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text(player.name).font(.callout).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: isSelected ? "chevron.up" : "chevron.down")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4).padding(.horizontal, 6)
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear))
            }
            .buttonStyle(.plain)
            if isSelected {
                playerActionPanel(name: player.name, isOnline: true)
                    .padding(.top, 4).padding(.leading, 6)
            }
        }
    }

    @ViewBuilder
    func playerRowHistory(name: String) -> some View {
        let isOnline = viewModel.onlinePlayers.contains { $0.name == name }
        let isSelected = selectedPlayerName == name
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedPlayerName = isSelected ? nil : name
                }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isOnline ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 6, height: 6)
                    Text(name).font(.callout)
                        .foregroundStyle(isOnline ? .primary : .secondary)
                    Spacer()
                    Image(systemName: isSelected ? "chevron.up" : "chevron.down")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4).padding(.horizontal, 6)
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear))
            }
            .buttonStyle(.plain)
            if isSelected {
                playerActionPanel(name: name, isOnline: isOnline)
                    .padding(.top, 4).padding(.leading, 6)
            }
        }
    }

    @ViewBuilder
    func playerActionPanel(name: String, isOnline: Bool) -> some View {
        let isBedrockServer = viewModel.selectedServer
            .flatMap { viewModel.configServer(for: $0) }?
            .isBedrock == true

        let knownBedrockXUID = isBedrockServer ? viewModel.bedrockXUID(forPlayerNamed: name) : nil
        let isBedrockOperator = isBedrockServer ? viewModel.isBedrockOperator(named: name) : false

        VStack(alignment: .leading, spacing: 8) {
            Divider()

            HStack(spacing: 8) {
                Button("Kick") {
                    viewModel.kickPlayer(named: name)
                    selectedPlayerName = nil
                }
                .foregroundStyle(.red)
                .controlSize(.small)
                .disabled(!isOnline || !viewModel.isServerRunning)

                Button("Message…") {
                    if let player = viewModel.onlinePlayers.first(where: { $0.name == name }) {
                        messageTarget = player
                        messageText = ""
                    }
                }
                .controlSize(.small)
                .disabled(!isOnline || !viewModel.isServerRunning)

                Spacer()
            }

            HStack(spacing: 8) {
                if isBedrockServer {
                    Button(isBedrockOperator ? "Operator" : "Promote to Op") {
                        viewModel.opPlayer(named: name)
                    }
                    .controlSize(.small)
                    .disabled(knownBedrockXUID == nil || isBedrockOperator)

                    Button("Remove Op") {
                        viewModel.deopPlayer(named: name)
                    }
                    .controlSize(.small)
                    .disabled(knownBedrockXUID == nil || !isBedrockOperator)
                } else {
                    Button("Op") { viewModel.opPlayer(named: name) }
                        .controlSize(.small)
                        .disabled(!viewModel.isServerRunning)

                    Button("Deop") { viewModel.deopPlayer(named: name) }
                        .controlSize(.small)
                        .disabled(!viewModel.isServerRunning)
                }

                Spacer()
            }

            if isBedrockServer, knownBedrockXUID == nil {
                Text("Bedrock operator changes need an XUID. Have this player join once so MSC can capture it from the console log.")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.caption)
            }

            HStack(spacing: 8) {
                Text("Gamemode")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(["survival", "creative", "adventure", "spectator"], id: \.self) { mode in
                    Button(mode.capitalized) {
                        viewModel.setGamemode(mode, forPlayer: name)
                    }
                    .controlSize(.small)
                    .disabled(!viewModel.isServerRunning)
                }

                Spacer()
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.6))
        )
    }
}


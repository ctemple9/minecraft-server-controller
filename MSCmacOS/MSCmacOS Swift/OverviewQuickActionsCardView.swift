//
//  OverviewQuickActionsCardView.swift
//  MinecraftServerController
//

import SwiftUI

struct OverviewQuickActionsCardView: View {
    @EnvironmentObject var viewModel: AppViewModel

    var body: some View {
        overviewQuickActionsCard
    }

    // MARK: - Overview: Quick Actions Card

    private var overviewQuickActionsCard: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {

            // Status row
            HStack(spacing: MSC.Spacing.sm) {
                MSCStatusDot(
                    color: viewModel.isServerRunning ? MSC.Colors.success : MSC.Colors.neutral,
                    label: viewModel.isServerRunning ? "Online" : "Offline",
                    size: 9
                )
                .font(.subheadline.weight(.medium))

                Spacer()

                if let uptime = viewModel.serverUptimeDisplay, viewModel.isServerRunning {
                    Label(uptime, systemImage: "clock")
                        .font(MSC.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Action buttons
                        HStack(spacing: MSC.Spacing.sm) {
                            Button {
                                if viewModel.isServerRunning { viewModel.stopServer() }
                                                                else { viewModel.startServer() }
                                                            } label: {
                                                                Label(
                                                                    viewModel.isServerRunning ? "Stop" : "Start",
                                                                    systemImage: viewModel.isServerRunning ? "stop.circle" : "play.circle"
                                                                )
                                                            }
                                                            .buttonStyle(MSCActionButtonStyle(color: viewModel.isServerRunning ? .red : .green))
                                                            .controlSize(.mini)
                                                            .disabled(viewModel.selectedServer == nil)

                            Button {
                                viewModel.sendQuickCommand("save-all")
                            } label: {
                                Label("Save World", systemImage: "arrow.down.doc")
                            }
                            .buttonStyle(MSCSecondaryButtonStyle())
                            .controlSize(.mini)
                            .disabled(!viewModel.isServerRunning)

                            Button {
                                viewModel.createBackupForSelectedServer()
                            } label: {
                                Label("Create Backup", systemImage: "externaldrive.badge.plus")
                            }
                            .buttonStyle(MSCSecondaryButtonStyle())
                            .controlSize(.mini)
                            .disabled(viewModel.selectedServer == nil)

                            Spacer()

                            Button {
                                viewModel.openSelectedServerFolder()
                            } label: {
                                Label("Server Folder", systemImage: "folder")
                            }
                            .buttonStyle(MSCSecondaryButtonStyle())
                            .controlSize(.mini)
                            .disabled(viewModel.selectedServer == nil)

                            Button {
                                viewModel.openSelectedLogsFolder()
                            } label: {
                                Label("Logs", systemImage: "doc.text")
                            }
                            .buttonStyle(MSCSecondaryButtonStyle())
                            .controlSize(.mini)
                            .disabled(viewModel.selectedServer == nil)
                        }
        }
        .padding(MSC.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .fill(MSC.Colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .stroke(MSC.Colors.cardBorder, lineWidth: 1)
        )
    }
}

//
//  OverviewServerStatusBarView.swift
//  MinecraftServerController
//
//  Redesigned: isShowingBackups binding removed.
//  Backups are now in the Worlds tab. The "Backups..." button is gone;
//  all other actions remain identical.
//
//

import SwiftUI

struct OverviewServerStatusBarView: View {
    @EnvironmentObject var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: MSC.Spacing.md) {

            // Left: status + uptime
            HStack(spacing: MSC.Spacing.sm) {
                MSCStatusDot(
                    color: viewModel.isServerRunning ? MSC.Colors.success : MSC.Colors.neutral,
                    label: viewModel.isServerRunning ? "Online" : "Offline",
                    size: 9
                )
                .font(.subheadline.weight(.medium))

                if let uptime = viewModel.serverUptimeDisplay, viewModel.isServerRunning {
                    Text("·")
                        .foregroundStyle(MSC.Colors.tertiary)
                    Label(uptime, systemImage: "clock")
                        .font(MSC.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 120, alignment: .leading)

            Divider().frame(height: 20)

            // Center: primary actions
                        HStack(spacing: MSC.Spacing.sm) {

                            Button {
                    viewModel.sendQuickCommand("save-all")
                } label: {
                    Label("Save World", systemImage: "arrow.down.doc")
                }
                .buttonStyle(MSCSecondaryButtonStyle())
                .controlSize(.small)
                .disabled(!viewModel.isServerRunning)

                Button {
                    viewModel.createBackupForSelectedServer()
                } label: {
                    Label("Create Backup", systemImage: "externaldrive.badge.plus")
                }
                .buttonStyle(MSCSecondaryButtonStyle())
                .controlSize(.small)
                .disabled(viewModel.selectedServer == nil)
            }

            Spacer()

            Divider().frame(height: 20)

            // Right: utility
            HStack(spacing: MSC.Spacing.sm) {
                Button {
                    viewModel.openSelectedServerFolder()
                } label: {
                    Label("Server Folder", systemImage: "folder")
                }
                .buttonStyle(MSCSecondaryButtonStyle())
                .controlSize(.small)
                .disabled(viewModel.selectedServer == nil)

                Button {
                    viewModel.openSelectedLogsFolder()
                } label: {
                    Label("Logs", systemImage: "doc.text")
                }
                .buttonStyle(MSCSecondaryButtonStyle())
                .controlSize(.small)
                .disabled(viewModel.selectedServer == nil)
            }
        }
        .padding(.horizontal, MSC.Spacing.md)
        .padding(.vertical, MSC.Spacing.sm)
        // Tier C fill provides sufficient visual lift without an added border overlay.
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .fill(MSC.Colors.tierContent)
        )
    }
}

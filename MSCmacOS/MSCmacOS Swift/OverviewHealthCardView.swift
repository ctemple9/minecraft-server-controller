//
//  OverviewHealthCardView.swift
//  MinecraftServerController
//
//  Bedrock servers show Docker container status and BDS version instead.
//

import SwiftUI

struct OverviewHealthCardView: View {
    @EnvironmentObject var viewModel: AppViewModel

    @Binding var isShowingBackups: Bool

    private var isBedrock: Bool {
        guard let s = viewModel.selectedServer else { return false }
        return viewModel.configServer(for: s)?.isBedrock ?? false
    }

    var body: some View {
        overviewHealthCard
    }

    // MARK: - Overview: Health Card

    private var overviewHealthCard: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {
            Label("Health", systemImage: "heart.text.square")
                .font(MSC.Typography.cardTitle)
                .foregroundStyle(.secondary)

            Divider()

            // ── Java-only: TPS ────────────────────────────────────────
            if !isBedrock {
                VStack(alignment: .leading, spacing: MSC.Spacing.xxs) {
                    Text("TPS (1m)")
                        .font(MSC.Typography.caption)
                        .foregroundStyle(.secondary)
                    if let tps = viewModel.latestTps1m {
                        Text(String(format: "%.1f", tps))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(tpsColor(for: tps))
                    } else {
                        Text("--")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Text("Target: 20.0")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Divider().opacity(0.5)
            }

            // ── Bedrock-only: Docker / container status ───────────────
            if isBedrock {
                VStack(alignment: .leading, spacing: MSC.Spacing.xxs) {
                    Text("Docker")
                        .font(MSC.Typography.caption)
                        .foregroundStyle(.secondary)
                    Label(
                        viewModel.dockerDaemonRunning ? "Running" : "Not running",
                        systemImage: viewModel.dockerDaemonRunning
                            ? "checkmark.circle.fill"
                            : "xmark.circle.fill"
                    )
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                        viewModel.dockerDaemonRunning ? MSC.Colors.success : MSC.Colors.error
                    )
                    if let ver = viewModel.bedrockRunningVersion {
                        Text("BDS \(ver)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider().opacity(0.5)
            }

            // ── Java-only: JAR Status ─────────────────────────────────
            if !isBedrock {
                VStack(alignment: .leading, spacing: MSC.Spacing.xxs) {
                    Text("JAR Status")
                        .font(MSC.Typography.caption)
                        .foregroundStyle(.secondary)
                    let outdated = outdatedJarCount
                    if viewModel.isCheckingComponentsOnline {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.mini)
                            Text("Checking\u{2026}")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if outdated == 0 {
                        Label("Up to date", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(MSC.Colors.success)
                    } else {
                        Label("\(outdated) outdated", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(MSC.Colors.warning)
                    }
                    Text("See Components tab")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Divider().opacity(0.5)
            }

            // ── Both server types: Backups ────────────────────────────
            VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                Text("Backups")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(.secondary)
                let count = viewModel.backupItems.count
                Text(count == 0 ? "No backups yet" : "\(count) backup\(count == 1 ? "" : "s")")
                    .font(.system(size: 13, weight: .semibold))
                if let sizeStr = viewModel.backupsFolderSizeDisplay {
                    Text(sizeStr + " total")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                    Button {
                        viewModel.createBackupForSelectedServer()
                    } label: {
                        Label("Create Backup", systemImage: "externaldrive.badge.plus")
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                    .controlSize(.mini)
                    .disabled(viewModel.selectedServer == nil)

                    Button {
                        isShowingBackups = true
                    } label: {
                        Label("View All Backups", systemImage: "list.bullet")
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                    .controlSize(.mini)
                    .disabled(viewModel.selectedServer == nil)
                }
            }
        }
        .padding(MSC.Spacing.md)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(
                    RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                        .fill(MSC.Colors.tierContent)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                        .stroke(MSC.Colors.contentBorder, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.22), radius: 6, x: 0, y: 3)
    }

    // MARK: - TPS color helper (Java only)

    private func tpsColor(for t: Double) -> Color {
        switch t {
        case 19.5...:     return .green
        case 18.0..<19.5: return .yellow
        default:          return .red
        }
    }
}


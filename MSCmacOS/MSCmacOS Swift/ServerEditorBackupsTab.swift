import SwiftUI

extension ServerEditorView {
// MARK: - BACKUPS TAB

var backupsTab: some View {
    VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
        if mode == .new || editingConfigServer == nil {
            SEUnavailableCard(
                icon: "archivebox.fill",
                title: "Save first to manage backups",
                message: "Backups are only available after this server has been created. Save, then reopen Edit Server."
            )
        } else if let server = editingConfigServer {

            // ── 1. Automated Backups ──────────────────────────────────
            SESection(icon: "clock.arrow.2.circlepath", title: "Automated Backups", color: .green) {
                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                    HStack(spacing: MSC.Spacing.sm) {
                        Toggle("", isOn: $autoBackupEnabledLocal)
                            .labelsHidden()
                            .onChange(of: autoBackupEnabledLocal) { newValue in
                                viewModel.setAutoBackupEnabled(newValue, for: server.id)
                            }
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Auto-Backup enabled")
                                .font(.system(size: 12, weight: .medium))
                            Text("Creates a backup every 30 minutes, keeps the last 12.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let sizeDisplay = viewModel.backupsFolderSizeDisplay {
                            Text(sizeDisplay)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // ── 2. Back Up Now ────────────────────────────────────────
            SESection(icon: "archivebox.fill", title: "Manual Backup", color: .blue) {
                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                    Text("Create an immediate snapshot of the current world. The server should be stopped first for a clean backup.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Back Up Now") {
                        viewModel.createBackupForSelectedServer(isAutomatic: false)
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                }
            }

            // ── 3. Cleanup ────────────────────────────────────────────
            SESection(icon: "trash.fill", title: "Cleanup", color: .orange) {
                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                    Text("Manually remove auto-backups beyond the 12-slot limit. This is done automatically on each new auto-backup, but you can trigger it early to free disk space.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Prune Old Backups") {
                        viewModel.pruneAutoBackupsForSelectedServer()
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                }
            }

            SECallout(
                icon: "info.circle.fill",
                color: .blue,
                text: "Backup history is now visible per world slot in the World tab. Select a slot to see its associated backups."
            )
        }
    }
}

}

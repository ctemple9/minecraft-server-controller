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

            // ── Auto-Backup ───────────────────────────────────────────
            SEBlockHeader(title: "Auto-Backup")
            SEBlock {
                SERow(label: "Enabled", hint: "Snapshots while server runs, pruned automatically") {
                    Toggle("", isOn: $autoBackupEnabledLocal)
                        .labelsHidden()
                        .onChange(of: autoBackupEnabledLocal) { _, newValue in
                            viewModel.setAutoBackupEnabled(newValue, for: server.id)
                        }
                }
                if autoBackupEnabledLocal {
                    Divider().padding(.leading, MSC.Spacing.md - 1)
                    SERow(label: "Interval") {
                        Picker("", selection: $autoBackupIntervalLocal) {
                            Text("15 min").tag(15)
                            Text("30 min").tag(30)
                            Text("45 min").tag(45)
                            Text("1 hour").tag(60)
                            Text("2 hours").tag(120)
                            Text("4 hours").tag(240)
                            Text("6 hours").tag(360)
                        }
                        .labelsHidden()
                        .frame(width: 110)
                        .onChange(of: autoBackupIntervalLocal) { _, newValue in
                            viewModel.setAutoBackupInterval(newValue, for: server.id)
                        }
                    }
                    Divider().padding(.leading, MSC.Spacing.md - 1)
                    SERow(label: "Max Stored", hint: "Oldest pruned on each new backup") {
                        HStack(spacing: MSC.Spacing.sm) {
                            Stepper("", value: $autoBackupMaxCountLocal, in: 3...50)
                                .labelsHidden()
                                .onChange(of: autoBackupMaxCountLocal) { _, newValue in
                                    viewModel.setAutoBackupMaxCount(newValue, for: server.id)
                                }
                            Text("\(autoBackupMaxCountLocal)")
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 28, alignment: .leading)
                        }
                    }
                }
                if let sizeDisplay = viewModel.backupsFolderSizeDisplay {
                    Divider().padding(.leading, MSC.Spacing.md - 1)
                    SERow(label: "Total Size") {
                        Text(sizeDisplay)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // ── Manual Actions ────────────────────────────────────────
            SEBlockHeader(title: "Manual Actions")
            SEBlock {
                SERow(label: "Back Up Now", hint: "Stop server first for a clean snapshot") {
                    Button("Back Up") {
                        viewModel.createBackupForSelectedServer(isAutomatic: false)
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                }
                Divider().padding(.leading, MSC.Spacing.md - 1)
                SERow(label: "Prune Old Backups", hint: "Free disk space before the next scheduled prune") {
                    Button("Prune") {
                        viewModel.pruneAutoBackupsForSelectedServer()
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                }
            }

            // ── Recent Backups ────────────────────────────────────────
            if !viewModel.backupItems.isEmpty {
                SEBlockHeader(title: "Recent Backups")
                SEBlock {
                    let sorted = viewModel.backupItems
                        .sorted { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) }
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, item in
                        if idx > 0 { Divider().padding(.leading, MSC.Spacing.md - 1) }
                        HStack(spacing: MSC.Spacing.sm) {
                            Circle()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(width: 5, height: 5)
                            Text(timeString(from: item.modificationDate))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(item.isAutomatic ? "Auto" : "Manual")
                                .font(.system(size: 10))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(item.isAutomatic
                                            ? Color.blue.opacity(0.1)
                                            : Color.gray.opacity(0.1))
                                .foregroundStyle(item.isAutomatic ? Color.blue : Color.secondary)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                            if let size = item.fileSize {
                                Text(formatBytes(size))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            if let slotId = item.slotId,
                               let slot = viewModel.worldSlots.first(where: { $0.id == slotId }) {
                                Spacer()
                                Text(slot.name)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            } else {
                                Spacer()
                            }
                        }
                        .padding(.horizontal, MSC.Spacing.md - 1)
                        .padding(.vertical, MSC.Spacing.sm - 1)
                    }
                }
            }

            SECallout(
                icon: "info.circle.fill",
                color: .blue,
                text: "Per-world backup history and Restore are available in the World tab — select a world slot to see its backups."
            )
        }
    }
}

}

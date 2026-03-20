//
//  BackupsView.swift
//  MinecraftServerController
//

import SwiftUI

struct BackupsView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Binding var isPresented: Bool

    @State private var selectedBackupId: String?
    @State private var autoBackupEnabled: Bool = false
    @State private var backupToRestore: BackupItem? = nil
    @State private var showDeleteConfirm = false
    @State private var showDuplicateSheet = false
    @State private var newServerName: String = ""

    private var selectedServer: Server? { viewModel.selectedServer }

    private var selectedBackup: BackupItem? {
        guard let id = selectedBackupId else { return nil }
        return viewModel.backupItems.first(where: { $0.id == id })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // MARK: Header
            MSCSheetHeader(
                "Backups",
                subtitle: selectedServer?.name ?? "No server selected."
            ) {
                isPresented = false
            }
            .padding([.horizontal, .top])

            if selectedServer == nil {
                Spacer()
                Text("Select a server to manage its backups.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {

                VStack(alignment: .leading, spacing: MSC.Spacing.md) {

                    // MARK: Auto-backup toggle row
                    HStack(spacing: MSC.Spacing.md) {
                        Text("Auto-Backup")
                            .font(.body)
                        Toggle("", isOn: $autoBackupEnabled)
                            .labelsHidden()
                            .onChange(of: autoBackupEnabled) { newValue in
                                if let id = selectedServer.flatMap({ viewModel.configServer(for: $0)?.id }) {
                                    viewModel.setAutoBackupEnabled(newValue, for: id)
                                }
                            }
                        Text("Every 30 min")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    // MARK: Folder size
                    if let sizeDisplay = viewModel.backupsFolderSizeDisplay {
                        Text("Backups Folder Size:  \(sizeDisplay)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 6)

                Divider()

                // MARK: Grouped backup list
                if viewModel.backupItems.isEmpty {
                    Spacer()
                    Text("No backups found for this server.\nUse \u{201C}Back Up Now\u{201D} to create one.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Spacer()
                } else {
                    List(selection: $selectedBackupId) {
                        ForEach(groupedBackupSections, id: \.title) { section in
                            Section(header:
                                Text(section.title)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                            ) {
                                ForEach(section.items) { item in
                                    backupRow(item)
                                        .tag(item.id)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }

                Divider()

                // MARK: Footer
                HStack {
                    Button("Back Up Now") {
                        viewModel.createBackupForSelectedServer(isAutomatic: false)
                    }
                    .buttonStyle(MSCPrimaryButtonStyle())

                    Spacer()

                    Button("Delete Selected") {
                        showDeleteConfirm = true
                    }
                    .buttonStyle(MSCDestructiveButtonStyle())
                    .disabled(selectedBackup == nil)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
        }
        .frame(minWidth: 560, minHeight: 460)
        .onAppear {
            viewModel.loadBackupsForSelectedServer()
            if let server = selectedServer,
               let cfg = viewModel.configServer(for: server) {
                autoBackupEnabled = cfg.autoBackupEnabled
            }
        }
        // Restore alert — triggered by the inline Restore button
        .alert("Restore Backup?",
               isPresented: Binding(
                get: { backupToRestore != nil },
                set: { if !$0 { backupToRestore = nil } }
               ),
               presenting: backupToRestore) { backup in
            Button("Restore", role: .destructive) {
                viewModel.restoreBackup(backup)
                backupToRestore = nil
            }
            Button("Cancel", role: .cancel) {
                backupToRestore = nil
            }
        } message: { backup in
            Text("This will overwrite the current world data for \"\(selectedServer?.name ?? "this server")\" with the contents of this backup. The server must be stopped first.")
        }
        // Delete alert — triggered by Delete Selected footer button
        .alert("Delete Backup?",
               isPresented: $showDeleteConfirm,
               presenting: selectedBackup) { backup in
            Button("Delete", role: .destructive) {
                viewModel.deleteBackup(backup)
                selectedBackupId = nil
            }
            Button("Cancel", role: .cancel) { }
        } message: { backup in
            Text("Are you sure you want to permanently delete this backup?\n\(backup.filename)")
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func backupRow(_ item: BackupItem) -> some View {
        HStack(spacing: 10) {
            // Bullet
            Circle()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 6, height: 6)

            // Time
            Text(timeString(from: item.modificationDate))
                .font(.body)
                .frame(width: 72, alignment: .leading)

            // Auto / Manual badge
            Text(item.isAutomatic ? "Auto" : "Manual")
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(item.isAutomatic ? Color.blue.opacity(0.12) : Color.gray.opacity(0.12))
                .foregroundStyle(item.isAutomatic ? Color.blue : Color.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            // File size
            if let size = item.fileSize {
                Text(formatBytes(size))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .leading)
            }

            Text(backupAssociationText(for: item))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)

            Spacer()

            // Inline Restore
            Button("Restore") {
                backupToRestore = item
            }
            .controlSize(.small)
            .disabled(viewModel.isServerRunning)
            .help(viewModel.isServerRunning ? "Stop the server before restoring a backup." : "Restore this backup")
        }
        .padding(.vertical, 3)
    }

    // MARK: - Grouping helpers

    private struct BackupSection {
        let title: String
        let items: [BackupItem]
    }

    private var groupedBackupSections: [BackupSection] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        let sectionFormatter = DateFormatter()
        sectionFormatter.dateStyle = .long
        sectionFormatter.timeStyle = .none

        var byDay: [(key: Date, items: [BackupItem])] = []
        var dayIndex: [Date: Int] = [:]

        for item in viewModel.backupItems {
            let day = calendar.startOfDay(for: item.modificationDate ?? .distantPast)
            if let idx = dayIndex[day] {
                byDay[idx].items.append(item)
            } else {
                dayIndex[day] = byDay.count
                byDay.append((key: day, items: [item]))
            }
        }

        byDay.sort { $0.key > $1.key }

        return byDay.map { (day, items) in
            let title: String
            if calendar.isDate(day, inSameDayAs: today) {
                title = "Today"
            } else if calendar.isDate(day, inSameDayAs: yesterday) {
                title = "Yesterday"
            } else {
                title = sectionFormatter.string(from: day)
            }
            return BackupSection(title: title, items: items)
        }
    }

    private func timeString(from date: Date?) -> String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    private func backupAssociationText(for item: BackupItem) -> String {
        if let slotId = item.slotId {
            if let slotName = item.slotName?.trimmingCharacters(in: .whitespacesAndNewlines), !slotName.isEmpty {
                return "Slot: \(slotName)"
            }
            return "Missing slot: \(slotId)"
        }
        return "Legacy / no slot"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}


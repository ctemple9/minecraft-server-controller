//
//  DetailsWorldsTabView.swift
//  MinecraftServerController
//
//  Worlds tab — inline Realms-style world slot grid.
//  Select a world slot -> its 12 backups appear below in the same tab.
//  Create Backup, Restore, Delete all happen inline — no sheets.
//

import SwiftUI

struct DetailsWorldsTabView: View {
    @EnvironmentObject var viewModel: AppViewModel

    // World slot selection and actions
    @State private var selectedSlot: WorldSlot? = nil
    @State private var showCreateWorldSheet: Bool = false
    @State private var showActivateConfirm: Bool = false
    @State private var showDeleteSlotConfirm: Bool = false
    @State private var showRenameSheet: Bool = false
    @State private var pendingSlot: WorldSlot? = nil

    // Backup actions
    @State private var autoBackupEnabled: Bool = false
    @State private var backupToRestore: BackupItem? = nil
    @State private var backupToDelete: BackupItem? = nil
    @State private var showRestoreConfirm: Bool = false
    @State private var showDeleteBackupConfirm: Bool = false

    private var cfgServer: ConfigServer? {
        guard let s = viewModel.selectedServer else { return nil }
        return viewModel.configServer(for: s)
    }

    private var serverIsRunning: Bool {
        viewModel.isServerRunning &&
        viewModel.configManager.config.activeServerId == cfgServer?.id
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: MSC.Spacing.md) {

                // World Slots section
                worldSlotsSection

                // Backup section — slot-aware history for the selected world slot
                backupsSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, MSC.Spacing.md)
        }
        .onAppear {
            viewModel.loadWorldSlotsForSelectedServer()
            viewModel.loadBackupsForSelectedServer()
            if let cfg = cfgServer {
                autoBackupEnabled = cfg.autoBackupEnabled
            }
        }
        .onChange(of: viewModel.selectedServer) { _ in
            selectedSlot = nil
            viewModel.loadWorldSlotsForSelectedServer()
            viewModel.loadBackupsForSelectedServer()
            if let cfg = cfgServer {
                autoBackupEnabled = cfg.autoBackupEnabled
            }
        }
        // Create world sheet
        .sheet(isPresented: $showCreateWorldSheet) {
            CreateWorldSlotSheet(isPresented: $showCreateWorldSheet) { name, seed in
                viewModel.createNewWorldSlot(name: name, seed: seed)
            }
        }
        // Rename sheet
        .sheet(isPresented: $showRenameSheet) {
            RenameSlotSheet(
                isPresented: $showRenameSheet,
                currentName: pendingSlot?.name ?? "",
                onRename: { newName in
                    if let slot = pendingSlot {
                        viewModel.renameWorldSlot(slot, newName: newName)
                    }
                }
            )
        }
        // Activate confirm
        .confirmationDialog(
            pendingSlot.map { "Activate \"\($0.name)\"?" } ?? "Activate World Slot?",
            isPresented: $showActivateConfirm,
            titleVisibility: .visible
        ) {
            Button("Activate Slot", role: .destructive) {
                if let slot = pendingSlot { viewModel.activateWorldSlot(slot) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current world will be backed up automatically before the swap. This cannot be undone without restoring from backup.")
        }
        // Delete slot confirm
        .confirmationDialog(
            pendingSlot.map { "Delete \"\($0.name)\"?" } ?? "Delete World Slot?",
            isPresented: $showDeleteSlotConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Slot", role: .destructive) {
                if let slot = pendingSlot { viewModel.deleteWorldSlot(slot) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the saved world slot. It cannot be undone.")
        }
        // Restore backup confirm
        .alert(
            "Restore Backup?",
            isPresented: $showRestoreConfirm,
            presenting: backupToRestore
        ) { backup in
            Button("Restore", role: .destructive) {
                if let slot = selectedSlot {
                    viewModel.restoreSlotBackup(backup, into: slot)
                }
                backupToRestore = nil
            }
            Button("Cancel", role: .cancel) {
                backupToRestore = nil
            }
        } message: { backup in
            if let slot = selectedSlot {
                Text("This will overwrite the saved contents of \"\(slot.name)\" with this backup. It will not be restored into a different slot.")
            } else {
                Text("Select a world slot before restoring a backup.")
            }
        }
        // Delete backup confirm
        .alert(
            "Delete Backup?",
            isPresented: $showDeleteBackupConfirm,
            presenting: backupToDelete
        ) { backup in
            Button("Delete", role: .destructive) {
                viewModel.deleteBackup(backup)
                backupToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                backupToDelete = nil
            }
        } message: { backup in
            Text("Are you sure you want to permanently delete this backup?\n\(backup.filename)")
        }
    }

    // MARK: - World Slots section

    private var worldSlotsSection: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {

            HStack {
                Label("World Slots", systemImage: "globe")
                    .font(MSC.Typography.cardTitle)
                    .foregroundStyle(.secondary)

                Spacer()

                if viewModel.isWorldSlotsLoading {
                    ProgressView().scaleEffect(0.7)
                }

                Button {
                    viewModel.saveCurrentWorldToActiveSlot()
                } label: {
                    Label("Save Current World", systemImage: "square.and.arrow.down")
                        .font(.system(size: 11))
                }
                .buttonStyle(MSCSecondaryButtonStyle())
                .disabled(viewModel.isWorldSlotsLoading)

                Button {
                    showCreateWorldSheet = true
                } label: {
                    Label("Create New World", systemImage: "plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(MSCSecondaryButtonStyle())
                .disabled(viewModel.isWorldSlotsLoading)
            }

            Divider()

            if viewModel.worldSlots.isEmpty && !viewModel.isWorldSlotsLoading {
                // Empty state
                VStack(spacing: MSC.Spacing.lg) {
                    Image(systemName: "globe.desk")
                        .font(.system(size: 36))
                        .foregroundStyle(MSC.Colors.caption)

                    VStack(spacing: MSC.Spacing.xs) {
                        Text("No World Slots Yet")
                            .font(MSC.Typography.sectionHeader)
                        Text("Create a new world slot or save the current active world back into its slot. You can switch between slots anytime the server is stopped.")
                            .font(MSC.Typography.caption)
                            .foregroundStyle(MSC.Colors.caption)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 360)
                    }

                    Button {
                        showCreateWorldSheet = true
                    } label: {
                        Label("Create New World", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding(MSC.Spacing.xl)
            } else {
                // 3-column grid
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: MSC.Spacing.md),
                        GridItem(.flexible(), spacing: MSC.Spacing.md),
                        GridItem(.flexible(), spacing: MSC.Spacing.md)
                    ],
                    spacing: MSC.Spacing.md
                ) {
                    ForEach(viewModel.worldSlots) { slot in
                        let activeSlotId = cfgServer.map { viewModel.activeWorldSlotId(forServerDir: $0.serverDir) } ?? nil
                        WorldSlotCard(
                            slot: slot,
                            isSelected: selectedSlot?.id == slot.id,
                            isActive: activeSlotId == slot.id,
                            serverIsRunning: serverIsRunning,
                            onSelect: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    if selectedSlot?.id == slot.id {
                                        selectedSlot = nil
                                    } else {
                                        selectedSlot = slot
                                        viewModel.loadBackupsForSelectedServer()
                                    }
                                }
                            },
                            onActivate: {
                                pendingSlot = slot
                                showActivateConfirm = true
                            },
                            onRename: {
                                pendingSlot = slot
                                showRenameSheet = true
                            },
                            onDelete: {
                                pendingSlot = slot
                                showDeleteSlotConfirm = true
                            }
                        )
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

    // MARK: - Backups section

    private var backupsSection: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {

            HStack {
                Label("Backups", systemImage: "externaldrive")
                    .font(MSC.Typography.cardTitle)
                    .foregroundStyle(.secondary)

                if let slot = selectedSlot {
                    Text("· \(slot.name)")
                        .font(MSC.Typography.caption)
                        .foregroundStyle(MSC.Colors.caption)
                }

                Spacer()

                // Auto-backup toggle
                HStack(spacing: MSC.Spacing.xs) {
                    Text("Auto (30 min)")
                        .font(MSC.Typography.caption)
                        .foregroundStyle(.secondary)
                    Toggle("", isOn: $autoBackupEnabled)
                        .labelsHidden()
                        .onChange(of: autoBackupEnabled) { newValue in
                            if let id = cfgServer?.id {
                                viewModel.setAutoBackupEnabled(newValue, for: id)
                            }
                        }
                }

                if let size = viewModel.backupsFolderSizeDisplay {
                    Text(size)
                        .font(MSC.Typography.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    if let cfg = cfgServer, let slot = selectedSlot {
                        Task {
                            await viewModel.createBackup(
                                for: cfg,
                                isAutomatic: false,
                                slotId: slot.id,
                                slotName: slot.name
                            )
                        }
                    }
                } label: {
                    Label("Back Up Now", systemImage: "externaldrive.badge.plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(MSCSecondaryButtonStyle())
                .disabled(viewModel.selectedServer == nil || selectedSlot == nil)
            }

            Divider()

            if selectedSlot == nil {
                VStack(spacing: MSC.Spacing.sm) {
                    Image(systemName: "externaldrive.badge.questionmark")
                        .font(.system(size: 28))
                        .foregroundStyle(MSC.Colors.tertiary)
                    Text("Select a world slot to view its backups.")
                        .font(MSC.Typography.caption)
                        .foregroundStyle(MSC.Colors.caption)
                    Text("Backups shown here stay attached to the selected slot.")
                        .font(MSC.Typography.caption)
                        .foregroundStyle(MSC.Colors.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(MSC.Spacing.lg)
            } else if selectedSlotBackups.isEmpty {
                VStack(spacing: MSC.Spacing.sm) {
                    Image(systemName: "externaldrive.badge.xmark")
                        .font(.system(size: 28))
                        .foregroundStyle(MSC.Colors.tertiary)
                    Text("No backups found for this slot.")
                        .font(MSC.Typography.caption)
                        .foregroundStyle(MSC.Colors.caption)
                    Text("Use \"Back Up Now\" to create one for the selected world slot.")
                        .font(MSC.Typography.caption)
                        .foregroundStyle(MSC.Colors.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(MSC.Spacing.lg)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(groupedBackupSections, id: \.title) { section in
                        // Day header
                        HStack {
                            Text(section.title)
                                .font(MSC.Typography.captionBold)
                                .foregroundStyle(MSC.Colors.tertiary)
                            Spacer()
                        }
                        .padding(.vertical, MSC.Spacing.xs)
                        .padding(.horizontal, MSC.Spacing.sm)
                        .background(MSC.Colors.subtleBackground.opacity(0.5))

                        ForEach(section.items) { item in
                            InlineBackupRow(
                                item: item,
                                serverIsRunning: serverIsRunning,
                                onRestore: {
                                    backupToRestore = item
                                    showRestoreConfirm = true
                                },
                                onDelete: {
                                    backupToDelete = item
                                    showDeleteBackupConfirm = true
                                }
                            )
                            Divider().padding(.horizontal, MSC.Spacing.sm)
                        }
                    }
                }
            }

            if !legacyOrUnmatchedBackups.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                    Text("Legacy / Unmatched Backups")
                        .font(MSC.Typography.captionBold)
                        .foregroundStyle(MSC.Colors.tertiary)

                    Text("These backups are still on disk, but they are not attached to any current world slot. They would otherwise disappear from the slot-specific list. Use Import as Slot to turn one into a new slot without loosening the normal slot-restore safety rules.")
                        .font(MSC.Typography.caption)
                        .foregroundStyle(MSC.Colors.caption)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(legacyOrUnmatchedBackups) { item in
                            LegacyBackupRow(
                                item: item,
                                reasonText: legacyBackupReasonText(for: item),
                                isBusy: viewModel.isWorldSlotsLoading,
                                onImportAsSlot: {
                                    viewModel.importLegacyBackupAsNewSlot(item)
                                },
                                onDelete: {
                                    backupToDelete = item
                                    showDeleteBackupConfirm = true
                                }
                            )
                            Divider().padding(.horizontal, MSC.Spacing.sm)
                        }
                    }
                    
                }
                .padding(.top, MSC.Spacing.xs)
            }
        }
        .padding(MSC.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .fill(MSC.Colors.tierContent)
        )
    }

    // MARK: - Backup grouping helpers

    private struct BackupSection {
        let title: String
        let items: [BackupItem]
    }

    private var selectedSlotBackups: [BackupItem] {
        guard let slot = selectedSlot else { return [] }
        return viewModel.backupItems.filter { $0.slotId == slot.id }
    }

    private var legacyOrUnmatchedBackups: [BackupItem] {
        let knownSlotIDs = Set(viewModel.worldSlots.map(\.id))
        return viewModel.backupItems.filter { item in
            guard let slotId = item.slotId else { return true }
            return !knownSlotIDs.contains(slotId)
        }
    }

    private func legacyBackupReasonText(for item: BackupItem) -> String {
        if let slotId = item.slotId {
            if let slotName = item.slotName?.trimmingCharacters(in: .whitespacesAndNewlines), !slotName.isEmpty {
                return "Missing slot: \(slotName)"
            }
            return "Missing slot ID: \(slotId)"
        }
        return "Legacy backup (no slot metadata)"
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

        for item in selectedSlotBackups {
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
}

private struct WorldSlotCard: View {
    let slot: WorldSlot
    let isSelected: Bool
    let isActive: Bool
    let serverIsRunning: Bool
    let onSelect: () -> Void
    let onActivate: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Realms-style thumbnail
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [Color(hue: 0.57, saturation: 0.6, brightness: 0.85),
                             Color(hue: 0.57, saturation: 0.45, brightness: 0.65)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 100)

                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color(hue: 0.33, saturation: 0.55, brightness: 0.42))
                        .frame(height: 8)
                    Rectangle()
                        .fill(Color(hue: 0.07, saturation: 0.45, brightness: 0.35))
                        .frame(height: 16)
                }
                .frame(maxWidth: .infinity)

                Image(systemName: "mountain.2.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white.opacity(0.25))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 24)

                if let bytes = slot.zipSizeBytes {
                    Text(WorldSlotManager.formatBytes(bytes))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.black.opacity(0.4)))
                        .padding(6)
                }

                // Active badge — top right
                if isActive {
                    HStack(spacing: 3) {
                        Circle().fill(MSC.Colors.success).frame(width: 5, height: 5)
                        Text("Active")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(MSC.Colors.success.opacity(0.75)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(6)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                        .shadow(radius: 3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(6)
                }
            }
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: MSC.Radius.lg,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: MSC.Radius.lg
            ))

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(slot.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("Saved \(Self.dateFormatter.string(from: slot.createdAt))")
                    .font(.system(size: 11))
                    .foregroundStyle(MSC.Colors.caption)
                    .lineLimit(1)

                if let seed = slot.worldSeed?.trimmingCharacters(in: .whitespacesAndNewlines), !seed.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "number")
                            .font(.system(size: 9))
                            .foregroundStyle(MSC.Colors.caption)
                        Text("Seed \(seed)")
                            .font(.system(size: 11))
                            .foregroundStyle(MSC.Colors.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(.horizontal, MSC.Spacing.md)
            .padding(.top, MSC.Spacing.sm)
            .padding(.bottom, MSC.Spacing.xs)

            Divider().padding(.horizontal, MSC.Spacing.sm)

            // Actions
            HStack(spacing: MSC.Spacing.xs) {
                Button(action: onActivate) {
                    Text("Activate")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(serverIsRunning)
                .help(serverIsRunning ? "Stop the server before switching worlds" : "Load this world")

                Spacer()

                Button(action: onRename) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)

                Button(action: onDelete) {
                    Image(systemName: "trash").foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            .padding(.horizontal, MSC.Spacing.md)
            .padding(.vertical, MSC.Spacing.sm)
        }
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.lg)
                .fill(MSC.Colors.tierContent)
                .overlay(
                    RoundedRectangle(cornerRadius: MSC.Radius.lg)
                        .stroke(
                            isActive ? MSC.Colors.success.opacity(0.8)
                                : isSelected ? Color.accentColor.opacity(0.7)
                                : (isHovered ? Color.accentColor.opacity(0.4) : Color.clear),
                            lineWidth: (isActive || isSelected) ? 2 : 1
                        )
                )
        )
        .shadow(color: isActive ? MSC.Colors.success.opacity(0.15) : .black.opacity(isHovered || isSelected ? 0.10 : 0.04),
                radius: isActive ? 6 : (isHovered ? 8 : 3), y: 2)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
        .onTapGesture { onSelect() }
    }
}

// MARK: - Inline backup row

private struct InlineBackupRow: View {
    let item: BackupItem
    let serverIsRunning: Bool
    let onRestore: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: MSC.Spacing.sm) {

            // Auto/Manual badge
            Text(item.isAutomatic ? "Auto" : "Manual")
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(item.isAutomatic ? Color.blue.opacity(0.12) : Color.gray.opacity(0.12))
                .foregroundStyle(item.isAutomatic ? Color.blue : Color.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .frame(width: 44)

            // Time
            Text(timeString(from: item.modificationDate))
                .font(MSC.Typography.mono)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)

            // Size
            if let size = item.fileSize {
                Text(formatBytes(size))
                    .font(MSC.Typography.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .leading)
            }

            Spacer()

            Button("Restore") { onRestore() }
                .controlSize(.small)
                .buttonStyle(MSCSecondaryButtonStyle())
                .disabled(serverIsRunning)
                .help(serverIsRunning ? "Stop the server before restoring a backup." : "Restore this backup")

            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(MSC.Colors.error)
            }
            .buttonStyle(.plain)
            .help("Delete this backup")
        }
        .padding(.horizontal, MSC.Spacing.sm)
        .padding(.vertical, MSC.Spacing.xs)
    }

    private func timeString(from date: Date?) -> String {
        guard let date else { return "\u{2014}" }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

private struct LegacyBackupRow: View {
    let item: BackupItem
    let reasonText: String
    let isBusy: Bool
    let onImportAsSlot: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: MSC.Spacing.sm) {
                Text(item.isAutomatic ? "Auto" : "Manual")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(item.isAutomatic ? Color.blue.opacity(0.12) : Color.gray.opacity(0.12))
                    .foregroundStyle(item.isAutomatic ? Color.blue : Color.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Text(reasonText)
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.caption)
                    .lineLimit(1)

                Spacer()

                if let size = item.fileSize {
                    Text(formatBytes(size))
                        .font(MSC.Typography.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Import as Slot") {
                    onImportAsSlot()
                }
                .controlSize(.small)
                .buttonStyle(MSCSecondaryButtonStyle())
                .disabled(isBusy)
                .help("Create a new world slot from this backup without overwriting any existing slot.")

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(MSC.Colors.error)
                }
                .buttonStyle(.plain)
                .help("Delete this backup")
            }

            Text(item.filename)
                .font(MSC.Typography.mono)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, MSC.Spacing.sm)
        .padding(.vertical, MSC.Spacing.xs)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}


// MARK: - Rename slot sheet

private struct RenameSlotSheet: View {
    @Binding var isPresented: Bool
    let currentName: String
    var onRename: (String) -> Void

    @State private var newName: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
            Text("Rename Slot")
                .font(MSC.Typography.pageTitle)
            TextField("New name", text: $newName)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Rename") { onRename(newName); isPresented = false }
                    .buttonStyle(.borderedProminent)
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newName == currentName)
            }
        }
        .padding(MSC.Spacing.xxl)
        .frame(width: 340)
        .onAppear { newName = currentName; focused = true }
    }
}


//
//  PlayerProfileDetailSheet.swift
//  MinecraftServerController
//
//  Full-detail sheet for a single Java Edition player profile.
//  Shows: skin render, stats, inventory, and data management actions.
//

import SwiftUI
import AppKit

struct PlayerProfileDetailSheet: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    let profile: PlayerProfile

    // Local state
    @State private var localProfile: PlayerProfile
    @State private var showDeleteConfirm: Bool = false
    @State private var showCopyPicker: Bool = false
    @State private var showMigrateManualInput: Bool = false
    @State private var manualUUIDInput: String = ""
    @State private var actionError: String? = nil
    @State private var actionSuccess: String? = nil

    init(profile: PlayerProfile) {
        self.profile = profile
        self._localProfile = State(initialValue: profile)
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Sheet header ───────────────────────────────────────────────
            HStack {
                Label("Player Profile", systemImage: "person.crop.rectangle")
                    .font(MSC.Typography.cardTitle)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MSC.Colors.tertiary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
            .padding(MSC.Spacing.md)

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: MSC.Spacing.xl) {

                    // ── Identity header ────────────────────────────────────
                    identityHeader

                    // ── Status feedback ────────────────────────────────────
                    if let msg = actionError {
                        HStack(spacing: MSC.Spacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(MSC.Colors.warning)
                            Text(msg).font(MSC.Typography.caption).foregroundStyle(.secondary)
                        }
                        .padding(MSC.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: MSC.Radius.sm)
                                .fill(MSC.Colors.warning.opacity(0.08))
                        )
                    }
                    if let msg = actionSuccess {
                        HStack(spacing: MSC.Spacing.sm) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(MSC.Colors.success)
                            Text(msg).font(MSC.Typography.caption).foregroundStyle(.secondary)
                        }
                        .padding(MSC.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: MSC.Radius.sm)
                                .fill(MSC.Colors.success.opacity(0.08))
                        )
                    }

                    // ── Stats section ──────────────────────────────────────
                    statsSection

                    // ── Inventory section ──────────────────────────────────
                    inventorySection

                    // ── Actions section ────────────────────────────────────
                    actionsSection
                }
                .padding(MSC.Spacing.md)
            }
        }
        .frame(width: 580, height: 740)
        .background(MSC.Colors.tierContent)
        .onAppear {
            // Sync with latest from the published array (use stable id, not UUID)
            if let updated = viewModel.playerProfiles.first(where: { $0.id == profile.id }) {
                localProfile = updated
            }
            // Load NBT lazily for Java (Bedrock profiles already have stats pre-populated)
            if localProfile.stats == nil && !localProfile.isBedrockPlayer {
                viewModel.loadProfileNBT(uuid: profile.uuid)
            }
        }
        .onChange(of: viewModel.playerProfiles) { profiles in
            if let updated = profiles.first(where: { $0.id == profile.id }) {
                localProfile = updated
            }
        }
        .confirmationDialog(
            "Delete Player Data",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete \(localProfile.displayName)'s .dat file. This cannot be undone.")
        }
        .sheet(isPresented: $showCopyPicker) {
            CopyDataPickerSheet(
                sourceProfile: localProfile,
                onCopy: { dest in performCopy(to: dest) }
            )
            .environmentObject(viewModel)
        }
        .sheet(isPresented: $showMigrateManualInput) {
            MigrateToUUIDSheet(
                uuidInput: $manualUUIDInput,
                onConfirm: { performMigrateToManualUUID() }
            )
        }
    }

    // MARK: - Identity header

    private var identityHeader: some View {
        HStack(alignment: .top, spacing: MSC.Spacing.xl) {

            // Full-body skin with idle sway
            PlayerBodyView(identifier: localProfile.imageIdentifier, height: 160)
                .frame(width: 70)

            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {

                // Name
                Text(localProfile.displayName)
                    .font(.system(size: 18, weight: .bold))
                    .lineLimit(1)

                // UUID or XUID (monospaced, copyable)
                if let xuid = localProfile.xuid {
                    Text("XUID: \(xuid)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(MSC.Colors.tertiary)
                        .textSelection(.enabled)
                } else {
                    Text(localProfile.uuid.uuidString.lowercased())
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(MSC.Colors.tertiary)
                        .textSelection(.enabled)
                }

                // Status badges
                HStack(spacing: MSC.Spacing.sm) {
                    if localProfile.isOnline {
                        statusBadge("Online", color: MSC.Colors.success, icon: "circle.fill")
                    } else {
                        statusBadge("Offline", color: MSC.Colors.tertiary, icon: "circle")
                    }
                    if localProfile.isOp {
                        statusBadge("Operator", color: Color.yellow.opacity(0.8), icon: "star.fill")
                    }
                    if localProfile.isBedrockPlayer {
                        statusBadge("Bedrock", color: MSC.Colors.info, icon: "cube.fill")
                    } else if let offUUID = viewModel.offlineUUID(for: localProfile),
                              offUUID != localProfile.uuid {
                        // Show mode badge only for Java
                        statusBadge("Online UUID", color: MSC.Colors.info, icon: "network")
                    }
                }

                // Last modified
                HStack(spacing: 4) {
                    Image(systemName: "clock").font(.system(size: 10))
                    Text("Last seen ").font(MSC.Typography.caption)
                    Text(localProfile.lastModified, style: .relative).font(MSC.Typography.caption)
                }
                .foregroundStyle(MSC.Colors.caption)
            }

            Spacer()
        }
    }

    // MARK: - Stats section

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
            sectionHeader("Stats", icon: "chart.bar.fill")

            if let stats = localProfile.stats {
                VStack(spacing: MSC.Spacing.sm) {

                    // Health bar
                    statRow(
                        icon: "heart.fill", iconColor: .red,
                        label: "Health",
                        value: String(format: "%.1f / %.0f", stats.health, stats.maxHealth)
                    ) {
                        ProgressView(value: stats.healthFraction)
                            .tint(.red)
                            .frame(width: 100)
                    }

                    // Food bar
                    statRow(
                        icon: "fork.knife", iconColor: .orange,
                        label: "Food",
                        value: "\(stats.foodLevel) / 20"
                    ) {
                        ProgressView(value: stats.foodFraction)
                            .tint(.orange)
                            .frame(width: 100)
                    }

                    Divider()

                    // XP
                    HStack {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.green)
                            .frame(width: 14)
                        Text("XP")
                            .font(MSC.Typography.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Level \(stats.xpLevel)")
                            .font(MSC.Typography.captionBold)
                        Text("·")
                            .foregroundStyle(MSC.Colors.tertiary)
                        Text("\(stats.xpTotal) total")
                            .font(MSC.Typography.caption)
                            .foregroundStyle(MSC.Colors.caption)
                    }

                    // Gamemode
                    HStack {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(MSC.Colors.info)
                            .frame(width: 14)
                        Text("Mode")
                            .font(MSC.Typography.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(stats.gameModeDisplay)
                            .font(MSC.Typography.captionBold)
                    }

                    // Position
                    HStack {
                        Image(systemName: "location.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(MSC.Colors.accent)
                            .frame(width: 14)
                        Text("Position")
                            .font(MSC.Typography.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "x %.0f  y %.0f  z %.0f", stats.posX, stats.posY, stats.posZ))
                            .font(.system(size: 11, design: .monospaced))
                        Text("·")
                            .foregroundStyle(MSC.Colors.tertiary)
                        Text(stats.dimensionDisplay)
                            .font(MSC.Typography.caption)
                            .foregroundStyle(MSC.Colors.caption)
                    }

                    // Score
                    if stats.score > 0 {
                        HStack {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.yellow)
                                .frame(width: 14)
                            Text("Score")
                                .font(MSC.Typography.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(stats.score)")
                                .font(MSC.Typography.captionBold)
                        }
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

            } else {
                HStack(spacing: MSC.Spacing.sm) {
                    ProgressView().scaleEffect(0.7)
                    Text("Loading stats…")
                        .font(MSC.Typography.caption)
                        .foregroundStyle(MSC.Colors.caption)
                }
                .padding(MSC.Spacing.md)
            }
        }
    }

    // MARK: - Inventory section

    private var inventorySection: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
            sectionHeader("Inventory", icon: "square.grid.3x3.fill")

            if localProfile.stats == nil {
                HStack(spacing: MSC.Spacing.sm) {
                    ProgressView().scaleEffect(0.7)
                    Text("Loading inventory…")
                        .font(MSC.Typography.caption)
                        .foregroundStyle(MSC.Colors.caption)
                }
                .padding(MSC.Spacing.md)
            } else if localProfile.inventory.isEmpty {
                Text("Inventory is empty.")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.caption)
                    .padding(MSC.Spacing.md)
            } else {
                PlayerInventoryView(inventory: localProfile.inventory)
                    .padding(MSC.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                            .fill(MSC.Colors.tierContent)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                            .stroke(MSC.Colors.contentBorder, lineWidth: 1)
                    )
            }
        }
    }

    // MARK: - Actions section

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
            sectionHeader("Data Management", icon: "gearshape.fill")

            if localProfile.isBedrockPlayer {
                bedrockActionsNote
            } else {
                javaActionsButtons
            }
        }
    }

    private var bedrockActionsNote: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
            HStack(spacing: MSC.Spacing.sm) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(MSC.Colors.info)
                Text("Bedrock player data is stored in a LevelDB database and cannot be edited directly from this app. Stop the server and use a LevelDB editor to modify or remove player data.")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(MSC.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.sm)
                    .fill(MSC.Colors.info.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MSC.Radius.sm)
                    .stroke(MSC.Colors.info.opacity(0.2), lineWidth: 1)
            )
        }
    }

    private var javaActionsButtons: some View {
        VStack(spacing: MSC.Spacing.sm) {

            // Primary action: migrate to offline UUID
            if let offUUID = viewModel.offlineUUID(for: localProfile) {
                actionButton(
                    label: "Migrate to Offline UUID",
                    subtitle: "Copy data to \(offUUID.uuidString.prefix(8))…",
                    icon: "arrow.triangle.swap",
                    color: MSC.Colors.info
                ) {
                    performMigrateToOffline()
                }
            } else {
                actionButton(
                    label: "Migrate to Custom UUID",
                    subtitle: "Enter a target UUID to copy data to",
                    icon: "arrow.triangle.swap",
                    color: MSC.Colors.info
                ) {
                    showMigrateManualInput = true
                }
            }

            actionButton(
                label: "Copy Data To…",
                subtitle: "Copy this player's data onto another profile",
                icon: "doc.on.doc",
                color: .secondary
            ) {
                showCopyPicker = true
            }

            actionButton(
                label: "Duplicate",
                subtitle: "Create a copy under a new random UUID",
                icon: "plus.square.on.square",
                color: .secondary
            ) {
                performDuplicate()
            }

            actionButton(
                label: "Delete Player Data",
                subtitle: "Permanently remove this player's .dat file",
                icon: "trash",
                color: MSC.Colors.error
            ) {
                showDeleteConfirm = true
            }
        }
    }

    // MARK: - Action implementations

    private func performMigrateToOffline() {
        do {
            try viewModel.migratePlayerToOfflineUUID(profile: localProfile)
            flash(success: "Data copied to offline UUID successfully.")
        } catch {
            flash(error: error.localizedDescription)
        }
    }

    private func performMigrateToManualUUID() {
        let trimmed = manualUUIDInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let uuid = UUID(uuidString: trimmed) else {
            flash(error: "Invalid UUID format. Use xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx.")
            return
        }
        do {
            try viewModel.migratePlayerToUUID(profile: localProfile, targetUUID: uuid)
            manualUUIDInput = ""
            flash(success: "Data copied to \(uuid.uuidString.lowercased()).")
        } catch {
            flash(error: error.localizedDescription)
        }
    }

    private func performCopy(to dest: PlayerProfile) {
        do {
            try viewModel.copyPlayerData(from: localProfile.uuid, to: dest.uuid)
            flash(success: "Data copied to \(dest.displayName).")
        } catch {
            flash(error: error.localizedDescription)
        }
    }

    private func performDuplicate() {
        do {
            try viewModel.duplicatePlayerData(uuid: localProfile.uuid)
            flash(success: "Duplicate created with a new UUID.")
        } catch {
            flash(error: error.localizedDescription)
        }
    }

    private func performDelete() {
        do {
            try viewModel.deletePlayerData(uuid: localProfile.uuid)
            dismiss()
        } catch {
            flash(error: error.localizedDescription)
        }
    }

    private func flash(success msg: String) {
        actionError = nil
        actionSuccess = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { actionSuccess = nil }
    }

    private func flash(error msg: String) {
        actionSuccess = nil
        actionError = msg
    }

    // MARK: - Reusable subviews

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(MSC.Typography.cardTitle)
            .foregroundStyle(.secondary)
    }

    private func statusBadge(_ label: String, color: Color, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 8))
            Text(label).font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(color.opacity(0.12))
        )
        .overlay(
            Capsule().stroke(color.opacity(0.25), lineWidth: 0.5)
        )
    }

    private func statRow<Bar: View>(
        icon: String, iconColor: Color,
        label: String, value: String,
        @ViewBuilder bar: () -> Bar
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(iconColor)
                .frame(width: 14)
            Text(label)
                .font(MSC.Typography.caption)
                .foregroundStyle(.secondary)
            Spacer()
            bar()
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(width: 80, alignment: .trailing)
        }
    }

    private func actionButton(
        label: String, subtitle: String,
        icon: String, color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: MSC.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(color)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(MSC.Typography.captionBold)
                        .foregroundStyle(color == MSC.Colors.error ? MSC.Colors.error : .primary)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(MSC.Colors.tertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(MSC.Colors.tertiary)
            }
            .padding(.horizontal, MSC.Spacing.md)
            .padding(.vertical, MSC.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                    .fill(color == MSC.Colors.error ? MSC.Colors.error.opacity(0.06) : MSC.Colors.subtleBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                    .stroke(
                        color == MSC.Colors.error ? MSC.Colors.error.opacity(0.2) : MSC.Colors.contentBorder,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Copy Data Picker Sheet

private struct CopyDataPickerSheet: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    let sourceProfile: PlayerProfile
    let onCopy: (PlayerProfile) -> Void

    @State private var selectedDest: PlayerProfile? = nil

    private var otherProfiles: [PlayerProfile] {
        viewModel.playerProfiles.filter { $0.uuid != sourceProfile.uuid }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Copy Data To…", systemImage: "doc.on.doc")
                    .font(MSC.Typography.cardTitle)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MSC.Colors.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(MSC.Spacing.md)

            Divider()

            if otherProfiles.isEmpty {
                Text("No other player profiles found.")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.caption)
                    .padding(MSC.Spacing.xl)
            } else {
                Text("Select the destination player. Their existing data will be overwritten.")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.caption)
                    .padding(.horizontal, MSC.Spacing.md)
                    .padding(.top, MSC.Spacing.sm)

                ScrollView {
                    VStack(spacing: MSC.Spacing.xs) {
                        ForEach(otherProfiles) { dest in
                            Button {
                                selectedDest = dest
                            } label: {
                                HStack(spacing: MSC.Spacing.md) {
                                    PlayerHeadView(identifier: dest.imageIdentifier, size: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(dest.displayName).font(MSC.Typography.captionBold)
                                        Text(dest.id.prefix(16) + "…")
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(MSC.Colors.tertiary)
                                    }
                                    Spacer()
                                    if selectedDest?.uuid == dest.uuid {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(MSC.Colors.success)
                                    }
                                }
                                .padding(MSC.Spacing.sm)
                                .background(
                                    RoundedRectangle(cornerRadius: MSC.Radius.sm)
                                        .fill(selectedDest?.uuid == dest.uuid
                                              ? MSC.Colors.success.opacity(0.08)
                                              : MSC.Colors.subtleBackground)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(MSC.Spacing.md)
                }
            }

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .controlSize(.small)
                Spacer()
                Button("Copy Data") {
                    if let dest = selectedDest {
                        onCopy(dest)
                        dismiss()
                    }
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled(selectedDest == nil)
            }
            .padding(MSC.Spacing.md)
        }
        .frame(width: 380, height: 380)
        .background(MSC.Colors.tierContent)
    }
}

// MARK: - Migrate to Custom UUID Sheet

private struct MigrateToUUIDSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var uuidInput: String
    let onConfirm: () -> Void

    var isValid: Bool {
        UUID(uuidString: uuidInput.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }

    var body: some View {
        VStack(spacing: MSC.Spacing.lg) {
            Label("Migrate to UUID", systemImage: "arrow.triangle.swap")
                .font(MSC.Typography.cardTitle)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Enter the destination UUID. The player's .dat file will be copied to that UUID. Existing data at the destination will be overwritten.")
                .font(MSC.Typography.caption)
                .foregroundStyle(MSC.Colors.caption)
                .fixedSize(horizontal: false, vertical: true)

            TextField("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", text: $uuidInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .onChange(of: uuidInput) { _ in }

            if !uuidInput.isEmpty && !isValid {
                Text("Not a valid UUID format.")
                    .font(.caption2)
                    .foregroundStyle(MSC.Colors.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .controlSize(.small)
                Spacer()
                Button("Migrate") {
                    onConfirm()
                    dismiss()
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
        }
        .padding(MSC.Spacing.lg)
        .frame(width: 360)
        .background(MSC.Colors.tierContent)
    }
}

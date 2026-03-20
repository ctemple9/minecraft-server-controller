// WorldSlotsView.swift
// MinecraftServerController
//
//
// Realms-style world slot picker for both Java and Bedrock servers.
// Displayed as a sheet from the server detail view.
//
// Layout:
//   - Header with server name and "Save Current World" button
//   - 3-column card grid of saved slots
//   - Each card: name, date saved, last played, size, Activate / Rename / Delete actions
//   - Empty state with guidance

import SwiftUI

struct WorldSlotsView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Binding var isPresented: Bool

    // Sheet state
    @State private var showCreateWorldSheet = false
    @State private var showActivateConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showRenameSheet = false

    @State private var pendingSlot: WorldSlot? = nil
    @State private var newSlotName: String = ""

    // Computed from ViewModel
    private var cfgServer: ConfigServer? {
        guard let s = viewModel.selectedServer else { return nil }
        return viewModel.configServer(for: s)
    }

    private var serverIsRunning: Bool {
        viewModel.isServerRunning &&
        viewModel.configManager.config.activeServerId == cfgServer?.id
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ──────────────────────────────────────────────────────────
            headerSection

            Divider()

            // ── Grid or empty state ──────────────────────────────────────────────
            if viewModel.worldSlots.isEmpty && !viewModel.isWorldSlotsLoading {
                emptyState
            } else {
                slotGrid
            }
        }
        .frame(minWidth: 700, minHeight: 520)
        .onAppear {
            viewModel.loadWorldSlotsForSelectedServer()
        }
        // ── Save sheet ──────────────────────────────────────────────────────────
        .sheet(isPresented: $showCreateWorldSheet) {
            CreateWorldSlotSheet(isPresented: $showCreateWorldSheet) { name, seed in
                viewModel.createNewWorldSlot(name: name, seed: seed)
            }
        }
        // ── Activate confirmation ────────────────────────────────────────────────
        .confirmationDialog(
            activateTitle,
            isPresented: $showActivateConfirm,
            titleVisibility: .visible
        ) {
            Button("Activate Slot", role: .destructive) {
                if let slot = pendingSlot {
                    viewModel.activateWorldSlot(slot)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current world will be backed up automatically before the swap. This cannot be undone without restoring from backup.")
        }
        // ── Delete confirmation ──────────────────────────────────────────────────
        .confirmationDialog(
            deleteTitle,
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Slot", role: .destructive) {
                if let slot = pendingSlot {
                    viewModel.deleteWorldSlot(slot)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the saved world slot. It cannot be undone.")
        }
        // ── Rename sheet ─────────────────────────────────────────────────────────
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
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: MSC.Spacing.lg) {
            VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                Text("World Slots")
                    .font(MSC.Typography.pageTitle)
                if let name = cfgServer?.displayName {
                    Text(name)
                        .font(MSC.Typography.caption)
                        .foregroundStyle(MSC.Colors.caption)
                }
            }

            Spacer()

            if viewModel.isWorldSlotsLoading {
                ProgressView()
                    .scaleEffect(0.7)
            }

            Button(action: { viewModel.saveCurrentWorldToActiveSlot() }) {
                Label("Save Current World", systemImage: "square.and.arrow.down")
            }
            .disabled(viewModel.isWorldSlotsLoading)
            .help("Save the current live world back into the active slot")

            Button(action: { showCreateWorldSheet = true }) {
                Label("Create New World", systemImage: "plus")
            }
            .disabled(viewModel.isWorldSlotsLoading)
            .help("Create a brand-new persistent world slot")

            Button("Done") { isPresented = false }
        }
        .padding(MSC.Spacing.lg)
    }

    // MARK: - Grid

    private var slotGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: MSC.Spacing.lg),
                    GridItem(.flexible(), spacing: MSC.Spacing.lg),
                    GridItem(.flexible(), spacing: MSC.Spacing.lg)
                ],
                spacing: MSC.Spacing.lg
            ) {
                ForEach(viewModel.worldSlots) { slot in
                    let activeSlotId = cfgServer.map { viewModel.activeWorldSlotId(forServerDir: $0.serverDir) } ?? nil
                    WorldSlotCard(
                        slot: slot,
                        isActive: activeSlotId == slot.id,
                        serverIsRunning: serverIsRunning,
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
                            showDeleteConfirm = true
                        }
                    )
                }
            }
            .padding(MSC.Spacing.lg)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: MSC.Spacing.xl) {
            Spacer()
            Image(systemName: "globe.desk")
                .font(.system(size: 48))
                .foregroundStyle(MSC.Colors.caption)

            VStack(spacing: MSC.Spacing.sm) {
                Text("No World Slots Yet")
                    .font(MSC.Typography.sectionHeader)
                Text("Create a new world slot or save the current active world back into its slot. You can switch between slots anytime the server is stopped.")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.caption)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            Button(action: { showCreateWorldSheet = true }) {
                Label("Create New World", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Confirmation dialog titles

    private var activateTitle: String {
        if let slot = pendingSlot {
            return "Activate \"\(slot.name)\"?"
        }
        return "Activate World Slot?"
    }

    private var deleteTitle: String {
        if let slot = pendingSlot {
            return "Delete \"\(slot.name)\"?"
        }
        return "Delete World Slot?"
    }
}

// MARK: - WorldSlotCard

private struct WorldSlotCard: View {
    let slot: WorldSlot
    let isActive: Bool
    let serverIsRunning: Bool
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

            // ── Realms-style thumbnail ────────────────────────────────────────
            ZStack(alignment: .bottomLeading) {
                // Sky gradient
                LinearGradient(
                    colors: [Color(hue: 0.57, saturation: 0.6, brightness: 0.85),
                             Color(hue: 0.57, saturation: 0.45, brightness: 0.65)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 110)

                // Ground strip — grass on top, dirt below
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color(hue: 0.33, saturation: 0.55, brightness: 0.42))
                        .frame(height: 10)
                    Rectangle()
                        .fill(Color(hue: 0.07, saturation: 0.45, brightness: 0.35))
                        .frame(height: 20)
                }
                .frame(maxWidth: .infinity)

                // World icon
                Image(systemName: "mountain.2.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.25))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 30)

                // Size badge — bottom left
                if let bytes = slot.zipSizeBytes {
                    Text(WorldSlotManager.formatBytes(bytes))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.black.opacity(0.4)))
                        .padding(8)
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
                    .padding(8)
                }
            }
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: MSC.Radius.lg,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: MSC.Radius.lg
            ))

            // ── Info ──────────────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 4) {
                Text(slot.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("Saved \(Self.dateFormatter.string(from: slot.createdAt))")
                    .font(.system(size: 11))
                    .foregroundStyle(MSC.Colors.caption)
                    .lineLimit(1)

                if let played = slot.lastPlayedAt {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                            .foregroundStyle(MSC.Colors.caption)
                        Text("Played \(Self.dateFormatter.string(from: played))")
                            .font(.system(size: 11))
                            .foregroundStyle(MSC.Colors.caption)
                            .lineLimit(1)
                    }
                }

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

            Divider()
                .padding(.horizontal, MSC.Spacing.sm)

            // ── Actions ───────────────────────────────────────────────────────
            HStack(spacing: MSC.Spacing.xs) {
                Button(action: onActivate) {
                    Text(isActive ? "Active" : "Activate")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(serverIsRunning || isActive)
                .help(serverIsRunning ? "Stop the server before switching worlds" : isActive ? "This world is already active" : "Load this world")

                Spacer()

                Button(action: onRename) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Rename this slot")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Delete this slot permanently")
            }
            .padding(.horizontal, MSC.Spacing.md)
            .padding(.vertical, MSC.Spacing.sm)
        }
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.lg)
                .fill(MSC.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: MSC.Radius.lg)
                        .stroke(
                            isActive ? MSC.Colors.success.opacity(0.8)
                                : (isHovered ? Color.accentColor.opacity(0.5) : MSC.Colors.cardBorder),
                            lineWidth: isActive ? 2 : 1
                        )
                )
        )
        .shadow(color: isActive ? MSC.Colors.success.opacity(0.15) : .black.opacity(isHovered ? 0.10 : 0.04),
                radius: isActive ? 6 : (isHovered ? 8 : 3), y: 2)
        .scaleEffect(isHovered ? 1.015 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
    }
}



// MARK: - RenameSlotSheet

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
                Button("Rename") {
                    onRename(newName)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newName == currentName)
            }
        }
        .padding(MSC.Spacing.xxl)
        .frame(width: 340)
        .onAppear {
            newName = currentName
            focused = true
        }
    }
}


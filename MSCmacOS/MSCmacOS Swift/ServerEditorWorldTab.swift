import SwiftUI
import AppKit

extension ServerEditorView {
// MARK: - WORLD TAB  (full-width master-detail, no outer ScrollView)

var worldTab: some View {
    Group {
        if mode == .new || editingConfigServer == nil {
            // Unavailable state — show card in a scroll view
            ScrollView {
                SEUnavailableCard(
                    icon: "globe",
                    title: "Save first to use world tools",
                    message: "World management is available after this server has been created. Save, then reopen Edit Server."
                )
                .padding(MSC.Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else if let cfg = editingConfigServer {
            HStack(spacing: 0) {
                worldListPanel(cfg: cfg)
                Divider()
                worldInspectorPanel(cfg: cfg)
            }
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    // Import ZIP sheet
    .sheet(isPresented: $showImportZIPSheet) {
        importZIPSheetView
    }
    // Replace World sheet
    .sheet(isPresented: $showReplaceWorldSheet) {
        if let cfg = editingConfigServer {
            replaceWorldSheetView(cfg: cfg)
        }
    }
    // Create World sheet
    .sheet(isPresented: $showCreateWorldSlotSheet) {
        CreateWorldSlotSheet(isPresented: $showCreateWorldSlotSheet) { name, seed in
            viewModel.createNewWorldSlot(name: name, seed: seed)
        }
    }
    // Repair World sheet (Bedrock only)
    .sheet(isPresented: $showRepairWorldSheet) {
        WorldRepairView(isPresented: $showRepairWorldSheet)
            .environmentObject(viewModel)
    }
    // Slot Duplicate sheet
    .sheet(isPresented: $showDuplicateSlotSheet) { duplicateSlotSheetView }
    // World conversion wizard
    .sheet(item: $conversionContextEditor) { ctx in
        WorldConversionWizardView(
            isPresented: Binding(
                get: { conversionContextEditor != nil },
                set: { if !$0 { conversionContextEditor = nil } }
            ),
            sourceSlot: ctx.slot,
            sourceServer: ctx.server
        )
        .environmentObject(viewModel)
    }
    .contextualHelpAnchor(worldSlotsAnchorID)
}

// MARK: - Left Panel: World List

@ViewBuilder
func worldListPanel(cfg: ConfigServer) -> some View {
    VStack(spacing: 0) {
        // Header
        HStack(spacing: MSC.Spacing.sm) {
            Text("World Slots")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(MSC.Colors.tertiary)
                .textCase(.uppercase)
            Spacer()
            Button {
                viewModel.saveCurrentWorldToActiveSlot()
            } label: {
                Label("Save", systemImage: "square.and.arrow.down.on.square")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(MSCSecondaryButtonStyle())
            .help("Save the live world back into the active slot")

            Button {
                showCreateWorldSlotSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(MSCSecondaryButtonStyle())
            .help("Create a new world slot")
        }
        .padding(.horizontal, MSC.Spacing.md)
        .padding(.vertical, MSC.Spacing.sm)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))

        Divider()

        // Slot list
        ScrollView {
            LazyVStack(spacing: MSC.Spacing.sm) {
                if viewModel.worldSlots.isEmpty {
                    VStack(spacing: MSC.Spacing.sm) {
                        Image(systemName: "square.dashed")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(.secondary.opacity(0.4))
                        Text("No world slots yet")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text("Use + to create one, or save the current active world.")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, MSC.Spacing.xxl)
                } else {
                    let activeId = viewModel.activeWorldSlotId(forServerDir: cfg.serverDir)
                    ForEach(viewModel.worldSlots) { slot in
                        WorldSlotListCard(
                            slot: slot,
                            isActive: activeId == slot.id,
                            isSelected: selectedSlotForEditor?.id == slot.id
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedSlotForEditor = selectedSlotForEditor?.id == slot.id ? nil : slot
                            }
                        }
                    }
                }
            }
            .padding(MSC.Spacing.sm)
        }

        Divider()

        // Footer: Import ZIP
        Button {
            browseForImportZIP()
            if !importZIPPath.isEmpty {
                showImportZIPSheet = true
            }
        } label: {
            Label("Import ZIP as New World…", systemImage: "square.and.arrow.down")
                .font(.system(size: 11))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .padding(.horizontal, MSC.Spacing.md)
        .padding(.vertical, MSC.Spacing.sm + 1)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
    }
    .frame(width: 220)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.2))
}

// MARK: - Right Panel: World Inspector

@ViewBuilder
func worldInspectorPanel(cfg: ConfigServer) -> some View {
    if let slot = selectedSlotForEditor {
        ScrollView {
            worldInspectorView(slot: slot, cfg: cfg)
                .padding(MSC.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
        VStack(spacing: MSC.Spacing.md) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary.opacity(0.35))
            Text("Select a world")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Click a world slot on the left to manage it.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - World Inspector Content

@ViewBuilder
func worldInspectorView(slot: WorldSlot, cfg: ConfigServer) -> some View {
    let isActive = viewModel.activeWorldSlotId(forServerDir: cfg.serverDir) == slot.id
    let slotBackups = viewModel.backupItems
        .filter { $0.slotId == slot.id }
        .sorted { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) }

    VStack(alignment: .leading, spacing: MSC.Spacing.lg) {

        // ── Hero thumbnail ─────────────────────────────────────────
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [
                    Color(hue: 0.57, saturation: 0.60, brightness: 0.85),
                    Color(hue: 0.57, saturation: 0.45, brightness: 0.65)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxWidth: .infinity)
            .frame(height: 130)
            .overlay(
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color(hue: 0.33, saturation: 0.55, brightness: 0.42))
                        .frame(height: 8)
                    Rectangle()
                        .fill(Color(hue: 0.07, saturation: 0.45, brightness: 0.35))
                        .frame(height: 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            )

            if isActive {
                HStack(spacing: 4) {
                    Circle().fill(MSC.Colors.success).frame(width: 5, height: 5)
                    Text("Active")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(MSC.Colors.success.opacity(0.85)))
                .padding(MSC.Spacing.sm)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous))

        // ── Name + Rename ──────────────────────────────────────────
        HStack(spacing: MSC.Spacing.sm) {
            if showSlotRenameId == slot.id {
                TextField("Slot name", text: $slotRenameText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 16, weight: .bold))
                    .onSubmit {
                        let newName = slotRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !newName.isEmpty {
                            Task { await viewModel.renameWorldSlot(slot, newName: newName) }
                        }
                        showSlotRenameId = nil
                    }
                Button("Cancel") { showSlotRenameId = nil }
                    .buttonStyle(MSCSecondaryButtonStyle())
            } else {
                Text(slot.name)
                    .font(.system(size: 17, weight: .bold))
                    .lineLimit(1)
                Spacer()
                Button {
                    exportSlot(slot, cfg: cfg)
                } label: {
                    Label("Export…", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(MSCSecondaryButtonStyle())
                Button {
                    slotRenameText = slot.name
                    showSlotRenameId = slot.id
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .buttonStyle(MSCSecondaryButtonStyle())
            }
        }

        // ── Badges ────────────────────────────────────────────────
        HStack(spacing: MSC.Spacing.sm) {
            if isActive {
                Text("● Active")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MSC.Colors.success)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(MSC.Colors.success.opacity(0.10)))
                    .overlay(Capsule().stroke(MSC.Colors.success.opacity(0.25), lineWidth: 0.5))
            } else {
                Text("Inactive")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.secondary.opacity(0.08)))
                    .overlay(Capsule().stroke(Color.secondary.opacity(0.2), lineWidth: 0.5))
            }
            if let bytes = slot.zipSizeBytes {
                Text(WorldSlotManager.formatBytes(bytes))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.secondary.opacity(0.07)))
                    .overlay(Capsule().stroke(Color.secondary.opacity(0.15), lineWidth: 0.5))
            }
            Text(shortDate(slot.createdAt))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.secondary.opacity(0.07)))
                .overlay(Capsule().stroke(Color.secondary.opacity(0.15), lineWidth: 0.5))
            if let seed = slot.worldSeed?.trimmingCharacters(in: .whitespacesAndNewlines), !seed.isEmpty {
                Text("Seed: \(seed)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.secondary.opacity(0.07)))
                    .overlay(Capsule().stroke(Color.secondary.opacity(0.15), lineWidth: 0.5))
                    .textSelection(.enabled)
            }
        }

        // ── Actions ───────────────────────────────────────────────
        SEBlockHeader(title: "Actions")
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: MSC.Spacing.sm),
                      GridItem(.flexible(), spacing: MSC.Spacing.sm)],
            spacing: MSC.Spacing.sm
        ) {
            if isActive {
                WorldActionButton(icon: "square.and.arrow.down.on.square",
                                  label: "Save Live World Here",
                                  style: .primary) {
                    viewModel.saveCurrentWorldToActiveSlot()
                }
                .contextualHelpAnchor(worldSaveCurrentAnchorID)
            } else {
                WorldActionButton(icon: "play.fill",
                                  label: "Set as Active",
                                  style: .primary) {
                    Task { await viewModel.activateWorldSlot(slot) }
                }
                .disabled(viewModel.isServerRunning)
            }

            WorldActionButton(icon: "doc.on.doc", label: "Duplicate…", style: .normal) {
                duplicateSlotName = slot.name + " Copy"
                showDuplicateSlotSheet = true
            }

            WorldActionButton(icon: "arrow.2.squarepath", label: "Convert World…", style: .normal) {
                conversionContextEditor = WorldConversionContext(slot: slot, server: cfg)
            }

            WorldActionButton(icon: "arrow.triangle.2.circlepath", label: "Replace World…", style: .normal) {
                replaceSourcePath = ""
                showReplaceWorldSheet = true
            }
            .contextualHelpAnchor(worldReplaceAnchorID)

            if cfg.isBedrock {
                WorldActionButton(icon: "wrench.and.screwdriver", label: "Repair World…", style: .normal) {
                    showRepairWorldSheet = true
                }
                .disabled(viewModel.isServerRunning)
            }
        }

        Button(role: .destructive) {
            slotToDelete = slot
            showSlotDeleteConfirm = true
        } label: {
            Label("Delete This World Slot", systemImage: "trash.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(MSCDestructiveButtonStyle())

        Divider().opacity(0.5)

        // ── Backup History ────────────────────────────────────────
        SEBlockHeader(title: "Backup History")

        if slotBackups.isEmpty {
            Text("No backups for this world yet.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, MSC.Spacing.md)
        } else {
            SEBlock {
                ForEach(Array(slotBackups.enumerated()), id: \.element.id) { idx, item in
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
                                        ? Color.blue.opacity(0.10)
                                        : Color.gray.opacity(0.10))
                            .foregroundStyle(item.isAutomatic ? Color.blue : Color.secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        if let size = item.fileSize {
                            Text(formatBytes(size))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Restore") {
                            selectedBackupId = item.id
                            showRestoreConfirm = true
                        }
                        .buttonStyle(MSCSecondaryButtonStyle())
                        .controlSize(.small)
                    }
                    .padding(.horizontal, MSC.Spacing.md - 1)
                    .padding(.vertical, MSC.Spacing.sm - 1)
                }
            }
        }

        Button("Back Up Now") {
            Task {
                await viewModel.createBackup(for: cfg,
                                             isAutomatic: false,
                                             slotId: slot.id,
                                             slotName: slot.name)
            }
        }
        .buttonStyle(MSCSecondaryButtonStyle())
        .disabled(viewModel.isServerRunning)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Import ZIP Sheet

var importZIPSheetView: some View {
    VStack(alignment: .leading, spacing: MSC.Spacing.md) {
        Text("Import ZIP as New World Slot")
            .font(.system(size: 16, weight: .bold))

        Text("Selected: \(URL(fileURLWithPath: importZIPPath).lastPathComponent)")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)

        VStack(alignment: .leading, spacing: 4) {
            Text("SLOT NAME")
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(MSC.Colors.tertiary)
            TextField("Slot name", text: $importSlotName)
                .textFieldStyle(.roundedBorder)
        }

        HStack {
            Spacer()
            Button("Cancel") {
                importZIPPath = ""
                importSlotName = ""
                showImportZIPSheet = false
            }
            .buttonStyle(MSCSecondaryButtonStyle())

            Button("Import") {
                let zipURL = URL(fileURLWithPath: importZIPPath)
                let name = importSlotName.trimmingCharacters(in: .whitespacesAndNewlines)
                Task {
                    let ok = await viewModel.importZIPAsSlot(zipURL: zipURL, name: name)
                    if ok {
                        importZIPPath = ""
                        importSlotName = ""
                    }
                }
                showImportZIPSheet = false
            }
            .buttonStyle(MSCPrimaryButtonStyle())
            .disabled(importSlotName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
    .padding(MSC.Spacing.xl)
    .frame(minWidth: 380)
}

// MARK: - Replace World Sheet

func replaceWorldSheetView(cfg: ConfigServer) -> some View {
    VStack(alignment: .leading, spacing: MSC.Spacing.md) {
        Text("Replace World")
            .font(.system(size: 16, weight: .bold))

        Text("Swap in a different world. A backup of the current world is taken first.")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        SECallout(
            icon: "exclamationmark.triangle.fill",
            color: .orange,
            text: "Stop the server before replacing the world. A safety backup is created automatically."
        )

        HStack(spacing: MSC.Spacing.sm) {
            TextField(replaceSourcePath.isEmpty ? "No source selected" : replaceSourcePath,
                      text: .constant(replaceSourcePath.isEmpty ? "" : URL(fileURLWithPath: replaceSourcePath).lastPathComponent))
                .textFieldStyle(.roundedBorder)
                .disabled(true)
                .foregroundStyle(.secondary)

            Menu("Choose…") {
                Button("World Folder…") { browseForReplaceSourceFolder() }
                Button("Backup ZIP…")   { browseForReplaceSourceZip() }
            }
            .buttonStyle(MSCSecondaryButtonStyle())
        }
        .contextualHelpAnchor(worldReplaceAnchorID)

        HStack {
            Spacer()
            Button("Cancel") {
                replaceSourcePath = ""
                showReplaceWorldSheet = false
            }
            .buttonStyle(MSCSecondaryButtonStyle())

            Button("Apply Replace") {
                let trimmed = replaceSourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                let sourceURL = URL(fileURLWithPath: trimmed)
                let isZip = sourceURL.pathExtension.lowercased() == "zip"
                let worldSource: AppViewModel.WorldSource = isZip
                    ? .backupZip(sourceURL)
                    : .existingFolder(sourceURL)
                let currentProps = ServerPropertiesManager.readProperties(serverDir: cfg.serverDir)
                let currentLevel = (currentProps["level-name"]?
                    .trimmingCharacters(in: .whitespacesAndNewlines))
                    .flatMap { $0.isEmpty ? nil : $0 } ?? "world"
                Task {
                    let ok = await viewModel.replaceWorld(
                        for: cfg,
                        newLevelName: currentLevel,
                        worldSource: worldSource,
                        backupFirst: true
                    )
                    if ok { replaceSourcePath = "" }
                }
                showReplaceWorldSheet = false
            }
            .buttonStyle(MSCPrimaryButtonStyle())
            .disabled(replaceSourcePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
    .padding(MSC.Spacing.xl)
    .frame(minWidth: 440)
}

// MARK: - Duplicate Slot Sheet (kept from original)

var duplicateSlotSheetView: some View {
    VStack(alignment: .leading, spacing: MSC.Spacing.md) {
        Text("Duplicate World Slot")
            .font(.system(size: 16, weight: .bold))

        if let slot = selectedSlotForEditor {
            Text("Source: \"\(slot.name)\"")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }

        TextField("New slot name", text: $duplicateSlotName)
            .textFieldStyle(.roundedBorder)

        HStack {
            Spacer()
            Button("Cancel") { showDuplicateSlotSheet = false }
                .buttonStyle(MSCSecondaryButtonStyle())
            Button("Duplicate") {
                if let slot = selectedSlotForEditor, let cfg = editingConfigServer {
                    let name = duplicateSlotName.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task { await viewModel.duplicateWorldSlot(slot, newName: name) }
                }
                showDuplicateSlotSheet = false
            }
            .buttonStyle(MSCPrimaryButtonStyle())
            .disabled(duplicateSlotName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
    .padding(MSC.Spacing.xl)
    .frame(minWidth: 380)
}

}

// MARK: - World Slot List Card

struct WorldSlotListCard: View {
    let slot: WorldSlot
    let isActive: Bool
    let isSelected: Bool

    private var borderColor: Color {
        if isActive && isSelected { return MSC.Colors.success }
        if isActive   { return MSC.Colors.success.opacity(0.7) }
        if isSelected { return Color.accentColor }
        return Color.clear
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail
            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    colors: [
                        Color(hue: 0.57, saturation: 0.60, brightness: 0.85),
                        Color(hue: 0.57, saturation: 0.45, brightness: 0.65)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 58)
                .overlay(
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(Color(hue: 0.33, saturation: 0.55, brightness: 0.42))
                            .frame(height: 6)
                        Rectangle()
                            .fill(Color(hue: 0.07, saturation: 0.45, brightness: 0.35))
                            .frame(height: 12)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                )

                if isActive {
                    HStack(spacing: 3) {
                        Circle().fill(Color.white).frame(width: 4, height: 4)
                        Text("Active")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(MSC.Colors.success.opacity(0.85)))
                    .padding(5)
                }
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.name)
                    .font(.system(size: 11, weight: .bold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 4) {
                    if let bytes = slot.zipSizeBytes {
                        Text(WorldSlotManager.formatBytes(bytes))
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                        Text("·")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                    }
                    Text(shortDate(slot.createdAt))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, MSC.Spacing.sm)
            .padding(.vertical, MSC.Spacing.xs + 1)
            .background(MSC.Colors.tierContent)
        }
        .clipShape(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .stroke(isSelected || isActive ? borderColor : MSC.Colors.contentBorder,
                        lineWidth: isSelected || isActive ? 1.5 : 1)
        )
        .shadow(
            color: isActive ? MSC.Colors.success.opacity(0.10) : .black.opacity(isSelected ? 0.07 : 0.03),
            radius: isActive ? 4 : 2, y: 1
        )
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .none
        return f.string(from: date)
    }
}

// MARK: - World Action Button

struct WorldActionButton: View {
    enum Style { case primary, normal }

    let icon: String
    let label: String
    let style: Style
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: MSC.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                Text(label)
                    .font(.system(size: 10.5))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, MSC.Spacing.sm)
            .padding(.vertical, MSC.Spacing.sm)
            .background {
                let bg: Color = style == .primary
                    ? Color.accentColor.opacity(isEnabled ? 0.12 : 0.05)
                    : MSC.Colors.tierContent
                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).fill(bg)
            }
            .overlay(
                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                    .stroke(style == .primary
                            ? Color.accentColor.opacity(isEnabled ? 0.35 : 0.12)
                            : MSC.Colors.contentBorder,
                            lineWidth: 1)
            )
            .foregroundStyle(style == .primary
                             ? (isEnabled ? Color.accentColor : Color.secondary)
                             : (isEnabled ? Color.primary : Color.secondary))
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1.0 : 0.55)
    }
}

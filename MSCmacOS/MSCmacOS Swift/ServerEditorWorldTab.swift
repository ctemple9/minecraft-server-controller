import SwiftUI
import AppKit

extension ServerEditorView {
// MARK: - WORLD TAB (P6 full admin surface)

var worldTab: some View {
    VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
        if mode == .new || editingConfigServer == nil {
            SEUnavailableCard(
                icon: "globe",
                title: "Save first to use world tools",
                message: "World management is available after this server has been created. Save, then reopen Edit Server."
            )
        } else if let cfg = editingConfigServer {

            // ── 1. World Slots Grid ───────────────────────────────────
            SESection(icon: "square.grid.3x3.fill", title: "World Slots", color: .blue) {
                VStack(alignment: .leading, spacing: MSC.Spacing.md) {
                    if viewModel.worldSlots.isEmpty {
                        VStack(spacing: MSC.Spacing.sm) {
                            Image(systemName: "square.dashed")
                                .font(.system(size: 28, weight: .light))
                                .foregroundStyle(.secondary.opacity(0.4))
                            Text("No world slots saved yet.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Text("Use \"Create New World\" below to make a new slot, or save the current active world back into its slot.")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MSC.Spacing.lg)
                    } else {
                        let activeSlotId = viewModel.activeWorldSlotId(forServerDir: cfg.serverDir)
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: MSC.Spacing.md),
                            GridItem(.flexible(), spacing: MSC.Spacing.md),
                            GridItem(.flexible(), spacing: MSC.Spacing.md)
                        ], spacing: MSC.Spacing.md) {
                            ForEach(viewModel.worldSlots) { slot in
                                worldSlotAdminCard(slot: slot, cfg: cfg, isActive: activeSlotId == slot.id)
                            }
                        }
                    }

                    // ── 2. Slot Admin Action Buttons (when a slot is selected) ──
                    if let selected = selectedSlotForEditor {
                        Divider().opacity(0.5)

                        HStack(spacing: MSC.Spacing.sm) {
                            // Duplicate
                            Button {
                                duplicateSlotName = selected.name + " Copy"
                                showDuplicateSlotSheet = true
                            } label: {
                                Label("Duplicate…", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(MSCSecondaryButtonStyle())
                            .controlSize(.small)

                            
                            // Export as ZIP
                            Button {
                                exportSlot(selected, cfg: cfg)
                            } label: {
                                Label("Export as ZIP…", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(MSCSecondaryButtonStyle())
                            .controlSize(.small)

                            Spacer()
                            Text("Selected: \(selected.name)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .contextualHelpAnchor(worldSlotsAnchorID)

            // ── 3. Import ZIP as New Slot ─────────────────────────────
            SESection(icon: "square.and.arrow.down", title: "Import ZIP as New Slot", color: .teal) {
                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                    Text("Import an external world ZIP (e.g. from another server or a download) as a new named slot.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: MSC.Spacing.sm) {
                        TextField("No ZIP selected", text: $importZIPPath)
                            .textFieldStyle(.roundedBorder)
                            .disabled(true)
                            .foregroundStyle(.secondary)
                        Button("Browse…") { browseForImportZIP() }
                            .buttonStyle(MSCSecondaryButtonStyle())
                    }

                    HStack(spacing: MSC.Spacing.sm) {
                        TextField("Slot name", text: $importSlotName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 220)

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
                        }
                        .buttonStyle(MSCPrimaryButtonStyle())
                        .disabled(importZIPPath.isEmpty || importSlotName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .contextualHelpAnchor(worldImportAnchorID)

            // ── 4. Slot-Aware Backup History ──────────────────────────
            if let selected = selectedSlotForEditor {
                let slotBackups = viewModel.backupItems.filter { $0.slotId == selected.id }
                SESection(icon: "clock.arrow.2.circlepath", title: "Backups for \"\(selected.name)\"", color: .green) {
                    VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                        if slotBackups.isEmpty {
                            Text("No backups associated with this slot yet.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, MSC.Spacing.md)
                        } else {
                            ForEach(slotBackups.sorted { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) }) { item in
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
                                        .background(item.isAutomatic ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                                        .foregroundStyle(item.isAutomatic ? Color.blue : Color.secondary)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                    if let size = item.fileSize {
                                        Text(formatBytes(size))
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 2)
                                Divider().opacity(0.4)
                            }
                        }

                        Button("Back Up Now (for this slot)") {
                            Task {
                                await viewModel.createBackup(for: cfg, isAutomatic: false,
                                                             slotId: selected.id,
                                                             slotName: selected.name)
                            }
                        }
                        .buttonStyle(MSCSecondaryButtonStyle())
                        .controlSize(.small)
                        .disabled(viewModel.isServerRunning)
                    }
                }
            }

            // ── 5. Save Current World ─────────────────────────────────
            SESection(icon: "square.and.arrow.down.on.square", title: "Save Current World", color: .purple) {
                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                    Text("Save the server's current live world back into the active persistent slot. This no longer creates a new snapshot slot.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: MSC.Spacing.sm) {
                        if let activeName = viewModel.activeWorldSlotId(forServerDir: cfg.serverDir).flatMap({ id in
                            viewModel.worldSlots.first(where: { $0.id == id })?.name
                        }) {
                            Text("Active slot: \(activeName)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("No active slot yet — saving will create the initial persistent slot.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("Save to Active Slot") {
                            viewModel.saveCurrentWorldToActiveSlot()
                        }
                        .buttonStyle(MSCSecondaryButtonStyle())
                    }
                }
            }
            .contextualHelpAnchor(worldSaveCurrentAnchorID)

            // ── 6. Create New World ───────────────────────────────────
                        SESection(icon: "plus.square.on.square", title: "Create New World", color: .teal) {
                            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                                Text("Add another persistent world slot to this server. Worlds can be switched anytime the server is stopped.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                Button("Create New World…") {
                                    showCreateWorldSlotSheet = true
                                }
                                .buttonStyle(MSCSecondaryButtonStyle())
                            }
                        }
                        .sheet(isPresented: $showCreateWorldSlotSheet) {
                            CreateWorldSlotSheet(isPresented: $showCreateWorldSlotSheet) { name, seed in
                                viewModel.createNewWorldSlot(name: name, seed: seed)
                            }
                        }


            // ── 7. Replace World ──────────────────────────────────────
            SESection(icon: "arrow.triangle.2.circlepath", title: "Replace World", color: .orange) {
                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                    Text("Swap in a different world folder. For ZIP backups created by this app, use Backups → Restore instead.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: MSC.Spacing.sm) {
                        TextField("No source selected", text: $replaceSourcePath)
                            .textFieldStyle(.roundedBorder)
                            .disabled(true)
                            .foregroundStyle(.secondary)

                        Menu("Choose…") {
                            Button("World Folder…") { browseForReplaceSourceFolder() }
                            Button("Backup ZIP…")   { browseForReplaceSourceZip() }
                        }
                        .buttonStyle(MSCSecondaryButtonStyle())
                    }

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
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                    .disabled(replaceSourcePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .contextualHelpAnchor(worldReplaceAnchorID)

            // ── 8. Rename World ───────────────────────────────────────
            SESection(icon: "pencil", title: "Rename World", color: .purple) {
                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                    Text("Renames the world folder and updates level-name in server.properties together, so they stay in sync.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: MSC.Spacing.sm) {
                        TextField("New world name", text: $renameWorldName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 300)

                        Button("Apply Rename") {
                            let newName = renameWorldName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !newName.isEmpty else { return }
                            Task {
                                let ok = await viewModel.renameWorld(for: cfg, newLevelName: newName, backupFirst: true)
                                if ok { renameWorldName = "" }
                            }
                        }
                        .buttonStyle(MSCSecondaryButtonStyle())
                        .disabled(renameWorldName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }

            SECallout(
                icon: "exclamationmark.triangle.fill",
                color: .orange,
                text: "Always stop the server before replacing or renaming a world. Both tools create a backup of the existing world first."
            )
        }
    }
}

// MARK: - World Slot Admin Card

@ViewBuilder
func worldSlotAdminCard(slot: WorldSlot, cfg: ConfigServer, isActive: Bool) -> some View {
    let isSelected = selectedSlotForEditor?.id == slot.id

    VStack(alignment: .leading, spacing: 0) {

        // ── Thumbnail ──────────────────────────────────────────────────
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color(hue: 0.57, saturation: 0.6, brightness: 0.85),
                         Color(hue: 0.57, saturation: 0.45, brightness: 0.65)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 90)

            VStack(spacing: 0) {
                Rectangle().fill(Color(hue: 0.33, saturation: 0.55, brightness: 0.42)).frame(height: 8)
                Rectangle().fill(Color(hue: 0.07, saturation: 0.45, brightness: 0.35)).frame(height: 16)
            }
            .frame(maxWidth: .infinity)

            Image(systemName: "mountain.2.fill")
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.22))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 22)

            if let bytes = slot.zipSizeBytes {
                Text(WorldSlotManager.formatBytes(bytes))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.black.opacity(0.4)))
                    .padding(6)
            }

            // Active badge
            if isActive {
                HStack(spacing: 3) {
                    Circle().fill(MSC.Colors.success).frame(width: 5, height: 5)
                    Text("Active")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(MSC.Colors.success.opacity(0.75)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(6)
            } else if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(6)
            }
        }
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: MSC.Radius.md,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: MSC.Radius.md
        ))

        // ── Info ───────────────────────────────────────────────────────
        VStack(alignment: .leading, spacing: 3) {
            if showSlotRenameId == slot.id {
                TextField("Slot name", text: $slotRenameText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, weight: .semibold))
                    .onSubmit {
                        let newName = slotRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !newName.isEmpty {
                            Task { await viewModel.renameWorldSlot(slot, newName: newName) }
                        }
                        showSlotRenameId = nil
                    }
            } else {
                Text(slot.name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            Text(shortDate(slot.createdAt))
                .font(.system(size: 10))
                .foregroundStyle(MSC.Colors.caption)

            if let seed = slot.worldSeed?.trimmingCharacters(in: .whitespacesAndNewlines), !seed.isEmpty {
                Text("Seed \(seed)")
                    .font(.system(size: 10))
                    .foregroundStyle(MSC.Colors.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, MSC.Spacing.sm)
        .padding(.top, MSC.Spacing.xs)
        .padding(.bottom, MSC.Spacing.xxs)

        Divider().padding(.horizontal, MSC.Spacing.xs)

        // ── Actions ────────────────────────────────────────────────────
        HStack(spacing: 2) {
            Button {
                Task { await viewModel.activateWorldSlot(slot) }
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.borderless)
            .controlSize(.mini)
            .disabled(isActive || viewModel.isServerRunning)
            .help(isActive ? "Already active" : viewModel.isServerRunning ? "Stop server first" : "Activate this slot")

            Button {
                slotRenameText = slot.name
                showSlotRenameId = slot.id
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .controlSize(.mini)
            .help("Rename this slot")

            Button {
                slotToDelete = slot
                showSlotDeleteConfirm = true
            } label: {
                Image(systemName: "trash").foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .controlSize(.mini)
            .help("Delete this slot")

            Spacer()
        }
        .padding(.horizontal, MSC.Spacing.sm)
        .padding(.vertical, MSC.Spacing.xs)
    }
    .background(
        RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
            .fill(MSC.Colors.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                    .stroke(
                        isActive ? MSC.Colors.success.opacity(0.8)
                            : isSelected ? Color.accentColor.opacity(0.7)
                            : MSC.Colors.cardBorder,
                        lineWidth: (isActive || isSelected) ? 2 : 1
                    )
            )
    )
    .shadow(
        color: isActive ? MSC.Colors.success.opacity(0.12) : .black.opacity(isSelected ? 0.08 : 0.03),
        radius: isActive ? 5 : 2, y: 1
    )
    .contentShape(Rectangle())
    .onTapGesture {
        withAnimation(.easeInOut(duration: 0.15)) {
            selectedSlotForEditor = isSelected ? nil : slot
        }
    }
}

// MARK: - Duplicate Slot Sheet

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

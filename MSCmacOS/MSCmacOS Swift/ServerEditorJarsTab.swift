import SwiftUI

extension ServerEditorView {
// MARK: - JARS TAB (Java only)

var jarsTab: some View {
    VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
        if mode == .new || editingConfigServer == nil {
            SEUnavailableCard(
                icon: "shippingbox.fill",
                title: "Save first to manage JARs",
                message: "Configure the server files after this server has been created. Save, then reopen Edit Server."
            )
        } else if let cfg = editingConfigServer {
            if cfg.isModded {
                moddedInstallationSection(cfg: cfg)
            } else if cfg.javaFlavor == .vanilla {
                vanillaJarSection(cfg: cfg)
            } else if cfg.isJava {
                paperJarsSection(cfg: cfg)
            }
        }
    }
}

// MARK: - Vanilla server JAR

private func vanillaJarSection(cfg: ConfigServer) -> some View {
    let summary = viewModel.jarSummary(for: cfg)
    return VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
        SEBlockHeader(title: "Server JAR")
        SEBlock {
            SEJarRow(
                icon: "server.rack",
                color: summary.paperFilename != nil ? .blue : .red,
                title: "Vanilla Server JAR",
                filename: summary.paperFilename ?? "Not found",
                isFound: summary.paperFilename != nil
            ) {
                EmptyView()
            }
            .padding(.horizontal, MSC.Spacing.sm)
            .padding(.vertical, MSC.Spacing.xs)
        }
    }
}

// MARK: - Modded server installation + mods list

private func moddedInstallationSection(cfg: ConfigServer) -> some View {
    let isInstalled = moddedServerIsInstalled(cfg: cfg)
    let mcVersion    = cfg.minecraftVersion ?? "Unknown"
    let loaderVer    = cfg.loaderVersion    ?? "Unknown"
    let versionLabel = "MC \(mcVersion) · \(cfg.javaFlavor.displayName) \(loaderVer)"
    let mods = viewModel.discoveredMods

    return VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
        SECallout(
            icon: "info.circle.fill",
            color: .blue,
            text: "The Minecraft version and \(cfg.javaFlavor.displayName) loader version are managed from the Components tab. Use the download button there to switch versions."
        )

        SEBlockHeader(title: "Server Installation")
        SEBlock {
            SEJarRow(
                icon: cfg.javaFlavor.iconName,
                color: isInstalled ? .blue : .red,
                title: "\(cfg.javaFlavor.displayName) Server",
                filename: isInstalled ? versionLabel : "Not installed",
                isFound: isInstalled
            ) {
                EmptyView()
            }
            .padding(.horizontal, MSC.Spacing.sm)
            .padding(.vertical, MSC.Spacing.xs)
        }

        if !mods.isEmpty {
            SEBlockHeader(title: "Installed Mods")
            SEBlock {
                ForEach(Array(mods.enumerated()), id: \.element.id) { idx, entry in
                    if idx > 0 { Divider().padding(.leading, MSC.Spacing.md) }
                    JarsTabModRow(entry: entry)
                        .padding(.horizontal, MSC.Spacing.sm)
                        .padding(.vertical, MSC.Spacing.xs)
                }
            }
        }
    }
}

private func moddedServerIsInstalled(cfg: ConfigServer) -> Bool {
    let serverDir = URL(fileURLWithPath: cfg.serverDir, isDirectory: true)
    let fm = FileManager.default
    switch cfg.javaFlavor {
    case .fabric:
        return fm.fileExists(atPath: serverDir.appendingPathComponent("fabric-server-launch.jar").path)
    case .quilt:
        return fm.fileExists(atPath: serverDir.appendingPathComponent("quilt-server-launch.jar").path)
    case .neoforge, .forge:
        return fm.fileExists(atPath: serverDir.appendingPathComponent("run.sh").path)
            || fm.fileExists(atPath: serverDir.appendingPathComponent("libraries").path)
    default:
        return false
    }
}

// MARK: - Paper / Purpur / Pufferfish plugin-server JARs

private func paperJarsSection(cfg: ConfigServer) -> some View {
    let summary      = viewModel.jarSummary(for: cfg)
    let extraEntries = otherPluginEntries()
    let xboxJarLabel = xboxBroadcastJarLabel(for: cfg)
    let serverName   = cfg.javaFlavor.displayName

    // Look up plugin entries for delete
    let geyserEntry    = viewModel.discoveredPlugins.first { $0.jarStem.lowercased().hasPrefix("geyser") }
    let floodgateEntry = viewModel.discoveredPlugins.first { $0.jarStem.lowercased().hasPrefix("floodgate") }

    return VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
        SECallout(
            icon: "info.circle.fill",
            color: .blue,
            text: "Installed plugins and their JARs for this server. Use the Components tab to browse and download updates."
        )

        SEBlockHeader(title: "Installed JARs")
        SEBlock {
            // Server JAR — Update only (no delete)
            SEJarRow(
                icon: "server.rack",
                color: summary.paperFilename != nil ? .blue : .red,
                title: "\(serverName) Server JAR",
                filename: summary.paperFilename ?? "Not found",
                isFound: summary.paperFilename != nil
            ) {
                Button("Update") {
                    Task { await viewModel.updatePaperFromLatestTemplate(for: cfg) }
                }
                .buttonStyle(MSCSecondaryButtonStyle())
            }
            .padding(.horizontal, MSC.Spacing.sm)
            .padding(.vertical, MSC.Spacing.xs)

            // Geyser — Delete when found, nothing when not installed
            if summary.geyserFilename != nil || geyserEntry != nil {
                Divider().padding(.leading, MSC.Spacing.md)
                SEJarRow(
                    icon: "puzzlepiece.fill",
                    color: summary.geyserFilename != nil ? .purple : .secondary,
                    title: "Geyser Plugin",
                    filename: summary.geyserFilename ?? "Not installed",
                    isFound: summary.geyserFilename != nil
                ) {
                    if let entry = geyserEntry {
                        JarsTabDeleteButton(displayName: entry.displayName) {
                            viewModel.removePlugin(jarStem: entry.jarStem)
                        }
                    }
                }
                .padding(.horizontal, MSC.Spacing.sm)
                .padding(.vertical, MSC.Spacing.xs)
            }

            // Floodgate — Delete when found, nothing when not installed
            if summary.floodgateFilename != nil || floodgateEntry != nil {
                Divider().padding(.leading, MSC.Spacing.md)
                SEJarRow(
                    icon: "person.badge.key.fill",
                    color: summary.floodgateFilename != nil ? .orange : .secondary,
                    title: "Floodgate Plugin",
                    filename: summary.floodgateFilename ?? "Not installed",
                    isFound: summary.floodgateFilename != nil
                ) {
                    if let entry = floodgateEntry {
                        JarsTabDeleteButton(displayName: entry.displayName) {
                            viewModel.removePlugin(jarStem: entry.jarStem)
                        }
                    }
                }
                .padding(.horizontal, MSC.Spacing.sm)
                .padding(.vertical, MSC.Spacing.xs)
            }

            if cfg.xboxBroadcastEnabled {
                Divider().padding(.leading, MSC.Spacing.md)
                SEJarRow(
                    icon: "dot.radiowaves.left.and.right",
                    color: .green,
                    title: "Xbox Broadcast",
                    filename: xboxJarLabel ?? "Not configured",
                    isFound: xboxJarLabel != nil
                ) {
                    Button("Update") {
                        viewModel.downloadOrUpdateXboxBroadcastJar()
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                }
                .padding(.horizontal, MSC.Spacing.sm)
                .padding(.vertical, MSC.Spacing.xs)
            }

            ForEach(extraEntries) { entry in
                Divider().padding(.leading, MSC.Spacing.md)
                JarsTabPluginRow(entry: entry)
                    .padding(.horizontal, MSC.Spacing.sm)
                    .padding(.vertical, MSC.Spacing.xs)
            }
        }
    }
}

private func otherPluginEntries() -> [PluginEntry] {
    viewModel.discoveredPlugins.filter { entry in
        let base = entry.jarStem.lowercased()
        return !base.hasPrefix("geyser") && !base.hasPrefix("floodgate")
    }
    .sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
}

private func xboxBroadcastJarLabel(for cfg: ConfigServer) -> String? {
    guard cfg.xboxBroadcastEnabled else { return nil }
    guard let path = viewModel.configManager.config.xboxBroadcastJarPath, !path.isEmpty else { return nil }
    let fm = FileManager.default
    guard fm.fileExists(atPath: path) else { return nil }
    let url = URL(fileURLWithPath: path)
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    if let attrs = try? fm.attributesOfItem(atPath: path),
       let date = attrs[.modificationDate] as? Date {
        return "\(url.lastPathComponent) — \(formatter.string(from: date))"
    }
    return url.lastPathComponent
}

}

// MARK: - Shared delete button

private struct JarsTabDeleteButton: View {
    let displayName: String
    let action: () -> Void

    @State private var showConfirm = false

    var body: some View {
        Button("Delete") { showConfirm = true }
            .buttonStyle(MSCSecondaryButtonStyle())
            .confirmationDialog(
                "Delete \(displayName)?",
                isPresented: $showConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive, action: action)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The JAR file will be permanently removed from the plugins folder.")
            }
    }
}

// MARK: - Per-plugin row (other plugins, link/delete)

private struct JarsTabPluginRow: View {
    @EnvironmentObject var viewModel: AppViewModel
    let entry: PluginEntry

    @State private var isShowingSourcePopover = false
    @State private var showDeleteConfirm = false

    private var filename: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let fm = FileManager.default
        if let cfg = viewModel.selectedServerConfig {
            let url = URL(fileURLWithPath: cfg.serverDir)
                .appendingPathComponent("plugins")
                .appendingPathComponent(entry.filename)
            if let attrs = try? fm.attributesOfItem(atPath: url.path),
               let date = attrs[.modificationDate] as? Date {
                return "\(entry.filename) — \(formatter.string(from: date))"
            }
        }
        return entry.filename
    }

    var body: some View {
        SEJarRow(
            icon: "puzzlepiece.extension.fill",
            color: entry.sourceConfig != nil ? Color.accentColor.opacity(0.85) : .secondary,
            title: entry.displayName,
            filename: filename,
            isFound: true
        ) {
            HStack(spacing: MSC.Spacing.xs) {
                Button("Delete") { showDeleteConfirm = true }
                    .buttonStyle(MSCSecondaryButtonStyle())
                    .confirmationDialog(
                        "Delete \(entry.displayName)?",
                        isPresented: $showDeleteConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Delete", role: .destructive) {
                            viewModel.removePlugin(jarStem: entry.jarStem)
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("The JAR file will be permanently removed from the plugins folder.")
                    }

                Button {
                    isShowingSourcePopover = true
                } label: {
                    Image(systemName: entry.sourceConfig != nil ? "link.badge.plus" : "link")
                }
                .buttonStyle(MSCSecondaryButtonStyle())
                .help(entry.sourceConfig != nil ? "Edit source URL" : "Add source URL for updates")
                .popover(isPresented: $isShowingSourcePopover, arrowEdge: .bottom) {
                    PluginSourcePopover(entry: entry, isPresented: $isShowingSourcePopover)
                        .environmentObject(viewModel)
                }
            }
        }
    }
}

// MARK: - Per-mod row (modded servers)

private struct JarsTabModRow: View {
    @EnvironmentObject var viewModel: AppViewModel
    let entry: ModEntry

    @State private var showDeleteConfirm = false

    private var filename: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let fm = FileManager.default
        if let cfg = viewModel.selectedServerConfig {
            let url = URL(fileURLWithPath: cfg.serverDir)
                .appendingPathComponent("mods")
                .appendingPathComponent(entry.filename)
            if let attrs = try? fm.attributesOfItem(atPath: url.path),
               let date = attrs[.modificationDate] as? Date {
                return "\(entry.filename) — \(formatter.string(from: date))"
            }
        }
        return entry.filename
    }

    var body: some View {
        SEJarRow(
            icon: "puzzlepiece.extension.fill",
            color: .accentColor.opacity(0.85),
            title: entry.displayName,
            filename: filename,
            isFound: true
        ) {
            Button("Delete") { showDeleteConfirm = true }
                .buttonStyle(MSCSecondaryButtonStyle())
                .confirmationDialog(
                    "Delete \(entry.displayName)?",
                    isPresented: $showDeleteConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        viewModel.removeMod(jarStem: entry.jarStem)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("The mod JAR will be permanently removed from the mods folder.")
                }
        }
    }
}

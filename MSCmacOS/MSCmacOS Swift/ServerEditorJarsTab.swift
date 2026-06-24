import SwiftUI

extension ServerEditorView {
// MARK: - JARS TAB (Java only)

var jarsTab: some View {
    VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
        if mode == .new || editingConfigServer == nil {
            SEUnavailableCard(
                icon: "shippingbox.fill",
                title: "Save first to manage JARs",
                message: "Configure Paper, Geyser, and Floodgate after this server has been created. Save, then reopen Edit Server."
            )
        } else if let cfg = editingConfigServer {
            let summary = viewModel.jarSummary(for: cfg)
            let extraEntries = otherPluginEntries()
            let xboxJarLabel = xboxBroadcastJarLabel(for: cfg)

            SECallout(
                icon: "info.circle.fill",
                color: .blue,
                text: "Update actions copy the latest template into this server's plugins/ folder, replacing older versions. Download templates in Preferences → JAR Library."
            )

            SEBlockHeader(title: "Installed JARs")
            SEBlock {
                SEJarRow(
                    icon: "server.rack",
                    color: .blue,
                    title: "Paper Server JAR",
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

                Divider().padding(.leading, MSC.Spacing.md)

                SEJarRow(
                    icon: "puzzlepiece.fill",
                    color: .purple,
                    title: "Geyser Plugin",
                    filename: summary.geyserFilename ?? "Not found",
                    isFound: summary.geyserFilename != nil
                ) {
                    Button("Update") {
                        Task { await viewModel.updateGeyserFromTemplate(for: cfg) }
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                }
                .padding(.horizontal, MSC.Spacing.sm)
                .padding(.vertical, MSC.Spacing.xs)

                Divider().padding(.leading, MSC.Spacing.md)

                SEJarRow(
                    icon: "person.badge.key.fill",
                    color: .orange,
                    title: "Floodgate Plugin",
                    filename: summary.floodgateFilename ?? "Not found",
                    isFound: summary.floodgateFilename != nil
                ) {
                    Button("Update") {
                        Task { await viewModel.updateFloodgateFromTemplate(for: cfg) }
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                }
                .padding(.horizontal, MSC.Spacing.sm)
                .padding(.vertical, MSC.Spacing.xs)

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

// MARK: - Per-plugin row with Update / Link buttons

private struct JarsTabPluginRow: View {
    @EnvironmentObject var viewModel: AppViewModel
    let entry: PluginEntry

    @State private var isShowingSourcePopover = false
    @State private var isShowingDownloadConfirm = false

    private var isDownloading: Bool { viewModel.downloadingPlugins.contains(entry.jarStem) }

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
                if entry.sourceConfig != nil {
                    Button {
                        isShowingDownloadConfirm = true
                    } label: {
                        if isDownloading {
                            ProgressView().controlSize(.mini)
                        } else {
                            Text("Update")
                        }
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                    .disabled(isDownloading)
                    .confirmationDialog(
                        "Download latest version of \(entry.displayName)?",
                        isPresented: $isShowingDownloadConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Download Latest") {
                            viewModel.downloadPluginWithSourceCheck(entry: entry)
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will replace the current JAR.")
                    }
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

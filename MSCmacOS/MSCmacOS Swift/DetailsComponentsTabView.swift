//
//  DetailsComponentsTabView.swift
//  MinecraftServerController
//
//  Unified component list — Paper, plugins, and broadcast in one clean block.
//  Each component is a row: toggle/spacer · icon · name+version · status chip · actions.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Main View

struct DetailsComponentsTabView: View {
    @EnvironmentObject var viewModel: AppViewModel

    @State private var showingModrinthBrowser = false
    @State private var isShowingModpackImporter = false
    @State private var isShowingUpdateAllSheet = false
    @State private var isShowingClientExportSheet = false

    private var isBedrock: Bool {
        guard let s = viewModel.selectedServer else { return false }
        return viewModel.configServer(for: s)?.isBedrock ?? false
    }

    private var isModded: Bool {
        guard let s = viewModel.selectedServer, let cfg = viewModel.configServer(for: s) else { return false }
        return cfg.isModded
    }

    private var selectedConfig: ConfigServer? {
        guard let s = viewModel.selectedServer else { return nil }
        return viewModel.configServer(for: s)
    }

    /// True for Java servers that accept add-ons (everything except Vanilla).
    private var addOnSupported: Bool {
        guard let s = viewModel.selectedServer, let cfg = viewModel.configServer(for: s) else { return false }
        return cfg.isJava && cfg.addOnKind != nil
    }

    /// "Browse mods" / "Browse plugins" depending on the server flavor.
    private var addOnBrowseLabel: String {
        guard let s = viewModel.selectedServer, let cfg = viewModel.configServer(for: s),
              let kind = cfg.addOnKind else { return "Browse" }
        return "Browse \(kind.displayName.lowercased())"
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: MSC.Spacing.md) {
                if isBedrock {
                    bedrockToolbar
                    BedrockRuntimeSectionCard()
                    bedrockBroadcastCard
                } else {
                    javaToolbar
                    javaComponentList
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, MSC.Spacing.sm)
        }
        .sheet(isPresented: $showingModrinthBrowser) {
            if let s = viewModel.selectedServer, let cfg = viewModel.configServer(for: s) {
                ModrinthBrowserView(serverConfig: cfg)
                    .environmentObject(viewModel)
            }
        }
        .sheet(isPresented: $isShowingUpdateAllSheet) {
            if let cfg = selectedConfig {
                AddonUpdateSheet(cfg: cfg, isPresented: $isShowingUpdateAllSheet)
                    .environmentObject(viewModel)
            }
        }
        .sheet(isPresented: $isShowingClientExportSheet) {
            if let cfg = selectedConfig {
                ClientExportSheet(isPresented: $isShowingClientExportSheet, cfg: cfg)
                    .environmentObject(viewModel)
            }
        }
        .fileImporter(
            isPresented: $isShowingModpackImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result,
                  let url = urls.first,
                  url.pathExtension.lowercased() == "mrpack",
                  let cfg = selectedConfig else { return }
            Task {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                await viewModel.importModpack(from: url, for: cfg)
            }
        }
    }

    // MARK: - Java toolbar

    private var javaToolbar: some View {
        HStack(spacing: MSC.Spacing.sm) {
            Text("Components")
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(MSC.Colors.tertiary)

            if let err = viewModel.componentsOnlineErrorMessage, !err.isEmpty {
                Divider().frame(height: 12).opacity(0.5)
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.warning)
                    .lineLimit(1)
            }

            Spacer()

            if isModded {
                Button {
                    isShowingModpackImporter = true
                } label: {
                    Label("Import Modpack", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(MSCSecondaryButtonStyle())
                .controlSize(.mini)
            }

            if addOnSupported {
                Button {
                    showingModrinthBrowser = true
                } label: {
                    Label(addOnBrowseLabel, systemImage: "magnifyingglass")
                }
                .buttonStyle(MSCSecondaryButtonStyle())
                .controlSize(.mini)
            }

            Button {
                viewModel.refreshComponentsSnapshotLocalAndTemplate(clearOnline: false)
                viewModel.checkComponentsOnline()
            } label: {
                if viewModel.isCheckingComponentsOnline {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text("Checking\u{2026}")
                    }
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(MSCSecondaryButtonStyle())
            .controlSize(.mini)
            .disabled(viewModel.isCheckingComponentsOnline)
        }
    }

    // MARK: - Bedrock toolbar

    private var bedrockToolbar: some View {
        HStack {
            Text("Components")
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(MSC.Colors.tertiary)
            Spacer()
        }
    }

    // MARK: - Java component list

    private var showCrossplay: Bool {
        guard let cfg = selectedConfig else { return false }
        return cfg.isJava && !isModded && cfg.javaFlavor != .vanilla
    }

    private func componentSectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(MSC.Colors.tertiary)
    }

    private var javaComponentList: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {

            // ── SERVER ────────────────────────────────────────────
            componentSectionLabel("Server")
            SEBlock {
                if isModded {
                    ModdedLoaderRow(cfg: selectedConfig)
                } else {
                    ServerJarListRow(cfg: selectedConfig, onReveal: revealPaperJarInFinder)
                }
            }

            // ── MODS / PLUGINS ────────────────────────────────────
            if isModded || addOnSupported {
                HStack(spacing: MSC.Spacing.sm) {
                    componentSectionLabel(isModded ? "Mods" : "Plugins")
                    Spacer()
                    let installedCount = isModded ? viewModel.discoveredMods.count : viewModel.discoveredPlugins.count
                    if installedCount > 0 {
                        Button {
                            isShowingClientExportSheet = true
                        } label: {
                            Label("Export for clients", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(MSCSecondaryButtonStyle())
                        .controlSize(.mini)
                        Button {
                            if let cfg = selectedConfig { viewModel.resolveAddonUpdates(for: cfg) }
                            isShowingUpdateAllSheet = true
                        } label: {
                            Label("Update All", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(MSCSecondaryButtonStyle())
                        .controlSize(.mini)
                    }
                }
                SEBlock {
                    if isModded {
                        modRows
                        rowDivider
                        modFooter
                    } else {
                        pluginRows
                        rowDivider
                        pluginFooter
                    }
                }
            }

            // ── CROSSPLAY ─────────────────────────────────────────
            if showCrossplay {
                componentSectionLabel("Crossplay")
                SEBlock {
                    BroadcastListRow()
                }
            }
        }
        .task(id: selectedConfig?.id) {
            if isModded { viewModel.refreshDiscoveredMods() }
            else { viewModel.refreshDiscoveredPlugins() }
            // Resolve-once-with-cache: drives per-row update badges. No-op when current.
            if let cfg = selectedConfig { viewModel.resolveAddonUpdates(for: cfg) }
        }
    }

    private var pluginFooter: some View {
        HStack(spacing: MSC.Spacing.sm) {
            Button { revealPluginsFolder() } label: {
                Label("Reveal plugins folder", systemImage: "folder")
            }
            .buttonStyle(MSCSecondaryButtonStyle())
            .controlSize(.mini)
            Spacer()
            Button { viewModel.addPluginFromFilePicker() } label: {
                Label("Add Plugin", systemImage: "plus")
            }
            .buttonStyle(MSCSecondaryButtonStyle())
            .controlSize(.mini)
        }
        .padding(.horizontal, MSC.Spacing.md)
        .padding(.vertical, MSC.Spacing.sm)
    }

    private var rowDivider: some View {
        Divider()
            .padding(.leading, 52)
            .opacity(0.55)
    }

    // MARK: - Plugin rows (inside the block)

    @ViewBuilder
    private var pluginRows: some View {
        if viewModel.discoveredPlugins.isEmpty {
            HStack(spacing: MSC.Spacing.sm) {
                Spacer().frame(width: 52)
                Text("No plugins installed.")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.tertiary)
                Spacer()
            }
            .padding(.horizontal, MSC.Spacing.md)
            .padding(.vertical, MSC.Spacing.sm + 1)
        } else {
            ForEach(Array(viewModel.discoveredPlugins.enumerated()), id: \.element.id) { idx, entry in
                if idx > 0 {
                    Divider()
                        .padding(.leading, 52)
                        .opacity(0.55)
                }
                PluginListRow(entry: entry)
            }
        }
    }

    private func revealPluginsFolder() {
        guard let cfg = viewModel.selectedServerConfig else { return }
        let pluginsDir = URL(fileURLWithPath: cfg.serverDir, isDirectory: true)
            .appendingPathComponent("plugins", isDirectory: true)
        try? FileManager.default.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
        viewModel.revealInFinder(url: pluginsDir)
    }

    // MARK: - Mod rows (modded servers)

    @ViewBuilder
    private var modRows: some View {
        if viewModel.discoveredMods.isEmpty {
            HStack(spacing: MSC.Spacing.sm) {
                Spacer().frame(width: 52)
                Text("No mods installed.")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.tertiary)
                Spacer()
            }
            .padding(.horizontal, MSC.Spacing.md)
            .padding(.vertical, MSC.Spacing.sm + 1)
        } else {
            ForEach(Array(viewModel.discoveredMods.enumerated()), id: \.element.id) { idx, entry in
                if idx > 0 {
                    Divider()
                        .padding(.leading, 52)
                        .opacity(0.55)
                }
                ModListRow(entry: entry)
            }
        }
    }

    private var modFooter: some View {
        HStack(spacing: MSC.Spacing.sm) {
            Button { revealModsFolder() } label: {
                Label("Reveal mods folder", systemImage: "folder")
            }
            .buttonStyle(MSCSecondaryButtonStyle())
            .controlSize(.mini)
            Spacer()
            Button { viewModel.addModFromFilePicker() } label: {
                Label("Add Mod", systemImage: "plus")
            }
            .buttonStyle(MSCSecondaryButtonStyle())
            .controlSize(.mini)
        }
        .padding(.horizontal, MSC.Spacing.md)
        .padding(.vertical, MSC.Spacing.sm)
    }

    private func revealModsFolder() {
        guard let cfg = selectedConfig else { return }
        let modsDir = URL(fileURLWithPath: cfg.serverDir, isDirectory: true)
            .appendingPathComponent("mods", isDirectory: true)
        try? FileManager.default.createDirectory(at: modsDir, withIntermediateDirectories: true)
        viewModel.revealInFinder(url: modsDir)
    }

    // MARK: - Bedrock broadcast card (unchanged)

    @ViewBuilder private var bedrockBroadcastCard: some View {
        SEBlock {
            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                HStack(spacing: MSC.Spacing.sm) {
                    Label("MCXboxBroadcast Standalone", systemImage: "antenna.radiowaves.left.and.right")
                        .font(MSC.Typography.cardTitle)
                        .foregroundStyle(.primary)
                    Spacer()
                    MSCStatusDot(
                        color: viewModel.isBedrockBroadcastRunning ? MSC.Colors.success : MSC.Colors.neutral,
                        label: viewModel.isBedrockBroadcastRunning ? "Running" : "Stopped"
                    )
                }

                HStack {
                    Text("JAR").font(MSC.Typography.caption).foregroundStyle(MSC.Colors.tertiary).frame(width: 44, alignment: .leading)
                    Text(viewModel.configManager.config.xboxBroadcastJarPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Not downloaded")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if let server = viewModel.selectedServer,
                   let cfg = viewModel.configServer(for: server) {
                    let port = viewModel.broadcastPortForConfig(for: cfg) ?? 19132
                    let transferHost = viewModel.previewBroadcastHost(for: cfg, mode: cfg.xboxBroadcastIPMode)
                    HStack {
                        Text("Transfers to").font(MSC.Typography.caption).foregroundStyle(MSC.Colors.tertiary).frame(width: 72, alignment: .leading)
                        Text(verbatim: "\(transferHost):\(port)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                Divider().opacity(0.5)

                Text("Broadcasts your BDS server over Xbox Live — PS5, Switch, Xbox, mobile, and Windows players can join via the Friends tab. Enable auto-start in the sidebar to have this container start and stop with your server.")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.caption)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: MSC.Spacing.sm) {
                    Button("Download JAR") { viewModel.downloadBedrockBroadcastJar() }
                    Button("Open Data Folder") {
                        if let server = viewModel.selectedServer,
                           let cfg = viewModel.configServer(for: server) {
                            let url = BedrockBroadcastManager.dataDirectoryURL(for: cfg)
                            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                .buttonStyle(MSCSecondaryButtonStyle())
            }
            .padding(MSC.Spacing.md)
        }
    }
}

// MARK: - Server JAR List Row

private struct ServerJarListRow: View {
    @EnvironmentObject var viewModel: AppViewModel
    let cfg: ConfigServer?
    let onReveal: () -> Void

    @State private var isShowingVersionPicker = false
    @State private var availableVersions: [ServerVersionEntry] = []
    @State private var pickerSelectedEntry: ServerVersionEntry? = nil
    @State private var pickerDidPick: Bool = false

    var body: some View {
        HStack(spacing: MSC.Spacing.sm) {
            // Non-interactive "always on" indicator — core JAR can't be disabled
            Toggle("", isOn: .constant(true))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .frame(width: 32)
                .allowsHitTesting(false)
                .saturation(0)
                .opacity(0.28)

            ZStack {
                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(cfg?.javaFlavor.displayName ?? "Server JAR")
                        .font(.system(size: 12.5, weight: .semibold))
                    componentBadge("Server JAR", color: .accentColor)
                }
                Text(viewModel.componentsSnapshot.paper.local ?? "Not installed")
                    .font(.system(size: 10.5))
                    .foregroundStyle(viewModel.componentsSnapshot.paper.local == nil ? MSC.Colors.error : MSC.Colors.caption)
            }

            Spacer()

            ComponentStatusPill(
                local: viewModel.componentsSnapshot.paper.local,
                template: nil,
                online: viewModel.componentsSnapshot.paper.online
            )

            if viewModel.isDownloadingJar {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("Downloading\u{2026}")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    availableVersions = []
                    pickerSelectedEntry = nil
                    pickerDidPick = false
                    isShowingVersionPicker = true
                    Task {
                        if let cfg {
                            availableVersions = (try? await ServerJarProvider.listVersions(for: cfg.javaFlavor)) ?? []
                        }
                    }
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.accentColor.opacity(0.65))
                }
                .buttonStyle(MSCSecondaryButtonStyle())
                .controlSize(.mini)
                .disabled(viewModel.isServerRunning)
            }
        }
        .padding(.horizontal, MSC.Spacing.md)
        .padding(.vertical, MSC.Spacing.sm + 1)
        .sheet(isPresented: $isShowingVersionPicker) {
            VersionPickerSheet(
                versions: availableVersions,
                selectedEntry: Binding(
                    get: { pickerSelectedEntry },
                    set: { pickerSelectedEntry = $0; pickerDidPick = true }
                ),
                isPresented: $isShowingVersionPicker
            )
        }
        .onChange(of: isShowingVersionPicker) { showing in
            if !showing {
                if pickerDidPick, let cfg {
                    viewModel.downloadAndApplyJarVersion(pickerSelectedEntry, for: cfg)
                }
                availableVersions = []
                pickerSelectedEntry = nil
                pickerDidPick = false
            }
        }
    }
}

// MARK: - Plugin List Row

private struct PluginListRow: View {
    @EnvironmentObject var viewModel: AppViewModel
    let entry: PluginEntry

    @State private var isShowingSourcePopover = false
    @State private var isShowingDownloadConfirm = false

    private var isDownloading: Bool { viewModel.downloadingPlugins.contains(entry.jarStem) }

    private var hasUpdate: Bool {
        guard let online = entry.onlineVersion, !online.isEmpty, online != "(direct)" else { return false }
        if let local = entry.parsedVersion ?? entry.localVersion { return online != local }
        return false
    }

    private var localVersion: String? { entry.parsedVersion ?? entry.localVersion }

    private var canDownload: Bool {
        switch entry.tier {
        case .managed:     return true
        case .userSourced: return entry.sourceConfig != nil
        case .unmanaged:   return false
        }
    }

    /// The resolver's plan entry for this plugin, if any. The hash/Modrinth path is
    /// preferred over the legacy source-URL updater when it has something to offer.
    ///
    /// Managed plugins (Geyser/Floodgate) are excluded: MSC installs them from GeyserMC's
    /// CDN (download.geysermc.org), not Modrinth, so hash-matching is unreliable and would
    /// make the two vendor-siblings behave differently. They keep their dedicated updater.
    private var resolverItem: AddonUpdateItem? {
        guard entry.tier != .managed else { return nil }
        return viewModel.addonUpdatePlan.first { $0.jarStem == entry.jarStem }
    }
    private var hasResolverUpdate: Bool { resolverItem?.bucket == .updateAvailable }

    /// True when the resolver recognizes this plugin (linked to Modrinth). When it does,
    /// the resolver owns the update affordance — we don't also show the legacy download
    /// button, so up-to-date managed plugins show no redundant button.
    private var resolverOwnsCurrent: Bool {
        guard let b = resolverItem?.bucket else { return false }
        return b != .unlinked
    }

    /// Installed version to show: prefer the resolver's (consistent scheme with the
    /// available build), fall back to the filename-parsed version.
    private var displayedCurrentVersion: String? {
        resolverItem?.currentVersion ?? localVersion
    }

    var body: some View {
        HStack(spacing: MSC.Spacing.sm) {
            // Enable/Disable toggle
            Toggle("", isOn: Binding(
                get: { entry.isEnabled },
                set: { _ in viewModel.togglePlugin(jarStem: entry.jarStem) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .frame(width: 32)

            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            // Name + badges + version
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.displayName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(entry.isEnabled ? Color.primary : Color.secondary)

                    switch entry.tier {
                    case .managed:
                        PluginTierBadge(label: "Managed", icon: "sparkles", color: MSC.Colors.info)
                    case .userSourced:
                        if let source = entry.sourceConfig {
                            PluginTierBadge(
                                label: source.type.displayName,
                                icon: source.type.symbolName,
                                color: sourceBadgeColor(source.type)
                            )
                        }
                    case .unmanaged:
                        EmptyView()
                    }
                }

                HStack(spacing: 4) {
                    if let local = displayedCurrentVersion {
                        Text(local)
                            .font(.system(size: 10.5))
                            .foregroundStyle(MSC.Colors.caption)
                    }
                    if hasResolverUpdate, let online = resolverItem?.availableVersion {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(MSC.Colors.tertiary)
                        Text(online)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(MSC.Colors.warning)
                    } else if hasUpdate, let online = entry.onlineVersion, online != "(direct)" {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(MSC.Colors.tertiary)
                        Text(online)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(MSC.Colors.warning)
                    }
                }
            }

            Spacer()

            // Status chip (only for tracked plugins with online data)
            if entry.isCheckingOnline {
                ProgressView().controlSize(.mini)
            } else if entry.tier != .unmanaged, entry.onlineVersion != nil {
                ComponentStatusPill(
                    local: localVersion,
                    template: entry.templateVersion,
                    online: entry.onlineVersion
                )
            }

            // Action buttons
            HStack(spacing: 4) {
                if hasResolverUpdate {
                    // Modrinth/hash-detected update — unified resolver path.
                    AddonRowUpdateControl(jarStem: entry.jarStem, cfg: viewModel.selectedServerConfig)
                } else if !resolverOwnsCurrent && canDownload {
                    // Legacy source-URL updater — only for plugins the resolver can't link
                    // (GitHub/Hangar/direct sources not on Modrinth).
                    Button { isShowingDownloadConfirm = true } label: {
                        if isDownloading {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(hasUpdate ? MSC.Colors.warning : Color.accentColor.opacity(0.65))
                        }
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                    .controlSize(.mini)
                    .disabled(
                        viewModel.isServerRunning || isDownloading ||
                        (entry.tier == .userSourced && entry.onlineDownloadURL == nil && !entry.isCheckingOnline)
                    )
                    .confirmationDialog(
                        "Download latest version of \(entry.displayName)?",
                        isPresented: $isShowingDownloadConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Download Latest") { triggerDownload() }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        if let v = entry.onlineVersion {
                            Text("This will download version \(v) and replace the current JAR.")
                        } else {
                            Text("This will download and replace the current JAR.")
                        }
                    }
                }

                // Legacy "attach a source URL" — only for plugins the resolver couldn't
                // link to Modrinth. Once a plugin is resolver-owned, its update source is
                // already known, so the manual link button would be redundant.
                if entry.tier != .managed && !resolverOwnsCurrent {
                    Button { isShowingSourcePopover = true } label: {
                        Image(systemName: entry.sourceConfig != nil ? "link.badge.plus" : "link")
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                    .controlSize(.mini)
                    .popover(isPresented: $isShowingSourcePopover, arrowEdge: .bottom) {
                        PluginSourcePopover(entry: entry, isPresented: $isShowingSourcePopover)
                            .environmentObject(viewModel)
                    }
                }
            }
        }
        .padding(.horizontal, MSC.Spacing.md)
        .padding(.vertical, MSC.Spacing.sm + 1)
        .opacity(entry.isEnabled ? 1.0 : 0.42)
    }

    private var iconName: String {
        switch entry.tier {
        case .managed:     return entry.jarStem.lowercased().contains("geyser") ? "water.waves" : "lock.open.fill"
        case .userSourced: return "puzzlepiece.extension"
        case .unmanaged:   return "puzzlepiece"
        }
    }

    private var iconColor: Color {
        switch entry.tier {
        case .managed:     return entry.jarStem.lowercased().contains("geyser") ? .blue : .orange
        case .userSourced: return .secondary
        case .unmanaged:   return MSC.Colors.tertiary
        }
    }

    private func sourceBadgeColor(_ type: PluginSourceType) -> Color {
        switch type {
        case .github:   return Color(red: 0.55, green: 0.58, blue: 0.62)
        case .modrinth: return Color(red: 0.11, green: 0.85, blue: 0.42)
        case .hangar:   return MSC.Colors.info
        case .direct:   return MSC.Colors.tertiary
        }
    }

    private func triggerDownload() {
        switch entry.tier {
        case .managed:
            if entry.jarStem.lowercased().contains("geyser") {
                viewModel.downloadAndApplyLatestGeyser()
            } else if entry.jarStem.lowercased().contains("floodgate") {
                viewModel.downloadAndApplyLatestFloodgate()
            }
        case .userSourced:
            viewModel.downloadLatestForPlugin(entry: entry)
        case .unmanaged:
            break
        }
    }
}

// MARK: - Broadcast List Row

private struct BroadcastListRow: View {
    @EnvironmentObject var viewModel: AppViewModel

    private var hasUpdate: Bool {
        guard let online = viewModel.componentsSnapshot.broadcast.online,
              let local  = viewModel.componentsSnapshot.broadcast.local,
              !online.isEmpty else { return false }
        return online != local
    }

    var body: some View {
        HStack(spacing: MSC.Spacing.sm) {
            // Enable/Disable toggle — mirrors Edit Server › Broadcast › Enable
            Toggle("", isOn: $viewModel.selectedServerXboxBroadcastEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .frame(width: 32)

            ZStack {
                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                    .fill(Color.purple.opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.purple)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("MCXboxBroadcast")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(viewModel.selectedServerXboxBroadcastEnabled ? Color.primary : Color.secondary)
                    componentBadge("Broadcast", color: .purple)
                }
                HStack(spacing: 4) {
                    if let local = viewModel.componentsSnapshot.broadcast.local {
                        Text(local)
                            .font(.system(size: 10.5))
                            .foregroundStyle(MSC.Colors.caption)
                    }
                    if hasUpdate, let online = viewModel.componentsSnapshot.broadcast.online {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(MSC.Colors.tertiary)
                        Text(online)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(MSC.Colors.warning)
                    }
                }
            }

            Spacer()

            ComponentStatusPill(
                local: viewModel.componentsSnapshot.broadcast.local,
                template: nil,
                online: viewModel.componentsSnapshot.broadcast.online
            )

            Button { viewModel.downloadOrUpdateXboxBroadcastJar() } label: {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(hasUpdate ? MSC.Colors.warning : Color.accentColor.opacity(0.65))
            }
            .buttonStyle(MSCSecondaryButtonStyle())
            .controlSize(.mini)
            .disabled(viewModel.isServerRunning)
        }
        .padding(.horizontal, MSC.Spacing.md)
        .padding(.vertical, MSC.Spacing.sm + 1)
        .opacity(viewModel.selectedServerXboxBroadcastEnabled ? 1.0 : 0.42)
    }
}

// MARK: - Modded Loader Row

private struct ModdedLoaderRow: View {
    @EnvironmentObject var viewModel: AppViewModel
    let cfg: ConfigServer?

    @State private var isShowingVersionPicker = false
    @State private var availableVersions: [ServerVersionEntry] = []
    @State private var pickerSelectedEntry: ServerVersionEntry? = nil
    @State private var pickerDidPick: Bool = false

    var body: some View {
        HStack(spacing: MSC.Spacing.sm) {
            Toggle("", isOn: .constant(true))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .frame(width: 32)
                .allowsHitTesting(false)
                .saturation(0)
                .opacity(0.28)

            ZStack {
                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(cfg?.javaFlavor.displayName ?? "Loader")
                        .font(.system(size: 12.5, weight: .semibold))
                    componentBadge("Loader", color: .accentColor)
                }
                Text(versionSubtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(MSC.Colors.caption)
            }

            Spacer()

            if viewModel.isDownloadingJar {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("Installing\u{2026}")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    availableVersions = []
                    pickerSelectedEntry = nil
                    pickerDidPick = false
                    isShowingVersionPicker = true
                    Task {
                        if let cfg {
                            availableVersions = (try? await ServerJarProvider.listVersions(for: cfg.javaFlavor)) ?? []
                        }
                    }
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.accentColor.opacity(0.65))
                }
                .buttonStyle(MSCSecondaryButtonStyle())
                .controlSize(.mini)
                .disabled(viewModel.isServerRunning)
            }
        }
        .padding(.horizontal, MSC.Spacing.md)
        .padding(.vertical, MSC.Spacing.sm + 1)
        .sheet(isPresented: $isShowingVersionPicker) {
            VersionPickerSheet(
                versions: availableVersions,
                selectedEntry: Binding(
                    get: { pickerSelectedEntry },
                    set: { pickerSelectedEntry = $0; pickerDidPick = true }
                ),
                isPresented: $isShowingVersionPicker
            )
        }
        .onChange(of: isShowingVersionPicker) { showing in
            if !showing {
                if pickerDidPick, let cfg {
                    viewModel.upgradeModdedLoader(pickerSelectedEntry, for: cfg)
                }
                availableVersions = []
                pickerSelectedEntry = nil
                pickerDidPick = false
            }
        }
    }

    private var iconName: String { cfg?.javaFlavor.iconName ?? "puzzlepiece.fill" }

    private var versionSubtitle: String {
        guard let cfg else { return "" }
        var parts: [String] = []
        if let mc = cfg.minecraftVersion { parts.append("MC \(mc)") }
        if let lv = cfg.loaderVersion    { parts.append("Loader \(lv)") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Mod List Row

private struct ModListRow: View {
    @EnvironmentObject var viewModel: AppViewModel
    let entry: ModEntry

    @State private var isShowingRemoveConfirm = false

    private var resolverItem: AddonUpdateItem? {
        viewModel.addonUpdatePlan.first { $0.jarStem == entry.jarStem }
    }
    /// Manifest version, falling back to the resolver's installed version when the
    /// manifest had none.
    private var displayedVersion: String? { entry.version ?? resolverItem?.currentVersion }

    var body: some View {
        HStack(spacing: MSC.Spacing.sm) {
            // Enable/Disable toggle
            Toggle("", isOn: Binding(
                get: { entry.isEnabled },
                set: { _ in viewModel.toggleMod(jarStem: entry.jarStem) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .frame(width: 32)

            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                    .fill(Color.purple.opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.purple)
            }

            // Name + version
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(entry.isEnabled ? Color.primary : Color.secondary)

                if let ver = displayedVersion {
                    Text(ver)
                        .font(.system(size: 10.5))
                        .foregroundStyle(MSC.Colors.caption)
                } else if let mid = entry.modId {
                    Text(mid)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(MSC.Colors.tertiary)
                }
            }

            Spacer()

            // Update affordance (only shown when Modrinth has a newer compatible build)
            AddonRowUpdateControl(jarStem: entry.jarStem, cfg: viewModel.selectedServerConfig)

            // Remove button
            Button { isShowingRemoveConfirm = true } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundStyle(MSC.Colors.error.opacity(0.7))
            }
            .buttonStyle(MSCSecondaryButtonStyle())
            .controlSize(.mini)
            .disabled(viewModel.isServerRunning)
            .confirmationDialog(
                "Remove \(entry.displayName)?",
                isPresented: $isShowingRemoveConfirm,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    viewModel.removeMod(jarStem: entry.jarStem)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The mod JAR will be permanently deleted from the mods folder.")
            }
        }
        .padding(.horizontal, MSC.Spacing.md)
        .padding(.vertical, MSC.Spacing.sm + 1)
        .opacity(entry.isEnabled ? 1.0 : 0.42)
    }
}

// MARK: - Shared badge helper

private func componentBadge(_ label: String, color: Color) -> some View {
    Text(label)
        .font(.system(size: 9.5, weight: .medium))
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(color.opacity(0.22), lineWidth: 0.5)
                )
        )
}

// MARK: - Shared per-row update control (resolver-driven)

/// Renders the inline "update available" affordance for a plugin/mod row by consulting
/// `viewModel.addonUpdatePlan`. Shows nothing unless the item has a Modrinth update.
/// Tapping offers Update / View on Modrinth / Cancel.
private struct AddonRowUpdateControl: View {
    @EnvironmentObject var viewModel: AppViewModel
    let jarStem: String
    let cfg: ConfigServer?

    @State private var isShowingConfirm = false
    @State private var detailHit: ModrinthSearchHit? = nil

    private var item: AddonUpdateItem? {
        viewModel.addonUpdatePlan.first { $0.jarStem == jarStem }
    }
    private var projectType: String { (cfg?.javaFlavor.addOnKind == .mod) ? "mod" : "plugin" }

    var body: some View {
        if viewModel.updatingAddonStems.contains(jarStem) {
            ProgressView().controlSize(.mini)
        } else if let item, item.bucket == .updateAvailable {
            Button { isShowingConfirm = true } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(MSC.Colors.warning)
            }
            .buttonStyle(MSCSecondaryButtonStyle())
            .controlSize(.mini)
            .disabled(viewModel.isServerRunning)
            .confirmationDialog(
                "Update \(item.displayName)?",
                isPresented: $isShowingConfirm,
                titleVisibility: .visible
            ) {
                Button("Update to \(item.availableVersion ?? "latest")") {
                    if let cfg { viewModel.updateAddon(item, for: cfg) }
                }
                Button("View on Modrinth") { detailHit = item.modrinthHit(projectType: projectType) }
                Button("Delete \(item.displayName)", role: .destructive) {
                    if cfg?.javaFlavor.addOnKind == .mod {
                        viewModel.removeMod(jarStem: jarStem)
                    } else {
                        viewModel.removePlugin(jarStem: jarStem)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                let base = "This will replace \(item.currentVersion ?? "the current version") with \(item.availableVersion ?? "the latest build")."
                if let cfg, cfg.packManaged {
                    let label: String = {
                        var parts: [String] = []
                        if let n = cfg.packName { parts.append(n) }
                        if let v = cfg.packVersion { parts.append(v) }
                        return parts.isEmpty ? "a modpack" : parts.joined(separator: " ")
                    }()
                    Text("\(base)\n\nThis server was installed from \(label). Updating individual mods may break the pack's tested version set.")
                } else {
                    Text(base)
                }
            }
            .sheet(item: $detailHit) { hit in
                if let cfg {
                    NavigationStack {
                        ModrinthProjectDetailView(hit: hit, serverConfig: cfg)
                            .environmentObject(viewModel)
                            .frame(width: 640, height: 680)
                    }
                }
            }
        }
    }
}

// MARK: - Plugin Source Popover (unchanged)

struct PluginSourcePopover: View {
    @EnvironmentObject var viewModel: AppViewModel
    let entry: PluginEntry
    @Binding var isPresented: Bool

    @State private var urlText: String = ""
    @State private var detectedType: PluginSourceType? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
            Text("Source URL")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(MSC.Colors.tertiary)
                .textCase(.uppercase)

            TextField("https://github.com/owner/repo", text: $urlText)
                .font(.system(size: 11, design: .monospaced))
                .textFieldStyle(.plain)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                        .fill(Color.black.opacity(0.3))
                        .overlay(
                            RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                        )
                )
                .onChange(of: urlText) { _, new in
                    detectedType = PluginSourceDetector.detect(url: new)
                }

            if let type = detectedType {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(MSC.Colors.success)
                    Text("Detected as \(type.displayName)")
                        .font(MSC.Typography.caption)
                        .foregroundStyle(MSC.Colors.success)
                }
            } else if !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(MSC.Colors.tertiary)
                    Text("Unrecognised URL — will use as direct download")
                        .font(MSC.Typography.caption)
                        .foregroundStyle(MSC.Colors.tertiary)
                }
            }

            Divider().opacity(0.5)

            HStack(spacing: MSC.Spacing.sm) {
                if entry.sourceConfig != nil {
                    Button("Remove Source") {
                        viewModel.removePluginSource(jarStem: entry.jarStem)
                        isPresented = false
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                    .controlSize(.mini)
                    .foregroundStyle(MSC.Colors.error)
                }

                Spacer()

                Button("Cancel") { isPresented = false }
                    .buttonStyle(MSCSecondaryButtonStyle())
                    .controlSize(.mini)

                Button("Confirm") {
                    let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { isPresented = false; return }
                    let type = PluginSourceDetector.detect(url: trimmed) ?? .direct
                    viewModel.setPluginSource(jarStem: entry.jarStem, url: trimmed, type: type)
                    isPresented = false
                }
                .buttonStyle(MSCPrimaryButtonStyle())
                .controlSize(.mini)
                .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(MSC.Spacing.md)
        .frame(width: 320)
        .onAppear {
            urlText = entry.sourceConfig?.url ?? ""
            detectedType = entry.sourceConfig.map { PluginSourceDetector.detect(url: $0.url) } ?? nil
        }
    }
}

// MARK: - Plugin Tier Badge (unchanged)

private struct PluginTierBadge: View {
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        Label(label, systemImage: icon)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, MSC.Spacing.xs)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(color.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(color.opacity(0.22), lineWidth: 0.5)
                    )
            )
    }
}

// MARK: - Component Status Pill (unchanged)

private struct ComponentStatusPill: View {
    let local: String?
    let template: String?
    let online: String?

    var body: some View {
        let status = ComponentStatus.derive(local: local, template: template, online: online)
        Label(status.label, systemImage: status.symbol)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(status.color)
            .padding(.horizontal, MSC.Spacing.sm)
            .padding(.vertical, MSC.Spacing.xxs + 1)
            .background(Capsule().fill(status.color.opacity(0.12)))
            .overlay(Capsule().stroke(status.color.opacity(0.25), lineWidth: 0.75))
    }
}

// MARK: - Component Status Model (unchanged)

private struct ComponentStatus {
    let label: String
    let symbol: String
    let color: Color

    static func derive(local: String?, template: String?, online: String?) -> ComponentStatus {
        if local == nil {
            return ComponentStatus(label: "Missing",           symbol: "xmark.circle.fill",            color: MSC.Colors.error)
        }
        if let t = template, let l = local, !versionsMatch(t, l) {
            return ComponentStatus(label: "Template mismatch", symbol: "exclamationmark.triangle.fill", color: .yellow)
        }
        if let o = online, let l = local, !versionsMatch(o, l) {
            if isVersionNewer(o, than: l) {
                return ComponentStatus(label: "Update available", symbol: "arrow.down.circle.fill", color: MSC.Colors.warning)
            }
        }
        return ComponentStatus(label: "Up to date", symbol: "checkmark.circle.fill", color: MSC.Colors.success)
    }

    private static func isVersionNewer(_ a: String, than b: String) -> Bool {
        let aBuild = buildNumber(a)
        let bBuild = buildNumber(b)
        if let ab = aBuild, let bb = bBuild { return ab > bb }
        let aParts = a.split(separator: " ").first.map(String.init) ?? a
        let bParts = b.split(separator: " ").first.map(String.init) ?? b
        let aComponents = aParts.split(separator: ".").compactMap { Int($0) }
        let bComponents = bParts.split(separator: ".").compactMap { Int($0) }
        let count = max(aComponents.count, bComponents.count)
        for i in 0..<count {
            let av = i < aComponents.count ? aComponents[i] : 0
            let bv = i < bComponents.count ? bComponents[i] : 0
            if av > bv { return true }
            if av < bv { return false }
        }
        return false
    }

    private static func buildNumber(_ s: String) -> Int? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let n = Int(trimmed) { return n }
        let lower = trimmed.lowercased()
        guard let range = lower.range(of: "build") else { return nil }
        let after  = lower[range.upperBound...]
        let digits = after.filter { $0.isNumber || $0 == " " }
            .trimmingCharacters(in: .whitespaces)
            .prefix(while: { $0.isNumber })
        return Int(String(digits))
    }

    private static func versionsMatch(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        if let ba = buildNumber(a), let bb = buildNumber(b) { return ba == bb }
        return false
    }
}

// MARK: - Row Divider (unchanged)

private struct ComponentRowDivider: View {
    var body: some View {
        Divider()
            .padding(.vertical, MSC.Spacing.xs)
            .opacity(0.5)
    }
}

// MARK: - Component Version Row (kept for Bedrock)

private struct ComponentVersionRow: View {
    let label: String
    let value: String
    var missing: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: MSC.Spacing.sm) {
            Text(label)
                .font(MSC.Typography.caption)
                .foregroundStyle(MSC.Colors.tertiary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(MSC.Typography.caption)
                .foregroundStyle(missing ? MSC.Colors.error : MSC.Colors.caption)
                .textSelection(.enabled)
            Spacer()
        }
    }
}

// MARK: - Bedrock Runtime Section Card (unchanged)

private struct BedrockRuntimeSectionCard: View {
    @EnvironmentObject var viewModel: AppViewModel

    private var pinnedVersion: String {
        viewModel.selectedServer
            .flatMap { viewModel.configServer(for: $0)?.bedrockVersion }
            ?? "LATEST"
    }

    private var imageName: String {
        viewModel.selectedServer
            .flatMap { viewModel.configServer(for: $0)?.bedrockDockerImage }
            ?? "itzg/minecraft-bedrock-server"
    }

    var body: some View {
        SEBlock {
            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                HStack(spacing: MSC.Spacing.sm) {
                    Label("Bedrock Server", systemImage: "memorychip")
                        .font(MSC.Typography.cardTitle)
                        .foregroundStyle(.primary)
                    Spacer()
                    BedrockStatusPill(
                        label: viewModel.isServerRunning ? "Running" : "Stopped",
                        symbol: viewModel.isServerRunning ? "checkmark.circle.fill" : "stop.circle.fill",
                        color: viewModel.isServerRunning ? MSC.Colors.success : MSC.Colors.tertiary
                    )
                }

                VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                    ComponentVersionRow(label: "Pinned", value: pinnedVersion == "LATEST" ? "Latest (auto)" : pinnedVersion)
                    ComponentVersionRow(label: "Running", value: viewModel.bedrockRunningVersion ?? "\u{2014}")
                }
                .padding(.horizontal, MSC.Spacing.xs)

                Divider().opacity(0.5).padding(.vertical, MSC.Spacing.xxs)

                BedrockVersionPickerRow(currentVersion: pinnedVersion)

                HStack(spacing: MSC.Spacing.sm) {
                    Button {
                        viewModel.updateBedrockImageAndRestart()
                    } label: {
                        if viewModel.isUpdatingBedrockImage {
                            HStack(spacing: 4) {
                                ProgressView().controlSize(.mini)
                                Text("Updating\u{2026}")
                            }
                        } else {
                            Label("Update server files", systemImage: "arrow.down.circle.fill")
                        }
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                    .controlSize(.mini)
                    .disabled(viewModel.isServerRunning || viewModel.isUpdatingBedrockImage)
                    Spacer()
                }
            }
            .padding(MSC.Spacing.md)
        }
        .onAppear { viewModel.fetchBedrockVersionsIfNeeded() }
    }
}

// MARK: - Bedrock Version Picker Row (unchanged)

private struct BedrockVersionPickerRow: View {
    @EnvironmentObject var viewModel: AppViewModel
    let currentVersion: String

    var body: some View {
        HStack(spacing: MSC.Spacing.sm) {
            Text("Version")
                .font(MSC.Typography.caption)
                .foregroundStyle(MSC.Colors.tertiary)
                .frame(width: 60, alignment: .leading)

            if viewModel.isFetchingBedrockVersions {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("Loading versions\u{2026}")
                        .font(MSC.Typography.caption)
                        .foregroundStyle(MSC.Colors.tertiary)
                }
            } else {
                Picker("", selection: Binding(
                    get: { currentVersion },
                    set: { viewModel.setBedrockVersion($0) }
                )) {
                    ForEach(viewModel.bedrockAvailableVersions) { entry in
                        Text(entry.displayName).tag(entry.version)
                    }
                    if !currentVersion.isEmpty
                        && currentVersion != "LATEST"
                        && !viewModel.bedrockAvailableVersions.contains(where: { $0.version == currentVersion }) {
                        Text(currentVersion).tag(currentVersion)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .disabled(viewModel.isServerRunning || viewModel.isUpdatingBedrockImage)
                .frame(maxWidth: 200, alignment: .leading)
            }
            Spacer()
        }
    }
}

// MARK: - Bedrock Status Pill (unchanged)

private struct BedrockStatusPill: View {
    let label: String
    let symbol: String
    let color: Color

    var body: some View {
        Label(label, systemImage: symbol)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, MSC.Spacing.sm)
            .padding(.vertical, MSC.Spacing.xxs + 1)
            .background(Capsule().fill(color.opacity(0.12)))
            .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 0.75))
    }
}

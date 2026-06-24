//
//  DetailsComponentsTabView.swift
//  MinecraftServerController
//
//  Unified component list — Paper, plugins, and broadcast in one clean block.
//  Each component is a row: toggle/spacer · icon · name+version · status chip · actions.
//

import SwiftUI

// MARK: - Main View

struct DetailsComponentsTabView: View {
    @EnvironmentObject var viewModel: AppViewModel

    private var isBedrock: Bool {
        guard let s = viewModel.selectedServer else { return false }
        return viewModel.configServer(for: s)?.isBedrock ?? false
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

            Button {
                viewModel.refreshComponentsSnapshotLocalAndTemplate(clearOnline: false)
            } label: {
                Label("Refresh local", systemImage: "arrow.clockwise")
            }
            .buttonStyle(MSCSecondaryButtonStyle())
            .controlSize(.mini)

            Button {
                viewModel.checkComponentsOnline()
            } label: {
                if viewModel.isCheckingComponentsOnline {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text("Checking\u{2026}")
                    }
                } else {
                    Label("Check online", systemImage: "cloud.fill")
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

    // MARK: - Java component list (unified block)

    private var javaComponentList: some View {
        SEBlock {
            // ── Paper ──────────────────────────────────────────────────────
            PaperListRow(onReveal: revealPaperJarInFinder)

            rowDivider

            // ── Plugins ────────────────────────────────────────────────────
            pluginRows

            rowDivider

            // ── Broadcast ──────────────────────────────────────────────────
            BroadcastListRow()

            rowDivider

            // ── Plugin folder footer ───────────────────────────────────────
            pluginFooter
        }
        .task { viewModel.refreshDiscoveredPlugins() }
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
                    Text("Image").font(MSC.Typography.caption).foregroundStyle(MSC.Colors.tertiary).frame(width: 44, alignment: .leading)
                    Text("ghcr.io/mcxboxbroadcast/standalone:latest")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if let server = viewModel.selectedServer,
                   let cfg = viewModel.configServer(for: server) {
                    let port = viewModel.effectiveBedrockPort(for: cfg) ?? 19132
                    let transferHost = viewModel.previewBroadcastHost(for: cfg, mode: cfg.xboxBroadcastIPMode)
                    HStack {
                        Text("Transfers to").font(MSC.Typography.caption).foregroundStyle(MSC.Colors.tertiary).frame(width: 72, alignment: .leading)
                        Text("\(transferHost):\(port)")
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
                    Button("Pull Latest") { viewModel.pullBedrockBroadcastImage() }
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

// MARK: - Paper List Row

private struct PaperListRow: View {
    @EnvironmentObject var viewModel: AppViewModel
    let onReveal: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // ── Header row ────────────────────────────────────────────
            HStack(spacing: MSC.Spacing.sm) {
                // Non-interactive "always on" indicator — Paper is the core JAR, it can't be disabled
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
                        Text("Paper")
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

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.accentColor.opacity(0.65))
                }
                .buttonStyle(MSCSecondaryButtonStyle())
                .controlSize(.mini)
            }
            .padding(.horizontal, MSC.Spacing.md)
            .padding(.vertical, MSC.Spacing.sm + 1)

            // ── Expansion ─────────────────────────────────────────────
            if isExpanded {
                Divider().opacity(0.5)

                VStack(alignment: .leading, spacing: MSC.Spacing.md) {
                    trackSelector

                    if viewModel.includeExperimentalPaperBuilds {
                        HStack(alignment: .top, spacing: MSC.Spacing.xs) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(MSC.Colors.warning)
                                .padding(.top, 1)
                            Text("Experimental builds are required for console cross-play on the latest Minecraft version. Not recommended for stable play.")
                                .font(MSC.Typography.caption)
                                .foregroundStyle(MSC.Colors.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    versionListContent

                    HStack(spacing: MSC.Spacing.sm) {
                        Button {
                            viewModel.downloadAndApplySelectedPaperVersion()
                        } label: {
                            if viewModel.isDownloadingAndApplyingPaper {
                                HStack(spacing: 4) {
                                    ProgressView().controlSize(.mini)
                                    Text("Downloading\u{2026}")
                                }
                            } else {
                                Label("Download selected", systemImage: "arrow.down.circle.fill")
                            }
                        }
                        .buttonStyle(MSCSecondaryButtonStyle())
                        .controlSize(.mini)
                        .disabled(
                            viewModel.isServerRunning ||
                            viewModel.isDownloadingAndApplyingPaper ||
                            viewModel.selectedPaperVersionOption == nil
                        )

                        Button { onReveal() } label: {
                            Label("Reveal", systemImage: "folder")
                        }
                        .buttonStyle(MSCSecondaryButtonStyle())
                        .controlSize(.mini)

                        Spacer()
                    }
                }
                .padding(.horizontal, MSC.Spacing.md)
                .padding(.vertical, MSC.Spacing.md)
                .transition(.opacity)
            }
        }
    }

    private var trackSelector: some View {
        HStack(spacing: 2) {
            trackSegment("Stable",       isSelected: !viewModel.includeExperimentalPaperBuilds) {
                viewModel.switchPaperTrack(includeExperimental: false)
            }
            trackSegment("Experimental", isSelected:  viewModel.includeExperimentalPaperBuilds) {
                viewModel.switchPaperTrack(includeExperimental: true)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.sm + 2, style: .continuous)
                .fill(MSC.Colors.tierAtmosphere)
        )
    }

    @ViewBuilder
    private func trackSegment(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .padding(.horizontal, MSC.Spacing.sm)
                .padding(.vertical, MSC.Spacing.xxs + 1)
                .background(
                    Group {
                        if isSelected {
                            RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                                .fill(MSC.Colors.tierContent)
                        }
                    }
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var versionListContent: some View {
        if viewModel.isCheckingComponentsOnline && viewModel.availablePaperVersions.isEmpty {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Fetching available versions\u{2026}")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.tertiary)
            }
        } else if viewModel.availablePaperVersions.isEmpty {
            Text("Click Check online above to see available versions.")
                .font(MSC.Typography.caption)
                .foregroundStyle(MSC.Colors.tertiary)
        } else {
            VStack(spacing: 2) {
                ForEach(viewModel.availablePaperVersions) { option in
                    PaperVersionRow(
                        option: option,
                        isSelected: viewModel.selectedPaperVersionOption == option,
                        isCurrent: option.displayString == viewModel.componentsSnapshot.paper.local
                    ) {
                        viewModel.selectedPaperVersionOption = option
                    }
                }
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
                    if let local = localVersion {
                        Text(local)
                            .font(.system(size: 10.5))
                            .foregroundStyle(MSC.Colors.caption)
                    }
                    if hasUpdate, let online = entry.onlineVersion, online != "(direct)" {
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
                if canDownload {
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

                if entry.tier != .managed {
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

// MARK: - Paper Version Row (unchanged)

private struct PaperVersionRow: View {
    let option: PaperVersionOption
    let isSelected: Bool
    let isCurrent: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: MSC.Spacing.sm) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.secondary.opacity(0.35),
                            lineWidth: 1.5
                        )
                        .frame(width: 13, height: 13)
                    if isSelected {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                    }
                }

                HStack(spacing: 4) {
                    Text(option.version)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                    Text("build \(option.build)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if isCurrent {
                        Text("— installed")
                            .font(.system(size: 10))
                            .foregroundStyle(MSC.Colors.tertiary)
                    }
                }

                Spacer()

                HStack(alignment: .center, spacing: 6) {
                    channelBadge(option.channel)
                    Text(option.formattedDate ?? "")
                        .font(.system(size: 10))
                        .foregroundStyle(MSC.Colors.tertiary)
                        .frame(width: 80, alignment: .leading)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, MSC.Spacing.xs)
        .padding(.vertical, 5)
        .background(
            Group {
                if isSelected {
                    RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                        .fill(Color.accentColor.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                                .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 0.5)
                        )
                }
            }
        )
    }

    @ViewBuilder
    private func channelBadge(_ channel: String) -> some View {
        let (label, color): (String, Color) = badgeInfo(for: channel)
        Text(label)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(color.opacity(0.25), lineWidth: 0.5)
                    )
            )
    }

    private func badgeInfo(for channel: String) -> (String, Color) {
        switch channel.uppercased() {
        case "STABLE": return ("Stable", MSC.Colors.success)
        case "BETA":   return ("Beta",   MSC.Colors.warning)
        default:       return ("Alpha",  Color.purple)
        }
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
                    Label("Docker Image", systemImage: "shippingbox")
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
                    ComponentVersionRow(label: "Image",  value: imageName)
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
                                Text("Pulling image\u{2026}")
                            }
                        } else {
                            Label("Update to latest", systemImage: "arrow.down.circle.fill")
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

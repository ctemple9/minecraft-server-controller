//
//  DetailsComponentsTabView.swift
//  MinecraftServerController
//
//  Components management surface for Paper, plugins, broadcast helpers, and
//  Bedrock runtime tooling.
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
        componentsContent
    }

    // MARK: - Scroll container

    private var componentsContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: MSC.Spacing.md) {

                if isBedrock {
                    BedrockComponentsToolbarCard()
                } else {
                    ComponentsToolbarCard()
                }

                if !isBedrock {
                    ComponentSectionCard(title: "Core Server", icon: "shippingbox.fill") {
                        PaperComponentCard(onReveal: revealPaperJarInFinder)
                    }

                    PluginsSectionCard()

                    ComponentSectionCard(title: "Broadcast", icon: "gamecontroller.fill") {
                        componentCard(
                            title: "MCXboxBroadcast",
                            icon: "antenna.radiowaves.left.and.right",
                            local: viewModel.componentsSnapshot.broadcast.local,
                            template: nil,
                            online: viewModel.componentsSnapshot.broadcast.online,
                            isDownloading: false,
                            onDownloadLatest: { viewModel.downloadOrUpdateXboxBroadcastJar() },
                            onReveal: revealBroadcastJarInFinder
                        )
                    }
                }

                if isBedrock {
                    BedrockRuntimeSectionCard()
                    bedrockBroadcastCard
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, MSC.Spacing.sm)
        }
    }

    // MARK: - Bedrock broadcast card (Docker container)

    @ViewBuilder private var bedrockBroadcastCard: some View {
        ComponentSectionCard(title: "Broadcast", icon: "gamecontroller.fill") {
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
                    Button("Pull Latest") {
                        viewModel.pullBedrockBroadcastImage()
                    }
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
        }
    }

    // MARK: - Generic component card row (Broadcast)

    private func componentCard(
        title: String,
        icon: String,
        local: String?,
        template: String?,
        online: String?,
        isDownloading: Bool,
        onDownloadLatest: (() -> Void)?,
        onReveal: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {

            HStack(spacing: MSC.Spacing.sm) {
                Label(title, systemImage: icon)
                    .font(MSC.Typography.cardTitle)
                    .foregroundStyle(.primary)
                Spacer()
                ComponentStatusPill(local: local, template: template, online: online)
            }

            VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                ComponentVersionRow(label: "Local",  value: local  ?? "Missing", missing: local == nil)
                if let template {
                    ComponentVersionRow(label: "Template", value: template)
                }
                ComponentVersionRow(label: "Online", value: online ?? "\u{2014}")
            }
            .padding(.horizontal, MSC.Spacing.xs)

            HStack(spacing: MSC.Spacing.sm) {
                if let onDownloadLatest {
                    Button {
                        onDownloadLatest()
                    } label: {
                        if isDownloading {
                            HStack(spacing: 4) {
                                ProgressView().controlSize(.mini)
                                Text("Downloading\u{2026}")
                            }
                        } else {
                            Label("Download Latest", systemImage: "arrow.down.circle.fill")
                        }
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                    .controlSize(.mini)
                    .disabled(viewModel.isServerRunning || isDownloading)
                }

                Button {
                    onReveal()
                } label: {
                    Label("Reveal", systemImage: "folder")
                }
                .buttonStyle(MSCSecondaryButtonStyle())
                .controlSize(.mini)

                Spacer()
            }
        }
        .padding(.vertical, MSC.Spacing.xxs)
    }
}

// MARK: - Plugins Section Card

private struct PluginsSectionCard: View {
    @EnvironmentObject var viewModel: AppViewModel

    var body: some View {
        ComponentSectionCard(
            title: "Plugins",
            icon: "puzzlepiece.extension.fill",
            count: viewModel.discoveredPlugins.isEmpty ? nil : viewModel.discoveredPlugins.count,
            headerTrailing: {
                HStack(spacing: MSC.Spacing.xs) {
                    Button {
                        revealPluginsFolder()
                    } label: {
                        Label("Reveal", systemImage: "folder")
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                    .controlSize(.mini)

                    Button {
                        viewModel.addPluginFromFilePicker()
                    } label: {
                        Label("Add Plugin", systemImage: "plus")
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                    .controlSize(.mini)
                }
            }
        ) {
            if viewModel.discoveredPlugins.isEmpty {
                Text("No plugins found. Click Add Plugin to install one.")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.tertiary)
                    .padding(.vertical, MSC.Spacing.xs)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.discoveredPlugins.enumerated()), id: \.element.id) { idx, entry in
                        if idx > 0 { ComponentRowDivider() }
                        PluginRowView(entry: entry)
                    }
                }
            }
        }
        .task {
            viewModel.refreshDiscoveredPlugins()
        }
    }

    private func revealPluginsFolder() {
        guard let cfg = viewModel.selectedServerConfig else { return }
        let pluginsDir = URL(fileURLWithPath: cfg.serverDir, isDirectory: true)
            .appendingPathComponent("plugins", isDirectory: true)
        try? FileManager.default.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
        viewModel.revealInFinder(url: pluginsDir)
    }
}

// MARK: - Plugin Row

private struct PluginRowView: View {
    @EnvironmentObject var viewModel: AppViewModel
    let entry: PluginEntry

    @State private var isShowingSourcePopover: Bool = false
    @State private var isShowingDownloadConfirm: Bool = false

    private var isDownloading: Bool { viewModel.downloadingPlugins.contains(entry.jarStem) }
    private var hasUpdate: Bool {
        guard let online = entry.onlineVersion, !online.isEmpty, online != "(direct)" else { return false }
        if let local = entry.parsedVersion ?? entry.localVersion {
            return online != local
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
            // Top row: icon + name + badges + Enable/Disable
            HStack(spacing: MSC.Spacing.sm) {
                Image(systemName: pluginIcon)
                    .font(.system(size: 13))
                    .foregroundStyle(MSC.Colors.tertiary)
                    .frame(width: 16)

                Text(entry.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(entry.isEnabled ? Color.primary : Color.secondary)

                // Tier badge
                switch entry.tier {
                case .managed:
                    PluginTierBadge(label: "Managed", icon: "sparkles", color: MSC.Colors.info)
                case .userSourced:
                    if let source = entry.sourceConfig {
                        PluginTierBadge(label: source.type.displayName,
                                        icon: source.type.symbolName,
                                        color: sourceBadgeColor(source.type))
                    }
                case .unmanaged:
                    EmptyView()
                }

                // Update / status pill
                if entry.tier != .unmanaged {
                    if hasUpdate {
                        ComponentStatusPill(
                            local: entry.parsedVersion ?? entry.localVersion,
                            template: entry.templateVersion,
                            online: entry.onlineVersion
                        )
                    } else if entry.onlineVersion != nil {
                        ComponentStatusPill(
                            local: entry.parsedVersion ?? entry.localVersion,
                            template: entry.templateVersion,
                            online: entry.onlineVersion
                        )
                    }
                }

                Spacer()

                // Enable / Disable button
                Button {
                    viewModel.togglePlugin(jarStem: entry.jarStem)
                } label: {
                    Text(entry.isEnabled ? "Disable" : "Enable")
                }
                .buttonStyle(MSCSecondaryButtonStyle())
                .controlSize(.mini)
            }

            // Extended row: version info + action buttons (only for managed/user-sourced)
            if entry.tier != .unmanaged || entry.parsedVersion != nil {
                HStack(alignment: .center) {
                    // Version info
                    HStack(spacing: MSC.Spacing.md) {
                        if let local = entry.parsedVersion ?? entry.localVersion {
                            versionPair(label: "Local", value: local)
                        }
                        if let template = entry.templateVersion {
                            versionPair(label: "Template", value: template)
                        }
                        if let online = entry.onlineVersion, online != "(direct)" {
                            versionPair(label: "Online", value: online, highlight: hasUpdate)
                        }
                    }
                    .padding(.leading, 24)  // indent to align under name

                    Spacer()

                    // Action buttons
                    HStack(spacing: 4) {
                        // Download button (managed always; user-sourced as soon as source is linked)
                        if canDownload {
                            Button {
                                isShowingDownloadConfirm = true
                            } label: {
                                if isDownloading {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Image(systemName: "arrow.down.circle.fill")
                                }
                            }
                            .buttonStyle(MSCSecondaryButtonStyle())
                            .controlSize(.mini)
                            .disabled(viewModel.isServerRunning || isDownloading || (entry.tier == .userSourced && entry.onlineDownloadURL == nil && !entry.isCheckingOnline))
                            .confirmationDialog(
                                "Download latest version of \(entry.displayName)?",
                                isPresented: $isShowingDownloadConfirm,
                                titleVisibility: .visible
                            ) {
                                Button("Download Latest") { triggerDownload() }
                                Button("Cancel", role: .cancel) { }
                            } message: {
                                if let version = entry.onlineVersion {
                                    Text("This will download version \(version) and replace the current JAR.")
                                } else {
                                    Text("This will download and replace the current JAR.")
                                }
                            }
                        }

                        // Source link button (shown for all non-managed plugins)
                        if entry.tier != .managed {
                            Button {
                                isShowingSourcePopover = true
                            } label: {
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
            } else {
                // Unmanaged with no version: just show source button
                HStack {
                    Spacer()
                    Button {
                        isShowingSourcePopover = true
                    } label: {
                        Image(systemName: "link")
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
        .padding(.vertical, MSC.Spacing.xxs)
        .opacity(entry.isEnabled ? 1.0 : 0.38)

    }

    // MARK: - Helpers

    @ViewBuilder
    private func versionPair(label: String, value: String, highlight: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(label)
                .font(MSC.Typography.caption)
                .foregroundStyle(MSC.Colors.tertiary)
            Text(value)
                .font(MSC.Typography.caption)
                .foregroundStyle(highlight ? MSC.Colors.warning : MSC.Colors.caption)
        }
    }

    private var pluginIcon: String {
        switch entry.tier {
        case .managed:    return entry.jarStem.lowercased().contains("geyser") ? "water.waves" : "lock.open.fill"
        case .userSourced: return "puzzlepiece.extension"
        case .unmanaged:  return "puzzlepiece"
        }
    }

    private func sourceBadgeColor(_ type: PluginSourceType) -> Color {
        switch type {
        case .github:   return Color(red: 0.55, green: 0.58, blue: 0.62) // GitHub grey
        case .modrinth: return Color(red: 0.11, green: 0.85, blue: 0.42) // Modrinth green
        case .hangar:   return MSC.Colors.info
        case .direct:   return MSC.Colors.tertiary
        }
    }

    private var canDownload: Bool {
        switch entry.tier {
        case .managed:      return true
        case .userSourced:  return entry.sourceConfig != nil
        case .unmanaged:    return false
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

// MARK: - Plugin Source Popover

private struct PluginSourcePopover: View {
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
                // Remove source option
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

                Button("Cancel") {
                    isPresented = false
                }
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

// MARK: - Plugin Tier Badge

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

// MARK: - Paper Component Card (unchanged)

private struct PaperComponentCard: View {
    @EnvironmentObject var viewModel: AppViewModel
    let onReveal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {

            // Header
            HStack(spacing: MSC.Spacing.sm) {
                Label("Paper", systemImage: "doc.zipper")
                    .font(MSC.Typography.cardTitle)
                    .foregroundStyle(.primary)
                Spacer()
                ComponentStatusPill(
                    local: viewModel.componentsSnapshot.paper.local,
                    template: nil,
                    online: viewModel.componentsSnapshot.paper.online
                )
            }

            // Local version row
            VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                ComponentVersionRow(
                    label: "Local",
                    value: viewModel.componentsSnapshot.paper.local ?? "Missing",
                    missing: viewModel.componentsSnapshot.paper.local == nil
                )
            }
            .padding(.horizontal, MSC.Spacing.xs)

            Divider().opacity(0.5)

            // Track selector
            HStack(spacing: MSC.Spacing.sm) {
                trackSelector
                Spacer()
            }

            // Experimental warning
            if viewModel.includeExperimentalPaperBuilds {
                HStack(alignment: .top, spacing: MSC.Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(MSC.Colors.warning)
                        .padding(.top, 1)
                    Text("Experimental builds are required for console crossplay on the latest Minecraft version. Not recommended for stable play.")
                        .font(MSC.Typography.caption)
                        .foregroundStyle(MSC.Colors.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, MSC.Spacing.xs)
            }

            // Version list
            versionListContent

            // Action buttons
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
                        Label("Download Selected", systemImage: "arrow.down.circle.fill")
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
        .padding(.vertical, MSC.Spacing.xxs)
    }

    // MARK: - Track selector

    private var trackSelector: some View {
        HStack(spacing: 2) {
            trackSegment(
                "Stable",
                isSelected: !viewModel.includeExperimentalPaperBuilds
            ) {
                viewModel.switchPaperTrack(includeExperimental: false)
            }
            trackSegment(
                "Experimental",
                isSelected: viewModel.includeExperimentalPaperBuilds
            ) {
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
    private func trackSegment(
        _ title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
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

    // MARK: - Version list

    @ViewBuilder
    private var versionListContent: some View {
        if viewModel.isCheckingComponentsOnline && viewModel.availablePaperVersions.isEmpty {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Fetching available versions\u{2026}")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.tertiary)
            }
            .padding(.horizontal, MSC.Spacing.xs)
            .padding(.vertical, MSC.Spacing.xxs)
        } else if viewModel.availablePaperVersions.isEmpty {
            Text("Click Check Online above to see available versions.")
                .font(MSC.Typography.caption)
                .foregroundStyle(MSC.Colors.tertiary)
                .padding(.horizontal, MSC.Spacing.xs)
                .padding(.vertical, MSC.Spacing.xxs)
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

// MARK: - Paper Version Row (unchanged)

private struct PaperVersionRow: View {
    let option: PaperVersionOption
    let isSelected: Bool
    let isCurrent: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: MSC.Spacing.sm) {

                // Radio indicator
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

                // Version + build
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

// MARK: - Toolbar Card (Java)

private struct ComponentsToolbarCard: View {
    @EnvironmentObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
            HStack {
                Label("Components", systemImage: "cpu")
                    .font(MSC.Typography.cardTitle)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    viewModel.refreshComponentsSnapshotLocalAndTemplate(clearOnline: false)
                } label: {
                    Label("Refresh Local", systemImage: "arrow.clockwise")
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
                        Label("Check Online", systemImage: "cloud.fill")
                    }
                }
                .buttonStyle(MSCSecondaryButtonStyle())
                .controlSize(.mini)
                .disabled(viewModel.isCheckingComponentsOnline)
            }

            if let err = viewModel.componentsOnlineErrorMessage, !err.isEmpty {
                Divider()
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.warning)
            }
        }
        .padding(MSC.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .fill(MSC.Colors.tierContent)
        )
    }
}

// MARK: - Toolbar Card (Bedrock)

private struct BedrockComponentsToolbarCard: View {
    var body: some View {
        HStack {
            Label("Components", systemImage: "cpu")
                .font(MSC.Typography.cardTitle)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(MSC.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .fill(MSC.Colors.tierContent)
        )
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
        ComponentSectionCard(title: "Bedrock Dedicated Server", icon: "shippingbox.fill") {
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
                    ComponentVersionRow(
                        label: "Pinned",
                        value: pinnedVersion == "LATEST" ? "Latest (auto)" : pinnedVersion
                    )
                    ComponentVersionRow(
                        label: "Running",
                        value: viewModel.bedrockRunningVersion ?? "\u{2014}"
                    )
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
        }
        .onAppear {
            viewModel.fetchBedrockVersionsIfNeeded()
        }
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

// MARK: - Section Card Shell (updated to support optional count)

private struct ComponentSectionCard<Content: View, Trailing: View>: View {
    let title: String
    let icon: String
    var count: Int? = nil
    @ViewBuilder let headerTrailing: () -> Trailing
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        icon: String,
        count: Int? = nil,
        @ViewBuilder headerTrailing: @escaping () -> Trailing = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.count = count
        self.headerTrailing = headerTrailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {
            HStack {
                Label(title, systemImage: icon)
                    .font(MSC.Typography.cardTitle)
                    .foregroundStyle(.secondary)
                if let count {
                    Text("\(count) installed")
                        .font(.system(size: 10))
                        .foregroundStyle(MSC.Colors.tertiary)
                }
                Spacer()
                headerTrailing()
            }
            Divider()
            content()
        }
        .padding(MSC.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .fill(MSC.Colors.tierContent)
        )
    }
}

// MARK: - Version Row (unchanged)

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

// MARK: - Status Pill (unchanged)

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
        return ComponentStatus(label: "Up to date",            symbol: "checkmark.circle.fill",         color: MSC.Colors.success)
    }

    private static func isVersionNewer(_ a: String, than b: String) -> Bool {
        // If one side is a bare build number, compare build numbers directly
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

    /// Returns a build number from either a bare integer string ("1126") or
    /// a string containing "build NNN" ("2.10.0 (build 1155)").
    private static func buildNumber(_ s: String) -> Int? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // Bare integer — treat the whole string as a build number
        if let n = Int(trimmed) { return n }
        // "build NNN" anywhere in the string
        let lower = trimmed.lowercased()
        guard let range = lower.range(of: "build") else { return nil }
        let after  = lower[range.upperBound...]
        let digits = after.filter { $0.isNumber || $0 == " " }
            .trimmingCharacters(in: .whitespaces)
            .prefix(while: { $0.isNumber })
        return Int(String(digits))
    }

    // Keep parseBuild as an alias for backward compat
    private static func parseBuild(_ s: String) -> Int? { buildNumber(s) }

    private static func versionsMatch(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        // Both sides resolve to a build number → compare those
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

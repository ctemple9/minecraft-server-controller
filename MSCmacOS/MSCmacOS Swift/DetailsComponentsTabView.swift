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

                    ComponentSectionCard(title: "Plugins", icon: "puzzlepiece.extension.fill") {
                        componentCard(
                            title: "Geyser",
                            icon: "water.waves",
                            local: viewModel.componentsSnapshot.geyser.local,
                            template: viewModel.componentsSnapshot.geyser.template,
                            online: viewModel.componentsSnapshot.geyser.online,
                            isDownloading: viewModel.isDownloadingAndApplyingGeyser,
                            onDownloadLatest: { viewModel.downloadAndApplyLatestGeyser() },
                            onReveal: { revealPluginInFinder(keyword: "geyser") }
                        )

                        ComponentRowDivider()

                        componentCard(
                            title: "Floodgate",
                            icon: "lock.open.fill",
                            local: viewModel.componentsSnapshot.floodgate.local,
                            template: viewModel.componentsSnapshot.floodgate.template,
                            online: viewModel.componentsSnapshot.floodgate.online,
                            isDownloading: viewModel.isDownloadingAndApplyingFloodgate,
                            onDownloadLatest: { viewModel.downloadAndApplyLatestFloodgate() },
                            onReveal: { revealPluginInFinder(keyword: "floodgate") }
                        )
                    }

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

                    ComponentSectionCard(title: "Bedrock Connect", icon: "network") {
                        componentCard(
                            title: "Bedrock Connect",
                            icon: "server.rack",
                            local: viewModel.componentsSnapshot.bedrockConnect.local,
                            template: nil,
                            online: viewModel.componentsSnapshot.bedrockConnect.online,
                            isDownloading: false,
                            onDownloadLatest: { viewModel.downloadOrUpdateBedrockConnectJar() },
                            onReveal: revealBedrockConnectJarInFinder
                        )
                    }
                }

                if isBedrock {
                    BedrockRuntimeSectionCard()
                    BedrockConnectStandaloneSectionCard()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, MSC.Spacing.sm)
        }
    }

    // MARK: - Generic component card row (Geyser, Floodgate, Broadcast, BedrockConnect)

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

// MARK: - Paper Component Card

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

// MARK: - Paper Version Row

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

// MARK: - Bedrock Runtime Section Card

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

// MARK: - Bedrock Connect Standalone Section Card

private struct BedrockConnectStandaloneSectionCard: View {
    @EnvironmentObject var viewModel: AppViewModel

    private var server: ConfigServer? {
        viewModel.selectedServer.flatMap { viewModel.configServer(for: $0) }
    }

    private var isInstalled: Bool { viewModel.isBedrockConnectJarInstalled }

    private var isEnabled: Bool {
        server?.bedrockConnectStandaloneEnabled ?? false
    }

    var body: some View {
        ComponentSectionCard(title: "Bedrock Connect", icon: "network") {
            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {

                HStack(spacing: MSC.Spacing.sm) {
                    Label("Bedrock Connect", systemImage: "gamecontroller.fill")
                        .font(MSC.Typography.cardTitle)
                        .foregroundStyle(.primary)
                    Spacer()
                    BedrockStatusPill(
                        label: isInstalled ? (isEnabled ? "Enabled" : "Installed") : "Not installed",
                        symbol: isInstalled ? (isEnabled ? "checkmark.circle.fill" : "circle") : "xmark.circle",
                        color: isInstalled ? (isEnabled ? MSC.Colors.success : MSC.Colors.tertiary) : MSC.Colors.error
                    )
                }

                Text("Bedrock Connect lets players on PlayStation, Nintendo Switch, and Xbox join your server by redirecting the built-in Featured Servers list to your IP.")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.caption)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().opacity(0.5)

                ComponentVersionRow(
                    label: "JAR",
                    value: viewModel.componentsSnapshot.bedrockConnect.local ?? "Not downloaded",
                    missing: viewModel.componentsSnapshot.bedrockConnect.local == nil
                )
                ComponentVersionRow(
                    label: "DNS Port",
                    value: viewModel.configManager.config.bedrockConnectDNSPort.map { "\($0)" } ?? "19132 (default)"
                )

                HStack(spacing: MSC.Spacing.sm) {
                    Button {
                        viewModel.downloadOrUpdateBedrockConnectJar()
                    } label: {
                        Label("Download Latest", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                    .controlSize(.mini)

                    Button {
                        viewModel.openBedrockConnectJarFolder()
                    } label: {
                        Label("Reveal", systemImage: "folder")
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                    .controlSize(.mini)

                    Spacer()

                    Button {
                        NSApp.sendAction(#selector(NSWindow.makeKeyAndOrderFront(_:)), to: nil, from: nil)
                        viewModel.logAppMessage("[BedrockConnect] See the Bedrock Connect section in the sidebar to configure DNS port and auto-start settings.")
                    } label: {
                        Label("Settings\u{2026}", systemImage: "sidebar.left")
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                    .controlSize(.mini)
                    .help("Open Cross-Platform Access in the sidebar for DNS port and auto-start settings")
                }

                let globalDNSPort = viewModel.configManager.config.bedrockConnectDNSPort ?? 19132
                if isEnabled,
                   let srv = server,
                   let serverPort = srv.bedrockPort,
                   globalDNSPort == serverPort {
                    HStack(spacing: MSC.Spacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(MSC.Colors.warning)
                            .font(MSC.Typography.caption)
                        Text("DNS port \(globalDNSPort) collides with this server's Bedrock port. Change the DNS port in Server Settings \u{2192} Bedrock Connect.")
                            .font(MSC.Typography.caption)
                            .foregroundStyle(MSC.Colors.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

// MARK: - Bedrock Version Picker Row

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

// MARK: - Bedrock Status Pill

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

// MARK: - Section Card Shell

private struct ComponentSectionCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {
            Label(title, systemImage: icon)
                .font(MSC.Typography.cardTitle)
                .foregroundStyle(.secondary)
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

// MARK: - Version Row

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

// MARK: - Status Pill (Java component status)

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

// MARK: - Component Status Model

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
                    // Only flag as needing update if online is actually newer than local.
                    // If local is ahead (e.g. user is on experimental while viewing stable),
                    // treat it as up to date.
                    if isVersionNewer(o, than: l) {
                        return ComponentStatus(label: "Update available", symbol: "arrow.down.circle.fill", color: MSC.Colors.warning)
                    }
                }
        return ComponentStatus(label: "Up to date",            symbol: "checkmark.circle.fill",         color: MSC.Colors.success)
    }

    private static func isVersionNewer(_ a: String, than b: String) -> Bool {
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
            // Same version string — compare build numbers
            if let ab = parseBuild(a), let bb = parseBuild(b) {
                return ab > bb
            }
            return false
        }

        private static func parseBuild(_ s: String) -> Int? {
        let lower = s.lowercased()
        guard let range = lower.range(of: "build") else { return nil }
        let after  = lower[range.upperBound...]
        let digits = after.filter { $0.isNumber }
        return Int(digits)
    }

    private static func versionsMatch(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        if let ba = parseBuild(a), let bb = parseBuild(b) { return ba == bb }
        return false
    }
}

// MARK: - Row Divider

private struct ComponentRowDivider: View {
    var body: some View {
        Divider()
            .padding(.vertical, MSC.Spacing.xs)
            .opacity(0.5)
    }
}

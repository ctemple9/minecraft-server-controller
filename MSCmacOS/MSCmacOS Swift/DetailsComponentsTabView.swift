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

                // Java-only: Core Server, Plugins, Broadcast, BedrockConnect (plugin)
                if !isBedrock {

                    ComponentSectionCard(title: "Core Server", icon: "shippingbox.fill") {
                        componentCard(
                            title: "Paper",
                            icon: "doc.zipper",
                            local: viewModel.componentsSnapshot.paper.local,
                            template: viewModel.componentsSnapshot.paper.template,
                            online: viewModel.componentsSnapshot.paper.online,
                            isDownloading: viewModel.isDownloadingAndApplyingPaper,
                            onDownloadLatest: { viewModel.downloadAndApplyLatestPaper() },
                            onReveal: revealPaperJarInFinder
                        )
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

                // Bedrock-only: Docker runtime (BDS image + version picker) + BedrockConnect standalone
                if isBedrock {
                    BedrockRuntimeSectionCard()
                    BedrockConnectStandaloneSectionCard()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, MSC.Spacing.sm)
        }
    }

    // MARK: - Component card row (Java only)

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
                ComponentVersionRow(label: "Local",    value: local    ?? "Missing", missing: local == nil)
                if let template {
                    ComponentVersionRow(label: "Template", value: template)
                }
                ComponentVersionRow(label: "Online",   value: online   ?? "\u{2014}")
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

// MARK: - Bedrock Runtime Section Card (BDS image + version management)

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

// MARK: - Bedrock Connect Standalone Section Card (Bedrock servers only)

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

                // Header with install status
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

                // Description
                Text("Bedrock Connect lets players on PlayStation, Nintendo Switch, and Xbox join your server by redirecting the built-in Featured Servers list to your IP.")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.caption)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().opacity(0.5)

                // Version info rows
                ComponentVersionRow(
                    label: "JAR",
                    value: viewModel.componentsSnapshot.bedrockConnect.local ?? "Not downloaded",
                    missing: viewModel.componentsSnapshot.bedrockConnect.local == nil
                )
                ComponentVersionRow(
                    label: "DNS Port",
                    value: viewModel.configManager.config.bedrockConnectDNSPort.map { "\($0)" } ?? "19132 (default)"
                )

                // Action buttons
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

                    // Deep-link to sidebar Cross-Platform section for full config
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

                // Port collision warning
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
        if let o = online,   let l = local, !versionsMatch(o, l) {
            return ComponentStatus(label: "Update available",  symbol: "arrow.down.circle.fill",        color: MSC.Colors.warning)
        }
        return ComponentStatus(label: "Up to date",            symbol: "checkmark.circle.fill",         color: MSC.Colors.success)
    }

    private static func parseBuild(_ s: String) -> Int? {
        let lower = s.lowercased()
        guard let range = lower.range(of: "build") else { return nil }
        let after = lower[range.upperBound...]
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

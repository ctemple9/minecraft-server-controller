//
//  SidebarView.swift
//  MinecraftServerController
//
//  Primary server-control sidebar for selection, start/stop, maintenance,
//  quick commands, and cross-platform access shortcuts.
//

import SwiftUI
import AppKit

struct SidebarView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @ObservedObject private var contextualHelp = ContextualHelpManager.shared

    @Binding var isShowingPluginTemplates: Bool
    @Binding var isShowingPaperTemplate: Bool
    @Binding var isShowingManageServers: Bool

    // Server accent color used for selector tinting.
    // Defaults to the app banner color when no server-specific accent is available.
    var bannerColor: Color = Color(red: 30/255, green: 30/255, blue: 30/255)

    @State private var isCrossPlatformExpanded: Bool = false
    @State private var isHowToConnectExpanded: Bool = false
    @State private var isMaintenanceExpanded: Bool = false
    @State private var isQuickCommandsExpanded: Bool = false
    @State private var isShowingKillJavaProcessConfirm: Bool = false

    private let crossPlatformGuideID = "sidebar.crossPlatform"
    private let maintenanceGuideID = "sidebar.maintenance"
    private let quickCommandsGuideID = "sidebar.quickCommands"

    private let crossPlatformHeaderAnchorID = "sidebar.crossPlatform.header"
    private let crossPlatformContentAnchorID = "sidebar.crossPlatform.content"
    private let crossPlatformAutoStartAnchorID = "sidebar.crossPlatform.autoStart"

    private let maintenanceHeaderAnchorID = "sidebar.maintenance.header"
    private let maintenanceButtonsAnchorID = "sidebar.maintenance.buttons"

    private let quickCommandsHeaderAnchorID = "sidebar.quickCommands.header"
    private let quickCommandsControlsAnchorID = "sidebar.quickCommands.controls"
    private let quickCommandsStateAnchorID = "sidebar.quickCommands.state"

    private func serverFlavorIcon(_ server: Server) -> String {
        guard let cfg = viewModel.configServer(for: server) else { return "server.rack" }
        return cfg.isJava ? cfg.javaFlavor.iconName : "cube.box.fill"
    }

    private var selectedServerBinding: Binding<Server?> {
        Binding(
            get: { viewModel.selectedServer },
            set: { newValue in viewModel.selectedServer = newValue }
        )
    }

    private var serverTypeForCrossPlay: ServerType? {
        viewModel.selectedServer
            .flatMap({ viewModel.configServer(for: $0) })?.serverType
    }

    private var showCrossPlatform: Bool {
        guard let cfg = viewModel.selectedServer.flatMap({ viewModel.configServer(for: $0) }) else { return false }
        if cfg.isBedrock { return true }
        // Modded and Vanilla Java servers don't support Geyser/Xbox Broadcast cross-play
        return cfg.isJava && cfg.javaFlavor != .vanilla && cfg.javaFlavor.category != .modded
    }

    private var contextualHelpGuideIDs: Set<String> {
        [
            crossPlatformGuideID,
            maintenanceGuideID,
            quickCommandsGuideID
        ]
    }

    private var crossPlatformHelpGuide: ContextualHelpGuide {
        let isBedrockServer = serverTypeForCrossPlay == .bedrock

        return ContextualHelpGuide(
            id: crossPlatformGuideID,
            steps: [
                sidebarHelpStep(
                    id: "crossPlatform.header",
                    title: "Console Access",
                    body: isBedrockServer
                        ? "This is a compact console-access summary for the selected Bedrock server. It is meant for quick checks and quick toggles, not full setup."
                        : "This is a compact console-access summary for the selected Java server. It gives you quick visibility into the helpers that let console and Bedrock players join.",
                    anchorID: crossPlatformHeaderAnchorID
                ),
                sidebarHelpStep(
                    id: "crossPlatform.content",
                    title: "What lives here",
                    body: isBedrockServer
                        ? "For Bedrock servers, this section shows Xbox Broadcast status. MCXboxBroadcast Standalone runs as a native background process alongside your BDS."
                        : "For Java servers, this section summarizes Xbox Broadcast so you can see what is installed and start or stop the helper without leaving the sidebar.",
                    anchorID: crossPlatformContentAnchorID
                ),
                sidebarHelpStep(
                    id: "crossPlatform.autostart",
                    title: "Auto-start and deeper setup",
                    body: isBedrockServer
                        ? "Use the Components tab to find setup guidance for MCXboxBroadcast Standalone alongside your BDS."
                        : "If Xbox Broadcast is installed, you can let it auto-start with the server here. Use Edit Server for the deeper setup path, because this sidebar section is only the quick-control surface.",
                    anchorID: crossPlatformAutoStartAnchorID,
                    nextLabel: "Done"
                )
            ]
        )
    }

    private var maintenanceHelpGuide: ContextualHelpGuide {
        let isJavaServer = viewModel.selectedServer
            .flatMap { viewModel.configServer(for: $0) }?.isJava ?? true

        return ContextualHelpGuide(
            id: maintenanceGuideID,
            steps: [
                sidebarHelpStep(
                    id: "maintenance.header",
                    title: "Maintenance",
                    body: "This section is for utility shortcuts around the selected server. It is meant to save clicks for common admin tasks.",
                    anchorID: maintenanceHeaderAnchorID
                ),
                sidebarHelpStep(
                    id: "maintenance.buttons",
                    title: "What these buttons are for",
                    body: isJavaServer
                        ? "Archives opens the JAR archive (downloaded server and plugin JARs), while Server Folder and Logs open the server's local files. For routine use, folder and logs are the most common shortcuts."
                        : "For Bedrock servers, this section stays focused on local file access like the server folder and logs. The Archives shortcut is intentionally not shown here because it is a Java-only path.",
                    anchorID: maintenanceButtonsAnchorID,
                    nextLabel: "Done"
                )
            ]
        )
    }

    private var quickCommandsHelpGuide: ContextualHelpGuide {
        ContextualHelpGuide(
            id: quickCommandsGuideID,
            steps: [
                sidebarHelpStep(
                    id: "quickCommands.header",
                    title: "Quick Commands",
                    body: "This section is for live, in-session shortcuts for the selected server. It is not the place for deeper server configuration.",
                    anchorID: quickCommandsHeaderAnchorID
                ),
                sidebarHelpStep(
                    id: "quickCommands.content",
                    title: "Use these for quick actions",
                    body: "Think of these controls as fast runtime actions you may want while the server is already in use, such as quick world or player-facing commands.",
                    anchorID: quickCommandsControlsAnchorID
                ),
                sidebarHelpStep(
                    id: "quickCommands.runningState",
                    title: "When this section matters",
                    body: "If the server is off, this area is intentionally less useful. The main idea is to keep high-frequency commands close at hand while the server is running.",
                    anchorID: quickCommandsStateAnchorID,
                    nextLabel: "Done"
                )
            ]
        )
    }

    private func sidebarHelpStep(
        id: String,
        title: String,
        body: String,
        anchorID: String?,
        nextLabel: String = "Next"
    ) -> ContextualHelpStep {
        ContextualHelpStep(
            id: id,
            title: title,
            body: body,
            anchorID: anchorID,
            nextLabel: nextLabel
        )
    }

    private func startSidebarGuide(
        _ guide: ContextualHelpGuide,
        initialAnchorID: String,
        scrollProxy: ScrollViewProxy,
        expandSection: () -> Void
    ) {
        expandSection()

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.18)) {
                scrollProxy.scrollTo(initialAnchorID, anchor: .center)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    scrollProxy.scrollTo(initialAnchorID, anchor: .center)
                }
                ContextualHelpManager.shared.start(guide)
            }
        }
    }

    private func scrollActiveSidebarHelpIfNeeded(using scrollProxy: ScrollViewProxy) {
        guard contextualHelp.isActive,
              let guideID = contextualHelp.currentGuide?.id,
              contextualHelpGuideIDs.contains(guideID),
              let anchorID = contextualHelp.currentStep?.anchorID else { return }

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.18)) {
                scrollProxy.scrollTo(anchorID, anchor: .center)
            }
        }
    }

    var body: some View {
        // Single VStack so the chrome surface spans the full sidebar height.
        // Removed the outer card wrapper (RoundedRectangle + border + padding).
        VStack(alignment: .leading, spacing: 0) {

            ScrollViewReader { scrollProxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: MSC.Spacing.lg) {

                        // SERVER CONTROLS — overline label, not sectionHeader
                        // Tint the selector block with a subtle accent wash
                        // to give the "selected server" context a visible identity color.
                        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                            HStack(spacing: 6) {
                                Text("SERVER CONTROLS")
                                    .font(MSC.Typography.overlineLabel)
                                    .foregroundStyle(.secondary)

                                Button {
                                    QuickStartWindowController.shared.show(viewModel: viewModel)
                                } label: {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 10))
                                        .foregroundStyle(MSC.Colors.tertiary)
                                }
                                .buttonStyle(.plain)
                                .help("Open quick start guide")

                                Spacer()
                            }
                            .padding(.bottom, MSC.Spacing.xs)

                            // Wrap the picker in an accent-tinted container.
                            // This is the closest we can get to "selected server highlight"
                            // with a system .menu Picker — the container signals identity color.
                            Picker("", selection: selectedServerBinding) {
                                ForEach(viewModel.servers) { server in
                                    Label(server.name, systemImage: serverFlavorIcon(server))
                                        .tag(server as Server?)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .padding(.horizontal, MSC.Spacing.xs)
                            .padding(.vertical, MSC.Spacing.xxs)
                            .background(
                                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                                    .fill(MSC.Colors.accent(from: bannerColor, opacity: 0.12))
                            )

                            HStack(spacing: MSC.Spacing.sm) {
                                Button {
                                    if viewModel.isServerRunning {
                                        viewModel.stopServer()
                                    } else {
                                        viewModel.startServer()
                                        if OnboardingManager.shared.isActive,
                                           OnboardingManager.shared.currentStep == .startButton {
                                            OnboardingManager.shared.advance()
                                        }
                                    }
                                } label: {
                                    Label(
                                        viewModel.isServerRunning ? "Stop" : viewModel.startActionTitleForSelectedServer,
                                        systemImage: viewModel.isServerRunning ? "stop.circle" : "play.circle"
                                    )
                                }
                                .buttonStyle(
                                    MSCActionButtonStyle(
                                        color: viewModel.isServerRunning ? .red : .green
                                    )
                                )
                                .controlSize(.small)
                                .disabled(viewModel.selectedServer == nil)
                                .onboardingAnchor(.startButton)

                                Button {
                                    isShowingKillJavaProcessConfirm = true
                                } label: {
                                    Image(systemName: "exclamationmark.octagon")
                                }
                                .buttonStyle(MSCSecondaryButtonStyle())
                                .controlSize(.small)
                                .disabled(viewModel.selectedServer == nil)

                                Spacer()

                                Button("Manage\u{2026}") {
                                    isShowingManageServers = true
                                }
                                .buttonStyle(MSCSecondaryButtonStyle())
                                .controlSize(.small)
                                .onboardingAnchor(.manageServersButton)
                            }
                        }

                        // CROSS-PLATFORM ACCESS — collapsible, no Divider separators
                        if showCrossPlatform {
                            SidebarDisclosureSection(
                                title: "Console Access",
                                headerAnchorID: crossPlatformHeaderAnchorID,
                                isExpanded: $isCrossPlatformExpanded,
                                helpAction: {
                                    startSidebarGuide(
                                        crossPlatformHelpGuide,
                                        initialAnchorID: crossPlatformHeaderAnchorID,
                                        scrollProxy: scrollProxy
                                    ) {
                                        isCrossPlatformExpanded = true
                                    }
                                },
                                setupGuideAction: {
                                    viewModel.isShowingCrossPlatformGuide = true
                                }
                            ) {
                                if serverTypeForCrossPlay == .bedrock {
                                    BedrockCrossPlatformSidebarSection()
                                        .environmentObject(viewModel)
                                        .contextualHelpAnchor(crossPlatformContentAnchorID)
                                        .id(crossPlatformContentAnchorID)
                                } else {
                                    CrossPlatformAccessSidebarSection()
                                        .environmentObject(viewModel)
                                        .contextualHelpAnchor(crossPlatformContentAnchorID)
                                        .id(crossPlatformContentAnchorID)
                                }
                            }
                        }

                        // HOW TO CONNECT — collapsible connection-address reference
                        if viewModel.selectedServer != nil {
                            SidebarDisclosureSection(
                                title: "How to Connect",
                                headerAnchorID: "sidebar.howToConnect.header",
                                isExpanded: $isHowToConnectExpanded
                            ) {
                                HowToConnectSidebarSection()
                                    .environmentObject(viewModel)
                            }
                        }

                        // MAINTENANCE — collapsible
                        SidebarDisclosureSection(
                            title: "Maintenance",
                            headerAnchorID: maintenanceHeaderAnchorID,
                            isExpanded: $isMaintenanceExpanded,
                            helpAction: {
                                startSidebarGuide(
                                    maintenanceHelpGuide,
                                    initialAnchorID: maintenanceHeaderAnchorID,
                                    scrollProxy: scrollProxy
                                ) {
                                    isMaintenanceExpanded = true
                                }
                            }
                        ) {
                            HStack(spacing: 6) {
                                let isJavaServer = viewModel.selectedServer
                                    .flatMap { viewModel.configServer(for: $0) }?.isJava ?? true
                                if isJavaServer {
                                    MaintenanceButton(icon: "shippingbox", label: "Archives") {
                                        isShowingPaperTemplate = true
                                    }
                                }
                                MaintenanceButton(icon: "folder", label: "Directory") {
                                    viewModel.openSelectedServerFolder()
                                }
                                .disabled(viewModel.selectedServer == nil)

                                MaintenanceButton(icon: "doc.text", label: "Logs") {
                                    viewModel.openSelectedLogsFolder()
                                }
                                .disabled(viewModel.selectedServer == nil)
                            }
                            .contextualHelpAnchor(maintenanceButtonsAnchorID)
                            .id(maintenanceButtonsAnchorID)
                        }

                        // QUICK COMMANDS — collapsible
                        SidebarDisclosureSection(
                            title: "Quick Commands",
                            headerAnchorID: quickCommandsHeaderAnchorID,
                            isExpanded: $isQuickCommandsExpanded,
                            helpAction: {
                                startSidebarGuide(
                                    quickCommandsHelpGuide,
                                    initialAnchorID: quickCommandsHeaderAnchorID,
                                    scrollProxy: scrollProxy
                                ) {
                                    isQuickCommandsExpanded = true
                                }
                            }
                        ) {
                            QuickCommandsView(
                                controlsAnchorID: quickCommandsControlsAnchorID,
                                runningStateAnchorID: quickCommandsStateAnchorID
                            )
                                .environmentObject(viewModel)
                        }
                    }
                    .padding(.horizontal, MSC.Spacing.md)
                    .padding(.top, MSC.Spacing.lg)
                    .padding(.bottom, MSC.Spacing.sm)
                }
                .onChange(of: contextualHelp.currentStep?.anchorID) { _, _ in
                    scrollActiveSidebarHelpIfNeeded(using: scrollProxy)
                }
                .onChange(of: contextualHelp.isActive) { _, isActive in
                    guard isActive else { return }
                    scrollActiveSidebarHelpIfNeeded(using: scrollProxy)
                }
            }
            .frame(maxHeight: .infinity)

            PlayerAvatarView()
                .padding(.horizontal, MSC.Spacing.md)
                .padding(.bottom, MSC.Spacing.lg)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(MSC.Colors.tierChrome)  // Tier B flat chrome rail
        .alert("Kill Java Process?", isPresented: $isShowingKillJavaProcessConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Kill Java Process", role: .destructive) {
                viewModel.killJavaServerProcesses()
            }
        } message: {
            Text("Killing a Java process will turn your server off if it’s intentionally running. Are you sure?")
        }
        .contextualHelpHost(guideIDs: contextualHelpGuideIDs)
    }
}

// MARK: - Sidebar Disclosure Section

private struct SidebarDisclosureSection<Content: View>: View {
    let title: String
    let headerAnchorID: String
    @Binding var isExpanded: Bool
    var helpAction: (() -> Void)? = nil
    var setupGuideAction: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            // Smaller tertiary chevron
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(MSC.Colors.tertiary)

                            // Overline label in uppercase with secondary color
                            Text(title.uppercased())
                                .font(MSC.Typography.overlineLabel)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    if let helpAction = helpAction {
                        Button {
                            helpAction()
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 10))
                                .foregroundStyle(MSC.Colors.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Explain \(title)")
                    }

                    if let setupGuideAction = setupGuideAction {
                        Button {
                            setupGuideAction()
                        } label: {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 10))
                                .foregroundStyle(MSC.Colors.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Setup guide")
                    }
                }
                .fixedSize()
                .contextualHelpAnchor(headerAnchorID)
                .id(headerAnchorID)

                Spacer(minLength: 0)
            }

            if isExpanded {
                content()
                    .padding(.top, MSC.Spacing.sm)
            }
        }
    }
}

// MARK: - Bedrock Cross-Platform Sidebar Section

struct BedrockCrossPlatformSidebarSection: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var showingInfoPopover = false

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {
            VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                HStack(spacing: 4) {
                    Text("Xbox Broadcast").font(MSC.Typography.cardTitle)
                    Button {
                        showingInfoPopover.toggle()
                    } label: {
                        Image(systemName: "info.circle").imageScale(.small).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingInfoPopover, arrowEdge: .trailing) {
                        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                            Text("Xbox Broadcast").font(MSC.Typography.sectionHeader)
                            Text("Runs a background process that broadcasts your BDS server to Xbox friends via a Microsoft alt account.")
                                .font(MSC.Typography.caption).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(MSC.Spacing.md).frame(width: 220)
                    }
                }

                HStack(spacing: MSC.Spacing.sm) {
                    MSCStatusDot(
                        color: viewModel.isBedrockBroadcastRunning ? MSC.Colors.success : MSC.Colors.neutral,
                        label: viewModel.isBedrockBroadcastRunning ? "Running" : "Stopped"
                    )
                    Spacer()
                    Button(viewModel.isBedrockBroadcastRunning ? "Stop" : "Start") {
                        if viewModel.isBedrockBroadcastRunning { viewModel.stopBedrockBroadcast() }
                        else { viewModel.startBedrockBroadcast() }
                    }
                    .controlSize(.small)
                }
            }
            .contextualHelpAnchor("sidebar.crossPlatform.content")
            .id("sidebar.crossPlatform.content")

            HStack {
                Text("Xbox Broadcast auto-start").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { viewModel.selectedServerXboxBroadcastEnabled },
                    set: { viewModel.selectedServerXboxBroadcastEnabled = $0 }
                ))
                .labelsHidden().toggleStyle(.switch).controlSize(.mini)
            }
            .padding(.horizontal, MSC.Spacing.xs)
            .padding(.vertical, MSC.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                    .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.15))
            )
            .contextualHelpAnchor("sidebar.crossPlatform.autoStart")
            .id("sidebar.crossPlatform.autoStart")
        }
    }
}

// MARK: - Maintenance Button

private struct MaintenanceButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(.secondary)
                Text(label).font(.system(size: 10, weight: .medium)).multilineTextAlignment(.center).lineLimit(2)
            }
        }
        .buttonStyle(MSCCompactButtonStyle())
    }
}

// MARK: - Xbox Broadcast Sidebar Row

struct XboxBroadcastSidebarRow: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var showingInfoPopover = false

    var notInstalledHint: String = "Set up in Edit Server \u{2192} Broadcast"

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
            HStack(spacing: 4) {
                Text("Xbox Broadcast").font(MSC.Typography.cardTitle)
                Button {
                    showingInfoPopover.toggle()
                } label: {
                    Image(systemName: "info.circle").imageScale(.small).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingInfoPopover, arrowEdge: .trailing) {
                    VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                        Text("Xbox Broadcast").font(MSC.Typography.sectionHeader)
                        Text("Broadcasts your server to Xbox friends via a Microsoft alt account.")
                            .font(MSC.Typography.caption).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(MSC.Spacing.md).frame(width: 220)
                }
            }

            if viewModel.isXboxBroadcastHelperInstalled {
                HStack(spacing: MSC.Spacing.sm) {
                    MSCStatusDot(
                        color: viewModel.isXboxBroadcastRunning ? MSC.Colors.success : MSC.Colors.neutral,
                        label: viewModel.isXboxBroadcastRunning ? "Running" : "Stopped"
                    )
                    Spacer()
                    Button(viewModel.isXboxBroadcastRunning ? "Stop" : "Start") {
                        if viewModel.isXboxBroadcastRunning { viewModel.stopXboxBroadcast() }
                        else { viewModel.startXboxBroadcast() }
                    }
                    .controlSize(.small)
                }
            } else {
                Text(notInstalledHint)
                    .font(MSC.Typography.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Cross-Platform Access Sidebar Section (Java)

struct CrossPlatformAccessSidebarSection: View {
    @EnvironmentObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {
            XboxBroadcastSidebarRow().environmentObject(viewModel)

            if viewModel.isXboxBroadcastHelperInstalled {
                HStack {
                    Text("Xbox Broadcast auto-start").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { viewModel.selectedServerXboxBroadcastEnabled },
                        set: { viewModel.selectedServerXboxBroadcastEnabled = $0 }
                    ))
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                }
                .padding(.horizontal, MSC.Spacing.xs)
                .padding(.vertical, MSC.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                        .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.15))
                )
                .contextualHelpAnchor("sidebar.crossPlatform.autoStart")
                .id("sidebar.crossPlatform.autoStart")
            }
        }
    }
}

// MARK: - How to Connect Sidebar Section

/// Compact, per-method connection-address reference for the selected server.
/// Rows stack vertically (never side-by-side) so a narrow sidebar doesn't cramp;
/// long addresses truncate in the middle but copy in full. Only methods that
/// actually exist are shown. Masking shares the global reveal toggle with the
/// Overview "Connection Info" card.
struct HowToConnectSidebarSection: View {
    @EnvironmentObject var viewModel: AppViewModel

    private struct Row: Identifiable {
        let id = UUID()
        let icon: String
        let color: Color
        let label: String
        let value: String
    }

    private var cfg: ConfigServer? {
        viewModel.selectedServer.flatMap { viewModel.configServer(for: $0) }
    }

    private var rows: [Row] {
        guard let cfg else { return [] }
        var out: [Row] = []
        let localIP = AppUtilities.localIPAddress()
        let usePlayitAddresses = cfg.playitEnabled
        let showJava = !cfg.isBedrock
        let showBedrock = cfg.isBedrock
            || (usePlayitAddresses && viewModel.playitBedrockAddress != nil)
            || cfg.bedrockPort != nil
            || cfg.xboxBroadcastEnabled

        if showJava {
            if let ip = localIP {
                out.append(Row(icon: "cup.and.saucer.fill", color: .orange,
                               label: "Java \u{00B7} same Wi-Fi",
                               value: "\(ip):\(viewModel.javaPortForDisplay)"))
            }
            if usePlayitAddresses, let playit = viewModel.playitJavaAddress {
                out.append(Row(icon: "globe", color: .blue,
                               label: "Java \u{00B7} anywhere",
                               value: playit))
            } else if let pub = viewModel.cachedPublicIPAddress {
                out.append(Row(icon: "globe", color: .blue,
                               label: "Java \u{00B7} public",
                               value: "\(pub):\(viewModel.javaPortForDisplay)"))
            }
        }
        if showBedrock {
            let bport = cfg.bedrockPort.map(String.init) ?? "19132"
            if let ip = localIP {
                out.append(Row(icon: "cube.fill", color: .green,
                               label: "Bedrock \u{00B7} same Wi-Fi",
                               value: "\(ip):\(bport)"))
            }
            if usePlayitAddresses, let playitB = viewModel.playitBedrockAddress {
                out.append(Row(icon: "globe", color: .blue,
                               label: "Bedrock \u{00B7} anywhere",
                               value: playitB))
            } else if let pub = viewModel.cachedPublicIPAddress {
                out.append(Row(icon: "globe", color: .blue,
                               label: "Bedrock \u{00B7} public",
                               value: "\(pub):\(bport)"))
            }
        }
        if cfg.xboxBroadcastEnabled,
           let tag = cfg.xboxBroadcastAltGamertag?.trimmingCharacters(in: .whitespacesAndNewlines),
           !tag.isEmpty {
            out.append(Row(icon: "gamecontroller.fill", color: .green,
                           label: "Xbox \u{00B7} add friend",
                           value: tag))
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
            if rows.isEmpty {
                Text("No connection info yet. Start the server once to set up tunnels.")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 6) {
                    Button {
                        viewModel.showConnectionAddresses.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: viewModel.showConnectionAddresses ? "eye.slash" : "eye")
                            Text(viewModel.showConnectionAddresses ? "Hide" : "Show")
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(viewModel.showConnectionAddresses ? "Hide addresses" : "Show addresses")
                    Spacer(minLength: 0)
                }

                ForEach(rows) { row in
                    rowView(row)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: row.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(row.color)
                    .frame(width: 14)
                Text(row.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                Text(viewModel.showConnectionAddresses ? row.value : String(repeating: "\u{2022}", count: 12))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(row.value, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy \(row.value)")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                    .fill(row.color.opacity(0.08))
            )
        }
    }
}

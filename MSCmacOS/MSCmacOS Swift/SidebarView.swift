//
//  SidebarView.swift
//  MinecraftServerController
//
//  Primary server-control sidebar for selection, start/stop, maintenance,
//  quick commands, and cross-platform access shortcuts.
//

import SwiftUI

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
        serverTypeForCrossPlay != nil
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
                    title: "Cross-Platform Access",
                    body: isBedrockServer
                        ? "This is a compact Bedrock access summary for the selected server. It is meant for quick checks and quick toggles, not full setup."
                        : "This is a compact cross-platform summary for the selected Java server. It gives you quick visibility into the helpers that make Bedrock or console-friendly access possible.",
                    anchorID: crossPlatformHeaderAnchorID
                ),
                sidebarHelpStep(
                    id: "crossPlatform.content",
                    title: isBedrockServer ? "What lives here" : "What lives here",
                    body: isBedrockServer
                        ? "For Bedrock servers, this section stays focused on Bedrock Connect status, DNS details, and whether the helper is installed."
                        : "For Java servers, this section summarizes Xbox Broadcast and Bedrock Connect so you can see what is installed and start or stop those helpers without leaving the sidebar.",
                    anchorID: crossPlatformContentAnchorID
                ),
                sidebarHelpStep(
                    id: "crossPlatform.autostart",
                    title: "Auto-start and deeper setup",
                    body: isBedrockServer
                        ? "If Bedrock Connect is installed, you can let it auto-start with the server here. If it is not installed yet, use Edit Server or Components for the real setup work."
                        : "If a helper is installed, you can let it auto-start with the server here. Use Edit Server for the deeper setup path, because this sidebar section is only the quick-control surface.",
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
                        ? "Jars opens the Java runtime/template path, while Server Folder and Logs open the server's local files. For routine use, folder and logs are the most common shortcuts."
                        : "For Bedrock servers, this section stays focused on local file access like the server folder and logs. The Jars shortcut is intentionally not shown here because it is a Java-only path.",
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
                                    Text(server.name).tag(server as Server?)
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
                                        viewModel.isServerRunning ? "Stop" : viewModel.startButtonTitleForSelectedServer,
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
                                title: "Cross-Platform Access",
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
                                    MaintenanceButton(icon: "shippingbox", label: "Jars") {
                                        isShowingPaperTemplate = true
                                    }
                                }
                                MaintenanceButton(icon: "folder", label: "Server Folder") {
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
    let helpAction: () -> Void
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

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {
            BedrockConnectSidebarRow().environmentObject(viewModel)

            if viewModel.isBedrockConnectJarInstalled {
                HStack {
                    Text("Bedrock Connect auto-start").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { viewModel.bedrockConnectAutoStartEnabled },
                        set: { viewModel.bedrockConnectAutoStartEnabled = $0 }
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
                        Text("Broadcasts your Bedrock server to Xbox friends via a Microsoft alt account. No port-forwarding needed.")
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
                Text("Set up in Edit Server \u{2192} Broadcast")
                    .font(MSC.Typography.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Bedrock Connect Sidebar Row

struct BedrockConnectSidebarRow: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var showingInfoPopover = false

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
            HStack(spacing: 4) {
                Text("Bedrock Connect").font(MSC.Typography.cardTitle)
                Button {
                    showingInfoPopover.toggle()
                } label: {
                    Image(systemName: "info.circle").imageScale(.small).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingInfoPopover, arrowEdge: .trailing) {
                    VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                        Text("Bedrock Connect").font(MSC.Typography.sectionHeader)
                        Text("Intercepts the Mojang server list on your network via DNS, replacing it with your own servers. Requires a DNS change on your router or console.")
                            .font(MSC.Typography.caption).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(MSC.Spacing.md).frame(width: 220)
                }
            }

            if viewModel.isBedrockConnectJarInstalled {
                HStack(spacing: MSC.Spacing.sm) {
                    MSCStatusDot(
                        color: viewModel.isBedrockConnectRunning ? MSC.Colors.success : MSC.Colors.neutral,
                        label: viewModel.isBedrockConnectRunning ? "Running" : "Stopped"
                    )
                    Spacer()
                    Button(viewModel.isBedrockConnectRunning ? "Stop" : "Start") {
                        if viewModel.isBedrockConnectRunning { viewModel.stopBedrockConnect() }
                        else { viewModel.startBedrockConnect() }
                    }
                    .controlSize(.small)
                }
            } else {
                Text("Set up in Edit Server \u{2192} Bedrock Connect")
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
            BedrockConnectSidebarRow().environmentObject(viewModel)

            let eitherInstalled = viewModel.isXboxBroadcastHelperInstalled || viewModel.isBedrockConnectJarInstalled
            if eitherInstalled {
                VStack(spacing: 4) {
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
                    }
                    if viewModel.isBedrockConnectJarInstalled {
                        HStack {
                            Text("Bedrock Connect auto-start").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { viewModel.bedrockConnectAutoStartEnabled },
                                set: { viewModel.bedrockConnectAutoStartEnabled = $0 }
                            ))
                            .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                        }
                    }
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

//
//  ContentView.swift
//  MinecraftServerController
//
//  Main macOS app shell: banner, sidebar, details workspace, console, and
//  shared app-level sheets above the workspace.
//

import SwiftUI
import SpriteKit
import WebKit
#if os(macOS)
import AppKit
#endif

// MARK: - Vibrancy background
//
// Wraps NSVisualEffectView with behindWindow blending so the dark Tier A
// color gains the same "smoked glass alive with the desktop" quality that
// Perplexity and Linear have. The Tier A color sits on top at ~82% opacity —
// dark enough to read as solid, light enough for the vibrancy to breathe.

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .underWindowBackground
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Banner color helpers

fileprivate let defaultBannerColor = Color(red: 30/255, green: 30/255, blue: 30/255)

extension Color {
    /// Clamps very-near-white colors to a pale gray so the accent wash stays visible
    /// on the dark chrome shell. Preserves all other colors untouched.
    func clampedAwayFromWhite() -> Color {
        #if os(macOS)
        let ns = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor(self)
        let r = ns.redComponent
        let g = ns.greenComponent
        let b = ns.blueComponent
        let isVeryCloseToWhite = (r > 0.96 && g > 0.96 && b > 0.96)
        if isVeryCloseToWhite {
            let adjusted = NSColor(calibratedRed: 0.92, green: 0.92, blue: 0.92, alpha: 1.0)
            return Color(adjusted)
        } else {
            return self
        }
        #else
        return self
        #endif
    }

    /// Clamps very-dark colors (perceived luminance < 0.05) to a neutral medium gray
    /// so accent washes on the chrome shell are perceptible rather than invisible.
    /// Pure-black or near-black banner colors are replaced with a cool mid-gray accent.
    func clampedAwayFromBlack() -> Color {
        #if os(macOS)
        let ns = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor(self)
        let r = ns.redComponent
        let g = ns.greenComponent
        let b = ns.blueComponent
        // Standard perceived luminance (ITU-R BT.709)
        let luminance = 0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)
        if luminance < 0.05 {
            // Fall back to a cool medium gray — visible on dark chrome without overpowering
            return Color(red: 0.40, green: 0.40, blue: 0.48)
        } else {
            return self
        }
        #else
        return self
        #endif
    }

    func toSKColor() -> SKColor {
        #if os(macOS)
        let ns = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor(self)
        return SKColor(cgColor: ns.cgColor) ?? SKColor.black
        #else
        let ui = UIColor(self)
        return SKColor(cgColor: ui.cgColor)!
        #endif
    }

    init?(hexRGB: String) {
        var s = hexRGB.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 else { return nil }
        guard let value = UInt32(s, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }

    func hexRGBString() -> String? {
        #if os(macOS)
        let ns = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor(self)
        let r = Int(round(ns.redComponent * 255.0))
        let g = Int(round(ns.greenComponent * 255.0))
        let b = Int(round(ns.blueComponent * 255.0))
        func twoHex(_ value: Int) -> String {
            let clamped = max(0, min(255, value))
            let s = String(clamped, radix: 16, uppercase: true)
            return s.count == 1 ? "0\(s)" : s
        }
        return "#\(twoHex(r))\(twoHex(g))\(twoHex(b))"
        #else
        return nil
        #endif
    }
}

private extension View {
    @ViewBuilder
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var viewModel: AppViewModel

    @State private var bannerColor: Color = defaultBannerColor

    // Sheet toggles — only those not moved into tabs
    @State private var isShowingPluginTemplates = false
    @State private var isShowingPaperTemplates = false
    @State private var isShowingManageServers = false
    @State private var isShowingHelpPopover = false

    // Draggable console split
    @State private var consoleSplitFraction: CGFloat = 0.7

    // Collapsible / resizable panels (persisted across launches)
    @AppStorage("msc.isSidebarCollapsed") private var isSidebarCollapsed = false
    @AppStorage("msc.sidebarWidth") private var sidebarWidth: Double = 280
    @AppStorage("msc.isConsoleHidden") private var isConsoleHidden = false

    // Per-drag baselines (captured at gesture start so translation isn't double-counted)
    @State private var sidebarWidthAtDragStart: CGFloat? = nil
    @State private var consoleFractionAtDragStart: CGFloat? = nil

    private let minSidebarWidth: CGFloat = 220
    private let maxSidebarWidth: CGFloat = 360
    private let sidebarCollapseThreshold: CGFloat = 190

    private var prerequisitesBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isShowingPrerequisites },
            set: { viewModel.isShowingPrerequisites = $0 }
        )
    }

    private var initialSetupBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isShowingInitialSetup },
            set: { viewModel.isShowingInitialSetup = $0 }
        )
    }

    private var preferencesBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isShowingPreferences },
            set: { viewModel.isShowingPreferences = $0 }
        )
    }

    private var serverHandbookBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isShowingServerHandbook },
            set: { viewModel.isShowingServerHandbook = $0 }
        )
    }

    private var conceptGuideBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isShowingConceptGuide },
            set: { viewModel.isShowingConceptGuide = $0 }
        )
    }

    private var routerPortForwardGuideBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isShowingRouterPortForwardGuide },
            set: { viewModel.isShowingRouterPortForwardGuide = $0 }
        )
    }

    private var crossPlatformGuideBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isShowingCrossPlatformGuide },
            set: { viewModel.isShowingCrossPlatformGuide = $0 }
        )
    }

    // MARK: - Collapsible panel helpers

    private var detailsPane: some View {
        DetailsView(
            isShowingManageServers: $isShowingManageServers,
            isShowingPluginTemplates: $isShowingPluginTemplates,
            isShowingPaperTemplate: $isShowingPaperTemplates,
            bannerColor: bannerColor
        )
        .environmentObject(viewModel)
    }

    /// Draggable divider between the sidebar and the main content.
    /// Resizes within [min, max]; dragging well past the minimum collapses the sidebar.
    private var sidebarResizeHandle: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 7)
                    .contentShape(Rectangle())
            )
            .cursor(.resizeLeftRight)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if sidebarWidthAtDragStart == nil { sidebarWidthAtDragStart = CGFloat(sidebarWidth) }
                        let base = sidebarWidthAtDragStart ?? CGFloat(sidebarWidth)
                        let proposed = base + value.translation.width
                        sidebarWidth = Double(min(maxSidebarWidth, max(minSidebarWidth, proposed)))
                    }
                    .onEnded { value in
                        let base = sidebarWidthAtDragStart ?? CGFloat(sidebarWidth)
                        let proposed = base + value.translation.width
                        sidebarWidthAtDragStart = nil
                        if proposed < sidebarCollapseThreshold {
                            withAnimation(.easeInOut(duration: 0.2)) { isSidebarCollapsed = true }
                        }
                    }
            )
    }

    /// Slim rail shown in place of the sidebar when collapsed — click to bring it back.
    private var sidebarRestoreRail: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { isSidebarCollapsed = false }
        } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.55))
                .frame(width: 18)
                .frame(maxHeight: .infinity)
                .background(MSC.Colors.tierChrome)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show sidebar (⌥⌘S)")
        .cursor(.pointingHand)
    }

    /// Slim bar shown in place of the console when hidden — click to bring it back.
    private var consoleRestoreBar: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { isConsoleHidden = false }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                Text("Console")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
            }
            .foregroundColor(.white.opacity(0.55))
            .padding(.horizontal, 12)
            .frame(height: 24)
            .frame(maxWidth: .infinity)
            .background(MSC.Colors.tierChrome)
            .overlay(alignment: .top) {
                Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show console (⌥⌘J)")
        .cursor(.pointingHand)
    }

    /// Draggable divider between the main content and the console.
    /// Resizes the split; dragging well past the console minimum hides it entirely.
    private func consoleDivider(totalHeight: CGFloat, minDetailsHeight: CGFloat, minConsoleHeight: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
            Capsule()
                .fill(Color(nsColor: .tertiaryLabelColor))
                .frame(width: 36, height: 4)
        }
        .frame(height: 8)
        .contentShape(Rectangle())
        .cursor(.resizeUpDown)
        .onboardingAnchor(.consoleDividerHandle)
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if consoleFractionAtDragStart == nil { consoleFractionAtDragStart = consoleSplitFraction }
                    let baseFraction = consoleFractionAtDragStart ?? consoleSplitFraction
                    let clampedBase = max(minDetailsHeight / totalHeight, min(1.0 - minConsoleHeight / totalHeight, baseFraction))
                    let baseDetails = totalHeight * clampedBase
                    let newFraction = (baseDetails + value.translation.height) / totalHeight
                    consoleSplitFraction = max(
                        minDetailsHeight / totalHeight,
                        min(1.0 - minConsoleHeight / totalHeight, newFraction)
                    )
                }
                .onEnded { value in
                    let baseFraction = consoleFractionAtDragStart ?? consoleSplitFraction
                    consoleFractionAtDragStart = nil
                    let clampedBase = max(minDetailsHeight / totalHeight, min(1.0 - minConsoleHeight / totalHeight, baseFraction))
                    let baseDetails = totalHeight * clampedBase
                    let proposedConsole = totalHeight - (baseDetails + value.translation.height)
                    if proposedConsole < minConsoleHeight * 0.5 {
                        withAnimation(.easeInOut(duration: 0.2)) { isConsoleHidden = true }
                    }
                }
        )
    }

    var body: some View {
        VStack(spacing: 0) {

            // TOP BANNER — restrained premium finish, not a redesign.
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.100, green: 0.100, blue: 0.118),
                        MSC.Colors.tierChrome
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                MSC.Colors.accent(from: bannerColor, opacity: 0.16)

                RadialGradient(
                    colors: [
                        MSC.Colors.accent(from: bannerColor, opacity: 0.22),
                        Color.clear
                    ],
                    center: .topTrailing,
                    startRadius: 12,
                    endRadius: 220
                )

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.12),
                        Color.white.opacity(0.03),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.62)
                )

                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.white.opacity(0.07))
                        .frame(height: 0.5)
                    Spacer()
                    Rectangle()
                        .fill(Color.black.opacity(0.22))
                        .frame(height: 0.5)
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Minecraft Server Controller")
                            .font(MSC.Typography.shellTitle)
                            .foregroundColor(.white)
                        Text("by TempleTech")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.45))
                    }

                    if viewModel.isServerRunning {
                        RunnerBannerView(
                            isRunning: viewModel.isServerRunning,
                            bannerColor: bannerColor
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Spacer()
                    }

                    HStack(spacing: 10) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { isSidebarCollapsed.toggle() }
                        } label: {
                            Image(systemName: "sidebar.left")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .buttonStyle(MSCGhostIconButtonStyle(size: 30))
                        .keyboardShortcut("s", modifiers: [.command, .option])
                        .help(isSidebarCollapsed ? "Show sidebar (⌥⌘S)" : "Hide sidebar (⌥⌘S)")

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { isConsoleHidden.toggle() }
                        } label: {
                            Image(systemName: "square.bottomthird.inset.filled")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .buttonStyle(MSCGhostIconButtonStyle(size: 30))
                        .keyboardShortcut("j", modifiers: [.command, .option])
                        .help(isConsoleHidden ? "Show console (⌥⌘J)" : "Hide console (⌥⌘J)")

                        Button {
                            isShowingHelpPopover.toggle()
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .buttonStyle(MSCGhostIconButtonStyle(size: 30))
                        .help("Help & guides")
                        .popover(isPresented: $isShowingHelpPopover, arrowEdge: .bottom) {
                            ToolbarHelpPopover(isPresented: $isShowingHelpPopover)
                                .environmentObject(viewModel)
                        }

                        Button {
                            viewModel.isShowingPreferences = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .buttonStyle(MSCGhostIconButtonStyle(size: 30))
                        .help("Preferences")

                        Button {
                            viewModel.refreshController()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .buttonStyle(MSCGhostIconButtonStyle(size: 30))
                        .keyboardShortcut("r", modifiers: .command)
                        .help("Refresh controller (⌘R)")
                        .disabled(viewModel.selectedServer == nil)
                    }
                }
                .padding(.horizontal, MSC.Spacing.xxl)
                .padding(.vertical, 10)
            }
            .frame(height: 66)

            Divider()

            if viewModel.showCrashRecoveryBanner {
                CrashRecoveryBanner()
                    .environmentObject(viewModel)
                Divider()
            }

            if viewModel.orphanedJavaProcessCount > 0 {
                OrphanedProcessBanner(count: viewModel.orphanedJavaProcessCount)
                    .environmentObject(viewModel)
                Divider()
            }

            // Main split
            HStack(spacing: 0) {

                // Sidebar — fixed intrinsic width on the inside, revealed by an outer
                // frame that animates to 0 on collapse. This clips (rather than compresses)
                // the content, so the avatar slides out at full size instead of smooshing.
                SidebarView(
                    isShowingPluginTemplates: $isShowingPluginTemplates,
                    isShowingPaperTemplate: $isShowingPaperTemplates,
                    isShowingManageServers: $isShowingManageServers,
                    bannerColor: bannerColor
                )
                .environmentObject(viewModel)
                .frame(width: CGFloat(sidebarWidth), alignment: .leading)
                .frame(width: isSidebarCollapsed ? 0 : CGFloat(sidebarWidth), alignment: .leading)
                .clipped()
                .allowsHitTesting(!isSidebarCollapsed)

                if isSidebarCollapsed {
                    sidebarRestoreRail
                } else {
                    sidebarResizeHandle
                }

                GeometryReader { geo in
                    let minDetailsHeight: CGFloat = 320
                    let compactConsoleHeight: CGFloat = 125
                    let minConsoleHeight: CGFloat = compactConsoleHeight
                    let totalHeight = geo.size.height

                    VStack(spacing: 0) {
                        if isConsoleHidden {
                            detailsPane
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            consoleRestoreBar
                        } else {
                            let clampedFraction = max(
                                minDetailsHeight / totalHeight,
                                min(1.0 - minConsoleHeight / totalHeight, consoleSplitFraction)
                            )
                            let detailsHeight = totalHeight * clampedFraction
                            let consoleHeight = totalHeight - detailsHeight
                            let consoleIsCollapsed = consoleHeight <= compactConsoleHeight

                            detailsPane
                                .frame(height: detailsHeight)

                            consoleDivider(
                                totalHeight: totalHeight,
                                minDetailsHeight: minDetailsHeight,
                                minConsoleHeight: minConsoleHeight
                            )

                            ConsoleView(isCollapsed: consoleIsCollapsed)
                                .environmentObject(viewModel)
                                .frame(height: consoleHeight - 8)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: .infinity)
        }
        .coordinateSpace(name: "mscRoot")
        .frame(minWidth: 900, minHeight: 600)
        // NSVisualEffectView samples the desktop behind the window,
        // then Tier A sits on top at 82% — dark enough to read as solid, alive enough
        // to feel like smoked glass rather than a painted box.
        .background(
            ZStack {
                VisualEffectBackground()
                MSC.Colors.tierAtmosphere.opacity(0.82)
            }
            .ignoresSafeArea()
        )
        .contextualHelpHost(guideIDs: ["details.workspace"])
        .overlay {
            OnboardingOverlayView(
                ownedSteps: [
                    .welcome,
                    .manageServers,
                    .acceptEula,
                    .startButton,
                    .console,
                    .continueDetails,
                    .expandDetails,
                    .detailsOverviewTab,
                    .detailsPlayersTab,
                    .detailsWorldsTab,
                    .detailsPacksTab,
                    .detailsPerformanceTab,
                    .detailsComponentsTab,
                    .detailsSettingsTab,
                    .detailsFilesTab,
                    .done
                ]
            )
        }
        // Both banner color guard rails are active here
        .onAppear {
            if let server = viewModel.selectedServer,
               let cfgServer = viewModel.configServer(for: server),
               let hex = cfgServer.bannerColorHex,
               let color = Color(hexRGB: hex) {
                bannerColor = color.clampedAwayFromWhite().clampedAwayFromBlack()
            } else if let hex = viewModel.configManager.config.defaultBannerColorHex,
                      let color = Color(hexRGB: hex) {
                bannerColor = color.clampedAwayFromWhite().clampedAwayFromBlack()
            } else {
                bannerColor = defaultBannerColor
            }
            viewModel.syncTourAccentColor()
        }
        .onChange(of: viewModel.requestConsoleExpand) { _, shouldExpand in
            guard shouldExpand else { return }
            viewModel.requestConsoleExpand = false
            if isConsoleHidden { isConsoleHidden = false }
            if consoleSplitFraction > 0.80 {
                withAnimation(.easeInOut(duration: 0.25)) { consoleSplitFraction = 0.65 }
            }
        }
        .onChange(of: viewModel.resolvedAccentColor) { _, newColor in
                    bannerColor = newColor
                }
                .onChange(of: viewModel.selectedServer?.id) { _, _ in
            if let server = viewModel.selectedServer,
               let cfgServer = viewModel.configServer(for: server),
               let hex = cfgServer.bannerColorHex,
               let color = Color(hexRGB: hex) {
                bannerColor = color.clampedAwayFromWhite().clampedAwayFromBlack()
            } else if let hex = viewModel.configManager.config.defaultBannerColorHex,
                      let color = Color(hexRGB: hex) {
                bannerColor = color.clampedAwayFromWhite().clampedAwayFromBlack()
            } else {
                bannerColor = defaultBannerColor
            }
            viewModel.syncTourAccentColor()
        }

        // First-run setup wizard
        .sheet(isPresented: initialSetupBinding, onDismiss: {
            viewModel.handleInitialSetupDismissed()
        }) {
            SetupWizardView().environmentObject(viewModel)
        }

        // Paper templates
        .sheet(isPresented: $isShowingPaperTemplates) {
            PaperTemplateView(isPresented: $isShowingPaperTemplates)
                .environmentObject(viewModel)
        }

        // Plugin templates
        .sheet(isPresented: $isShowingPluginTemplates) {
            PluginTemplatesView(isPresented: $isShowingPluginTemplates)
                .environmentObject(viewModel)
        }

        // Manage servers
        .sheet(isPresented: $isShowingManageServers) {
            ManageServersView(isPresented: $isShowingManageServers)
                .environmentObject(viewModel)
        }

        // Preferences
        .sheet(isPresented: preferencesBinding) {
            MSCSettingsView().environmentObject(viewModel)
        }

        // Prerequisites
        .sheet(isPresented: prerequisitesBinding) {
            PrerequisitesView().environmentObject(viewModel)
        }

        // Concept Guide (visual mental model walkthrough — first-run + on-demand from Settings)
        .sheet(isPresented: conceptGuideBinding, onDismiss: {
            viewModel.handleConceptGuideDismissed()
        }) {
            ConceptGuideView()
                .environmentObject(viewModel)
        }

        // Server Handbook (long-form reference manual)
        .sheet(isPresented: serverHandbookBinding, onDismiss: {
            viewModel.handleHandbookDismissed()
        }) {
            ServerHandbookView()
                .environmentObject(viewModel)
        }

        // Router Port Forwarding Guide
        .sheet(isPresented: routerPortForwardGuideBinding) {
            RouterPortForwardGuideSheet(
                runtimeContext: viewModel.routerPortForwardGuideRuntimeContextForSelectedServer()
            )
            .environmentObject(viewModel)
        }

        // Cross-Platform Setup Guide (Xbox Broadcast)
        .sheet(isPresented: crossPlatformGuideBinding) {
            CrossPlatformGuideSheet()
                .environmentObject(viewModel)
        }

        // Xbox Broadcast auth sheet
        .sheet(item: $viewModel.pendingBroadcastAuthPrompt) { prompt in
            BroadcastAuthWebSheet(prompt: prompt).environmentObject(viewModel)
        }

        // playit.gg setup — shown on first use when no key is stored
        .sheet(isPresented: $viewModel.isShowingPlayitSecretSetup) {
            PlayitSetupSheet()
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $viewModel.isShowingStartupProblems) {
            StartupProblemsSheet(isPresented: $viewModel.isShowingStartupProblems)
                .environmentObject(viewModel)
        }

        // First-start alert
        .alert(item: $viewModel.firstStartNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("Got it"))
            )
        }

        // Offer to save the alt account after a successful Xbox broadcast sign-in.
        .sheet(item: $viewModel.pendingBroadcastGamertagSave) { prompt in
            BroadcastAltAccountSaveSheet(prompt: prompt).environmentObject(viewModel)
        }

        // Error alerts
        .alert(item: $viewModel.errorAlert) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }

        // Flow 1: SVC installed + playit on + voice tunnel off (three-button form)
        .alert("Simple Voice Chat needs a tunnel",
               isPresented: Binding(
                get: { viewModel.pendingSVCTunnelMismatch != nil },
                set: { if !$0 { viewModel.pendingSVCTunnelMismatch = nil } }
               )) {
            Button("Enable Tunnel") {
                if let id = viewModel.pendingSVCTunnelMismatch?.serverId {
                    viewModel.setPlayitEnabled(true, voiceChat: true, for: id)
                }
            }
            Button("Disable Voice Chat", role: .destructive) {
                if let id = viewModel.pendingSVCTunnelMismatch?.serverId {
                    viewModel.disableSVCPlugin(for: id)
                }
            }
            Button("Don\u{2019}t Ask Again", role: .cancel) {
                if let id = viewModel.pendingSVCTunnelMismatch?.serverId {
                    viewModel.dismissSVCTunnelMismatch(for: id)
                }
                viewModel.pendingSVCTunnelMismatch = nil
            }
        } message: {
            Text("Simple Voice Chat is enabled but its playit.gg tunnel is off. Players connecting via playit.gg won\u{2019}t be able to use voice chat.")
        }

        // Flow 2: port forwarding + SVC installed — remind user to forward UDP 24454
        .alert("Simple Voice Chat — Port Check",
               isPresented: Binding(
                get: { viewModel.pendingSVCPortForwardingPrompt != nil },
                set: { if !$0 { viewModel.pendingSVCPortForwardingPrompt = nil } }
               )) {
            Button("Yes, it\u{2019}s set up") {
                if let id = viewModel.pendingSVCPortForwardingPrompt?.serverId {
                    viewModel.confirmSVCPortForwarding(for: id)
                }
                viewModel.pendingSVCPortForwardingPrompt = nil
            }
            Button("Not yet", role: .cancel) {
                // "No" is not persisted — re-shown on next start
                viewModel.pendingSVCPortForwardingPrompt = nil
            }
        } message: {
            Text("Have you forwarded UDP port 24454 on your router for Simple Voice Chat? Players on different networks won\u{2019}t be able to connect to voice chat without it.")
        }

        // Bedrock tunnel missing — playit on + bedrock port set but no Bedrock tunnel created yet
        .alert("Bedrock Tunnel Not Set Up",
               isPresented: Binding(
                get: { viewModel.pendingBedrockTunnelMissing != nil },
                set: { if !$0 { viewModel.pendingBedrockTunnelMissing = nil } }
               )) {
            Button("Add Bedrock Tunnel") {
                viewModel.pendingBedrockTunnelMissing = nil
                viewModel.isShowingPlayitSecretSetup = true
            }
            Button("Not Now", role: .cancel) {
                viewModel.pendingBedrockTunnelMissing = nil
            }
        } message: {
            Text("A Bedrock port is configured but no Bedrock tunnel exists on your playit.gg account yet. Sign in to add it — your existing agent and Java tunnel will be reused.")
        }

        // Keep viewModel aware of ContentView-local sheets so broadcast auth
        // knows not to interrupt them.
        .onChange(of: isShowingManageServers || isShowingPaperTemplates || isShowingPluginTemplates) { _, anyLocal in
            viewModel.contentViewSheetIsPresented = anyLocal
        }

        // (R3) Corrupt-config recovery alert — on a separate Color.clear anchor per the
        // one-presentation-per-view rule; never conflicts with errorAlert above.
        .overlay {
            Color.clear
                .frame(width: 0, height: 0)
                .alert(item: $viewModel.configCorruptAlert) { alert in
                    Alert(
                        title: Text(alert.title),
                        message: Text(alert.message),
                        dismissButton: .default(Text("OK"))
                    )
                }
        }
    }
}

// MARK: - Banner / runner support moved to ContentViewRunnerSupport.swift

struct BroadcastAuthWebSheet: View {
    @EnvironmentObject var viewModel: AppViewModel
    let prompt: BroadcastAuthPrompt

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                    Text("Sign in to your broadcast alt account")
                        .font(MSC.Typography.pageTitle)
                    Text("Use the Microsoft account you keep as your Xbox alt. This is a private session — your personal accounts won't appear here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Done") {
                    viewModel.pendingBroadcastAuthPrompt = nil
                }
                .buttonStyle(MSCSecondaryButtonStyle())
            }
            .padding(MSC.Spacing.xl)

            Divider()

            MicrosoftDeviceCodeWebView(prompt: prompt) {
                viewModel.pendingBroadcastAuthPrompt = nil
            }
        }
        .frame(minWidth: 540, minHeight: 580)
    }
}

// MARK: - Save Alt Account Sheet (after Xbox broadcast sign-in)

/// Pops up after a successful broadcast sign-in so the user can save a record of
/// the alt/dummy account they used. The gamertag is prefilled from the auth log;
/// the email, password, and photo are entered here by the user (the app never
/// reads them from Microsoft's page). The password is stored in the Keychain.
struct BroadcastAltAccountSaveSheet: View {
    @EnvironmentObject var viewModel: AppViewModel
    let prompt: BroadcastGamertagSavePrompt

    @State private var email: String = ""
    @State private var gamertag: String = ""
    @State private var password: String = ""
    @State private var showPassword = false
    @State private var avatarPath: String = ""
    @State private var avatarImage: NSImage?
    @State private var didLoad = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: MSC.Spacing.md) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 24))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Save Alt Account")
                        .font(.system(size: 16, weight: .bold))
                    Text("Signed in as \(prompt.gamertag)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(MSC.Spacing.xl)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
                    Text("Keep a record of the alt/dummy account you use for Xbox broadcast so you don't lose it. Stored locally in this server's config; the password is kept in your Mac's Keychain. Enter the email and password yourself — the app never reads them from the Microsoft sign-in page.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: MSC.Spacing.md) {
                        ZStack {
                            if let img = avatarImage {
                                Image(nsImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 52, height: 52)
                                    .clipShape(Circle())
                            } else {
                                Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 52, height: 52)
                                Text(String(prompt.gamertag.prefix(1)).uppercased())
                                    .font(.title2.bold())
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        Button("Choose Photo…") { choosePhoto() }
                            .buttonStyle(MSCSecondaryButtonStyle())
                            .controlSize(.small)
                        Spacer()
                    }

                    labeledField("Email") {
                        TextField("email@example.com", text: $email)
                            .textFieldStyle(.roundedBorder)
                    }
                    labeledField("Gamertag") {
                        TextField("Gamertag", text: $gamertag)
                            .textFieldStyle(.roundedBorder)
                    }
                    labeledField("Password") {
                        HStack(spacing: MSC.Spacing.xs) {
                            if showPassword {
                                TextField("Password", text: $password)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                SecureField("Password", text: $password)
                                    .textFieldStyle(.roundedBorder)
                            }
                            Button {
                                showPassword.toggle()
                            } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .padding(MSC.Spacing.xl)
            }

            Divider()

            HStack {
                Button("Not Now") {
                    viewModel.broadcastGamertagSaveDeclinedServerIds.insert(prompt.serverId)
                    viewModel.pendingBroadcastGamertagSave = nil
                }
                .buttonStyle(MSCSecondaryButtonStyle())

                Spacer()

                Button("Save") { save() }
                    .buttonStyle(MSCPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, MSC.Spacing.xl)
            .padding(.vertical, MSC.Spacing.md)
        }
        .frame(width: 460, height: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: loadInitial)
    }

    @ViewBuilder
    private func labeledField<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12, weight: .semibold))
            content()
        }
    }

    private func loadInitial() {
        guard !didLoad else { return }
        didLoad = true
        gamertag = prompt.gamertag
        if let cfg = viewModel.configServer(id: prompt.serverId) {
            email = cfg.xboxBroadcastAltEmail ?? ""
            if let p = cfg.xboxBroadcastAltAvatarPath, !p.isEmpty {
                avatarPath = p
                avatarImage = NSImage(contentsOfFile: p)
            }
        }
        if let pw = KeychainManager.shared.readXboxBroadcastAltPassword(forServerId: prompt.serverId) {
            password = pw
        }
    }

    private func choosePhoto() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedFileTypes = ["png", "jpg", "jpeg", "heic", "gif"]
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            avatarPath = url.path
            avatarImage = NSImage(contentsOf: url)
        }
    }

    private func save() {
        let cfg = viewModel.configServer(id: prompt.serverId)
        viewModel.updateBroadcastProfile(
            for: prompt.serverId,
            enabled: cfg?.xboxBroadcastEnabled ?? true,
            ipMode: cfg?.xboxBroadcastIPMode ?? .auto,
            altEmail: email,
            altGamertag: gamertag,
            altPassword: password,
            altAvatarPath: avatarPath
        )
        viewModel.pendingBroadcastGamertagSave = nil
    }
}

struct MicrosoftDeviceCodeWebView: NSViewRepresentable {
    let prompt: BroadcastAuthPrompt
    let onComplete: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator

        var components = URLComponents(url: prompt.linkURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "otc", value: prompt.code))
        components.queryItems = items
        let url = components.url ?? prompt.linkURL
        webView.load(URLRequest(url: url))

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onComplete: () -> Void
        private var didComplete = false

        init(onComplete: @escaping () -> Void) { self.onComplete = onComplete }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !didComplete else { return }
            webView.evaluateJavaScript("document.querySelector('h1')?.textContent ?? ''") { [weak self] result, _ in
                guard let self, !self.didComplete else { return }
                let heading = (result as? String ?? "").lowercased()
                if heading.contains("all done") {
                    self.didComplete = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self.onComplete()
                    }
                }
            }
        }
    }
}

// MARK: - Orphaned Process Banner

private struct OrphanedProcessBanner: View {
    @EnvironmentObject var viewModel: AppViewModel
    let count: Int

    var body: some View {
        HStack(spacing: MSC.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 14, weight: .semibold))

            Text("\(count) orphaned Java server \(count == 1 ? "process" : "processes") detected from an unclean exit.")
                .font(.system(size: 13))
                .foregroundStyle(.primary)

            Spacer()

            Button("Kill All") {
                viewModel.killJavaServerProcesses()
                viewModel.orphanedJavaProcessCount = 0
            }
            .buttonStyle(MSCDestructiveButtonStyle())
            .controlSize(.small)

            Button("Dismiss") {
                viewModel.orphanedJavaProcessCount = 0
            }
            .buttonStyle(MSCSecondaryButtonStyle())
            .controlSize(.small)
        }
        .padding(.horizontal, MSC.Spacing.xxl)
        .padding(.vertical, MSC.Spacing.sm)
        .background(Color.orange.opacity(0.10))
    }
}

// MARK: - Crash Recovery Banner

private struct CrashRecoveryBanner: View {
    @EnvironmentObject var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: MSC.Spacing.md) {
            Image(systemName: "arrow.counterclockwise.circle.fill")
                .foregroundStyle(.blue)
                .font(.system(size: 14, weight: .semibold))

            Text("MSC recovered from an unexpected exit.")
                .font(.system(size: 13))
                .foregroundStyle(.primary)

            Spacer()

            if let ipsURL = latestMSCCrashReport() {
                Button("Reveal Crash Report") {
                    NSWorkspace.shared.activateFileViewerSelecting([ipsURL])
                    viewModel.showCrashRecoveryBanner = false
                }
                .buttonStyle(MSCSecondaryButtonStyle())
                .controlSize(.small)
            }

            Button("Dismiss") {
                viewModel.showCrashRecoveryBanner = false
            }
            .buttonStyle(MSCSecondaryButtonStyle())
            .controlSize(.small)
        }
        .padding(.horizontal, MSC.Spacing.xxl)
        .padding(.vertical, MSC.Spacing.sm)
        .background(Color.blue.opacity(0.08))
    }

    private func latestMSCCrashReport() -> URL? {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports")
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        )) ?? []
        return files
            .filter { $0.pathExtension == "ips" && $0.lastPathComponent.contains("MinecraftServerController") }
            .sorted {
                let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return d1 > d2
            }
            .first
    }
}

// MARK: - Toolbar Help Popover

private struct ToolbarHelpPopover: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            helpRow(
                icon: "questionmark.circle",
                label: "Explain this workspace",
                isDisabled: viewModel.selectedServer == nil
            ) {
                isPresented = false
                viewModel.triggerExplainWorkspace = true
            }

            Divider()
                .padding(.vertical, 4)

            helpRow(icon: "info.circle",   label: "How MSC Works…") {
                isPresented = false
                viewModel.showConceptGuideFromPreferences()
            }
            helpRow(icon: "book",          label: "Server Handbook…") {
                isPresented = false
                viewModel.showServerHandbookFromPreferences()
            }
            helpRow(icon: "checklist",     label: "Prerequisites & Dependencies…") {
                isPresented = false
                viewModel.isShowingPrerequisites = true
            }
            helpRow(icon: "arrow.clockwise", label: "Restart Setup Tour…") {
                isPresented = false
                OnboardingManager.shared.reset()
            }
            helpRow(icon: "network",       label: "Port Forwarding Guide…") {
                isPresented = false
                viewModel.isShowingRouterPortForwardGuide = true
            }

            Divider()
                .padding(.vertical, 4)

            helpRow(icon: "arrow.up.right.square", label: "GitHub Repository") {
                if let url = URL(string: "https://github.com/ctemple9/minecraft-server-controller") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding(8)
        .frame(width: 248)
    }

    @ViewBuilder
    private func helpRow(icon: String, label: String, isDisabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .frame(width: 16, alignment: .center)
                Text(label)
                    .font(.system(size: 12))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isDisabled ? AnyShapeStyle(Color.secondary.opacity(0.45)) : AnyShapeStyle(Color.primary))
        .disabled(isDisabled)
    }
}

// MARK: - playit.gg Setup Sheet (native — no browser, no webview)

struct PlayitSetupSheet: View {
    @EnvironmentObject var viewModel: AppViewModel

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isWorking: Bool = false
    @State private var statusText: String = ""
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        !isWorking &&
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
            MSCSheetHeader("Set up playit.gg Tunnel") {
                viewModel.isShowingPlayitSecretSetup = false
            }

            Text("Sign in with your playit.gg account and MSC sets up the tunnel for you — no browser, no copying keys.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Prerequisites callout — only relevant to people who plan to use playit.gg.
            HStack(alignment: .top, spacing: MSC.Spacing.sm) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Before you begin")
                        .font(MSC.Typography.caption.weight(.semibold))
                    Text("MSC creates one agent and two tunnels (Java + Bedrock) on your account. Free playit.gg accounts limit how many agents and tunnels you can have — if you've hit those limits, remove unused ones on playit.gg first.")
                        .font(MSC.Typography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(MSC.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.sm)
                    .fill(Color.secondary.opacity(0.08))
            )

            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                Text("Email")
                    .font(MSC.Typography.sectionHeader)
                TextField("you@example.com", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isWorking)

                Text("Password")
                    .font(MSC.Typography.sectionHeader)
                SecureField("playit.gg password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isWorking)
                    .onSubmit { start() }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isWorking {
                HStack(spacing: MSC.Spacing.sm) {
                    ProgressView().controlSize(.small)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: MSC.Spacing.xs) {
                Text("Don't have an account?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Create a free account") {
                    #if os(macOS)
                    NSWorkspace.shared.open(URL(string: "https://playit.gg/login")!)
                    #endif
                }
                .buttonStyle(.link)
                .font(.caption)
            }
            Text("Just sign up on playit.gg, then come back here and sign in. (Two-factor accounts aren't supported yet.)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel") {
                    viewModel.isShowingPlayitSecretSetup = false
                }
                .buttonStyle(MSCSecondaryButtonStyle())
                .disabled(isWorking)

                Button("Set Up Tunnel") { start() }
                    .buttonStyle(MSCPrimaryButtonStyle())
                    .disabled(!canSubmit)
            }
        }
        .padding(MSC.Spacing.xl)
        .frame(width: 460)
    }

    private func start() {
        guard canSubmit else { return }
        isWorking = true
        errorMessage = nil
        statusText = "Signing in…"
        let currentEmail = email.trimmingCharacters(in: .whitespaces)
        let currentPassword = password
        Task {
            let err = await viewModel.setupPlayitViaSignin(
                email: currentEmail,
                password: currentPassword
            ) { step in
                statusText = step
            }
            isWorking = false
            if let err {
                errorMessage = err
            } else {
                viewModel.isShowingPlayitSecretSetup = false
            }
        }
    }
}


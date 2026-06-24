//
//  ContentView.swift
//  MinecraftServerController
//
//  Main macOS app shell: banner, sidebar, details workspace, console, and
//  shared app-level sheets above the workspace.
//

import SwiftUI
import SpriteKit
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

    private var welcomeGuideBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isShowingWelcomeGuide },
            set: { viewModel.isShowingWelcomeGuide = $0 }
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
                            viewModel.triggerExplainWorkspace = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .buttonStyle(MSCGhostIconButtonStyle(size: 30))
                        .help("Explain this workspace")
                        .disabled(viewModel.selectedServer == nil)

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

        // Welcome Guide
        .sheet(isPresented: welcomeGuideBinding, onDismiss: {
            viewModel.handleWelcomeGuideDismissed()
        }) {
            WelcomeGuideView()
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
            BroadcastAuthSheet(prompt: prompt).environmentObject(viewModel)
        }

        // playit.gg secret key setup — shown on first use when no key is stored
        .sheet(isPresented: $viewModel.isShowingPlayitSecretSetup) {
            PlayitSecretKeySheet()
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

        // Error alerts
        .alert(item: $viewModel.errorAlert) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

// MARK: - Banner / runner support moved to ContentViewRunnerSupport.swift

struct BroadcastAuthSheet: View {
    @EnvironmentObject var viewModel: AppViewModel
    let prompt: BroadcastAuthPrompt

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
            Text("Sign in to your broadcast alt account")
                .font(MSC.Typography.pageTitle)

            Text("To finish setting up Xbox broadcast for this server, sign in with the Microsoft/Xbox account you use as your alt.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            // URL row
            VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                Text("Step 1 – Open this page:")
                    .font(MSC.Typography.sectionHeader)

                HStack {
                    Text(prompt.linkURL.absoluteString)
                        .font(MSC.Typography.mono)
                        .textSelection(.enabled)

                    Spacer()

                    Button("Open in Browser") {
                        #if os(macOS)
                        NSWorkspace.shared.open(prompt.linkURL)
                        #endif
                    }
                    .buttonStyle(MSCPrimaryButtonStyle())
                }
            }

            // Code row
            VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                Text("Step 2 – Enter this code:")
                    .font(MSC.Typography.sectionHeader)

                HStack(spacing: MSC.Spacing.md) {
                    Text(prompt.code)
                        .font(.system(size: 20, design: .monospaced))
                        .padding(.vertical, MSC.Spacing.sm)
                        .padding(.horizontal, MSC.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: MSC.Radius.sm)
                                .fill(Color.secondary.opacity(0.08))
                        )

                    Button("Copy Code") {
                        #if os(macOS)
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(prompt.code, forType: .string)
                        #endif
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                }
            }

            Text("On the Microsoft page, sign in with your alt account. Once you finish, this broadcast helper will use that account so your friends can see and join your world from the Friends tab on Xbox.")
                .font(MSC.Typography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            HStack {
                Spacer()
                Button("Close") {
                    viewModel.pendingBroadcastAuthPrompt = nil
                }
                .buttonStyle(MSCSecondaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(MSC.Spacing.xxl)
        .frame(minWidth: 480, minHeight: 320)
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

// MARK: - playit.gg Secret Key Setup Sheet

struct PlayitSecretKeySheet: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var secretKey: String = ""

    private static let setupURL = URL(string: "https://playit.gg/account/setup/wizard/new-account/docker/docker-name")!

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
            MSCSheetHeader("Set up playit.gg Tunnel") {
                viewModel.isShowingPlayitSecretSetup = false
            }

            Text("One-time setup — takes about 1 minute.")
                .font(MSC.Typography.sectionHeader)

            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                Text("1.  Click the button below to open the playit.gg setup page in your browser.")
                Text("2.  Create a free account (or log in) and follow the Docker setup wizard.")
                Text("3.  Copy the Secret Key shown at the end and paste it below.")
                Text("4.  Click Save. The tunnel starts automatically with your server from now on.")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Button("Open playit.gg Setup in Browser") {
                NSWorkspace.shared.open(Self.setupURL)
            }
            .buttonStyle(MSCSecondaryButtonStyle())

            Divider()

            VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                Text("Secret Key")
                    .font(MSC.Typography.sectionHeader)
                SecureField("Paste your playit.gg secret key here", text: $secretKey)
                    .textFieldStyle(.roundedBorder)
                Text("Stored locally — never sent anywhere by MSC.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Save") {
                    viewModel.savePlayitSecretKey(secretKey)
                    viewModel.isShowingPlayitSecretSetup = false
                }
                .buttonStyle(MSCPrimaryButtonStyle())
                .disabled(secretKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(MSC.Spacing.xl)
        .frame(width: 480)
    }
}


//
//  SetupWizardView.swift
//  MinecraftServerController
//
//  Multi-page first-run setup wizard.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Setup Page

private enum SetupPage: Int, CaseIterable, Hashable {
    case welcome = 0
    case serverType = 1
    case serverRootAndJava = 2
    case playit = 3
    case xboxBroadcast = 4
    case tailscale = 5
    case done = 6

    var title: String {
        switch self {
        case .welcome:           return "First-time Setup"
        case .serverType:        return "Server Type"
        case .serverRootAndJava: return "Server Setup"
        case .playit:            return "playit.gg"
        case .xboxBroadcast:     return "Xbox Broadcast"
        case .tailscale:         return "Tailscale"
        case .done:              return "You\u{2019}re All Set"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome:           return "Let\u{2019}s get Minecraft Server Controller configured."
        case .serverType:        return "Choose which platform you\u{2019}ll host servers on."
        case .serverRootAndJava: return "Where your servers live and how to run them."
        case .playit:            return "Optional \u{00B7} Let friends join without port forwarding."
        case .xboxBroadcast:     return "Optional \u{00B7} Console players see your server in Friends."
        case .tailscale:         return "Optional \u{00B7} Remote access from any network."
        case .done:              return "Create your first server to get started."
        }
    }

    var icon: String {
        switch self {
        case .welcome:           return "server.rack"
        case .serverType:        return "cpu"
        case .serverRootAndJava: return "folder.fill"
        case .playit:            return "antenna.radiowaves.left.and.right"
        case .xboxBroadcast:     return "dot.radiowaves.left.and.right"
        case .tailscale:         return "network"
        case .done:              return "checkmark.circle.fill"
        }
    }

    var isOptional: Bool {
        switch self {
        case .playit, .xboxBroadcast, .tailscale: return true
        default: return false
        }
    }

    var next: SetupPage? { SetupPage(rawValue: rawValue + 1) }
    var previous: SetupPage? { SetupPage(rawValue: rawValue - 1) }
}

// MARK: - Java Check Status

private enum JavaCheckStatus: Equatable {
    case unknown
    case checking
    case found(path: String)
    case notFound

    static func == (lhs: JavaCheckStatus, rhs: JavaCheckStatus) -> Bool {
        switch (lhs, rhs) {
        case (.unknown, .unknown), (.checking, .checking), (.notFound, .notFound): return true
        case (.found(let a), .found(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - Tailscale Check Status

private enum TailscaleCheckStatus {
    case unknown, checking, installed, notInstalled
}

// MARK: - SetupWizardView

struct SetupWizardView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    // MARK: Navigation state
    @State private var currentPage: SetupPage = .welcome
    @State private var navigatingForward: Bool = true

    // MARK: Setup state
    @State private var serversRoot: String = ""
    @State private var javaPath: String = ""
    @State private var isInitialRun: Bool = false
    @State private var accentColor: Color = .green

    // Server type selection
    @State private var wantsJava: Bool = true
    @State private var wantsBedrock: Bool = false

    // Detection state
    @State private var javaStatus: JavaCheckStatus = .unknown
    @State private var tailscaleStatus: TailscaleCheckStatus = .unknown
    @State private var isDownloadingJava = false

    // Xbox Broadcast
    @State private var xboxDownloadStatus: String? = nil

    // Server type expansion stagger state
    @State private var javaVisible: Bool = false
    @State private var bedrockVisible: Bool = false

    // MARK: - Validation

    private var hasValidServersRoot: Bool {
        !serversRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasValidJava: Bool {
        if case .found(let p) = javaStatus, !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return !javaPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isNextDisabled: Bool {
        switch currentPage {
        case .serverType:
            return !wantsJava && !wantsBedrock
        case .serverRootAndJava:
            if !hasValidServersRoot { return true }
            if wantsJava && !hasValidJava { return true }
            return false
        default:
            return false
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            heroHeader

            ZStack {
                Group {
                    switch currentPage {
                    case .welcome:           welcomePage
                    case .serverType:        serverTypePage
                    case .serverRootAndJava: serverRootPage
                    case .playit:            playitPage
                    case .xboxBroadcast:     xboxBroadcastPage
                    case .tailscale:         tailscalePage
                    case .done:              donePage
                    }
                }
                .id(currentPage)
                .transition(.asymmetric(
                    insertion: .move(edge: navigatingForward ? .trailing : .leading),
                    removal: .move(edge: navigatingForward ? .leading : .trailing)
                ))
            }
            .clipped()
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { prefill() }
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        ZStack(alignment: .bottomLeading) {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.06, green: 0.06, blue: 0.10),
                        Color(red: 0.04, green: 0.18, blue: 0.18)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                accentColor.opacity(0.45)
            }
            .overlay(
                Canvas { ctx, size in
                    let spacing: CGFloat = 18
                    var x: CGFloat = spacing
                    while x < size.width {
                        var y: CGFloat = spacing
                        while y < size.height {
                            let rect = CGRect(x: x, y: y, width: 2, height: 2)
                            ctx.fill(Path(rect), with: .color(.white.opacity(0.04)))
                            y += spacing
                        }
                        x += spacing
                    }
                }
            )

            VStack(alignment: .leading, spacing: 0) {
                stepTrack
                    .padding(.horizontal, MSC.Spacing.xl)
                    .padding(.top, MSC.Spacing.md)

                Spacer()

                HStack(alignment: .center, spacing: MSC.Spacing.lg) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.white.opacity(0.12))
                            .frame(width: 52, height: 52)
                        Image(systemName: currentPage.icon)
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(.white)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(currentPage.title)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(currentPage.subtitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, MSC.Spacing.xl)
                .padding(.bottom, MSC.Spacing.xl)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !isInitialRun {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(6)
                                .background(Circle().fill(.black.opacity(0.35)))
                        }
                        .buttonStyle(.plain)
                        .padding(MSC.Spacing.md)
                    }
                    Spacer()
                }
            }
        }
        .frame(height: 130)
    }

    // MARK: - Step Track

    private var stepTrack: some View {
        HStack(spacing: 5) {
            ForEach(SetupPage.allCases, id: \.self) { page in
                if page.rawValue > 0 {
                    Rectangle()
                        .fill(page.rawValue <= currentPage.rawValue
                              ? accentColor.opacity(0.6)
                              : Color.white.opacity(0.18))
                        .frame(height: 1.5)
                        .animation(.easeInOut(duration: 0.25), value: currentPage)
                }
                Circle()
                    .fill(page.rawValue <= currentPage.rawValue
                          ? accentColor
                          : Color.white.opacity(0.25))
                    .frame(
                        width: page == currentPage ? 9 : 6,
                        height: page == currentPage ? 9 : 6
                    )
                    .animation(.easeInOut(duration: 0.25), value: currentPage)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: MSC.Spacing.sm) {

                // Back button (hidden on first and last page)
                if currentPage != .welcome && currentPage != .done {
                    Button {
                        goBack()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Back")
                        }
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                } else {
                    // Placeholder to keep layout stable
                    Color.clear.frame(width: 70, height: 1)
                }

                Spacer()

                // Validation hint on gated pages
                if currentPage == .serverType && !wantsJava && !wantsBedrock {
                    Text("Select at least one server type")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else if currentPage == .serverRootAndJava {
                    if !hasValidServersRoot {
                        Text("Servers folder required")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    } else if wantsJava && !hasValidJava {
                        Text("Java path required")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }

                // Skip link on optional pages
                if currentPage.isOptional {
                    Button("Skip") {
                        advance()
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                }

                // Primary action button
                if currentPage == .done {
                    Button {
                        applyAndDismiss()
                    } label: {
                        Text("Get Started")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(MSCPrimaryButtonStyle())
                } else {
                    Button {
                        advance()
                    } label: {
                        HStack(spacing: 6) {
                            Text(currentPage == .tailscale ? "Continue" : "Next")
                                .font(.system(size: 15, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                    .disabled(isNextDisabled)
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(MSCPrimaryButtonStyle())
                }
            }
            .padding(.horizontal, MSC.Spacing.xl)
            .padding(.vertical, MSC.Spacing.md)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Navigation

    private func advance() {
        guard let next = currentPage.next else { return }
        navigatingForward = true
        withAnimation(.easeInOut(duration: 0.25)) {
            currentPage = next
        }
    }

    private func goBack() {
        guard let prev = currentPage.previous else { return }
        navigatingForward = false
        withAnimation(.easeInOut(duration: 0.25)) {
            currentPage = prev
        }
    }

    // MARK: - Welcome Page

    private var welcomePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MSC.Spacing.lg) {

                // What MSC does
                setupCard(
                    icon: "server.rack",
                    iconColor: .blue,
                    title: "What is Minecraft Server Controller?",
                    subtitle: "MSC helps you run and manage Minecraft servers on your Mac."
                ) {
                    VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                        featureBullet(icon: "play.circle.fill",  color: .green,  text: "Start and stop Java and Bedrock servers with one click")
                        featureBullet(icon: "person.3.fill",     color: .blue,   text: "Invite friends via tunnels, port forwarding, or Tailscale")
                        featureBullet(icon: "cube.box.fill",     color: .purple, text: "Install plugins, mods, and resource packs from Modrinth")
                        featureBullet(icon: "externaldrive.fill", color: .orange, text: "Schedule backups and manage multiple worlds")
                    }
                }

                // Accent color
                setupCard(
                    icon: "paintpalette.fill",
                    iconColor: accentColor,
                    title: "Pick an Accent Color",
                    subtitle: "Tints the app shell and overlays. Change it anytime in Preferences."
                ) {
                    HStack(spacing: MSC.Spacing.sm) {
                        let presets: [(Color, String)] = [
                            (Color(red: 0.133, green: 0.784, blue: 0.349), "#22C85A"),
                            (Color(red: 0.231, green: 0.510, blue: 0.965), "#3B82F6"),
                            (Color(red: 0.545, green: 0.361, blue: 0.965), "#8B5CF6"),
                            (Color(red: 0.976, green: 0.451, blue: 0.086), "#F97316"),
                            (Color(red: 0.937, green: 0.267, blue: 0.267), "#EF4444"),
                            (Color(red: 0.078, green: 0.722, blue: 0.651), "#14B8A6"),
                        ]
                        ForEach(presets, id: \.1) { preset, hex in
                            Button {
                                accentColor = preset
                                viewModel.configManager.config.defaultBannerColorHex = preset.hexRGBString()
                                viewModel.configManager.save()
                                viewModel.syncTourAccentColor()
                            } label: {
                                ZStack {
                                    Circle().fill(preset).frame(width: 28, height: 28)
                                    if let selectedHex = accentColor.hexRGBString(),
                                       selectedHex.uppercased() == hex.uppercased() {
                                        Circle()
                                            .stroke(Color.white, lineWidth: 2)
                                            .frame(width: 28, height: 28)
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        ColorPicker("Custom", selection: $accentColor, supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())
                            .help("Pick a custom color")
                            .onChange(of: accentColor) { _, newColor in
                                let adjusted = newColor.clampedAwayFromWhite().clampedAwayFromBlack()
                                viewModel.configManager.config.defaultBannerColorHex = adjusted.hexRGBString()
                                viewModel.configManager.save()
                                viewModel.syncTourAccentColor()
                            }
                    }
                }

                Text("This setup takes about 2 minutes.")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(MSC.Spacing.xl)
        }
        .scrollIndicators(.hidden)
    }

    private func featureBullet(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: MSC.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Server Type Page

    private var serverTypePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MSC.Spacing.md) {
                HStack(spacing: MSC.Spacing.md) {
                    serverTypeToggleCard(
                        label: "Java Servers",
                        subtitle: "Plugins, mods & crossplay",
                        icon: "cup.and.saucer.fill",
                        color: .orange,
                        isOn: $wantsJava
                    )
                    serverTypeToggleCard(
                        label: "Bedrock Servers",
                        subtitle: "Mobile, console & Windows",
                        icon: "cube.fill",
                        color: .green,
                        isOn: $wantsBedrock
                    )
                }

                if !wantsJava && !wantsBedrock {
                    inlineCallout(
                        icon: "info.circle.fill",
                        color: .secondary,
                        text: "Select at least one type to continue. You can change this later."
                    )
                    .transition(.opacity)
                }

                if wantsJava {
                    if wantsJava && wantsBedrock {
                        expansionHeader("Java")
                    }
                    javaExpansion
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if wantsBedrock {
                    if wantsJava && wantsBedrock {
                        expansionHeader("Bedrock")
                    }
                    bedrockExpansion
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(MSC.Spacing.xl)
            .animation(.easeInOut(duration: 0.28), value: wantsJava)
            .animation(.easeInOut(duration: 0.28), value: wantsBedrock)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Java Expansion

    private var javaExpansion: some View {
        VStack(spacing: 4) {
            flavorBar(icon: "doc.fill",                       color: .teal,
                      name: "Paper",
                      description: "Plugin-based. Fast, stable, largest ecosystem.",
                      index: 0, isVisible: javaVisible)
            flavorBar(icon: "wand.and.stars",                 color: .purple,
                      name: "Purpur",
                      description: "Paper + extra gameplay tweaks. All Paper plugins work.",
                      index: 1, isVisible: javaVisible)
            flavorBar(icon: "cube.fill",                      color: Color(.systemGray),
                      name: "Vanilla",
                      description: "No plugins. Fully authentic Mojang experience.",
                      index: 2, isVisible: javaVisible)
            flavorBar(icon: "scissors",                       color: .blue,
                      name: "Fabric",
                      description: "Lightweight mods. Fast updates, great for optimization.",
                      index: 3, isVisible: javaVisible)
            flavorBar(icon: "hammer.fill",                    color: .orange,
                      name: "Forge",
                      description: "Classic modding platform. Widest mod selection.",
                      index: 4, isVisible: javaVisible)
            flavorBar(icon: "wrench.and.screwdriver.fill",    color: Color(red: 0.08, green: 0.72, blue: 0.65),
                      name: "NeoForge",
                      description: "Forge\u{2019}s modern successor. More active development.",
                      index: 5, isVisible: javaVisible)

            inlineCallout(
                icon: "person.3.fill",
                color: .blue,
                text: "Java Edition players always. Bedrock, mobile, and console can join standard servers via Geyser crossplay (set up per server)."
            )
            .opacity(javaVisible ? 1 : 0)
            .animation(.easeOut(duration: 0.2).delay(6 * 0.055), value: javaVisible)
        }
        .onAppear  { withAnimation { javaVisible = true  } }
        .onDisappear {                javaVisible = false   }
    }

    // MARK: - Bedrock Expansion

    private var bedrockExpansion: some View {
        VStack(spacing: 4) {
            flavorBar(icon: "memorychip",  color: .green,
                      name: "BDS",
                      description: "Official Mojang Bedrock server. Runs in a built-in VM, no Docker needed.",
                      index: 0, isVisible: bedrockVisible)

            inlineCallout(
                icon: "person.3.fill",
                color: .green,
                text: "Mobile (iOS/Android), console (Xbox, PlayStation, Switch), Windows 10/11 Bedrock Edition. Java Edition players cannot join."
            )
            .opacity(bedrockVisible ? 1 : 0)
            .animation(.easeOut(duration: 0.2).delay(1 * 0.055), value: bedrockVisible)
        }
        .onAppear  { withAnimation { bedrockVisible = true  } }
        .onDisappear {                bedrockVisible = false   }
    }

    // MARK: - Expansion Section Header

    private func expansionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .kerning(1)
            .padding(.bottom, 2)
    }

    // MARK: - Flavor Bar (informational strip with left accent stripe)

    private func flavorBar(
        icon: String,
        color: Color,
        name: String,
        description: String,
        index: Int,
        isVisible: Bool
    ) -> some View {
        HStack(spacing: MSC.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 16)
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Text("\u{00B7}")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
            Text(description)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, MSC.Spacing.sm)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(color.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous))
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 6)
        .animation(.easeOut(duration: 0.2).delay(Double(index) * 0.055), value: isVisible)
    }

    private func serverTypeToggleCard(
        label: String,
        subtitle: String,
        icon: String,
        color: Color,
        isOn: Binding<Bool>
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: MSC.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isOn.wrappedValue ? color : color.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isOn.wrappedValue ? .white : color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isOn.wrappedValue ? color : .secondary.opacity(0.4))
            }
            .padding(MSC.Spacing.md)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                    .fill(isOn.wrappedValue ? color.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                            .strokeBorder(isOn.wrappedValue ? color.opacity(0.4) : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Server Root + Java Page

    private var serverRootPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MSC.Spacing.lg) {

                // Servers root folder
                setupCard(
                    icon: "folder.fill",
                    iconColor: .blue,
                    title: "Servers Root Folder",
                    subtitle: "All your servers will live inside this folder."
                ) {
                    HStack(spacing: MSC.Spacing.sm) {
                        Image(systemName: hasValidServersRoot ? "checkmark.circle.fill" : "circle.dashed")
                            .font(.system(size: 14))
                            .foregroundStyle(hasValidServersRoot ? .green : .secondary)
                        TextField("~/MinecraftServers", text: $serversRoot)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13, design: .monospaced))
                        Button("Browse\u{2026}") { browseForServersRoot() }
                            .controlSize(.small)
                    }
                }

                // Java (only if Java servers selected)
                if wantsJava {
                    javaCard
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Bedrock note (only if Bedrock selected)
                if wantsBedrock {
                    setupCard(
                        icon: "memorychip",
                        iconColor: .green,
                        title: "Bedrock \u{2014} Built In",
                        subtitle: "No extra software needed. MSC runs Bedrock Dedicated Server in a built-in virtual machine."
                    ) {
                        inlineCallout(
                            icon: "checkmark.circle.fill",
                            color: .green,
                            text: "Ready. Bedrock servers start instantly \u{2014} no Docker, no installs."
                        )
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(MSC.Spacing.xl)
            .animation(.easeInOut(duration: 0.2), value: wantsJava)
            .animation(.easeInOut(duration: 0.2), value: wantsBedrock)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Java Card

    private var javaCard: some View {
        setupCard(
            icon: "cup.and.saucer.fill",
            iconColor: .orange,
            title: "Java Executable",
            subtitle: "Java servers require JDK 21 or later. Point to your binary or let the app find it on PATH."
        ) {
            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                HStack(spacing: MSC.Spacing.sm) {
                    TextField("/usr/bin/java", text: $javaPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                    Button("Browse\u{2026}") { browseForJava() }
                        .controlSize(.small)
                    Button("Use PATH") {
                        javaPath = ""
                        checkJavaOnPath()
                    }
                    .controlSize(.small)
                }

                HStack(spacing: MSC.Spacing.sm) {
                    Button("Check for Java") { checkJavaOnPath() }
                        .controlSize(.small)
                    javaStatusBadge
                    Spacer()
                }

                if javaStatus == .notFound {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.orange)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No Java found on PATH. Install the current Temurin LTS, then click Check for Java again.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            if isDownloadingJava {
                                HStack(spacing: 6) {
                                    ProgressView().scaleEffect(0.65)
                                    Text("Downloading installer\u{2026}")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                HStack(spacing: MSC.Spacing.sm) {
                                    Button("Install Java (Temurin LTS)") {
                                        downloadAndInstallJava()
                                    }
                                    .controlSize(.mini)
                                    .buttonStyle(.borderedProminent)
                                    Button("Manual Download \u{2192}") {
                                        openTemurin21DownloadPage()
                                    }
                                    .font(.system(size: 13))
                                    .foregroundStyle(.orange)
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(MSC.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                            .fill(Color.orange.opacity(0.08))
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var javaStatusBadge: some View {
        switch javaStatus {
        case .unknown:
            Text("Not checked yet")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.55)
                Text("Checking\u{2026}")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        case .found(let path):
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.green)
                Text("Found at \(path)")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        case .notFound:
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                Text("Not found")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - playit.gg Page

    private var playitPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MSC.Spacing.lg) {

                setupCard(
                    icon: "antenna.radiowaves.left.and.right",
                    iconColor: .purple,
                    title: "What is playit.gg?",
                    subtitle: "A free tunneling service that lets friends connect to your server without port forwarding."
                ) {
                    VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                        featureBullet(icon: "checkmark.circle.fill", color: .green,  text: "No router configuration required")
                        featureBullet(icon: "checkmark.circle.fill", color: .green,  text: "Works on any network, including strict NAT")
                        featureBullet(icon: "checkmark.circle.fill", color: .green,  text: "MSC sets up tunnels automatically after you sign in")
                    }
                }

                setupCard(
                    icon: "person.badge.plus",
                    iconColor: .purple,
                    title: "Create a playit.gg Account",
                    subtitle: "A free account is required. MSC will handle tunnel setup after you\u{2019}ve signed in."
                ) {
                    VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                        Button("Sign up at playit.gg \u{2192}") {
                            NSWorkspace.shared.open(URL(string: "https://playit.gg/login")!)
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.purple)
                        .buttonStyle(.plain)

                        inlineCallout(
                            icon: "exclamationmark.triangle.fill",
                            color: .orange,
                            text: "Free accounts include 1 agent and up to 3 tunnels. If you already have an account, make sure you have room for at least 1 agent and 3 tunnels before connecting."
                        )
                    }
                }

                Text("You\u{2019}ll sign in to playit.gg from within MSC once your first server is created. You can skip this step and set it up later.")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            }
            .padding(MSC.Spacing.xl)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Xbox Broadcast Page

    private var xboxBroadcastPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MSC.Spacing.lg) {

                setupCard(
                    icon: "gamecontroller.fill",
                    iconColor: .green,
                    title: "What is Xbox Broadcast?",
                    subtitle: "The most reliable way for console players to find and join your server."
                ) {
                    VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                        featureBullet(icon: "tv.fill",             color: .green,  text: "Console players see your server in the Xbox Friends tab \u{2014} no IP address needed")
                        featureBullet(icon: "iphone",              color: .green,  text: "Works for Java servers (via Geyser) and Bedrock servers")
                        featureBullet(icon: "arrow.down.circle.fill", color: .blue, text: "MSC downloads the broadcast tool automatically")
                    }
                }

                // Safety advisory
                setupCard(
                    icon: "exclamationmark.shield.fill",
                    iconColor: .orange,
                    title: "Use a Dedicated Microsoft Account",
                    subtitle: "We recommend not using your personal Microsoft or Xbox account for broadcasting."
                ) {
                    VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                        Text("Xbox Broadcast may be against Microsoft\u{2019}s Terms of Service per their own GitHub repository. To keep your personal account safe, sign in with a separate, dedicated account.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Creating a new Outlook account automatically gives you a fresh Xbox Live identity \u{2014} free and takes under a minute.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button("Create a new Microsoft / Outlook account \u{2192}") {
                            NSWorkspace.shared.open(URL(string: "https://signup.live.com")!)
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.orange)
                        .buttonStyle(.plain)
                    }
                }

                // Download status
                setupCard(
                    icon: "arrow.down.circle.fill",
                    iconColor: .blue,
                    title: "Broadcast Helper",
                    subtitle: "The broadcast tool is downloaded once and shared across all your servers."
                ) {
                    HStack(spacing: MSC.Spacing.sm) {
                        if viewModel.isXboxBroadcastHelperInstalled {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.green)
                            Text("Installed and ready.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        } else if let status = xboxDownloadStatus {
                            if status.hasPrefix("Downloading") {
                                ProgressView().scaleEffect(0.65)
                            } else {
                                Image(systemName: status.hasPrefix("\u{2713}") ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(status.hasPrefix("\u{2713}") ? Color.green : Color.red)
                            }
                            Text(status)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "circle.dashed")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                            Text("Not downloaded yet")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !viewModel.isXboxBroadcastHelperInstalled {
                            Button("Download Now") {
                                downloadXboxBroadcastHelper()
                            }
                            .controlSize(.small)
                            .disabled(xboxDownloadStatus?.hasPrefix("Downloading") == true)
                        }
                    }
                }

                inlineCallout(
                    icon: "info.circle.fill",
                    color: .blue,
                    text: "When you first start a server with Xbox Broadcast enabled, MSC will prompt you to sign in with your Microsoft account in a private session."
                )
            }
            .padding(MSC.Spacing.xl)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Tailscale Page

    private var tailscalePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MSC.Spacing.lg) {

                setupCard(
                    icon: "network",
                    iconColor: .blue,
                    title: "What is Tailscale?",
                    subtitle: "A private mesh VPN that connects your devices no matter where they are."
                ) {
                    VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                        featureBullet(icon: "checkmark.circle.fill", color: .green, text: "Access your Mac\u{2019}s servers from your phone, another Mac, or anywhere")
                        featureBullet(icon: "checkmark.circle.fill", color: .green, text: "Free for personal use \u{2014} takes about a minute to set up")
                        featureBullet(icon: "checkmark.circle.fill", color: .green, text: "Works alongside playit.gg \u{2014} they solve different problems")
                    }
                }

                setupCard(
                    icon: "network",
                    iconColor: .blue,
                    title: "Tailscale  \u{00B7}  Optional",
                    subtitle: "Check whether Tailscale is already installed."
                ) {
                    VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                        HStack(spacing: MSC.Spacing.sm) {
                            Button("Check") { checkTailscale() }
                                .controlSize(.small)
                            tailscaleStatusBadge
                            Spacer()
                        }

                        switch tailscaleStatus {
                        case .notInstalled:
                            inlineCallout(
                                icon: "info.circle.fill",
                                color: .blue,
                                text: "Tailscale isn\u{2019}t installed. Download it free from tailscale.com \u{2014} takes about a minute.",
                                actionLabel: "Download Tailscale \u{2192}",
                                action: { NSWorkspace.shared.open(URL(string: "https://tailscale.com/download/mac")!) }
                            )
                        case .installed:
                            inlineCallout(
                                icon: "checkmark.circle.fill",
                                color: .green,
                                text: "Tailscale is installed. Enable it and join your tailnet to access servers remotely."
                            )
                        default:
                            EmptyView()
                        }
                    }
                }
            }
            .padding(MSC.Spacing.xl)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var tailscaleStatusBadge: some View {
        switch tailscaleStatus {
        case .unknown:
            Text("Not checked yet")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.55)
                Text("Checking\u{2026}")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        case .installed:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.green)
                Text("Installed")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        case .notInstalled:
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                Text("Not installed")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Done Page

    private var donePage: some View {
        VStack(spacing: MSC.Spacing.xl) {
            Spacer()

            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(accentColor)
            }

            VStack(spacing: MSC.Spacing.sm) {
                Text("You\u{2019}re All Set")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("MSC is configured and ready. Click \u{201C}Get Started\u{201D} to create your first Minecraft server.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            VStack(spacing: MSC.Spacing.sm) {
                summaryRow(icon: "folder.fill",       color: .blue,   label: "Servers root", value: serversRoot.isEmpty ? "Not set" : serversRoot)
                if wantsJava {
                    summaryRow(icon: "cup.and.saucer.fill", color: .orange, label: "Java", value: {
                        if case .found(let p) = javaStatus { return p }
                        return javaPath.isEmpty ? "Not configured" : javaPath
                    }())
                }
                summaryRow(
                    icon: "cpu",
                    color: .purple,
                    label: "Server types",
                    value: [wantsJava ? "Java" : nil, wantsBedrock ? "Bedrock" : nil]
                        .compactMap { $0 }
                        .joined(separator: " + ")
                )
            }
            .padding(MSC.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.lg, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: MSC.Radius.lg, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                    )
            )

            Spacer()
        }
        .padding(.horizontal, MSC.Spacing.xl)
    }

    private func summaryRow(icon: String, color: Color, label: String, value: String) -> some View {
        HStack(spacing: MSC.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(color)
                .frame(width: 18)
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // MARK: - Shared Components

    private func setupCard<Content: View>(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {
            HStack(spacing: MSC.Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
        }
        .padding(MSC.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.lg, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MSC.Radius.lg, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func inlineCallout(
        icon: String,
        color: Color,
        text: String,
        actionLabel: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(color)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let label = actionLabel, let action = action {
                    Button(label) { action() }
                        .font(.system(size: 13))
                        .foregroundStyle(color)
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(MSC.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                .fill(color.opacity(0.08))
        )
    }

    // MARK: - Actions

    private func prefill() {
        let cfg = viewModel.configManager.config
        isInitialRun = viewModel.servers.isEmpty
        serversRoot = cfg.serversRoot.isEmpty ? AppConfig.defaultConfig().serversRoot : cfg.serversRoot
        javaPath = cfg.javaPath
        if let hex = cfg.defaultBannerColorHex, let color = Color(hexRGB: hex) {
            accentColor = color
        }
        if javaPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            checkJavaOnPath()
        } else {
            javaStatus = .found(path: javaPath)
        }
    }

    private func applyAndDismiss() {
        viewModel.configManager.config.defaultBannerColorHex = accentColor.hexRGBString()
        viewModel.configManager.save()
        viewModel.syncTourAccentColor()
        viewModel.applyInitialSetup(serversRoot: serversRoot, javaPath: javaPath)
        dismiss()
    }

    // MARK: - Browse Helpers

    private func browseForServersRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                DispatchQueue.main.async { serversRoot = url.path }
            }
        }
    }

    private func browseForJava() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                DispatchQueue.main.async {
                    javaPath = url.path
                    javaStatus = .found(path: url.path)
                }
            }
        }
    }

    // MARK: - Java Detection

    private func checkJavaOnPath() {
        javaStatus = .checking
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            process.arguments = ["java"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                DispatchQueue.main.async {
                    if !output.isEmpty {
                        self.javaStatus = .found(path: output)
                        if self.javaPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            self.javaPath = output
                        }
                    } else {
                        self.javaStatus = .notFound
                    }
                }
            } catch {
                DispatchQueue.main.async { self.javaStatus = .notFound }
            }
        }
    }

    private func openTemurin21DownloadPage() {
        guard let url = URL(string: "https://adoptium.net/temurin/releases/?package=jdk&os=mac") else { return }
        NSWorkspace.shared.open(url)
    }

    private func downloadAndInstallJava() {
        isDownloadingJava = true
        Task {
            defer { Task { @MainActor in isDownloadingJava = false } }
            do {
                #if arch(arm64)
                let arch = "aarch64"
                #else
                let arch = "x64"
                #endif

                let releasesURL = URL(string: "https://api.adoptium.net/v3/info/available_releases")!
                let (relData, _) = try await URLSession.shared.data(from: releasesURL)
                let ltsVersion: Int
                if let relJson = try JSONSerialization.jsonObject(with: relData) as? [String: Any],
                   let v = relJson["most_recent_lts"] as? Int {
                    ltsVersion = v
                } else {
                    ltsVersion = 21
                }

                let assetsURLString = "https://api.adoptium.net/v3/assets/latest/\(ltsVersion)/hotspot?os=mac&image_type=jdk&vendor=eclipse&architecture=\(arch)"
                let (assetData, _) = try await URLSession.shared.data(from: URL(string: assetsURLString)!)
                guard let assets = try JSONSerialization.jsonObject(with: assetData) as? [[String: Any]],
                      let first = assets.first,
                      let binary = first["binary"] as? [String: Any],
                      let installer = binary["installer"] as? [String: Any],
                      let pkgURLString = installer["link"] as? String,
                      let pkgURL = URL(string: pkgURLString) else {
                    await MainActor.run { openTemurin21DownloadPage() }
                    return
                }

                let (tempURL, _) = try await URLSession.shared.download(from: pkgURL)
                let destURL = FileManager.default.temporaryDirectory.appendingPathComponent(pkgURL.lastPathComponent)
                try? FileManager.default.removeItem(at: destURL)
                try FileManager.default.moveItem(at: tempURL, to: destURL)
                await MainActor.run { NSWorkspace.shared.open(destURL) }
            } catch {
                await MainActor.run { openTemurin21DownloadPage() }
            }
        }
    }

    // MARK: - Xbox Broadcast Download

    private func downloadXboxBroadcastHelper() {
        guard !viewModel.isXboxBroadcastHelperInstalled else {
            xboxDownloadStatus = "\u{2713} Already installed."
            return
        }
        xboxDownloadStatus = "Downloading\u{2026}"
        viewModel.downloadOrUpdateXboxBroadcastJar()
        // Poll until installed (the download is async in the viewModel)
        Task {
            for _ in 0..<60 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if viewModel.isXboxBroadcastHelperInstalled {
                    await MainActor.run { xboxDownloadStatus = "\u{2713} Downloaded successfully." }
                    return
                }
            }
            await MainActor.run { xboxDownloadStatus = nil }
        }
    }

    // MARK: - Tailscale Detection

    private func checkTailscale() {
        tailscaleStatus = .checking
        DispatchQueue.global(qos: .userInitiated).async {
            let paths = [
                "/Applications/Tailscale.app",
                "/usr/local/bin/tailscale",
                "/opt/homebrew/bin/tailscale"
            ]
            let found = paths.contains { FileManager.default.fileExists(atPath: $0) }
            DispatchQueue.main.async { tailscaleStatus = found ? .installed : .notInstalled }
        }
    }

    // MARK: - Docker Detection (kept for reference — no longer called)

    /* private func checkDocker() {
        dockerStatus = .checking
        DispatchQueue.global(qos: .userInitiated).async {
            let candidatePaths = [
                "/usr/local/bin/docker",
                "/opt/homebrew/bin/docker",
                "/usr/bin/docker",
                "/Applications/Docker.app/Contents/Resources/bin/docker"
            ]
            let fm = FileManager.default
            guard let dockerPath = candidatePaths.first(where: { fm.isExecutableFile(atPath: $0) }) else {
                DispatchQueue.main.async { self.dockerStatus = .notInstalled }
                return
            }
            do {
                let infoProcess = Process()
                infoProcess.executableURL = URL(fileURLWithPath: dockerPath)
                infoProcess.arguments = ["info"]
                infoProcess.standardOutput = Pipe()
                infoProcess.standardError = Pipe()
                try infoProcess.run()
                infoProcess.waitUntilExit()
                DispatchQueue.main.async {
                    self.dockerStatus = infoProcess.terminationStatus == 0 ? .running : .notRunning
                }
            } catch {
                DispatchQueue.main.async { self.dockerStatus = .notRunning }
            }
        }
    }

    private func openDockerDownloadPage() {
        guard let url = URL(string: "https://www.docker.com/products/docker-desktop") else { return }
        NSWorkspace.shared.open(url)
    }

    private func downloadAndInstallDocker() {
        isDownloadingDocker = true
        Task {
            defer { Task { @MainActor in isDownloadingDocker = false } }
            do {
                #if arch(arm64)
                let dmgURL = URL(string: "https://desktop.docker.com/mac/main/arm64/Docker.dmg")!
                #else
                let dmgURL = URL(string: "https://desktop.docker.com/mac/main/amd64/Docker.dmg")!
                #endif
                let (tempURL, _) = try await URLSession.shared.download(from: dmgURL)
                let destURL = FileManager.default.temporaryDirectory.appendingPathComponent("Docker.dmg")
                try? FileManager.default.removeItem(at: destURL)
                try FileManager.default.moveItem(at: tempURL, to: destURL)
                await MainActor.run { NSWorkspace.shared.open(destURL) }
            } catch {
                await MainActor.run { openDockerDownloadPage() }
            }
        }
    }
    */ // end commented-out Docker detection methods
}

//
//  CrossPlatformGuideSheet.swift
//  MinecraftServerController
//
//  Step-by-step setup and troubleshooting guide for Xbox Broadcast (MCXboxBroadcastStandalone by GeyserMC).
//

import SwiftUI
import Combine

// MARK: - Screen Enum

private enum CGScreen: Hashable {
    case landing
    case xbIntro
    case xbInstall
    case xbAccount
    case xbSettings
    case xbActivation
    case xbTroubleshooting
}

// MARK: - Guide ViewModel

private final class CrossPlatformGuideViewModel: ObservableObject {
    @Published var currentScreen: CGScreen = .landing
    private var history: [CGScreen] = []

    func navigate(to screen: CGScreen) {
        history.append(currentScreen)
        withAnimation(.easeInOut(duration: 0.18)) {
            currentScreen = screen
        }
    }

    func goBack() {
        guard let previous = history.popLast() else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            currentScreen = previous
        }
    }

    var canGoBack: Bool { !history.isEmpty }
}

// MARK: - Sheet Root

struct CrossPlatformGuideSheet: View {
    @EnvironmentObject var viewModel: AppViewModel
    @StateObject private var guide = CrossPlatformGuideViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {

            // Header bar
            HStack(spacing: MSC.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cross-Platform Setup")
                        .font(MSC.Typography.shellTitle)
                        .foregroundStyle(.primary)
                    Text(screenSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(Circle().fill(Color.secondary.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .help("Close guide")
            }
            .padding(.horizontal, MSC.Spacing.xl)
            .padding(.vertical, MSC.Spacing.md)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(alignment: .bottom) { Divider() }

            // Screen
            Group {
                switch guide.currentScreen {
                case .landing:         CGLandingScreen(guide: guide)
                case .xbIntro:         CGXBIntroScreen(guide: guide)
                case .xbInstall:       CGXBInstallScreen(guide: guide)
                case .xbAccount:       CGXBAccountScreen(guide: guide)
                case .xbSettings:      CGXBSettingsScreen(guide: guide)
                case .xbActivation:    CGXBActivationScreen(guide: guide)
                case .xbTroubleshooting: CGXBTroubleshootingScreen(guide: guide)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environmentObject(viewModel)
        }
        .frame(minWidth: 560, idealWidth: 640, minHeight: 520, idealHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var screenSubtitle: String {
        switch guide.currentScreen {
        case .landing:              return "Choose a topic"
        case .xbIntro:              return "Xbox Broadcast — 1 of 5"
        case .xbInstall:            return "Xbox Broadcast — 2 of 5"
        case .xbAccount:            return "Xbox Broadcast — 3 of 5"
        case .xbSettings:           return "Xbox Broadcast — 4 of 5"
        case .xbActivation:         return "Xbox Broadcast — 5 of 5"
        case .xbTroubleshooting:    return "Xbox Broadcast — Troubleshooting"
        }
    }
}

// MARK: - Landing Screen

private struct CGLandingScreen: View {
    @ObservedObject var guide: CrossPlatformGuideViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MSC.Spacing.xl) {

                CGScreenHeader(
                    title: "Cross-platform connections",
                    subtitle: "Xbox Broadcast lets Bedrock players on any platform — Xbox, PlayStation, Switch, mobile, and Windows — see your server in the Xbox friends list and join without typing an address."
                )

                CGLandingCard(
                    label: "XBOX BROADCAST",
                    labelColor: .green,
                    title: "All Bedrock platforms",
                    description: "Broadcasts your server over Xbox Live. Players add your alt account as a friend and see the server in their Friends tab.",
                    action: { guide.navigate(to: .xbIntro) }
                )

                Divider()

                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                    Text("Already set up and something isn't working?")
                        .font(MSC.Typography.cardTitle)
                    Button("Xbox Broadcast troubleshooting") {
                        guide.navigate(to: .xbTroubleshooting)
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                }
            }
            .padding(MSC.Spacing.xl)
        }
    }
}

// MARK: - Xbox Broadcast: Screen 1 — Introduction

private struct CGXBIntroScreen: View {
    @ObservedObject var guide: CrossPlatformGuideViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: MSC.Spacing.xl) {

                    CGScreenHeader(
                        title: "What is Xbox Broadcast?",
                        subtitle: "Makes your server appear in the Xbox friends list. Bedrock players join with one tap — no IP address needed."
                    )

                    CGCreditCallout(
                        color: .green,
                        text: "Built by the GeyserMC team. MSC manages it for you.",
                        githubURL: "https://github.com/GeyserMC/MCXboxBroadcastStandalone",
                        githubLabel: "GeyserMC/MCXboxBroadcastStandalone"
                    )

                    VStack(alignment: .leading, spacing: MSC.Spacing.md) {
                        CGFactRow(icon: "dot.radiowaves.left.and.right", text: "Runs as a background process alongside your Java server")
                        CGFactRow(icon: "person.crop.circle.badge.checkmark", text: "Signs into Xbox Live using a dedicated alt account you control")
                        CGFactRow(icon: "person.2", text: "Your Bedrock players see your server in their Friends tab")
                        CGFactRow(icon: "exclamationmark.triangle", text: "Requires a separate Microsoft account — not your real one")
                    }
                }
                .padding(MSC.Spacing.xl)
            }
            CGNavFooter(
                guide: guide,
                nextLabel: "Next: Install",
                nextScreen: .xbInstall
            )
        }
    }
}

// MARK: - Xbox Broadcast: Screen 2 — Install

private struct CGXBInstallScreen: View {
    @EnvironmentObject var viewModel: AppViewModel
    @ObservedObject var guide: CrossPlatformGuideViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: MSC.Spacing.lg) {

                    CGScreenHeader(
                        title: "Enable & download the helper",
                        subtitle: "MSC downloads and manages the MCXboxBroadcastStandalone JAR automatically. No manual file handling needed."
                    )

                    CGGuideCard(icon: "shippingbox", title: "Helper status") {
                        VStack(spacing: 0) {
                            CGFieldRow(label: "Installation") {
                                if viewModel.isXboxBroadcastHelperInstalled {
                                    HStack(spacing: 6) {
                                        Circle().fill(MSC.Colors.success).frame(width: 7, height: 7)
                                        Text("Installed").font(.system(size: 12)).foregroundStyle(MSC.Colors.success)
                                    }
                                } else {
                                    HStack(spacing: 6) {
                                        Circle().fill(.red).frame(width: 7, height: 7)
                                        Text("Not installed").font(.system(size: 12)).foregroundStyle(.red)
                                        Button("Download") { viewModel.downloadOrUpdateXboxBroadcastJar() }
                                            .buttonStyle(MSCSecondaryButtonStyle())
                                            .controlSize(.small)
                                    }
                                }
                            }
                            if let server = viewModel.selectedServer,
                               let cfg = viewModel.configServer(for: server) {
                                let propsModel = viewModel.loadServerPropertiesModel(for: cfg)
                                let port = cfg.xboxBroadcastPortOverride ?? propsModel.bedrockPort
                                CGFieldRow(label: "Bedrock port") {
                                    Text(port.map(String.init) ?? "—")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                CGFieldRow(label: "IP mode") {
                                    Text(cfg.xboxBroadcastIPMode.displayName)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    CGCallout(
                        icon: "info.circle.fill",
                        color: .orange,
                        text: "Public broadcasts your external IP (requires port forwarding). Private broadcasts your LAN IP (same network only). Your players must connect via the same mode you choose here."
                    )

                    CGGuideCard(icon: "gearshape", title: "Changing IP mode or port") {
                        Text("IP mode and port overrides are set in Edit Server → Broadcast tab. Come back to this guide after adjusting them if anything isn't working — IP mode mismatch is the most common cause of players not seeing your server.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(MSC.Spacing.xl)
            }
            CGNavFooter(
                guide: guide,
                nextLabel: "Next: Alt account",
                nextScreen: .xbAccount
            )
        }
    }
}

// MARK: - Xbox Broadcast: Screen 3 — Alt Account

private struct CGXBAccountScreen: View {
    @EnvironmentObject var viewModel: AppViewModel
    @ObservedObject var guide: CrossPlatformGuideViewModel

    @State private var email: String = ""
    @State private var gamertag: String = ""
    @State private var password: String = ""
    @State private var showPassword: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: MSC.Spacing.lg) {

                    CGScreenHeader(
                        title: "Set up a dedicated Microsoft account",
                        subtitle: "Xbox Broadcast stays signed into Xbox Live continuously while your server runs. You need a free dedicated account — not your real one."
                    )

                    CGCallout(
                        icon: "person.badge.plus",
                        color: .blue,
                        text: "Go to outlook.com and create a new free Microsoft account. Something like yourname-mc-broadcast@outlook.com is easy to remember. It doesn't need any subscriptions or Game Pass — just a valid Microsoft account."
                    )

                    CGGuideCard(icon: "person.fill.questionmark", title: "Why not your real account?") {
                        Text("Xbox Broadcast signs into Xbox Live constantly to keep the server visible. Using your real account means it's always \"signed in\" somewhere else, which can cause issues with other Xbox activity. A dedicated alt account keeps this completely separate.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    CGGuideCard(icon: "note.text", title: "Save your credentials (optional)") {
                        VStack(alignment: .leading, spacing: MSC.Spacing.md) {
                            Text("Store the email and password here so the app can remind you which account you used. These are saved locally — MSC does not use these credentials to sign in automatically. The actual Xbox sign-in happens in your browser the first time you start the server.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Divider().opacity(0.5)

                            CGFormField(label: "Alt email") {
                                TextField("broadcast-alt@outlook.com", text: $email)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12))
                            }
                            CGFormField(label: "Alt gamertag") {
                                TextField("Xbox gamertag (optional)", text: $gamertag)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12))
                            }
                            CGFormField(label: "Password") {
                                HStack(spacing: MSC.Spacing.xs) {
                                    if showPassword {
                                        TextField("Password (optional)", text: $password)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(size: 12))
                                    } else {
                                        SecureField("Password (optional)", text: $password)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(size: 12))
                                    }
                                    Button {
                                        showPassword.toggle()
                                    } label: {
                                        Image(systemName: showPassword ? "eye.slash" : "eye")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }

                            Text("These fields sync with Edit Server → Broadcast tab. If you've already filled them in there, they'll appear here. Changes here are reflected there immediately.")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(MSC.Spacing.xl)
            }
            CGNavFooter(
                guide: guide,
                nextLabel: "Next: Review settings",
                nextScreen: .xbSettings,
                onNext: saveAccountIfNeeded
            )
        }
        .onAppear { loadFromConfig() }
    }

    private func loadFromConfig() {
        guard let server = viewModel.selectedServer,
              let cfg = viewModel.configServer(for: server) else { return }
        email    = cfg.xboxBroadcastAltEmail    ?? ""
        gamertag = cfg.xboxBroadcastAltGamertag ?? ""
        password = KeychainManager.shared.readXboxBroadcastAltPassword(forServerId: cfg.id) ?? ""
    }

    private func saveAccountIfNeeded() {
        guard let server = viewModel.selectedServer,
              let cfg = viewModel.configServer(for: server) else { return }
        viewModel.updateBroadcastProfile(
            for: cfg.id,
            enabled: cfg.xboxBroadcastEnabled,
            ipMode: cfg.xboxBroadcastIPMode,
            altEmail: email,
            altGamertag: gamertag,
            altPassword: password,
            altAvatarPath: cfg.xboxBroadcastAltAvatarPath ?? ""
        )
    }
}

// MARK: - Xbox Broadcast: Screen 4 — Settings Review

private struct CGXBSettingsScreen: View {
    @EnvironmentObject var viewModel: AppViewModel
    @ObservedObject var guide: CrossPlatformGuideViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: MSC.Spacing.lg) {

                    CGScreenHeader(
                        title: "Settings review",
                        subtitle: "Everything should be in order before activating. Review the current state for your selected server."
                    )

                    if let server = viewModel.selectedServer,
                       let cfg = viewModel.configServer(for: server) {
                        let propsModel = viewModel.loadServerPropertiesModel(for: cfg)
                        let port = cfg.xboxBroadcastPortOverride ?? propsModel.bedrockPort

                        CGGuideCard(icon: "checklist", title: "Current configuration") {
                            VStack(spacing: 0) {
                                CGFieldRow(label: "Helper JAR") {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(viewModel.isXboxBroadcastHelperInstalled ? MSC.Colors.success : .red)
                                            .frame(width: 7, height: 7)
                                        Text(viewModel.isXboxBroadcastHelperInstalled ? "Installed" : "Not installed")
                                            .font(.system(size: 12))
                                            .foregroundStyle(viewModel.isXboxBroadcastHelperInstalled ? MSC.Colors.success : .red)
                                    }
                                }
                                CGFieldRow(label: "Bedrock port") {
                                    Text(port.map(String.init) ?? "—")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                CGFieldRow(label: "IP mode") {
                                    Text(cfg.xboxBroadcastIPMode.displayName)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                CGFieldRow(label: "Alt email") {
                                    Text(cfg.xboxBroadcastAltEmail.flatMap { $0.isEmpty ? nil : $0 } ?? "Not set")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(cfg.xboxBroadcastAltEmail?.isEmpty == false ? Color.secondary : Color.red)
                                }
                                CGFieldRow(label: "Auto-start") {
                                    Toggle("", isOn: Binding(
                                        get: { viewModel.selectedServerXboxBroadcastEnabled },
                                        set: { viewModel.selectedServerXboxBroadcastEnabled = $0 }
                                    ))
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                                }
                            }
                        }

                        CGCallout(
                            icon: "info.circle.fill",
                            color: .blue,
                            text: "Auto-start launches Xbox Broadcast every time your server starts. You almost certainly want this on."
                        )

                        if !viewModel.isXboxBroadcastHelperInstalled {
                            CGCallout(
                                icon: "exclamationmark.triangle.fill",
                                color: .orange,
                                text: "The helper JAR is not installed. Go back to the Install step and download it before continuing."
                            )
                        }

                    } else {
                        CGCallout(
                            icon: "server.rack",
                            color: .orange,
                            text: "No server is currently selected. Select a server in the sidebar to review its broadcast settings."
                        )
                    }
                }
                .padding(MSC.Spacing.xl)
            }
            CGNavFooter(
                guide: guide,
                nextLabel: "Next: Activate",
                nextScreen: .xbActivation
            )
        }
    }
}

// MARK: - Xbox Broadcast: Screen 5 — Activation

private struct CGXBActivationScreen: View {
    @EnvironmentObject var viewModel: AppViewModel
    @ObservedObject var guide: CrossPlatformGuideViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: MSC.Spacing.lg) {

                    CGScreenHeader(
                        title: "Activate Xbox Broadcast",
                        subtitle: "Time to start your server. The first run triggers a one-time Microsoft sign-in. Here's exactly what will happen so nothing surprises you."
                    )

                    CGGuideCard(icon: "1.circle.fill", title: "Start your server") {
                        Text("Start your server from the sidebar as normal, or use the button below. If auto-start is on, Xbox Broadcast will launch automatically alongside it.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    CGGuideCard(icon: "2.circle.fill", title: "Watch for a code and URL") {
                        Text("The first time Xbox Broadcast runs with a new account, it needs to verify your identity with Microsoft. MSC will display a short code (like AB3C7X) and a URL (microsoft.com/devicelogin). This will appear as a sheet in the app — you won't miss it.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    CGGuideCard(icon: "3.circle.fill", title: "Sign in with your alt account") {
                        Text("Open the URL in any browser, enter the code, and sign in with the dedicated alt account you created in the previous step. That's it. Microsoft marks your device as trusted, and Xbox Broadcast begins broadcasting. You only do this once per account.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    CGCallout(
                        icon: "checkmark.circle.fill",
                        color: .green,
                        text: "After sign-in, your server appears in the Xbox friends list automatically every time it runs. You only do this once per account."
                    )

                    if viewModel.selectedServer != nil {
                        Button {
                            if !viewModel.isServerRunning {
                                viewModel.startServer()
                            }
                        } label: {
                            Label(
                                viewModel.isServerRunning ? "Server is running" : "Start server now",
                                systemImage: viewModel.isServerRunning ? "checkmark.circle.fill" : "play.circle.fill"
                            )
                        }
                        .buttonStyle(MSCPrimaryButtonStyle())
                        .disabled(viewModel.isServerRunning)
                    }
                }
                .padding(MSC.Spacing.xl)
            }
            CGNavFooter(
                guide: guide,
                nextLabel: "Troubleshooting →",
                nextScreen: .xbTroubleshooting,
                nextIsSecondary: true,
                doneLabel: "Done"
            )
        }
    }
}

// MARK: - Xbox Broadcast: Troubleshooting

private struct CGXBTroubleshootingScreen: View {
    @EnvironmentObject var viewModel: AppViewModel
    @ObservedObject var guide: CrossPlatformGuideViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: MSC.Spacing.lg) {

                    CGScreenHeader(
                        title: "Xbox Broadcast troubleshooting",
                        subtitle: "Match your symptom to a fix."
                    )

                    CGTroubleshootItem(
                        symptom: "Players can't see the server in the friends list",
                        fix: "Almost always IP mode mismatch. Check Edit Server → Broadcast tab — Public requires port forwarding, Private requires same local network.",
                        detail: "If IP mode is Public, the player must be connecting from outside your network and you must have port forwarded your Bedrock port. If it's Private, the player must be on the same Wi-Fi as you. These need to match exactly."
                    )

                    CGTroubleshootItem(
                        symptom: "Players can see the server but can't connect",
                        fix: "Broadcast is working but Bedrock connection is failing. Check Geyser is up to date in the Components tab.",
                        detail: "This is a Geyser or port forwarding issue, not an Xbox Broadcast issue. Confirm Geyser shows as up to date in the Components tab. Also confirm your Bedrock port (default 19132) is forwarded in your router."
                    )

                    CGTroubleshootItem(
                        symptom: "Device login code never appeared",
                        fix: "Delete the 'accounts' folder in the broadcast config folder, then restart the server.",
                        detail: "Open the broadcast config folder via Edit Server → Broadcast → Open Config Folder. Delete the 'accounts' folder inside it. Restart the server to force a fresh Microsoft sign-in."
                    )

                    CGTroubleshootItem(
                        symptom: "Was working, now players can't see it",
                        fix: "Alt account session expired. Delete the 'accounts' folder and restart to re-authenticate.",
                        detail: "Microsoft sessions eventually expire or get invalidated. Delete the 'accounts' folder in the broadcast config directory (Edit Server → Broadcast → Open Config Folder) and restart the server."
                    )
                }
                .padding(MSC.Spacing.xl)
            }
            CGNavFooter(guide: guide, showDoneOnly: true)
        }
    }
}

// MARK: - Shared Components

private struct CGScreenHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
            Text(title)
                .font(MSC.Typography.pageTitle)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CGGuideCard<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
            HStack(spacing: MSC.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(title)
                    .font(MSC.Typography.cardTitle)
            }
            content()
                .padding(.leading, 24)
        }
        .padding(MSC.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .fill(Color(red: 0.18, green: 0.18, blue: 0.21))
                .overlay(
                    RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }
}

private struct CGCallout: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: MSC.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
                .frame(width: 16, alignment: .top)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(MSC.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .fill(color.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                        .strokeBorder(color.opacity(0.20), lineWidth: 0.5)
                )
        )
    }
}

private struct CGFieldRow<Content: View>: View {
    let label: String
    @ViewBuilder let value: () -> Content

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            value()
        }
        .padding(.vertical, MSC.Spacing.xs)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5)
        }
    }
}

private struct CGFormField<Content: View>: View {
    let label: String
    @ViewBuilder let field: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            field()
        }
    }
}

private struct CGStepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: MSC.Spacing.sm) {
            Text("\(number)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.secondary.opacity(0.15)))
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CGTroubleshootItem: View {
    let symptom: String
    let fix: String
    let detail: String
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
            HStack(spacing: MSC.Spacing.xs) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                Text(symptom)
                    .font(.system(size: 12, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(fix)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 18)

            if isExpanded {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 18)
                    .padding(.top, 2)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text(isExpanded ? "Less" : "More detail")
                        .font(.system(size: 11))
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 18)
        }
        .padding(MSC.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .fill(Color(red: 0.18, green: 0.18, blue: 0.21))
                .overlay(
                    RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }
}

private struct CGCreditCallout: View {
    let color: Color
    let text: String
    let githubURL: String
    let githubLabel: String

    var body: some View {
        HStack(alignment: .top, spacing: MSC.Spacing.sm) {
            Image(systemName: "heart.fill")
                .font(.system(size: 11))
                .foregroundStyle(color)
                .frame(width: 16, alignment: .top)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Link(githubLabel, destination: URL(string: githubURL)!)
                    .font(.system(size: 11))
                    .foregroundStyle(color.opacity(0.85))
            }
        }
        .padding(MSC.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .fill(color.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                        .strokeBorder(color.opacity(0.20), lineWidth: 0.5)
                )
        )
    }
}

private struct CGFactRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: MSC.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .top)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CGLandingCard: View {
    let label: String
    let labelColor: Color
    let title: String
    let description: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: MSC.Spacing.md) {
                VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                    Text(label)
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(labelColor)
                    Text(title)
                        .font(MSC.Typography.cardTitle)
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
            .padding(MSC.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                    .fill(Color(red: 0.18, green: 0.18, blue: 0.21))
                    .overlay(
                        RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                            .strokeBorder(labelColor.opacity(0.25), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Nav Footer

private struct CGNavFooter: View {
    @EnvironmentObject var viewModel: AppViewModel
    @ObservedObject var guide: CrossPlatformGuideViewModel
    @Environment(\.dismiss) private var dismiss

    var nextLabel: String = ""
    var nextScreen: CGScreen? = nil
    var nextIsSecondary: Bool = false
    var doneLabel: String? = nil
    var showDoneOnly: Bool = false
    var onNext: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                if guide.canGoBack {
                    Button("← Back") {
                        guide.goBack()
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                }
                Spacer()
                if showDoneOnly {
                    Button("Done") { dismiss() }
                        .buttonStyle(MSCPrimaryButtonStyle())
                } else {
                    if let nextScreen = nextScreen {
                        if nextIsSecondary {
                            Button(nextLabel) {
                                onNext?()
                                guide.navigate(to: nextScreen)
                            }
                            .buttonStyle(MSCSecondaryButtonStyle())
                        } else {
                            Button(nextLabel) {
                                onNext?()
                                guide.navigate(to: nextScreen)
                            }
                            .buttonStyle(MSCPrimaryButtonStyle())
                        }
                    }
                    if let doneLabel = doneLabel {
                        Button(doneLabel) { dismiss() }
                            .buttonStyle(MSCPrimaryButtonStyle())
                    }
                }
            }
            .padding(.horizontal, MSC.Spacing.xl)
            .padding(.vertical, MSC.Spacing.md)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
}


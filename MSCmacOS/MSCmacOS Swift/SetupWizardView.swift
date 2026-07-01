//
//  SetupWizardView.swift
//  MinecraftServerController
//
//  First-run setup flow for choosing a servers root and validating the
//  local requirements for Java and/or Bedrock hosting.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Docker Check Status

private enum DockerCheckStatus: Equatable {
    case unknown
    case checking
    case running
    case notRunning
    case notInstalled
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

    @State private var serversRoot: String = ""
    @State private var javaPath: String = ""
    @State private var isInitialRun: Bool = false
    @State private var accentColor: Color = .green

    // Server type selection
    @State private var wantsJava: Bool = true
    @State private var wantsBedrock: Bool = false

    // Detection state
    @State private var javaStatus: JavaCheckStatus = .unknown
    @State private var dockerStatus: DockerCheckStatus = .unknown
    @State private var tailscaleStatus: TailscaleCheckStatus = .unknown
    @State private var isDownloadingJava = false
    @State private var isDownloadingDocker = false

    // MARK: - Validation

    private var hasValidServersRoot: Bool {
        !serversRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasValidJava: Bool {
        if case .found(let p) = javaStatus, !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return !javaPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isContinueDisabled: Bool {
        guard wantsJava || wantsBedrock else { return true }
        guard hasValidServersRoot else { return true }
        if wantsJava && !hasValidJava { return true }
        // Bedrock VM backend: no Docker required — virtualization is built-in.
        return false
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {

            // Hero Banner
            heroHeader

            // Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
                    serverTypePicker
                    accentColorCard
                    serversRootCard

                    if wantsJava {
                        javaCard
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if wantsBedrock {
                        vmBedrockCard
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    tailscaleCard
                }
                .padding(MSC.Spacing.xl)
                .animation(.easeInOut(duration: 0.2), value: wantsJava)
                .animation(.easeInOut(duration: 0.2), value: wantsBedrock)
            }

            footer
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 520)
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
            .frame(height: 130)
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

            HStack(alignment: .center, spacing: MSC.Spacing.lg) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white.opacity(0.12))
                        .frame(width: 52, height: 52)
                    Image(systemName: "server.rack")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("First-time Setup")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Choose where your servers will live and set up the tools you need.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, MSC.Spacing.xl)
            .padding(.bottom, MSC.Spacing.xl)

            if !isInitialRun {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .semibold))
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

    // MARK: - Server Type Picker

    private var serverTypePicker: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
            Label("What type of servers will you run?", systemImage: "questionmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            HStack(spacing: MSC.Spacing.md) {
                serverTypeToggleCard(
                    label: "Java Servers",
                    subtitle: "Paper, Purpur, Fabric & more\nPlugin ecosystem",
                    icon: "cup.and.saucer.fill",
                    color: .orange,
                    isOn: $wantsJava
                )
                serverTypeToggleCard(
                    label: "Bedrock Servers",
                    subtitle: "Mobile, console\n& Windows 10/11",
                    icon: "cube.fill",
                    color: .green,
                    isOn: $wantsBedrock
                )
            }

            if !wantsJava && !wantsBedrock {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("Select at least one server type to continue.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, MSC.Spacing.xs)
            }
        }
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
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 11))
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

    // MARK: - Servers Root Card

    private var accentColorCard: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
            Label("Pick an accent color", systemImage: "paintpalette.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Text("This tints the app shell and tour overlays. You can change it anytime in preferences.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

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
        .padding(MSC.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.lg, style: .continuous)
                .fill(MSC.Colors.cardBackground.opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MSC.Radius.lg, style: .continuous)
                .stroke(MSC.Colors.cardBorder, lineWidth: 1)
        )
    }

    private var serversRootCard: some View {
        setupCard(
            icon: "folder.fill",
            iconColor: .blue,
            title: "Servers Root Folder",
            subtitle: "All your servers will live inside this folder."
        ) {
            HStack(spacing: MSC.Spacing.sm) {
                Image(systemName: hasValidServersRoot ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 13))
                    .foregroundStyle(hasValidServersRoot ? .green : .secondary)

                TextField("~/MinecraftServers", text: $serversRoot)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))

                Button("Browse\u{2026}") { browseForServersRoot() }
                    .controlSize(.small)
            }
        }
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
                        .font(.system(size: 12, design: .monospaced))

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
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No Java found on PATH. Install the current Temurin LTS, then click Check for Java again.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            if isDownloadingJava {
                                HStack(spacing: 6) {
                                    ProgressView().scaleEffect(0.65)
                                    Text("Downloading installer\u{2026}")
                                        .font(.system(size: 11))
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
                                    .font(.system(size: 11))
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
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.55)
                Text("Checking\u{2026}")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        case .found(let path):
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
                Text("Found at \(path)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        case .notFound:
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                Text("Not found")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Bedrock VM Card

    private var vmBedrockCard: some View {
        setupCard(
            icon: "memorychip",
            iconColor: .green,
            title: "Bedrock Server — Built In",
            subtitle: "No external software required. The app runs Bedrock Dedicated Server in a lightweight built-in virtual machine."
        ) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
                    .padding(.top, 1)
                Text("Ready. Bedrock servers start instantly — no Docker, no installs.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(MSC.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                    .fill(Color.green.opacity(0.08))
            )
        }
    }

    // MARK: - Docker Card (kept for reference — Docker path no longer used)

    /* private var dockerCard: some View {
        setupCard(
            icon: "shippingbox.fill",
            iconColor: .green,
            title: "Docker Desktop",
            subtitle: "Bedrock Dedicated Server runs in a Docker container. Install once \u{2014} the app manages everything after that."
        ) {
            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                HStack(spacing: MSC.Spacing.sm) {
                    Button("Check Again") { checkDocker() }
                        .controlSize(.small)
                    dockerStatusBadge
                    Spacer()
                }

                switch dockerStatus {
                case .notInstalled:
                    VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                        // Tier 3 + Tier 1: install button with DMG download, or manual link
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.blue)
                                .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Docker Desktop is not installed. It\u{2019}s free for personal use.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                if isDownloadingDocker {
                                    HStack(spacing: 6) {
                                        ProgressView().scaleEffect(0.65)
                                        Text("Downloading installer\u{2026} (this is a large file)")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    HStack(spacing: MSC.Spacing.sm) {
                                        Button("Install Docker Desktop") {
                                            downloadAndInstallDocker()
                                        }
                                        .controlSize(.mini)
                                        .buttonStyle(.borderedProminent)

                                        Button("Manual Download \u{2192}") {
                                            openDockerDownloadPage()
                                        }
                                        .font(.system(size: 11))
                                        .foregroundStyle(.blue)
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(MSC.Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                                .fill(Color.blue.opacity(0.08))
                        )

                        // Tier 2: Docker Hub account note
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("You\u{2019}ll also need a free Docker Hub account to sign in when you first launch Docker Desktop.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Button("Sign up at hub.docker.com \u{2192}") {
                                    NSWorkspace.shared.open(URL(string: "https://hub.docker.com/signup")!)
                                }
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(MSC.Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )
                    }
                case .notRunning:
                    inlineHelpCard(
                        icon: "exclamationmark.triangle.fill",
                        color: .orange,
                        message: "Docker is installed but not running. Open Docker Desktop, wait for the whale icon in your menu bar, then click Check Again.",
                        actionLabel: nil,
                        action: nil
                    )
                case .running:
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.green)
                            .padding(.top, 1)
                        Text("Docker is ready. The app will pull the Bedrock server image automatically on first start.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(MSC.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                            .fill(Color.green.opacity(0.08))
                    )
                default:
                    EmptyView()
                }
            }
        }
    }

    @ViewBuilder
    private var dockerStatusBadge: some View {
        switch dockerStatus {
        case .unknown:
            Text("Not checked yet")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.55)
                Text("Checking\u{2026}")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        case .running:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
                Text("Docker is running")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        case .notRunning:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                Text("Not running")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        case .notInstalled:
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                Text("Not installed")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
    */ // end commented-out dockerCard + dockerStatusBadge

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
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
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

    private func inlineHelpCard(
        icon: String,
        color: Color,
        message: String,
        actionLabel: String?,
        action: (() -> Void)?
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if let label = actionLabel, let action = action {
                    Button(label) { action() }
                        .font(.system(size: 11))
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

    // MARK: - Tailscale Card

    private var tailscaleCard: some View {
        setupCard(
            icon: "network",
            iconColor: .blue,
            title: "Tailscale  ·  Optional",
            subtitle: "Access your servers remotely from anywhere, even on mobile or a different network. Not required to continue."
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
                    inlineHelpCard(
                        icon: "info.circle.fill",
                        color: .blue,
                        message: "Tailscale isn\u{2019}t installed. It\u{2019}s free for personal use and takes about a minute to set up.",
                        actionLabel: "Download Tailscale \u{2192}",
                        action: { NSWorkspace.shared.open(URL(string: "https://tailscale.com/download/mac")!) }
                    )
                case .installed:
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.green)
                            .padding(.top, 1)
                        Text("Tailscale is installed. Enable it and join your tailnet to access servers remotely.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(MSC.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                            .fill(Color.green.opacity(0.08))
                    )
                default:
                    EmptyView()
                }
            }
        }
    }

    @ViewBuilder
    private var tailscaleStatusBadge: some View {
        switch tailscaleStatus {
        case .unknown:
            Text("Not checked yet")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.55)
                Text("Checking\u{2026}")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        case .installed:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
                Text("Installed")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        case .notInstalled:
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                Text("Not installed")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                if !isInitialRun {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(MSCSecondaryButtonStyle())
                }

                Spacer()

                // Contextual hint
                Group {
                    if !wantsJava && !wantsBedrock {
                        Text("Select a server type above")
                    } else if wantsJava && !hasValidJava {
                        Text("Java path required")
                    } else if !hasValidServersRoot {
                        Text("Servers folder required")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

                Button {
                    applyAndDismiss()
                } label: {
                    HStack(spacing: 6) {
                        Text("Continue")
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .disabled(isContinueDisabled)
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(MSCPrimaryButtonStyle())
            }
            .padding(.horizontal, MSC.Spacing.xl)
            .padding(.vertical, MSC.Spacing.md)
        }
        .background(Color(nsColor: .windowBackgroundColor))
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
                // Detect architecture at compile time — reliable regardless of Rosetta
                #if arch(arm64)
                let arch = "aarch64"
                #else
                let arch = "x64"
                #endif

                // Find the most recent LTS version from Adoptium
                let releasesURL = URL(string: "https://api.adoptium.net/v3/info/available_releases")!
                let (relData, _) = try await URLSession.shared.data(from: releasesURL)
                let ltsVersion: Int
                if let relJson = try JSONSerialization.jsonObject(with: relData) as? [String: Any],
                   let v = relJson["most_recent_lts"] as? Int {
                    ltsVersion = v
                } else {
                    ltsVersion = 21
                }

                // Fetch the PKG asset for that LTS + this machine's architecture
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

                // Download the PKG to a temp location and open it
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
            // Known locations Docker Desktop installs its CLI on macOS.
            // Also try PATH-derived locations as a fallback.
            let candidatePaths = [
                "/usr/local/bin/docker",
                "/opt/homebrew/bin/docker",        // Apple Silicon Homebrew
                "/usr/bin/docker",
                "/Applications/Docker.app/Contents/Resources/bin/docker"
            ]

            let fm = FileManager.default
            guard let dockerPath = candidatePaths.first(where: { fm.isExecutableFile(atPath: $0) }) else {
                DispatchQueue.main.async { self.dockerStatus = .notInstalled }
                return
            }

            // Binary found — now check if the daemon is responding via `docker info`
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
                // Binary exists but couldn't run — treat as not running
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


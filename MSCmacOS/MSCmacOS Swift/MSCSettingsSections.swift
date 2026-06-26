import SwiftUI
import Network

struct PreferencesJavaSection: View {
    @Binding var javaPath: String
    @Binding var extraFlags: String
    let anchorID: String

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {
            Label("Java", systemImage: "terminal")
                .font(MSC.Typography.cardTitle)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                Text("Java executable path")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.caption)
                TextField("Path to java executable", text: $javaPath)
                    .textFieldStyle(.roundedBorder)
                    .font(MSC.Typography.mono)
            }

            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                Text("Extra JVM flags")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.caption)
                TextField("Optional JVM flags (e.g. -XX:+UseG1GC)", text: $extraFlags, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(MSC.Typography.mono)
                    .lineLimit(3, reservesSpace: true)
                Text("Optional flags passed to Java when starting servers. Leave blank unless you know what you're doing (e.g. GC tuning flags).")
                    .font(.caption2)
                    .foregroundStyle(MSC.Colors.tertiary)
            }
        }
        .pscCard()
        .id(anchorID)
        .contextualHelpAnchor(anchorID)
    }
}

struct PreferencesProcessCleanupSection: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var detectedCount: Int? = nil
    @State private var isScanning: Bool = false
    @State private var watchdogInFlight: Bool = false
    @State private var watchdogError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {
            Label("Process Management", systemImage: "terminal")
                .font(MSC.Typography.cardTitle)
                .foregroundStyle(.secondary)

            Divider()

            Text("If MSC crashes, Java server processes it launched may continue running in the background. Use this to detect and clean them up.")
                .font(.caption2)
                .foregroundStyle(MSC.Colors.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: MSC.Spacing.sm) {
                Button {
                    isScanning = true
                    viewModel.scanOrphansInBackground { count in
                        detectedCount = count
                        isScanning = false
                    }
                } label: {
                    if isScanning {
                        HStack(spacing: MSC.Spacing.xs) {
                            ProgressView().controlSize(.mini)
                            Text("Scanning…")
                        }
                    } else {
                        Text("Scan for Orphaned Processes")
                    }
                }
                .buttonStyle(MSCSecondaryButtonStyle())
                .disabled(isScanning)

                if let count = detectedCount {
                    if count == 0 {
                        Label("None found", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(MSC.Colors.success)
                    } else {
                        HStack(spacing: MSC.Spacing.xs) {
                            Label("\(count) found", systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.orange)

                            Button("Kill All") {
                                viewModel.killJavaServerProcesses()
                                viewModel.orphanedJavaProcessCount = 0
                                detectedCount = 0
                            }
                            .buttonStyle(MSCDestructiveButtonStyle())
                            .controlSize(.small)
                        }
                    }
                }
            }

            Divider().opacity(0.5)

            // ── WATCHDOG ────────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                HStack(spacing: MSC.Spacing.sm) {
                    Toggle(
                        "Relaunch MSC on crash",
                        isOn: Binding(
                            get: { viewModel.watchdogEnabled },
                            set: { newValue in
                                guard !watchdogInFlight else { return }
                                watchdogInFlight = true
                                watchdogError = nil
                                Task {
                                    do {
                                        if newValue { try await viewModel.enableWatchdog() }
                                        else        { try await viewModel.disableWatchdog() }
                                    } catch {
                                        watchdogError = error.localizedDescription
                                    }
                                    watchdogInFlight = false
                                }
                            }
                        )
                    )
                    .toggleStyle(.switch)
                    .disabled(watchdogInFlight)

                    if watchdogInFlight {
                        ProgressView().controlSize(.mini)
                    }
                }

                if let err = watchdogError {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if viewModel.watchdogEnabled && !watchdogInFlight {
                    Label("Watchdog active — MSC will relaunch on crash.", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(MSC.Colors.success)
                } else if !viewModel.watchdogEnabled && !watchdogInFlight {
                    Text("When enabled, launchd monitors MSC and relaunches it on a crash. Normal Cmd+Q does not trigger a relaunch.")
                        .font(.caption2)
                        .foregroundStyle(MSC.Colors.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .pscCard()
        .onAppear {
            // Pre-populate from the startup scan so the user sees results immediately
            // without having to click Scan if the app already detected orphans.
            if viewModel.orphanedJavaProcessCount > 0 {
                detectedCount = viewModel.orphanedJavaProcessCount
            }
        }
    }
}

struct PreferencesRemoteAPISection: View {
    @Binding var remoteAPIExposeOnLAN: Bool
    @Binding var preferredPairingHostInput: String
    @Binding var newSharedAccessLabel: String
    @Binding var newSharedAccessRole: String
    @Binding var showPairingQR: Bool
    @Binding var pairingLinkForQR: String
    @Binding var showCopiedAlert: Bool
    @Binding var copiedMessage: String
    @Binding var showRegenerateTokenConfirm: Bool

    let config: AppConfig
    let port: Int
    let tailscaleIP: String?
    let recommendedHost: String?
    let cardAnchorID: String
    let toggleAnchorID: String
    let urlBoxAnchorID: String
    let preferredHostAnchorID: String
    let actionsAnchorID: String
    let onCopyToClipboard: (String) -> Void
    let onBuildPairingLink: (String) -> String
    let onAddSharedAccessEntry: (String) -> Void
    let onRevokeSharedAccessEntry: (String) -> Void
    let onSetSharedAccessEntryRole: (String, String) -> Void
    let onRegenerateToken: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {
            Label("Remote Access", systemImage: "iphone.and.arrow.forward")
                .font(MSC.Typography.cardTitle)
                .foregroundStyle(.secondary)

            Divider()

            HStack {
                Toggle("Expose Remote API on LAN/VPN (opt-in)", isOn: $remoteAPIExposeOnLAN)
                    .toggleStyle(.switch)
                Spacer()
                PreferencesModeBadge(enabled: remoteAPIExposeOnLAN)
            }
            .id(toggleAnchorID)
            .contextualHelpAnchor(toggleAnchorID)

            PreferencesRemoteAPIURLBox(
                remoteAPIExposeOnLAN: remoteAPIExposeOnLAN,
                port: port,
                recommendedHost: recommendedHost,
                tailscaleIP: tailscaleIP
            )
            .id(urlBoxAnchorID)
            .contextualHelpAnchor(urlBoxAnchorID)

            Divider().opacity(0.5)

            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                Text("Preferred pairing host")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.caption)
                TextField("e.g. your-mac.ts.net", text: $preferredPairingHostInput)
                    .textFieldStyle(.roundedBorder)
                    .font(MSC.Typography.mono)
                Text("MagicDNS hostname recommended. If set, QR and pairing links use this instead of a raw IP.")
                    .font(.caption2)
                    .foregroundStyle(MSC.Colors.tertiary)
            }
            .id(preferredHostAnchorID)
            .contextualHelpAnchor(preferredHostAnchorID)

            VStack(alignment: .leading, spacing: MSC.Spacing.md) {
                PreferencesPairingActionsRow(
                    showPairingQR: $showPairingQR,
                    pairingLinkForQR: $pairingLinkForQR,
                    showCopiedAlert: $showCopiedAlert,
                    copiedMessage: $copiedMessage,
                    showRegenerateTokenConfirm: $showRegenerateTokenConfirm,
                    token: config.remoteAPIToken,
                    onCopyToClipboard: onCopyToClipboard,
                    onBuildPairingLink: onBuildPairingLink,
                    onRegenerateToken: onRegenerateToken
                )

                Divider().opacity(0.5)

                PreferencesSharedAccessSection(
                    newSharedAccessLabel: $newSharedAccessLabel,
                    newSharedAccessRole: $newSharedAccessRole,
                    showPairingQR: $showPairingQR,
                    pairingLinkForQR: $pairingLinkForQR,
                    showCopiedAlert: $showCopiedAlert,
                    copiedMessage: $copiedMessage,
                    sharedAccess: config.remoteAPISharedAccess,
                    onCopyToClipboard: onCopyToClipboard,
                    onBuildPairingLink: onBuildPairingLink,
                    onAddSharedAccessEntry: onAddSharedAccessEntry,
                    onRevokeSharedAccessEntry: onRevokeSharedAccessEntry,
                    onSetRole: onSetSharedAccessEntryRole
                )
            }
            .id(actionsAnchorID)
            .contextualHelpAnchor(actionsAnchorID)

            DisclosureGroup("Details") {
                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                    Text("When OFF, the Remote API binds to 127.0.0.1 (this Mac only). When ON, it binds to 0.0.0.0 (all interfaces), so your iPhone can reach it over LAN and/or VPN (e.g. Tailscale). Your bearer token is still required for all requests.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Pairing link format: mscremote://pair?base=<baseURL>&token=<token>")
                        .font(MSC.Typography.monoSmall)
                        .foregroundStyle(MSC.Colors.tertiary)
                    Text("Admin tokens have full control. Guest tokens allow view-only access and start/stop only — no commands, no config changes. Shared access tokens can be individually set to Admin or Guest and revoked at any time.")
                        .font(.caption2)
                        .foregroundStyle(MSC.Colors.tertiary)
                }
                .padding(.top, MSC.Spacing.sm)
            }
            .font(MSC.Typography.caption)
        }
        .pscCard()
        .id(cardAnchorID)
        .contextualHelpAnchor(cardAnchorID)
    }
}

private struct PreferencesRemoteAPIURLBox: View {
    let remoteAPIExposeOnLAN: Bool
    let port: Int
    let recommendedHost: String?
    let tailscaleIP: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                .fill(MSC.Colors.insetBackground)

            if !remoteAPIExposeOnLAN {
                VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                    PreferencesURLRow(label: "Remote API", url: "http://127.0.0.1:\(port)")
                    HStack(spacing: MSC.Spacing.xs) {
                        Image(systemName: "iphone.slash")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("Turn this ON to pair with iOS (LAN/VPN).")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(MSC.Spacing.md)
                .transition(.opacity)
            }

            if remoteAPIExposeOnLAN {
                VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                    PreferencesURLRow(label: "Remote API", url: "http://127.0.0.1:\(port)")
                    if let host = recommendedHost {
                        PreferencesURLRow(label: "Best pairing URL", url: "http://\(host):\(port)")
                    }
                    if let ts = tailscaleIP {
                        HStack(spacing: MSC.Spacing.xs) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(MSC.Colors.success)
                            Text("Tailscale detected: \(ts)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack(alignment: .top, spacing: MSC.Spacing.xs) {
                            Image(systemName: "info.circle")
                                .font(.caption2)
                                .foregroundStyle(MSC.Colors.info)
                                .padding(.top, 1)
                            Text("Tailscale not detected. For away-from-home control, install/enable Tailscale on both devices.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text("Same Wi-Fi works without Tailscale. Not on the same Wi-Fi? Use a VPN like Tailscale.")
                        .font(.caption2)
                        .foregroundStyle(MSC.Colors.tertiary)
                }
                .padding(MSC.Spacing.md)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 90)
        .animation(.easeInOut(duration: 0.18), value: remoteAPIExposeOnLAN)
    }
}

private struct PreferencesPairingActionsRow: View {
    @Binding var showPairingQR: Bool
    @Binding var pairingLinkForQR: String
    @Binding var showCopiedAlert: Bool
    @Binding var copiedMessage: String
    @Binding var showRegenerateTokenConfirm: Bool

    let token: String
    let onCopyToClipboard: (String) -> Void
    let onBuildPairingLink: (String) -> String
    let onRegenerateToken: () -> Void

    var body: some View {
        HStack(spacing: MSC.Spacing.lg) {
            Button("Copy Token") {
                onCopyToClipboard(token)
                copiedMessage = "Token copied."
                showCopiedAlert = true
            }
            .buttonStyle(MSCSecondaryButtonStyle())

            Button("Copy Pairing Link") {
                let link = onBuildPairingLink(token)
                onCopyToClipboard(link)
                copiedMessage = "Pairing link copied."
                showCopiedAlert = true
            }
            .buttonStyle(MSCSecondaryButtonStyle())

            Button("Show Pairing QR") {
                pairingLinkForQR = onBuildPairingLink(token)
                showPairingQR = true
            }
            .buttonStyle(MSCSecondaryButtonStyle())

            Button("New Token…") {
                showRegenerateTokenConfirm = true
            }
            .buttonStyle(MSCDestructiveButtonStyle())
        }
        .controlSize(.small)
        .alert("Regenerate token?", isPresented: $showRegenerateTokenConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Regenerate", role: .destructive) {
                onRegenerateToken()
            }
        } message: {
            Text("This will immediately invalidate existing iOS pairings that use the old token.")
        }
    }
}

private struct PreferencesSharedAccessSection: View {
    @Binding var newSharedAccessLabel: String
    @Binding var newSharedAccessRole: String
    @Binding var showPairingQR: Bool
    @Binding var pairingLinkForQR: String
    @Binding var showCopiedAlert: Bool
    @Binding var copiedMessage: String

    let sharedAccess: [RemoteAPISharedAccessEntry]
    let onCopyToClipboard: (String) -> Void
    let onBuildPairingLink: (String) -> String
    let onAddSharedAccessEntry: (String) -> Void
    let onRevokeSharedAccessEntry: (String) -> Void
    let onSetRole: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: MSC.Spacing.xxs) {
                    Text("Shared access")
                        .font(MSC.Typography.cardTitle)
                    Text("Add a label, choose a role, share the pairing link or QR, and revoke anytime.")
                        .font(.caption2)
                        .foregroundStyle(MSC.Colors.tertiary)
                }
                Spacer()
                Picker("", selection: $newSharedAccessRole) {
                    Text("Admin").tag("admin")
                    Text("Guest").tag("guest")
                }
                .pickerStyle(.segmented)
                .frame(width: 110)
                .controlSize(.small)
                TextField("Label (e.g. Josh's iPhone)", text: $newSharedAccessLabel)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(width: 170)
                Button("Add") {
                    onAddSharedAccessEntry(newSharedAccessLabel)
                }
                .buttonStyle(MSCSecondaryButtonStyle())
                .disabled(newSharedAccessLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .controlSize(.small)
            }

            if sharedAccess.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: MSC.Spacing.sm) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 22))
                            .foregroundStyle(MSC.Colors.tertiary)
                        Text("No shared access entries")
                            .font(MSC.Typography.caption)
                            .foregroundStyle(MSC.Colors.caption)
                        Text("Add a label above to grant a friend or device access.")
                            .font(.caption2)
                            .foregroundStyle(MSC.Colors.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, MSC.Spacing.lg)
                    Spacer()
                }
                .background(
                    RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                        .fill(MSC.Colors.insetBackground)
                )
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(sharedAccess.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Divider().padding(.horizontal, MSC.Spacing.sm)
                        }
                        PreferencesSharedAccessRow(
                            entry: entry,
                            showPairingQR: $showPairingQR,
                            pairingLinkForQR: $pairingLinkForQR,
                            showCopiedAlert: $showCopiedAlert,
                            copiedMessage: $copiedMessage,
                            onCopyToClipboard: onCopyToClipboard,
                            onBuildPairingLink: onBuildPairingLink,
                            onRevokeSharedAccessEntry: onRevokeSharedAccessEntry,
                            onSetRole: onSetRole
                        )
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                        .fill(MSC.Colors.insetBackground)
                )
            }
        }
    }
}

private struct PreferencesSharedAccessRow: View {
    let entry: RemoteAPISharedAccessEntry
    @Binding var showPairingQR: Bool
    @Binding var pairingLinkForQR: String
    @Binding var showCopiedAlert: Bool
    @Binding var copiedMessage: String

    let onCopyToClipboard: (String) -> Void
    let onBuildPairingLink: (String) -> String
    let onRevokeSharedAccessEntry: (String) -> Void
    let onSetRole: (String, String) -> Void

    @State private var roleDraft: String

    init(
        entry: RemoteAPISharedAccessEntry,
        showPairingQR: Binding<Bool>,
        pairingLinkForQR: Binding<String>,
        showCopiedAlert: Binding<Bool>,
        copiedMessage: Binding<String>,
        onCopyToClipboard: @escaping (String) -> Void,
        onBuildPairingLink: @escaping (String) -> String,
        onRevokeSharedAccessEntry: @escaping (String) -> Void,
        onSetRole: @escaping (String, String) -> Void
    ) {
        self.entry = entry
        self._showPairingQR = showPairingQR
        self._pairingLinkForQR = pairingLinkForQR
        self._showCopiedAlert = showCopiedAlert
        self._copiedMessage = copiedMessage
        self.onCopyToClipboard = onCopyToClipboard
        self.onBuildPairingLink = onBuildPairingLink
        self.onRevokeSharedAccessEntry = onRevokeSharedAccessEntry
        self.onSetRole = onSetRole
        self._roleDraft = State(initialValue: entry.role)
    }

    var body: some View {
        HStack(spacing: MSC.Spacing.sm) {
            Image(systemName: entry.role == "guest" ? "eyes" : "iphone")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(entry.label.isEmpty ? "Unnamed" : entry.label)
                .font(.system(size: 13))
                .lineLimit(1)

            Spacer()

            HStack(spacing: MSC.Spacing.xs) {
                Picker("", selection: $roleDraft) {
                    Text("Admin").tag("admin")
                    Text("Guest").tag("guest")
                }
                .pickerStyle(.segmented)
                .frame(width: 110)
                .onChange(of: roleDraft) { _, newRole in
                    onSetRole(entry.id, newRole)
                }

                Button("Copy Link") {
                    let link = onBuildPairingLink(entry.token)
                    onCopyToClipboard(link)
                    copiedMessage = "Pairing link copied for \(entry.label.isEmpty ? "shared entry" : entry.label)."
                    showCopiedAlert = true
                }
                .buttonStyle(MSCSecondaryButtonStyle())

                Button("QR") {
                    pairingLinkForQR = onBuildPairingLink(entry.token)
                    showPairingQR = true
                }
                .buttonStyle(MSCSecondaryButtonStyle())

                Button("Revoke") {
                    onRevokeSharedAccessEntry(entry.id)
                }
                .buttonStyle(MSCDestructiveButtonStyle())
            }
            .controlSize(.small)
        }
        .padding(.horizontal, MSC.Spacing.md)
        .padding(.vertical, MSC.Spacing.sm)
    }
}

struct PreferencesDataFoldersSection: View {
    let isServerFolderButtonDisabled: Bool
    @Binding var showResetStepOne: Bool
    let anchorID: String
    let onOpenAppSupportFolder: () -> Void
    let onOpenSelectedServerFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {
            Label("Data & Folders", systemImage: "folder")
                .font(MSC.Typography.cardTitle)
                .foregroundStyle(.secondary)

            Divider()

            HStack(spacing: MSC.Spacing.sm) {
                Button("Open App Support Folder…", action: onOpenAppSupportFolder)
                    .buttonStyle(MSCSecondaryButtonStyle())

                Button("Open Server Folder…", action: onOpenSelectedServerFolder)
                    .buttonStyle(MSCSecondaryButtonStyle())
                    .disabled(isServerFolderButtonDisabled)
            }

            Divider().opacity(0.5)

            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                Text("Testing reset")
                    .font(MSC.Typography.captionBold)
                    .foregroundStyle(MSC.Colors.caption)

                Text("Deletes MSC Application Support data, the configured servers folder, and saved controller secrets from Keychain. Afterward, MSC quits so the next launch behaves like a fresh download.")
                    .font(.caption2)
                    .foregroundStyle(MSC.Colors.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: MSC.Spacing.sm) {
                    Button("Reset MSC…") {
                        showResetStepOne = true
                    }
                    .buttonStyle(MSCDestructiveButtonStyle())

                    Text("Destructive and irreversible.")
                        .font(.caption2)
                        .foregroundStyle(MSC.Colors.tertiary)
                }
            }
        }
        .pscCard()
        .id(anchorID)
        .contextualHelpAnchor(anchorID)
    }
}

struct PreferencesStorageSection: View {
    let appSupportBytes: Int64?
    let serversRootBytes: Int64?
    let isLoading: Bool
    let anchorID: String
    let onRefresh: () -> Void

    private var totalBytes: Int64? {
        guard let a = appSupportBytes, let s = serversRootBytes else { return nil }
        return a + s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {
            HStack {
                Label("Storage", systemImage: "internaldrive")
                    .font(MSC.Typography.cardTitle)
                    .foregroundStyle(.secondary)
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button(action: onRefresh) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                    .controlSize(.small)
                }
            }

            Divider()

            if let total = totalBytes {
                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                    StorageBarRow(label: "App Support", bytes: appSupportBytes ?? 0, total: total)
                    StorageBarRow(label: "Servers Root", bytes: serversRootBytes ?? 0, total: total)
                    Divider().opacity(0.5)
                    HStack {
                        Text("Total")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))
                            .font(.system(size: 12, design: .monospaced))
                    }
                }
            } else if isLoading {
                HStack {
                    Spacer()
                    VStack(spacing: MSC.Spacing.xs) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Calculating…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, MSC.Spacing.sm)
                    Spacer()
                }
            }
        }
        .pscCard()
        .id(anchorID)
        .contextualHelpAnchor(anchorID)
    }
}

private struct StorageBarRow: View {
    let label: String
    let bytes: Int64
    let total: Int64

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1.0, Double(bytes) / Double(total))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(MSC.Colors.insetBackground)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.accentColor.opacity(0.65))
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 4)
        }
    }
}

struct PreferencesLearnHelpSection: View {
    let onShowConceptGuide: () -> Void
    let onShowServerHandbook: () -> Void
    let onShowPrerequisites: () -> Void
    let onRestartSetupTour: () -> Void
    let onOpenPortForwardGuide: () -> Void
    let onOpenPlayitGuide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {
            Label("Learn & Help", systemImage: "questionmark.circle")
                .font(MSC.Typography.cardTitle)
                .foregroundStyle(.secondary)

            Divider()

            Button("How MSC Works\u{2026}", action: onShowConceptGuide)
                .buttonStyle(MSCSecondaryButtonStyle())
                .help("Visual walkthrough of the server \u{2192} world mental model.")

            Button("Server Handbook\u{2026}", action: onShowServerHandbook)
                .buttonStyle(MSCSecondaryButtonStyle())
                .help("Long-form reference covering every feature and concept.")

            Button("Prerequisites & Dependencies\u{2026}", action: onShowPrerequisites)
                .buttonStyle(MSCSecondaryButtonStyle())

            Button("Restart Setup Tour\u{2026}", action: onRestartSetupTour)
                .buttonStyle(MSCSecondaryButtonStyle())

            Button("Port Forwarding Guide\u{2026}", action: onOpenPortForwardGuide)
                .buttonStyle(MSCSecondaryButtonStyle())

            Button("playit.gg Tunnel Setup Guide\u{2026}", action: onOpenPlayitGuide)
                .buttonStyle(MSCSecondaryButtonStyle())
        }
        .pscCard()
    }
}

private struct PreferencesModeBadge: View {
    let enabled: Bool

    var body: some View {
        Text(enabled ? "LAN/VPN" : "Local only")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(enabled ? MSC.Colors.success : MSC.Colors.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(enabled ? MSC.Colors.success.opacity(0.12) : MSC.Colors.insetBackground)
            )
    }
}

private struct PreferencesURLRow: View {
    let label: String
    let url: String

    var body: some View {
        HStack(spacing: MSC.Spacing.sm) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(MSC.Colors.tertiary)
                .frame(width: 88, alignment: .trailing)
            Text(verbatim: url)
                .font(MSC.Typography.monoSmall)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Network Ports

/// One port the app or one of its servers uses.
struct AppPortInfo: Identifiable {
    let id = UUID()
    let service: String        // e.g. "Game (Java)"
    let serverName: String?    // nil = app-wide
    let port: Int
    let isUDP: Bool
    let needsForwarding: Bool
    let note: String
    var isListening: Bool? = nil   // nil = probing in progress

    var proto: String { isUDP ? "UDP" : "TCP" }
}

/// Best-effort loopback probe to see if something is currently listening on a port.
/// TCP is reliable; UDP is ambiguous (stateless) and treated optimistically, matching
/// the health-card behaviour.
enum PortProbe {
    static func isListening(port: Int, isUDP: Bool) async -> Bool {
        guard port > 0, port <= 65535, let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return false }
        return await withCheckedContinuation { continuation in
            let connection = NWConnection(host: NWEndpoint.Host("127.0.0.1"), port: nwPort, using: isUDP ? .udp : .tcp)
            let lock = NSLock()
            var resolved = false
            func finish(_ value: Bool) {
                lock.lock(); defer { lock.unlock() }
                guard !resolved else { return }
                resolved = true
                connection.cancel()
                continuation.resume(returning: value)
            }
            let timeout = DispatchWorkItem { finish(isUDP) } // UDP: assume listening if no error by timeout
            DispatchQueue.global().asyncAfter(deadline: .now() + (isUDP ? 1.0 : 1.5), execute: timeout)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    timeout.cancel(); finish(true)
                case .failed, .waiting:
                    timeout.cancel(); finish(false)
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
    }
}

extension AppViewModel {
    /// Gather every inbound port the app and its configured servers use.
    /// Per-server game/Geyser rows that share a port+protocol are merged into one row
    /// listing all the affected servers. App-wide ports appear once.
    func collectPortInfos() -> [AppPortInfo] {
        var infos: [AppPortInfo] = []
        let cfg = configManager.config

        // App-wide: Remote API control channel (iOS app).
        infos.append(AppPortInfo(
            service: "Remote API (iOS app)",
            serverName: nil,
            port: cfg.remoteAPIPort,
            isUDP: false,
            needsForwarding: false,
            note: cfg.remoteAPIExposeOnLAN ? "Exposed on LAN" : "Local only"
        ))

        // App-wide: resource pack host — one HTTP host serves whichever Java pack is active,
        // so list it a single time rather than per server.
        if let javaServer = cfg.servers.first(where: { $0.isJava }) {
            infos.append(AppPortInfo(
                service: "Resource pack host",
                serverName: nil,
                port: javaServer.resourcePackHostPort,
                isUDP: false,
                needsForwarding: true,
                note: "Active only while hosting a Java pack"
            ))
        }

        // Per-server game / Geyser ports, merged by (service, port, protocol) so that
        // multiple servers sharing a port collapse into one row, while different services
        // on the same port (e.g. a Bedrock game and Geyser both on 19000/UDP) stay distinct.
        struct PortKey: Hashable { let service: String; let port: Int; let isUDP: Bool }
        var groups: [PortKey: [String]] = [:]
        var order: [PortKey] = []
        func add(service: String, name: String, port: Int, isUDP: Bool) {
            let key = PortKey(service: service, port: port, isUDP: isUDP)
            if groups[key] == nil {
                groups[key] = [name]
                order.append(key)
            } else {
                groups[key]?.append(name)
            }
        }

        for server in cfg.servers {
            if server.isBedrock {
                add(service: "Game (Bedrock)", name: server.displayName,
                    port: effectiveBedrockPort(for: server) ?? 19132, isUDP: true)
            } else {
                add(service: "Game (Java)", name: server.displayName,
                    port: loadServerPropertiesModel(for: server).serverPort, isUDP: false)
                if ResourcePackManager.isGeyserInstalled(serverDir: server.serverDir),
                   let geyserPort = GeyserConfigManager.readConfig(serverDir: server.serverDir)?.port {
                    add(service: "Geyser (Bedrock)", name: server.displayName,
                        port: geyserPort, isUDP: true)
                }
            }
        }

        for key in order {
            guard let names = groups[key] else { continue }
            infos.append(AppPortInfo(
                service: key.service,
                serverName: names.joined(separator: ", "),
                port: key.port,
                isUDP: key.isUDP,
                needsForwarding: true,
                note: ""
            ))
        }
        return infos
    }
}

struct PreferencesPortsSection: View {
    @EnvironmentObject var viewModel: AppViewModel
    let anchorID: String

    @State private var ports: [AppPortInfo] = []

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {
            HStack {
                Label("Network Ports", systemImage: "network")
                    .font(MSC.Typography.cardTitle)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(MSCSecondaryButtonStyle())
                .help("Re-check ports")
            }

            Divider()

            if ports.isEmpty {
                Text("No ports to display.")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, MSC.Spacing.sm)
            } else {
                // Column header
                HStack(spacing: MSC.Spacing.sm) {
                    Text("Service").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Port").frame(width: 64, alignment: .trailing)
                    Text("Proto").frame(width: 48, alignment: .center)
                    Text("Status").frame(width: 90, alignment: .leading)
                }
                .font(MSC.Typography.captionBold)
                .foregroundStyle(.secondary)
                .padding(.vertical, MSC.Spacing.xs)

                Divider()

                ForEach(ports) { port in
                    portRow(port)
                    Divider().opacity(0.4)
                }
            }

            Text("Game, Geyser, and resource-pack-host ports must be forwarded in your router for players outside your network. The Remote API port is for the iOS app only and is not for players.")
                .font(.caption2)
                .foregroundStyle(MSC.Colors.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, MSC.Spacing.xs)
        }
        .pscCard()
        .id(anchorID)
        .contextualHelpAnchor(anchorID)
        .onAppear { reload() }
    }

    @ViewBuilder
    private func portRow(_ port: AppPortInfo) -> some View {
        HStack(spacing: MSC.Spacing.sm) {
            VStack(alignment: .leading, spacing: 1) {
                Text(port.service)
                    .font(MSC.Typography.caption)
                if let serverName = port.serverName {
                    Text(serverName)
                        .font(.caption2)
                        .foregroundStyle(MSC.Colors.tertiary)
                        .lineLimit(1)
                } else {
                    Text(port.note)
                        .font(.caption2)
                        .foregroundStyle(MSC.Colors.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(verbatim: String(port.port))
                .font(MSC.Typography.monoSmall)
                .frame(width: 64, alignment: .trailing)

            Text(port.proto)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .center)

            HStack(spacing: 5) {
                statusDot(port.isListening)
                Text(statusLabel(port.isListening))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 90, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusDot(_ listening: Bool?) -> some View {
        switch listening {
        case .some(true):  Circle().fill(MSC.Colors.success).frame(width: 7, height: 7)
        case .some(false): Circle().fill(MSC.Colors.tertiary).frame(width: 7, height: 7)
        case .none:        ProgressView().scaleEffect(0.45).frame(width: 7, height: 7)
        }
    }

    private func statusLabel(_ listening: Bool?) -> String {
        switch listening {
        case .some(true):  return "Listening"
        case .some(false): return "Not in use"
        case .none:        return "Checking…"
        }
    }

    private func reload() {
        let collected = viewModel.collectPortInfos()
        ports = collected
        for port in collected {
            Task {
                let listening = await PortProbe.isListening(port: port.port, isUDP: port.isUDP)
                await MainActor.run {
                    if let idx = ports.firstIndex(where: { $0.id == port.id }) {
                        ports[idx].isListening = listening
                    }
                }
            }
        }
    }
}

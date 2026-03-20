//
//  PreferencesView.swift
//  MinecraftServerController
//

import SwiftUI
import Foundation

#if os(macOS)
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
#endif

struct PreferencesView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var contextualHelpManager = ContextualHelpManager.shared

    @State private var javaPath: String = ""
    @State private var extraFlags: String = ""
    @State private var remoteAPIExposeOnLAN: Bool = false

    // Preferred pairing host + shared access
    @State private var preferredPairingHostInput: String = ""
    @State private var newSharedAccessLabel: String = ""

    // Pairing UI state
    @State private var showPairingQR: Bool = false
    @State private var pairingLinkForQR: String = ""
    @State private var showCopiedAlert: Bool = false
    @State private var copiedMessage: String = ""

    // Token regeneration
    @State private var showRegenerateTokenConfirm: Bool = false

    // Warnings
    @AppStorage(MSCSuppressQuitWarningKey) private var suppressQuitWarning: Bool = false

    // Appearance
        @State private var bannerColorDraft: Color = Color(red: 30/255, green: 30/255, blue: 30/255)

        // Reset MSC flow
        @State private var showResetStepOne: Bool = false
    @State private var showResetStepTwo: Bool = false
    @State private var showResetStepThree: Bool = false
    @State private var showResetStepFour: Bool = false
    @State private var showResetCompleted: Bool = false
    @State private var showResetFailed: Bool = false
    @State private var resetFailureMessage: String = ""

    private let contextualHelpGuideIDs: Set<String> = [
        "preferences.page",
        "preferences.remote-access"
    ]

    private let preferencesHeaderAnchorID = "preferences.header"
    private let appearanceCardAnchorID = "preferences.appearance"
    private let javaCardAnchorID = "preferences.java"
    private let remoteAccessCardAnchorID = "preferences.remoteAccess"
    private let remoteAccessToggleAnchorID = "preferences.remoteAccess.toggle"
    private let remoteAccessURLBoxAnchorID = "preferences.remoteAccess.urlBox"
    private let remoteAccessPreferredHostAnchorID = "preferences.remoteAccess.preferredHost"
    private let remoteAccessActionsAnchorID = "preferences.remoteAccess.actions"
    private let dataFoldersCardAnchorID = "preferences.dataFolders"
    private let saveButtonAnchorID = "preferences.saveButton"

    private var preferencesPageHelpGuide: ContextualHelpGuide {
        ContextualHelpGuide(
            id: "preferences.page",
            steps: [
                helpStep(
                    id: "preferences.page.overview",
                    title: "Preferences is app-level setup",
                    body: "This page controls app-wide behavior like the Java runtime, Remote Access, appearance, and utility folders. It is not the place for per-server gameplay changes.",
                    anchorID: preferencesHeaderAnchorID
                ),
                helpStep(
                    id: "preferences.page.appearance",
                    title: "Appearance controls the app header accent",
                    body: "Use Appearance to choose the banner color accent used by the app header. This is a visual preference only, and the change is saved when you press Save.",
                    anchorID: appearanceCardAnchorID
                ),
                helpStep(
                    id: "preferences.page.java",
                    title: "Java affects how Java servers launch",
                    body: "Use the Java section to point MSC at the Java executable and add optional JVM flags. Most people leave the flags blank unless they are intentionally tuning launch behavior.",
                    anchorID: javaCardAnchorID
                ),
                helpStep(
                    id: "preferences.page.remote",
                    title: "Remote Access is for MSCRemoteiOS pairing",
                    body: "This section controls whether the Remote API stays local to this Mac or is reachable from your iPhone over LAN or VPN. The deeper help here explains pairing links, QR, and shared access tokens.",
                    anchorID: remoteAccessCardAnchorID
                ),
                helpStep(
                    id: "preferences.page.data",
                    title: "Data & Folders is utility space",
                    body: "These buttons are maintenance shortcuts so you can jump straight to the app support folder or the selected server folder without digging through Finder.",
                    anchorID: dataFoldersCardAnchorID
                ),
                helpStep(
                    id: "preferences.page.save",
                    title: "Save commits the page drafts",
                    body: "Java path, extra flags, LAN/VPN exposure, the preferred pairing host, and appearance changes all commit when you press Save. Remote Access token actions are different: regenerate, add shared access, and revoke shared access apply immediately because they change live credentials.",
                    anchorID: saveButtonAnchorID,
                    nextLabel: "Done"
                )
            ]
        )
    }

    private var remoteAccessHelpGuide: ContextualHelpGuide {
        ContextualHelpGuide(
            id: "preferences.remote-access",
            steps: [
                helpStep(
                    id: "preferences.remote.overview",
                    title: "Remote Access powers iPhone control",
                    body: "This card is where you prepare MSC for MSCRemoteiOS. It covers whether the Remote API is reachable off this Mac, what host the iPhone should use, and which tokens are allowed to control the app.",
                    anchorID: remoteAccessCardAnchorID
                ),
                helpStep(
                    id: "preferences.remote.toggle",
                    title: "This toggle changes who can reach the API",
                    body: "OFF keeps the Remote API on 127.0.0.1 so only this Mac can reach it. ON tells MSC to bind across LAN or VPN interfaces, which is what you need for an iPhone on the same Wi-Fi or on a VPN like Tailscale.",
                    anchorID: remoteAccessToggleAnchorID
                ),
                helpStep(
                    id: "preferences.remote.url",
                    title: "The URL box is a preview, not the saved pairing state",
                    body: "This box helps you see the local URL and the best pairing host for the draft state on screen. The actual Copy Pairing Link and QR actions still use the saved Remote Access settings, so press Save first after changing the toggle or preferred host.",
                    anchorID: remoteAccessURLBoxAnchorID
                ),
                helpStep(
                    id: "preferences.remote.host",
                    title: "Preferred pairing host keeps links cleaner",
                    body: "Set a MagicDNS or other stable host here when you have one. That value becomes the saved base host for pairing links and QR after you press Save, which is usually nicer than handing out a raw IP.",
                    anchorID: remoteAccessPreferredHostAnchorID
                ),
                helpStep(
                    id: "preferences.remote.actions",
                    title: "Pairing and shared access control the actual secrets",
                    body: "Copy Pairing Link and Show Pairing QR produce the MSCRemoteiOS pairing payload. Regenerate Token replaces the owner secret immediately, and Shared Access entries create or revoke additional full-control tokens immediately too.",
                    anchorID: remoteAccessActionsAnchorID,
                    nextLabel: "Done"
                )
            ]
        )
    }

    private func presentPreferencesHelp() {
        ContextualHelpManager.shared.start(preferencesPageHelpGuide)
    }

    private func presentRemoteAccessHelp() {
        ContextualHelpManager.shared.start(remoteAccessHelpGuide)
    }

    private func helpStep(
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

    private func scrollContextualHelpIfNeeded(using proxy: ScrollViewProxy) {
        guard contextualHelpManager.isActive,
              let anchorID = contextualHelpManager.currentStep?.anchorID,
              isScrollableContextualHelpAnchor(anchorID) else { return }

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.24)) {
                proxy.scrollTo(anchorID, anchor: preferredScrollAnchor(for: anchorID))
            }
        }
    }

    private func isScrollableContextualHelpAnchor(_ anchorID: String) -> Bool {
        anchorID == appearanceCardAnchorID ||
        anchorID == javaCardAnchorID ||
        anchorID == remoteAccessCardAnchorID ||
        anchorID == remoteAccessToggleAnchorID ||
        anchorID == remoteAccessURLBoxAnchorID ||
        anchorID == remoteAccessPreferredHostAnchorID ||
        anchorID == remoteAccessActionsAnchorID ||
        anchorID == dataFoldersCardAnchorID
    }

    private func preferredScrollAnchor(for anchorID: String) -> UnitPoint {
        switch anchorID {
        case dataFoldersCardAnchorID, remoteAccessActionsAnchorID:
            return .center
        default:
            return .top
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── HEADER ─────────────────────────────────────────────────────
            HStack(alignment: .top, spacing: MSC.Spacing.md) {
                VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                    Text("Preferences")
                        .font(MSC.Typography.pageTitle)
                    Text("Java runtime, remote access, and app settings.")
                        .font(MSC.Typography.caption)
                        .foregroundStyle(MSC.Colors.caption)
                }

                Spacer()

                Button {
                    presentPreferencesHelp()
                } label: {
                    Label("Explain this page", systemImage: "questionmark.circle")
                }
                .buttonStyle(MSCSecondaryButtonStyle())
                .help("Explains the main Preferences sections and save behavior.")
            }
            .padding(.horizontal, MSC.Spacing.xl)
            .padding(.top, MSC.Spacing.xl)
            .padding(.bottom, MSC.Spacing.lg)
            .contextualHelpAnchor(preferencesHeaderAnchorID)

            Divider()

            // ── SCROLLABLE BODY ────────────────────────────────────────────
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: MSC.Spacing.lg) {

                        // ── APPEARANCE ──────────────────────────────────────────
                                                appearanceCard

                                                // ── JAVA ────────────────────────────────────────────────
                                                javaCard

                        // ── REMOTE ACCESS ───────────────────────────────────────
                        remoteAccessCard

                        // ── DATA & FOLDERS ──────────────────────────────────────
                        dataFoldersCard

                        // ── LEARN & HELP ────────────────────────────────────────
                        learnHelpCard

                        
                    }
                    .padding(.horizontal, MSC.Spacing.xl)
                    .padding(.vertical, MSC.Spacing.lg)
                }
                .frame(maxHeight: .infinity)
                .onAppear {
                    scrollContextualHelpIfNeeded(using: proxy)
                }
                .onChange(of: contextualHelpManager.isActive) { _, active in
                    guard active else { return }
                    scrollContextualHelpIfNeeded(using: proxy)
                }
                .onChange(of: contextualHelpManager.currentStep?.anchorID) { _, _ in
                    scrollContextualHelpIfNeeded(using: proxy)
                }
            }

            Divider()

            // ── FOOTER ─────────────────────────────────────────────────────
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(MSCSecondaryButtonStyle())

                Button("Save") {
                                    persistPreferredPairingHost()
                                    viewModel.updatePreferences(
                                        javaPath: javaPath,
                                        extraFlags: extraFlags,
                                        remoteAPIExposeOnLAN: remoteAPIExposeOnLAN
                                    )
                                    // Save banner color
                                    let adjusted = bannerColorDraft.clampedAwayFromWhite().clampedAwayFromBlack()
                                    let newHex = adjusted.hexRGBString()
                                    if let server = viewModel.selectedServer,
                                       let idx = viewModel.configManager.config.servers.firstIndex(where: { $0.id == server.id }) {
                                        viewModel.configManager.config.servers[idx].bannerColorHex = newHex
                                    } else {
                                        viewModel.configManager.config.defaultBannerColorHex = newHex
                                    }
                                    viewModel.configManager.save()
                                    viewModel.syncTourAccentColor()
                                    dismiss()
                                }
                .buttonStyle(MSCPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .contextualHelpAnchor(saveButtonAnchorID)
            }
            .padding(.horizontal, MSC.Spacing.xl)
            .padding(.vertical, MSC.Spacing.lg)
        }
        .frame(minWidth: 560, minHeight: 480)
        .onAppear {
                    let cfg = viewModel.configManager.config
                    javaPath = cfg.javaPath
                    extraFlags = cfg.extraFlags
                    remoteAPIExposeOnLAN = cfg.remoteAPIExposeOnLAN
                    preferredPairingHostInput = cfg.remoteAPIPreferredPairingHost ?? ""

                    // Load banner color: per-server if one is selected, else global default
                    if let server = viewModel.selectedServer,
                       let cfgServer = viewModel.configServer(for: server),
                       let hex = cfgServer.bannerColorHex,
                       let color = Color(hexRGB: hex) {
                        bannerColorDraft = color.clampedAwayFromWhite().clampedAwayFromBlack()
                    } else if let hex = cfg.defaultBannerColorHex,
                              let color = Color(hexRGB: hex) {
                        bannerColorDraft = color.clampedAwayFromWhite().clampedAwayFromBlack()
                    }
                }
        .alert("Copied", isPresented: $showCopiedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(copiedMessage)
        }
        .sheet(isPresented: $showPairingQR) {
            PairingQRCodeSheet(pairingLink: pairingLinkForQR)
        }
        .alert("Are you sure?", isPresented: $showResetStepOne) {
            Button("Cancel", role: .cancel) { }
            Button("Yeah, keep going", role: .destructive) {
                showResetStepTwo = true
            }
        } message: {
            Text("This is the dramatic option. There are calmer ways to troubleshoot MSC.")
        }
        .alert("Seriously?", isPresented: $showResetStepTwo) {
            Button("Never mind", role: .cancel) { }
            Button("I am serious", role: .destructive) {
                showResetStepThree = true
            }
        } message: {
            Text("This will delete MSC app data and your configured server folder from disk.")
        }
        .alert("Last chance to back out", isPresented: $showResetStepThree) {
            Button("Back out", role: .cancel) { }
            Button("Show final warning", role: .destructive) {
                showResetStepFour = true
            }
        } message: {
            Text("Application Support, the configured servers root, and saved controller secrets in Keychain will all be removed.")
        }
        .alert("Do it for real?", isPresented: $showResetStepFour) {
            Button("Cancel", role: .cancel) { }
            Button("Delete everything", role: .destructive) {
                runFullReset()
            }
        } message: {
            Text("MSC will reset to a fresh-install state, then ask you to quit immediately.")
        }
        .alert("Reset complete", isPresented: $showResetCompleted) {
            Button("Quit Now") {
                quitApplicationAfterReset()
            }
        } message: {
            Text("MSC finished deleting its stored data. Quit now to complete the reset.")
        }
        .alert("Reset failed", isPresented: $showResetFailed) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(resetFailureMessage)
        }
        .contextualHelpHost(guideIDs: contextualHelpGuideIDs)
    }

    private func runFullReset() {
        do {
            try viewModel.resetApplicationForTesting()
            showResetCompleted = true
        } catch {
            resetFailureMessage = error.localizedDescription
            showResetFailed = true
        }
    }

    private func quitApplicationAfterReset() {
        dismiss()

        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if NSApplication.shared.isRunning {
                    exit(0)
                }
            }
        }
    }

    private var javaCard: some View {
        PreferencesJavaSection(
            javaPath: $javaPath,
            extraFlags: $extraFlags,
            anchorID: javaCardAnchorID
        )
    }

    private var remoteAccessCard: some View {
        let cfg = viewModel.configManager.config
        let port = cfg.remoteAPIPort
        let ips = candidateIPv4Addresses()
        let tailscaleIP = ips.first(where: { $0.hasPrefix("100.") })
        let recommendedHost = preferredPairingHost(exposeOnLAN: remoteAPIExposeOnLAN)

        return PreferencesRemoteAPISection(
            remoteAPIExposeOnLAN: $remoteAPIExposeOnLAN,
            preferredPairingHostInput: $preferredPairingHostInput,
            newSharedAccessLabel: $newSharedAccessLabel,
            showPairingQR: $showPairingQR,
            pairingLinkForQR: $pairingLinkForQR,
            showCopiedAlert: $showCopiedAlert,
            copiedMessage: $copiedMessage,
            showRegenerateTokenConfirm: $showRegenerateTokenConfirm,
            config: cfg,
            port: port,
            tailscaleIP: tailscaleIP,
            recommendedHost: recommendedHost,
            cardAnchorID: remoteAccessCardAnchorID,
            toggleAnchorID: remoteAccessToggleAnchorID,
            urlBoxAnchorID: remoteAccessURLBoxAnchorID,
            preferredHostAnchorID: remoteAccessPreferredHostAnchorID,
            actionsAnchorID: remoteAccessActionsAnchorID,
            onPresentHelp: presentRemoteAccessHelp,
            onCopyToClipboard: copyToClipboard,
            onBuildPairingLink: buildPairingLink,
            onAddSharedAccessEntry: addSharedAccessEntry,
            onRevokeSharedAccessEntry: revokeSharedAccessEntry,
            onRegenerateToken: regenerateRemoteAPIToken
        )
    }

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {
            Label("Appearance", systemImage: "paintpalette")
                .font(MSC.Typography.cardTitle)
                .foregroundStyle(.secondary)

            Divider()

            SEField(label: "Banner Color", hint: "accent color for the app header") {
                HStack(spacing: MSC.Spacing.sm) {
                    ColorPicker("", selection: $bannerColorDraft, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 28, height: 28)
                    Text("  Changes apply when you press Save.")
                        .font(MSC.Typography.caption)
                        .foregroundStyle(MSC.Colors.caption)
                }
            }
        }
        .pscCard()
        .contextualHelpAnchor(appearanceCardAnchorID)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

                        private var dataFoldersCard: some View {
        PreferencesDataFoldersSection(
            isServerFolderButtonDisabled: viewModel.selectedServer == nil,
            showResetStepOne: $showResetStepOne,
            anchorID: dataFoldersCardAnchorID,
            onOpenAppSupportFolder: viewModel.openAppSupportFolder,
            onOpenSelectedServerFolder: viewModel.openSelectedServerFolder
        )
    }

    private var learnHelpCard: some View {
        PreferencesLearnHelpSection(
            onShowWelcomeGuide: {
                viewModel.showWelcomeGuideFromPreferences()
                dismiss()
            },
            onShowPrerequisites: {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    viewModel.isShowingPrerequisites = true
                }
            },
            onRestartSetupTour: {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    OnboardingManager.shared.reset()
                }
            }
        )
    }

    // MARK: - Logic (unchanged from original)

    private func buildPairingLink(token: String) -> String {
        let cfg = viewModel.configManager.config
        let port = cfg.remoteAPIPort

        let baseHost = preferredPairingHost(exposeOnLAN: cfg.remoteAPIExposeOnLAN) ?? "127.0.0.1"
        let baseURL = "http://\(baseHost):\(port)"

        var comps = URLComponents()
        comps.scheme = "mscremote"
        comps.host = "pair"
        comps.queryItems = [
            URLQueryItem(name: "base", value: baseURL),
            URLQueryItem(name: "token", value: token)
        ]

        return comps.url?.absoluteString ?? "mscremote://pair"
    }

    private func preferredPairingHost(exposeOnLAN: Bool) -> String? {
        guard exposeOnLAN else { return nil }

        let preferred = preferredPairingHostInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !preferred.isEmpty { return preferred }

        let ips = candidateIPv4Addresses()

        if let ts = ips.first(where: { $0.hasPrefix("100.") }) {
            return ts
        }

        if let lan = ips.first(where: { isLocalOrPrivateHost($0) && $0 != "127.0.0.1" }) {
            return lan
        }

        return nil
    }

    private func isLocalOrPrivateHost(_ host: String) -> Bool {
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !h.isEmpty else { return false }

        if h == "localhost" || h == "127.0.0.1" { return true }
        if h.hasSuffix(".local") { return true }

        if h.hasPrefix("10.") { return true }
        if h.hasPrefix("192.168.") { return true }

        if h.hasPrefix("172.") {
            let parts = h.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]) {
                if (16...31).contains(second) { return true }
            }
        }

        if h.hasPrefix("169.254.") { return true }

        return false
    }

    private func candidateIPv4Addresses() -> [String] {
        #if os(macOS)
        var results: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr

            if (flags & IFF_UP) == 0 { continue }
            guard let addr else { continue }
            guard addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let len = socklen_t(addr.pointee.sa_len)

            let res = getnameinfo(addr, len, &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)

            if res == 0 {
                let ip = String(cString: hostname)
                if !ip.isEmpty { results.append(ip) }
            }
        }

        var seen = Set<String>()
        return results.filter { seen.insert($0).inserted }
        #else
        return []
        #endif
    }

    private func persistPreferredPairingHost() {
        var cfg = viewModel.configManager.config
        let trimmed = preferredPairingHostInput.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.remoteAPIPreferredPairingHost = trimmed.isEmpty ? nil : trimmed
        viewModel.configManager.config = cfg
        viewModel.configManager.save()
    }

    private func addSharedAccessEntry(label: String) {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty else { return }

        var cfg = viewModel.configManager.config

        var token = AppConfig.generateRemoteAPIToken()
        var attempts = 0
        let existingTokens = Set(cfg.remoteAPISharedAccess.map { $0.token })
        while existingTokens.contains(token) && attempts < 5 {
            token = AppConfig.generateRemoteAPIToken()
            attempts += 1
        }

        let entry = RemoteAPISharedAccessEntry.make(label: trimmedLabel, token: token)
        cfg.remoteAPISharedAccess.append(entry)

        viewModel.configManager.config = cfg
        viewModel.configManager.save()

        viewModel.logAppMessage("[Remote API] Added shared access: \(trimmedLabel).")

        newSharedAccessLabel = ""
        copiedMessage = "Shared access added. Use Copy Pairing Link / Show QR to share."
        showCopiedAlert = true
    }

    private func revokeSharedAccessEntry(id: String) {
        var cfg = viewModel.configManager.config
        let beforeCount = cfg.remoteAPISharedAccess.count
        cfg.remoteAPISharedAccess.removeAll { $0.id == id }
        let afterCount = cfg.remoteAPISharedAccess.count

        guard beforeCount != afterCount else { return }

        viewModel.configManager.config = cfg
        viewModel.configManager.save()

        viewModel.logAppMessage("[Remote API] Revoked shared access entry.")

        copiedMessage = "Shared access revoked."
        showCopiedAlert = true
    }

    private func regenerateRemoteAPIToken() {
        var cfg = viewModel.configManager.config
        cfg.remoteAPIToken = AppConfig.generateRemoteAPIToken()

        viewModel.configManager.config = cfg
        viewModel.configManager.save()

        viewModel.logAppMessage("[Remote API] Regenerated bearer token.")

        copiedMessage = "New token generated. Re-pair iOS (or copy token again)."
        showCopiedAlert = true
    }

    private func copyToClipboard(_ s: String) {
        #if os(macOS)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
        #endif
    }
}

// MARK: - Pairing QR Sheet (unchanged layout, polished footer)

#if os(macOS)
private struct PairingQRCodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let pairingLink: String

    var body: some View {
        VStack(alignment: .center, spacing: 14) {
            Text("Pair with iOS")
                .font(.title3)
                .bold()

            Text("Open MSCRemoteiOS → Settings → Scan QR")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let img = qrCodeImage(from: pairingLink) {
                Image(nsImage: img)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 260, height: 260)
                    .padding(10)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                Text("Failed to generate QR.")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                Text("This QR contains your pairing secret. Don't share screenshots.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Button("Copy Pairing Link") {
                    copyToClipboard(pairingLink)
                }
                .controlSize(.small)
            }

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(minWidth: 560, minHeight: 440)
    }

    private func copyToClipboard(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }

    private func qrCodeImage(from string: String) -> NSImage? {
        let data = Data(string.utf8)
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let ciImage = filter.outputImage else { return nil }

        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaled = ciImage.transformed(by: transform)

        let rep = NSCIImageRep(ciImage: scaled)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        return nsImage
    }
}
#endif

// MARK: - Inline Destructive Button Style
// Same shape/size as MSCSecondaryButtonStyle but with red text.
// Useful when a destructive action lives in a row alongside secondary actions.
struct MSCDestructiveInlineButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    func makeBody(configuration: Configuration) -> some View {
        let isSmall = controlSize == .small || controlSize == .mini
        configuration.label
            .font(.system(size: isSmall ? 11 : 12, weight: .medium))
            .foregroundColor(isEnabled ? MSC.Colors.error : MSC.Colors.caption)
            .padding(.horizontal, isSmall ? MSC.Spacing.xs : MSC.Spacing.sm)
            .padding(.vertical, isSmall ? 3 : MSC.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                    .fill(MSC.Colors.error.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                    .stroke(MSC.Colors.error.opacity(0.2), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

#Preview {
    PreferencesView()
        .environmentObject(AppViewModel())
}


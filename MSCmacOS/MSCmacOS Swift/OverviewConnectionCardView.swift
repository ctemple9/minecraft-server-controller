//
//  OverviewConnectionCardView.swift
//  MinecraftServerController
//
//  Connection Info card. "Share Join Card" opens
//  JoinCardView as the canonical share surface.
//
//  Redesign: 2-column layout. Java servers show Java + Bedrock (Geyser)
//  columns; Bedrock dedicated servers show IPv4 + IPv6 columns.
//  Ghost column shown for Java servers when Geyser is not configured.
//  Single global eye toggle masks all IPs and ports.
//
//  Visual update: footer removed, share in header, columns fill height.
//  Cell update: IP and PORT shown with labels at equal type size.
//  DuckDNS: duck toggle in header swaps IP field to hostname (Public only).
//

import SwiftUI

struct OverviewConnectionCardView: View {
    @EnvironmentObject var viewModel: AppViewModel

    /// Single global visibility toggle — masks all IPs and ports when false.
    @Binding var showAddresses: Bool
    @Binding var hasSavedDuckDNS: Bool
    @Binding var isEditingDuckDNS: Bool

    let copyToPasteboard: (String) -> Void
    let showHUDMessage: (String) -> Void

    @State private var isShowingJoinCard: Bool = false
    @State private var useDuckDNS: Bool = false
    @State private var isHeaderActionsExpanded: Bool = false

    // MARK: - Local / Public toggle
    /// true = show public (WAN) IP, false = show local (LAN) IP
    @State var showPublicIP: Bool = false

    var body: some View {
        overviewConnectionCard
            .sheet(isPresented: $isShowingJoinCard) {
                JoinCardView(isPresented: $isShowingJoinCard)
                    .environmentObject(viewModel)
            }
            // Reset duck toggle when switching back to Local
            .onChange(of: showPublicIP) { isPublic in
                if !isPublic { useDuckDNS = false }
            }
    }

    // MARK: - Helpers

    private var selectedConfigServer: ConfigServer? {
        guard let server = viewModel.selectedServer else { return nil }
        return viewModel.configServer(for: server)
    }

    private var isBedrockServer: Bool {
        selectedConfigServer?.isBedrock == true
    }

    private var hasGeyser: Bool {
        resolvedBedrockAddress != nil && resolvedBedrockPort != nil
    }

    private var duckDNSHost: String {
        viewModel.duckdnsInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether the duck toggle is available to activate
    private var duckDNSAvailable: Bool {
        hasSavedDuckDNS && !duckDNSHost.isEmpty && showPublicIP
    }

    // MARK: - Address resolution (respects Local / Public and DuckDNS toggles)

    var resolvedJavaAddress: String {
        if showPublicIP { return viewModel.cachedPublicIPAddress ?? "Fetching…" }
        return viewModel.javaAddressForDisplay
    }

    var resolvedBedrockAddress: String? {
        if isBedrockServer {
            if showPublicIP { return viewModel.cachedPublicIPAddress ?? "Fetching…" }
            return viewModel.javaAddressForDisplay
        }
        guard let _ = viewModel.bedrockAddressForDisplay else { return nil }
        if showPublicIP { return viewModel.cachedPublicIPAddress ?? "Fetching…" }
        return viewModel.bedrockAddressForDisplay
    }

    var resolvedBedrockPort: Int? {
        if isBedrockServer {
            if let server = viewModel.selectedServer,
               let cfg = viewModel.configServer(for: server),
               let p = cfg.bedrockPort { return p }
            return 19132
        }
        return viewModel.bedrockPortForDisplay
    }

    var resolvedBedrockPortV6: Int? {
        guard isBedrockServer,
              let server = viewModel.selectedServer,
              let cfg = viewModel.configServer(for: server) else { return nil }
        return viewModel.bedrockPropertiesModel(for: cfg).serverPortV6
    }

    /// Effective public address — substitutes DuckDNS, playit Java tunnel, or WAN IP
    private var effectivePublicAddress: String {
        if useDuckDNS && duckDNSAvailable { return duckDNSHost }
        // When playit is active and a Java tunnel address is stored, use it
        if isPlayitActive, let javaAddr = viewModel.playitJavaAddress,
           let host = javaAddr.components(separatedBy: ":").first, !host.isEmpty {
            return host
        }
        return viewModel.cachedPublicIPAddress ?? "Fetching…"
    }

    /// Effective public port — uses stored playit Java tunnel port when active
    private var effectivePublicPort: String? {
        guard isPlayitActive, let javaAddr = viewModel.playitJavaAddress else { return nil }
        let parts = javaAddr.components(separatedBy: ":")
        return parts.count == 2 ? parts[1] : nil
    }

    /// Effective public Bedrock address for playit tunnel
    private var effectivePlayitBedrockAddress: String? {
        guard isPlayitActive, let addr = viewModel.playitBedrockAddress,
              let host = addr.components(separatedBy: ":").first, !host.isEmpty else { return nil }
        return host
    }

    /// Effective public Bedrock port for playit tunnel
    private var effectivePlayitBedrockPort: String? {
        guard isPlayitActive, let addr = viewModel.playitBedrockAddress else { return nil }
        let parts = addr.components(separatedBy: ":")
        return parts.count == 2 ? parts[1] : nil
    }

    private func tunnelHost(from address: String) -> String {
        String(address.split(separator: ":").first ?? Substring(address))
    }

    private func tunnelPort(from address: String) -> String? {
        let parts = address.split(separator: ":")
        guard parts.count == 2 else { return nil }
        return String(parts[1])
    }

    private var isPlayitActive: Bool {
        // Active if the container is running AND we have stored tunnel addresses.
        // (playitTunnelAddress is the legacy parsed value; playitJavaAddress is the API-fetched one)
        viewModel.isPlayitRunning &&
        (viewModel.playitTunnelAddress != nil || viewModel.playitJavaAddress != nil)
    }

    private var effectiveJavaAddress: String {
        if showPublicIP { return effectivePublicAddress }
        return viewModel.javaAddressForDisplay
    }

    private func effectiveBedrockAddress(fallback: String) -> String {
        if showPublicIP { return effectivePublicAddress }
        return fallback
    }

    // MARK: - Card

    private var overviewConnectionCard: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {

            // Header row
            HStack {
                HStack(spacing: MSC.Spacing.xs) {
                    Image(systemName: "network")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(MSC.Colors.tertiary)
                    MSCOverline("Connection Info")

                    if isPlayitActive {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(MSC.Colors.connectionOnline)
                                .frame(width: 5, height: 5)
                            Text("TUNNEL")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(MSC.Colors.connectionOnline)
                                .tracking(0.6)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(MSC.Colors.connectionOnline.opacity(0.12))
                        )
                    }
                }

                Spacer()

                if viewModel.selectedServer != nil {
                    HStack(spacing: MSC.Spacing.xs) {
                        if isHeaderActionsExpanded {
                            // Eye toggle
                            Button {
                                showAddresses.toggle()
                            } label: {
                                Image(systemName: showAddresses ? "eye.slash" : "eye")
                                    .font(.system(size: 11))
                                    .foregroundStyle(MSC.Colors.caption)
                            }
                            .buttonStyle(.borderless)
                            .help(showAddresses ? "Hide addresses" : "Show addresses")

                            // DuckDNS toggle — left click swaps hostname/IP when available.
                            // Two-finger click exposes edit actions.
                            Button {
                                if duckDNSAvailable { useDuckDNS.toggle() }
                            } label: {
                                Text("🦆")
                                    .font(.system(size: 11))
                                    .opacity(duckDNSAvailable ? (useDuckDNS ? 1.0 : 0.5) : 0.2)
                            }
                            .buttonStyle(.borderless)
                            .contextMenu {
                                Button {
                                    isEditingDuckDNS = true
                                } label: {
                                    Label(
                                        hasSavedDuckDNS && !duckDNSHost.isEmpty
                                            ? "Edit DuckDNS Hostname"
                                            : "Add DuckDNS Hostname",
                                        systemImage: "pencil"
                                    )
                                }
                            }
                            .help(
                                !hasSavedDuckDNS || duckDNSHost.isEmpty
                                    ? "No DuckDNS hostname configured"
                                    : !showPublicIP
                                        ? "Switch to Public to use DuckDNS hostname"
                                        : useDuckDNS
                                            ? "Showing DuckDNS hostname — click to show IP"
                                            : "Show DuckDNS hostname instead of IP"
                            )

                            // Share Join Card
                            Button {
                                isShowingJoinCard = true
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 11))
                                    .foregroundStyle(MSC.Colors.caption)
                            }
                            .buttonStyle(.borderless)
                            .help("Share Join Card")
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        }

                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                isHeaderActionsExpanded.toggle()
                            }
                        } label: {
                            Image(systemName: isHeaderActionsExpanded ? "chevron.right" : "chevron.left")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(MSC.Colors.caption)
                                .frame(width: 16, height: 16)
                        }
                        .buttonStyle(.borderless)
                        .help(isHeaderActionsExpanded ? "Hide connection actions" : "Show connection actions")

                        Picker("", selection: $showPublicIP) {
                            Text("Local").tag(false)
                            Text("Public").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 120)
                        .controlSize(.mini)
                    }
                }
            }

            if viewModel.selectedServer == nil {
                Text("No server selected.")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {

                    // 2-column endpoint grid — fills remaining card height
                    if isBedrockServer {
                        bedrockDedicatedColumns
                    } else {
                        javaColumns
                    }

                    // Public IP unavailable notice
                    if showPublicIP && viewModel.cachedPublicIPAddress == nil && !useDuckDNS {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                            Text("Public IP not yet available. Check your internet connection.")
                                .font(MSC.Typography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

        }
        .padding(MSC.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .fill(MSC.Colors.tierContent)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .stroke(MSC.Colors.contentBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 6, x: 0, y: 3)
    }

    // MARK: - Java 2-column layout

    @ViewBuilder
    private var javaColumns: some View {
        let jAddr = effectiveJavaAddress
        let jPort = (showPublicIP && isPlayitActive) ? (effectivePublicPort ?? viewModel.javaPortForDisplay) : viewModel.javaPortForDisplay
        let platformLabel = (showPublicIP && isPlayitActive) ? "Tunnel · PC / Mac" : "Java · PC / Mac"
        HStack(alignment: .top, spacing: MSC.Spacing.sm) {
            endpointCell(
                platformLabel: platformLabel,
                dotColor: isPlayitActive && showPublicIP ? MSC.Colors.connectionOnline : MSC.Colors.connectionWarning,
                address: jAddr,
                port: jPort,
                copyLabel: "Copy Java",
                onCopy: {
                    copyToPasteboard("\(jAddr):\(jPort)")
                    showHUDMessage(showPublicIP && isPlayitActive ? "Tunnel address copied" : showPublicIP ? "Public Java address copied" : "Java address copied")
                }
            )

            if showPublicIP && isPlayitActive,
               let playitBedAddr = effectivePlayitBedrockAddress,
               let playitBedPort = effectivePlayitBedrockPort {
                // Show playit Bedrock tunnel in Public mode
                endpointCell(
                    platformLabel: "Tunnel · Bedrock",
                    dotColor: MSC.Colors.connectionOnline,
                    address: playitBedAddr,
                    port: playitBedPort,
                    copyLabel: "Copy Bedrock",
                    onCopy: {
                        copyToPasteboard("\(playitBedAddr):\(playitBedPort)")
                        showHUDMessage("Bedrock tunnel address copied")
                    }
                )
            } else if let rawBedAddr = resolvedBedrockAddress, let bedPort = resolvedBedrockPort {
                let bedAddr = effectiveBedrockAddress(fallback: rawBedAddr)
                endpointCell(
                    platformLabel: "Bedrock (Geyser)",
                    dotColor: MSC.Colors.connectionOnline,
                    address: bedAddr,
                    port: String(bedPort),
                    copyLabel: "Copy Bedrock",
                    onCopy: {
                        copyToPasteboard("\(bedAddr):\(bedPort)")
                        showHUDMessage(showPublicIP ? "Public Bedrock address copied" : "Bedrock address copied")
                    }
                )
            } else {
                geyserGhostCell
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Bedrock Dedicated 2-column layout

    @ViewBuilder
    private var bedrockDedicatedColumns: some View {
        let rawAddr = resolvedBedrockAddress ?? viewModel.javaAddressForDisplay
        let addr = effectiveBedrockAddress(fallback: rawAddr)
        let ipv4Port = resolvedBedrockPort ?? 19132
        let ipv6Port = resolvedBedrockPortV6 ?? 19133

        HStack(alignment: .top, spacing: MSC.Spacing.sm) {
            endpointCell(
                platformLabel: "Bedrock · IPv4",
                dotColor: MSC.Colors.connectionOnline,
                address: addr,
                port: String(ipv4Port),
                copyLabel: "Copy IPv4",
                onCopy: {
                    copyToPasteboard("\(addr):\(ipv4Port)")
                    showHUDMessage("IPv4 address copied")
                }
            )

            if !showPublicIP {
                endpointCell(
                    platformLabel: "Bedrock · IPv6",
                    dotColor: MSC.Colors.connectionBedrock,
                    address: addr,
                    port: String(ipv6Port),
                    copyLabel: "Copy IPv6",
                    onCopy: {
                        copyToPasteboard("\(addr):\(ipv6Port)")
                        showHUDMessage("IPv6 address copied")
                    },
                    isSecondary: true
                )
            } else {
                Color.clear.frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Connection source tag

    private var connectionSourceTag: (label: String, color: Color) {
        if !showPublicIP {
            return ("LAN", Color.secondary)
        }
        if selectedConfigServer?.playitEnabled == true {
            return ("playit.gg", MSC.Colors.connectionOnline)
        }
        return ("Router", Color.secondary)
    }

    // MARK: - Endpoint cell

    @ViewBuilder
    private func endpointCell(
        platformLabel: String,
        dotColor: Color,
        address: String,
        port: String,
        copyLabel: String,
        onCopy: @escaping () -> Void,
        isSecondary: Bool = false
    ) -> some View {
        let (tagLabel, tagColor) = connectionSourceTag
        VStack(alignment: .leading, spacing: 0) {

            // Platform label row
            HStack(spacing: 5) {
                Circle()
                    .fill(dotColor.opacity(isSecondary ? 0.6 : 0.85))
                    .frame(width: 6, height: 6)
                Text(platformLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(MSC.Colors.tertiary)
                    .tracking(0.8)
                    .textCase(.uppercase)
                Spacer()
                Text(tagLabel)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(tagColor)
                    .tracking(0.4)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(tagColor.opacity(0.12)))
            }

            Spacer()

            // IP section
            Text("IP")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(MSC.Colors.tertiary)
                .tracking(0.8)
                .textCase(.uppercase)
                .padding(.bottom, 3)

            if showAddresses {
                Text(address)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(isSecondary ? MSC.Colors.tertiary : MSC.Colors.caption)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("•••••••••••••••")
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(MSC.Colors.tertiary)
            }

            Spacer().frame(height: 12)

            // PORT section
            Text("PORT")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(MSC.Colors.tertiary)
                .tracking(0.8)
                .textCase(.uppercase)
                .padding(.bottom, 3)

            if showAddresses {
                Text(port)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(isSecondary ? MSC.Colors.caption : MSC.Colors.heading)
                    .lineLimit(1)
            } else {
                Text("•••••")
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(MSC.Colors.tertiary)
            }

            Spacer()

            // Copy button — anchored to bottom
            Button(action: onCopy) {
                Text(copyLabel)
                    .font(.system(size: 10))
            }
            .buttonStyle(MSCSecondaryButtonStyle())
            .controlSize(.mini)
            .opacity(isSecondary ? 0.7 : 1.0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                .fill(Color.white.opacity(isSecondary ? 0.03 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                .stroke(Color.white.opacity(isSecondary ? 0.07 : 0.10), lineWidth: 0.5)
        )
    }

    // MARK: - Ghost cell (Geyser not configured)

    private var geyserGhostCell: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Circle()
                    .fill(MSC.Colors.connectionOnline.opacity(0.45))
                    .frame(width: 6, height: 6)
                Text("Bedrock (Geyser)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(MSC.Colors.tertiary.opacity(0.6))
                    .tracking(0.8)
                    .textCase(.uppercase)
            }

            Text("Not configured")
                .font(MSC.Typography.caption)
                .foregroundStyle(MSC.Colors.tertiary)

            Text("Enable in Settings")
                .font(.system(size: 10))
                .foregroundStyle(MSC.Colors.tertiary.opacity(0.7))
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                .fill(Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                .stroke(Color.white.opacity(0.07), style: StrokeStyle(lineWidth: 0.5, dash: [4, 3]))
        )
        .opacity(0.55)
    }
}

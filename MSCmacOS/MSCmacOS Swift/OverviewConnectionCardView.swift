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

    /// Effective public address — substitutes DuckDNS hostname when duck toggle is active
    private var effectivePublicAddress: String {
        if useDuckDNS && duckDNSAvailable { return duckDNSHost }
        return viewModel.cachedPublicIPAddress ?? "Fetching…"
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
        HStack(alignment: .top, spacing: MSC.Spacing.sm) {
            endpointCell(
                platformLabel: "Java · PC / Mac",
                dotColor: MSC.Colors.connectionWarning,
                address: jAddr,
                port: viewModel.javaPortForDisplay,
                copyLabel: "Copy Java",
                onCopy: {
                    copyToPasteboard("\(jAddr):\(viewModel.javaPortForDisplay)")
                    showHUDMessage(showPublicIP ? "Public Java address copied" : "Java address copied")
                }
            )

            if let rawBedAddr = resolvedBedrockAddress, let bedPort = resolvedBedrockPort {
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

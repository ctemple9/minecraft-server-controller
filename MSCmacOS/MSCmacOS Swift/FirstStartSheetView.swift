//
//  FirstStartSheetView.swift
//  MinecraftServerController
//
//  Post-start guidance sheet that explains what just happened and points
//  the user to the next safe setup or server-management steps.
//

import SwiftUI
import AppKit

struct FirstStartSheetView: View {
    @EnvironmentObject var viewModel: AppViewModel

    @Binding var isShowingManageServers: Bool

    var body: some View {
        let parsed = parseFirstStartMessage(viewModel.firstStartAlertMessage)

        VStack(spacing: 0) {

            // ── Coloured hero header ──────────────────────────────────────
            firstStartHeader

            Divider()

            // ── Scrollable body ───────────────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: MSC.Spacing.lg) {

                    // "What happened" card
                    FSCard(
                        icon: "sparkles",
                        color: .green,
                        title: "What happened"
                    ) {
                        Text(parsed.body)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }

                    // "Next steps" card — only when there are steps
                    if !parsed.nextSteps.isEmpty {
                        FSCard(
                            icon: "list.number",
                            color: .blue,
                            title: "Next steps"
                        ) {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(Array(parsed.nextSteps.enumerated()), id: \.offset) { idx, step in
                                    FSStep(number: idx + 1, text: step)
                                }
                            }
                            .textSelection(.enabled)
                        }
                    }

                    // "So how do people connect?" — dynamic per-transport guidance.
                    if let cfg = selectedCfg {
                        let rows = connectionRows(cfg: cfg)
                        if !rows.isEmpty {
                            FSCard(
                                icon: "point.3.filled.connected.trianglepath.dotted",
                                color: .blue,
                                title: "So how do people connect?"
                            ) {
                                VStack(alignment: .leading, spacing: MSC.Spacing.md) {
                                    ForEach(rows) { row in
                                        connectRowView(row)
                                    }
                                }
                            }
                        }
                    }

                    // One-time setup reassurance.
                    FSCallout(
                        icon: "checkmark.seal.fill",
                        color: .green,
                        text: "This one-time setup is complete. Your server won't start and stop on its own again — press Start whenever you want to play."
                    )

                    // Footer callout (Xbox Broadcast note, etc.)
                    if let footer = parsed.footer, !footer.isEmpty,
                       footer != parsed.body {
                        FSCallout(
                            icon: "info.circle.fill",
                            color: .secondary,
                            text: footer
                        )
                    }

                }
                .padding(MSC.Spacing.xl)
            }

            // ── Action footer ─────────────────────────────────────────────
            Divider()
            HStack(spacing: MSC.Spacing.sm) {
                Button("Open Server Settings\u{2026}") {
                    viewModel.manageServersShouldAutoEditSelectedOnSettingsTab = true
                    isShowingManageServers = true
                    viewModel.showFirstStartAlert = false
                }
                .buttonStyle(MSCSecondaryButtonStyle())

                Spacer()

                Button("OK") {
                    viewModel.showFirstStartAlert = false
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(MSCPrimaryButtonStyle())
            }
            .padding(.horizontal, MSC.Spacing.xl)
            .padding(.vertical, MSC.Spacing.md)
        }
        .frame(minWidth: 560, idealWidth: 580, minHeight: 380)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Hero Header

    private var firstStartHeader: some View {
        HStack(spacing: MSC.Spacing.md) {
            // App icon
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.firstStartAlertTitle.isEmpty
                     ? "Server Initialised"
                     : viewModel.firstStartAlertTitle)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.primary)

                if let headline = parseFirstStartMessage(viewModel.firstStartAlertMessage).headline,
                   !headline.isEmpty {
                    Text(headline)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Success badge
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
                Text("Ready")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.green.opacity(0.1)))
            .overlay(Capsule().stroke(Color.green.opacity(0.25), lineWidth: 1))
        }
        .padding(.horizontal, MSC.Spacing.xl)
        .padding(.vertical, MSC.Spacing.lg)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Connection guidance

    /// A single "how to connect" row in the completion sheet.
    private struct ConnectRow: Identifiable {
        let id = UUID()
        let icon: String
        let color: Color
        let title: String
        let detail: String
        let value: String?   // monospaced, copyable address (nil for text-only rows)
    }

    private var selectedCfg: ConfigServer? {
        guard let sel = viewModel.selectedServer else { return nil }
        return viewModel.configServer(for: sel)
    }

    /// Builds per-transport connection guidance from the current config + live
    /// playit addresses + captured Xbox gamertag.
    private func connectionRows(cfg: ConfigServer) -> [ConnectRow] {
        var rows: [ConnectRow] = []
        let localIP = AppUtilities.localIPAddress() ?? "your-mac-ip"
        let publicIP = viewModel.cachedPublicIPAddress
        let usePlayitAddresses = cfg.playitEnabled

        let showJava = !cfg.isBedrock
        let showBedrock = cfg.isBedrock
            || (usePlayitAddresses && viewModel.playitBedrockAddress != nil)
            || cfg.bedrockPort != nil
            || cfg.xboxBroadcastEnabled

        if showJava {
            let port = viewModel.loadServerPropertiesModel(for: cfg).serverPort
            rows.append(ConnectRow(
                icon: "cup.and.saucer.fill", color: .orange,
                title: "Java — same Wi-Fi",
                detail: "Friends on your network join with your Mac's local address.",
                value: "\(localIP):\(port)"))
            if usePlayitAddresses, let playit = viewModel.playitJavaAddress {
                rows.append(ConnectRow(
                    icon: "globe", color: .blue,
                    title: "Java — anywhere (playit.gg)",
                    detail: "Preferred for players outside your home. No port forwarding needed.",
                    value: playit))
            } else if let publicIP {
                rows.append(ConnectRow(
                    icon: "network", color: .blue,
                    title: "Java — outside your network",
                    detail: "Works only if you forward TCP \(port) on your router.",
                    value: "\(publicIP):\(port)"))
            }
        }

        if showBedrock {
            let bport = cfg.bedrockPort ?? 19132
            rows.append(ConnectRow(
                icon: "cube.fill", color: .green,
                title: "Bedrock — same Wi-Fi",
                detail: "Mobile, console & Windows friends on your network.",
                value: "\(localIP):\(bport)"))
            if usePlayitAddresses, let playitB = viewModel.playitBedrockAddress {
                rows.append(ConnectRow(
                    icon: "globe", color: .blue,
                    title: "Bedrock — anywhere (playit.gg)",
                    detail: "Preferred for players outside your home.",
                    value: playitB))
            } else if let publicIP {
                rows.append(ConnectRow(
                    icon: "network", color: .blue,
                    title: "Bedrock — outside your network",
                    detail: "Works only if you forward UDP \(bport) on your router.",
                    value: "\(publicIP):\(bport)"))
            }
        }

        if cfg.xboxBroadcastEnabled {
            let tag = viewModel.initiationBroadcastGamertag ?? cfg.xboxBroadcastAltGamertag
            if let tag, !tag.isEmpty {
                rows.append(ConnectRow(
                    icon: "gamecontroller.fill", color: .green,
                    title: "Xbox / console players",
                    detail: "Add \(tag) as a friend on Xbox Live, then open Friends → Worlds to join.",
                    value: nil))
            } else {
                rows.append(ConnectRow(
                    icon: "gamecontroller.fill", color: .green,
                    title: "Xbox / console players",
                    detail: "Once broadcast signs in, add its gamertag as a friend, then open Friends → Worlds to join.",
                    value: nil))
            }
        }

        return rows
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @ViewBuilder
    private func connectRowView(_ row: ConnectRow) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: row.icon)
                .font(.system(size: 13))
                .foregroundStyle(row.color)
                .frame(width: 18)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(row.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let value = row.value {
                    HStack(spacing: 6) {
                        Text(value)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(row.color.opacity(0.10))
                            )
                        Button {
                            copyToPasteboard(value)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Copy \(value)")
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Parser

    private func parseFirstStartMessage(_ raw: String) -> (headline: String?, body: String, nextSteps: [String], footer: String?) {
        let blocks = raw.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var headline: String? = nil
        var body: String = raw
        var nextSteps: [String] = []
        var footer: String? = nil

        if blocks.count >= 1 { headline = blocks[0] }
        if blocks.count >= 2 { body = blocks[1] } else { body = raw }

        let lines = raw.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        nextSteps = lines.compactMap { line in
            if line.hasPrefix("\u{2022}") {
                return line.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return nil
        }

        if let last = blocks.last, last.contains("Xbox") || last.contains("Broadcast") {
            footer = last
        } else if blocks.count >= 3 {
            footer = blocks.last
        }

        return (headline: headline, body: body, nextSteps: nextSteps, footer: footer)
    }
}

// MARK: - Card Container

/// Section card with icon badge + title header — mirrors QSStep outer shell.
private struct FSCard<Content: View>: View {
    let icon: String
    let color: Color
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
            // Card header
            HStack(spacing: MSC.Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                        .fill(color.opacity(0.13))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(color)
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            Rectangle()
                .fill(Color.secondary.opacity(0.1))
                .frame(height: 1)

            content
        }
        .padding(MSC.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.lg, style: .continuous)
                .fill(MSC.Colors.cardBackground.opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MSC.Radius.lg, style: .continuous)
                .stroke(MSC.Colors.cardBorder, lineWidth: 1)
        )
    }
}

// MARK: - Step Row

/// A numbered step row — mirrors ChecklistStep from ServerHandbookView.
private struct FSStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 22, height: 22)
                Text("\(number)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.top, 1)

            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Callout

/// Tinted callout — mirrors GuideCallout / QSCallout.
private struct FSCallout: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(color)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(MSC.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Initiation Progress Overlay (pass 2)

/// Non-modal panel shown while playit / Xbox broadcast come up during first-time
/// initiation. Non-modal so the in-app Xbox sign-in sheet can present over it.
struct InitiationProgressOverlay: View {
    @EnvironmentObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
            HStack(spacing: MSC.Spacing.sm) {
                ProgressView().controlSize(.small)
                Text("Setting up connections\u{2026}")
                    .font(.system(size: 13, weight: .semibold))
            }
            Text("Finishing your one-time setup. This ends automatically.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if viewModel.initiationPlayitStatus != .notApplicable {
                transportRow(title: "playit.gg tunnel",
                             status: viewModel.initiationPlayitStatus,
                             skip: { viewModel.skipInitiationPlayit() })
            }
            if viewModel.initiationBroadcastStatus != .notApplicable {
                transportRow(title: "Xbox broadcast",
                             status: viewModel.initiationBroadcastStatus,
                             skip: { viewModel.skipInitiationBroadcast() })
            }
        }
        .padding(MSC.Spacing.md)
        .frame(width: 300, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.lg, style: .continuous)
                .fill(MSC.Colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MSC.Radius.lg, style: .continuous)
                .stroke(MSC.Colors.cardBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .padding(MSC.Spacing.lg)
    }

    @ViewBuilder
    private func transportRow(title: String,
                              status: InitiationTransportStatus,
                              skip: @escaping () -> Void) -> some View {
        HStack(spacing: MSC.Spacing.sm) {
            statusIcon(status)
            Text(title).font(.system(size: 12, weight: .medium))
            Spacer()
            switch status {
            case .waiting:
                Button("Skip", action: skip)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            case .ready:
                Text("Ready").font(.system(size: 11, weight: .semibold)).foregroundStyle(.green)
            case .skipped:
                Text("Skipped").font(.system(size: 11)).foregroundStyle(.secondary)
            case .failed:
                Text("Not set up").font(.system(size: 11)).foregroundStyle(.orange)
            case .notApplicable:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: InitiationTransportStatus) -> some View {
        switch status {
        case .waiting:
            ProgressView().controlSize(.small)
        case .ready:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .skipped:
            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .notApplicable:
            EmptyView()
        }
    }
}

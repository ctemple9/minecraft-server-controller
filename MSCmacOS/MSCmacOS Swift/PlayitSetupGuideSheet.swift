//
//  PlayitSetupGuideSheet.swift
//  MinecraftServerController
//
//  Visual language matches RouterPortForwardGuideSheet:
//    controlBackgroundColor chrome bars, windowBackgroundColor body,
//    colored section cards (purple intro, blue prerequisites, green values, neutral steps).
//

import SwiftUI

struct PlayitSetupGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    let localPort: Int
    let bedrockPort: Int?

    @State private var introExpanded: Bool = true

    var body: some View {
        VStack(spacing: 0) {

            // MARK: Header bar — matches RouterPortForwardGuideSheet exactly
            HStack(spacing: MSC.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("playit.gg Tunnel Setup")
                        .font(MSC.Typography.shellTitle)
                        .foregroundStyle(.primary)
                    Text("How this works — one-time setup")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
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

            // MARK: Sticky values strip — mirrors StickyValuesStrip
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    PlayitValueCell(label: "Local Port",   value: "\(localPort)",          copyable: "\(localPort)")
                    Divider().frame(height: 28)
                    if let bp = bedrockPort {
                        PlayitValueCell(label: "Bedrock Port", value: "\(bp)", copyable: "\(bp)")
                        Divider().frame(height: 28)
                    }
                    PlayitValueCell(label: "Tunnel Address", value: "Auto-assigned",        copyable: nil)
                    Spacer()
                }
                .padding(.horizontal, MSC.Spacing.xl)
                .padding(.vertical, MSC.Spacing.sm)
                .background(Color(nsColor: .controlBackgroundColor))
                Divider()
            }

            // MARK: Guide body
            ScrollView {
                VStack(alignment: .leading, spacing: MSC.Spacing.xl) {

                    // Guide header
                    VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                        MSCOverline("External Access — No Router Needed")
                        Text("playit.gg Tunnel")
                            .font(MSC.Typography.pageTitle)
                            .foregroundStyle(.primary)
                    }

                    // Purple — WHAT YOU ARE DOING
                    introSection

                    // Blue — BEFORE YOU START
                    prerequisitesSection

                    // Green — WHAT YOU WILL DO ON PLAYIT.GG
                    setupStepsSection

                    // Neutral — NUMBERED STEPS
                    numberedStepsSection

                    // Notes
                    notesSection
                }
                .padding(MSC.Spacing.xl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))

            // MARK: Footer bar
            Divider()
            HStack {
                Text("Latency: playit.gg adds ~10–50 ms. Game traffic passes through their relay servers.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Got it") { dismiss() }
                    .buttonStyle(MSCPrimaryButtonStyle())
            }
            .padding(.horizontal, MSC.Spacing.xl)
            .padding(.vertical, MSC.Spacing.md)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(minWidth: 560, idealWidth: 640, minHeight: 520, idealHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Intro section (purple)

    private var introSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(MSC.Animation.tabSwitch) { introExpanded.toggle() }
            } label: {
                HStack(spacing: MSC.Spacing.sm) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 11)).foregroundStyle(.purple)
                    MSCOverline("What you are doing")
                    Spacer()
                    Image(systemName: introExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, MSC.Spacing.md).padding(.vertical, MSC.Spacing.sm + 2)
            }
            .buttonStyle(.plain)

            if introExpanded {
                Rectangle().fill(MSC.Colors.guideMenuPath.opacity(0.12)).frame(height: 1)
                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                    Text("playit.gg creates an outbound tunnel from your Mac to their relay servers. Friends connect to a public address playit.gg gives you — no router or port forwarding needed on your end.")
                        .font(.system(size: 12)).foregroundStyle(.primary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("A native playitd agent runs automatically alongside your Minecraft server. The whole process is managed by MSC — you only need to set it up once on the playit.gg website.")
                        .font(.system(size: 12)).foregroundStyle(.primary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, MSC.Spacing.md).padding(.vertical, MSC.Spacing.md)
            }
        }
        .background(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).fill(MSC.Colors.guideMenuPathFill))
        .overlay(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).stroke(MSC.Colors.guideMenuPathBorder, lineWidth: 1))
    }

    // MARK: - Prerequisites section (blue)

    private var prerequisitesSection: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "checklist").font(.system(size: 11)).foregroundStyle(.blue)
                MSCOverline("Before you start")
            }
            .padding(.horizontal, MSC.Spacing.md).padding(.top, MSC.Spacing.md)

            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                ForEach([
                    "A free playit.gg account (no credit card, takes about 2 minutes to create).",
                    "About 5 minutes total for the one-time website setup.",
                ], id: \.self) { bullet in
                    HStack(alignment: .top, spacing: MSC.Spacing.sm) {
                        Circle().fill(MSC.Colors.guideInfo.opacity(0.5))
                            .frame(width: 4, height: 4).padding(.top, 5)
                        Text(bullet)
                            .font(.system(size: 12)).foregroundStyle(.primary.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, MSC.Spacing.md).padding(.bottom, MSC.Spacing.md)
        }
        .background(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).fill(MSC.Colors.guideInfoFill))
        .overlay(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).stroke(MSC.Colors.guideInfoBorder, lineWidth: 1))
    }

    // MARK: - Setup steps section (green — mirrors ValueSummarySectionView)

    private var setupStepsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.and.pencil.and.ellipsis")
                    .font(.system(size: 11)).foregroundStyle(.green)
                MSCOverline("What you will do on playit.gg")
            }
            .padding(.horizontal, MSC.Spacing.md).padding(.top, MSC.Spacing.md).padding(.bottom, MSC.Spacing.sm)

            let rows: [(String, String)] = [
                ("Create agent", "playit.gg → Setup Wizard → New Agent"),
                ("Copy secret key", "Shown at the end of the wizard"),
                ("Create Java tunnel", "Minecraft Java · TCP · port \(localPort)"),
                ("Create Bedrock tunnel", bedrockPort != nil ? "Minecraft Bedrock · UDP · port \(bedrockPort!)" : "Skip if not using Geyser"),
            ]

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                    PlayitValueRow(label: row.0, value: row.1)
                    if idx < rows.count - 1 {
                        Rectangle().fill(MSC.Colors.guideStep.opacity(0.12))
                            .frame(height: 1).padding(.leading, MSC.Spacing.md)
                    }
                }
            }
            .padding(.bottom, MSC.Spacing.xs)
        }
        .background(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).fill(MSC.Colors.guideStepFill))
        .overlay(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).stroke(MSC.Colors.guideStepBorder, lineWidth: 1))
    }

    // MARK: - Numbered steps (neutral)

    private var numberedStepsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "list.number")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                MSCOverline("Step by step")
            }
            .padding(.horizontal, MSC.Spacing.md).padding(.top, MSC.Spacing.md).padding(.bottom, MSC.Spacing.xs)

            let steps: [(String, String)] = [
                ("Go to the playit.gg Setup Wizard",
                 "Open playit.gg → Setup → New Agent. Name your agent (e.g. msc-server) and copy the Secret Key shown at the end of the wizard."),
                ("Enable the tunnel in MSC",
                 "When creating a server choose Tunnel (playit.gg) in the Network step, or toggle it on in Edit Server → Settings → Network for an existing server."),
                ("Start your server",
                 "MSC starts the playit agent automatically. A secret key prompt appears — paste the key you copied in step 1 and click Save."),
                ("Create your tunnels on playit.gg",
                 "Go to playit.gg → Tunnels → New Tunnel. Create a Minecraft Java tunnel (port \(localPort)).\(bedrockPort != nil ? " Also create a Minecraft Bedrock tunnel (port \(bedrockPort!)) for Geyser/iPad players." : "")"),
                ("Assign tunnels to your agent",
                 "When creating each tunnel, select your agent from the list. The tunnel goes live immediately — no restart needed."),
                ("Share your address",
                 "Your public addresses appear automatically in the Overview connection card. Friends use these to join. No router setup required on your end."),
            ]

            VStack(spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                    HStack(alignment: .top, spacing: MSC.Spacing.md) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.12))
                                .frame(width: 24, height: 24)
                            Text("\(idx + 1)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                        }
                        .padding(.top, 1)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.0)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text(step.1)
                                .font(.system(size: 12))
                                .foregroundStyle(.primary.opacity(0.75))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, MSC.Spacing.md)
                    .padding(.vertical, MSC.Spacing.sm + 2)

                    if idx < steps.count - 1 {
                        Rectangle().fill(MSC.Colors.guideNeutralDivider)
                            .frame(height: 1).padding(.leading, 52)
                    }
                }
            }
            .padding(.bottom, MSC.Spacing.xs)
        }
        .background(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).fill(MSC.Colors.guideNeutralFill))
        .overlay(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).stroke(MSC.Colors.guideNeutralBorder, lineWidth: 1))
    }

    // MARK: - Notes section (neutral)

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "mic.fill").font(.system(size: 11)).foregroundStyle(.secondary)
                MSCOverline("Using Simple Voice Chat?")
            }
            .padding(.horizontal, MSC.Spacing.md).padding(.top, MSC.Spacing.md)

            Text("Voice chat uses a separate UDP port (24454). After your server is created, go to Edit Server → Settings → Network and toggle \"Voice Chat Tunnel\". Then create a third tunnel on playit.gg — Custom UDP, port 24454 — and assign it to your agent.")
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, MSC.Spacing.md)
                .padding(.bottom, MSC.Spacing.md)
        }
        .background(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).fill(MSC.Colors.guideNeutralFill))
        .overlay(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).stroke(MSC.Colors.guideNeutralBorder, lineWidth: 1))
    }
}

// MARK: - Shared sub-views (mirror StickyValueCell / ValueSummaryRow)

private struct PlayitValueCell: View {
    let label: String
    let value: String
    let copyable: String?
    @State private var copied = false

    var body: some View {
        HStack(spacing: MSC.Spacing.xs) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased())
                    .font(.system(size: 8, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
                Text(value)
                    .font(MSC.Typography.mono).foregroundStyle(.primary).lineLimit(1)
            }
            if let copyable {
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(copyable, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9))
                        .foregroundStyle(copied ? Color.green : Color.secondary)
                }
                .buttonStyle(.plain)
                .animation(MSC.Animation.buttonPress, value: copied)
            }
        }
        .padding(.horizontal, MSC.Spacing.md)
    }
}

private struct PlayitValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(MSC.Typography.mono)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, MSC.Spacing.sm)
        .padding(.horizontal, MSC.Spacing.md)
    }
}

//
//  QuickStartView.swift
//  MinecraftServerController
//
//  Compact quick-start checklist for Java and Bedrock servers.
//  Keeps the short actionable path separate from the deeper Welcome Guide.
//

import SwiftUI

struct QuickStartView: View {
    @EnvironmentObject var viewModel: AppViewModel

    @State private var quickStartType: ServerType = .java

    var body: some View {
        VStack(spacing: 0) {
            // ── Compact inline header ─────────────────────────────────────
            HStack(spacing: MSC.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.green)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Quick Start")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("Get your first Minecraft server online \u{2014} choose Java or Bedrock.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Link to the deeper reference guide
                Button {
                    viewModel.isShowingWelcomeGuide = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "book.fill")
                            .font(.system(size: 10))
                        Text("Welcome Guide")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(MSCSecondaryButtonStyle())
                .help("Open the Welcome Guide for deeper explanations and troubleshooting.")
            }
            .padding(.horizontal, MSC.Spacing.xl)
            .padding(.vertical, MSC.Spacing.lg)

            Divider()

            // ── Server type selector ──────────────────────────────────────
            HStack(spacing: 0) {
                serverTypeButton(type: .java, label: "Java", icon: "server.rack")
                serverTypeButton(type: .bedrock, label: "Bedrock", icon: "cube.fill")
            }
            .padding(.horizontal, MSC.Spacing.xl)
            .padding(.top, MSC.Spacing.md)
            .padding(.bottom, MSC.Spacing.sm)

            Divider()

            // ── Scrollable steps ──────────────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
                    if quickStartType == .java {
                        javaSteps
                    } else {
                        bedrockSteps
                    }
                }
                .padding(MSC.Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(minWidth: 520, minHeight: 600)
    }

    // MARK: - Server Type Toggle Button

    private func serverTypeButton(type: ServerType, label: String, icon: String) -> some View {
        let isSelected = quickStartType == type
        let color: Color = type == .java ? .orange : .green

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                quickStartType = type
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? color : .secondary)
                Text(label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                    .fill(isSelected ? color.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                    .stroke(isSelected ? color.opacity(0.35) : Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }

    // MARK: - Java Steps

    @ViewBuilder
    private var javaSteps: some View {
        // Before you begin
        QSCallout(
            icon: "lightbulb.fill",
            color: .purple,
            title: "Before you begin",
            text: "Install Java 21+ (Temurin recommended) and know where you want to keep your server folder, e.g. ~/MinecraftServers. This app handles Paper downloads and startup \u{2014} no Terminal needed."
        )

        // Step 1
        QSStep(
            number: 1,
            icon: "network",
            color: .blue,
            title: "Forward router ports",
            subtitle: "Required for friends outside your home network to connect.",
            rows: [
                QSRow(label: "Java / Paper", value: "TCP 25565 \u{2192} your Mac's local IP"),
                QSRow(label: "Bedrock / Geyser", value: "UDP 19132 \u{2192} same Mac  (optional, cross-play only)"),
            ],
            note: "Log into your router \u{2192} Port Forwarding / Virtual Server \u{2192} add the rules above. You only do this once. The app shows these addresses in Server Details \u{2192} Connection Info."
        )

        // Step 2
        QSStep(
            number: 2,
            icon: "server.rack",
            color: .green,
            title: "Create your Java server",
            subtitle: "Takes about 60 seconds.",
            rows: [
                QSRow(label: "1", value: "Click Manage Servers\u{2026} \u{2192} Create New Server\u{2026}"),
                QSRow(label: "2", value: "Select Java as the server type"),
                QSRow(label: "3", value: "Set a display name and choose a server folder"),
                QSRow(label: "4", value: "Select Use latest Paper template for the JAR"),
                QSRow(label: "5", value: "RAM: 2 GB min / 4 GB max is a solid starting point"),
                QSRow(label: "6", value: "Enable Bedrock Cross-play if you want mobile/console players"),
            ],
            note: nil
        )

        // Step 3
        QSStep(
            number: 3,
            icon: "gearshape.fill",
            color: .orange,
            title: "Accept EULA & configure settings",
            subtitle: "Required before the server will fully start.",
            rows: [
                QSRow(label: "1", value: "Select your server in Server Controls"),
                QSRow(label: "2", value: "Server Details \u{2192} EULA section \u{2192} Accept EULA"),
                QSRow(label: "3", value: "Open Server Settings\u{2026} to set MOTD, difficulty, gamemode, and max players"),
                QSRow(label: "4", value: "Leave Online Mode ON unless you specifically need a cracked server"),
            ],
            note: "If the console says \"You need to agree to the EULA,\" accept it and start again."
        )

        // Step 4 (optional)
        QSOptionalStep(
            number: 4,
            icon: "gamecontroller.fill",
            color: .purple,
            title: "Enable Bedrock cross-play & Xbox broadcast",
            parts: [
                QSOptionalPart(
                    heading: "Geyser / Floodgate (cross-play)",
                    bullets: [
                        "Download Geyser + Floodgate templates in JARs if not already done",
                        "They were copied into plugins/ when you created the server with cross-play enabled",
                        "Confirm Bedrock port 19132 is forwarded on your router (UDP)",
                    ]
                ),
                QSOptionalPart(
                    heading: "Xbox Broadcast (Friends tab visibility)",
                    bullets: [
                        "Create a dedicated alt Microsoft/Xbox account for broadcasting",
                        "Manage Servers \u{2192} Edit \u{2192} Broadcast tab \u{2192} enable broadcast + enter alt account details",
                        "Friends who add your alt account see a joinable world in their Friends tab",
                        "This advertises your server \u{2014} port forwarding is still required",
                    ]
                ),
            ]
        )

        // Step 5
        QSStep(
            number: 5,
            icon: "play.fill",
            color: .green,
            title: "Start, test, and back up",
            subtitle: "You're almost there.",
            rows: [
                QSRow(label: "1", value: "Click Start and watch the Console"),
                QSRow(label: "2", value: "Ready when you see: \"Done (xx.xx s)! For help, type /help\""),
                QSRow(label: "3", value: "Test on Java: add server localhost:25565"),
                QSRow(label: "4", value: "Test on Bedrock: add server using your LAN IP + port 19132"),
                QSRow(label: "5", value: "Once everything works, open Server Details → Worlds and create your first backup"),
            ],
            note: "After the first backup, you can safely try plugins or change settings \u{2014} restore if anything breaks."
        )

        // Done callout
        QSCallout(
            icon: "flag.checkered",
            color: .green,
            title: "You're live",
            text: "Share your DuckDNS hostname or public IP with friends. Java players use Multiplayer \u{2192} Add Server; Bedrock players add a custom server entry with your IP and port 19132. Need DuckDNS? See Help \u{2192} Welcome Guide \u{2192} Ports & DuckDNS."
        )
    }

    // MARK: - Bedrock Steps

    @ViewBuilder
    private var bedrockSteps: some View {
        // Before you begin
        QSCallout(
            icon: "lightbulb.fill",
            color: .blue,
            title: "Before you begin",
            text: "Install Docker Desktop (docker.com) before creating a Bedrock server. It's free for personal use. The app will detect it automatically. No Java installation needed."
        )

        // Step 1
        QSStep(
            number: 1,
            icon: "network",
            color: .blue,
            title: "Forward router port (UDP)",
            subtitle: "Required for friends outside your home network to connect.",
            rows: [
                QSRow(label: "Bedrock / BDS", value: "UDP 19132 \u{2192} your Mac's local IP"),
            ],
            note: "Important: Bedrock uses UDP, not TCP. If you forward TCP 19132 instead, external players cannot connect. Log into your router \u{2192} Port Forwarding and add a UDP rule."
        )

        // Step 2
        QSStep(
            number: 2,
            icon: "cube.fill",
            color: .green,
            title: "Create your Bedrock server",
            subtitle: "Takes about 60 seconds.",
            rows: [
                QSRow(label: "1", value: "Click Manage Servers\u{2026} \u{2192} Create New Server\u{2026}"),
                QSRow(label: "2", value: "Select Bedrock as the server type"),
                QSRow(label: "3", value: "Set a display name and server folder"),
                QSRow(label: "4", value: "Port: 19132 (default \u{2014} leave as-is unless you have a conflict)"),
                QSRow(label: "5", value: "Set max players, difficulty, and gamemode"),
                QSRow(label: "6", value: "Click Create"),
            ],
            note: nil
        )

        // Step 3
        QSStep(
            number: 3,
            icon: "play.fill",
            color: .orange,
            title: "Start and test",
            subtitle: "First start pulls the Docker image automatically.",
            rows: [
                QSRow(label: "1", value: "Click Start"),
                QSRow(label: "2", value: "First launch: the app pulls the Docker image (may take a minute \u{2014} watch the console)"),
                QSRow(label: "3", value: "Ready when the console shows: \"Server started\""),
                QSRow(label: "4", value: "Test: Bedrock client \u{2192} Add Server \u{2192} your Mac's LAN IP + port 19132"),
                QSRow(label: "5", value: "Mobile (iOS/Android), console, and Windows 10/11 all connect the same way"),
            ],
            note: "Docker Desktop must be open and running before you can start a Bedrock server. The app shows a warning if it's not."
        )

        // Step 4
        QSStep(
            number: 4,
            icon: "archivebox.fill",
            color: .purple,
            title: "Back up",
            subtitle: "Always create a backup before inviting others.",
            rows: [
                QSRow(label: "1", value: "Open Server Details → Worlds for this server"),
                QSRow(label: "2", value: "Click Create Backup and label it \"initial setup\""),
                QSRow(label: "3", value: "Now you can safely experiment \u{2014} restore if anything breaks"),
            ],
            note: nil
        )

        // Done callout
        QSCallout(
            icon: "flag.checkered",
            color: .green,
            title: "You're live",
            text: "Share your DuckDNS hostname or public IP + port 19132 with friends. They add it as a custom server in Bedrock's server list (Settings \u{2192} Servers \u{2192} Add Server). Bedrock Edition cross-play is built in \u{2014} mobile, console, and Windows 10/11 players can all join. Bedrock uses UDP \u{2014} make sure your router forwards UDP 19132, not TCP."
        )
    }
}

// MARK: - Quick Start Building Blocks
// These are private to this file — they follow the exact same visual grammar
// as GuideCallout / InAppBox in WelcomeGuideView, adapted for a narrower window.

/// Tinted callout card — mirrors GuideCallout from WelcomeGuideView.
private struct QSCallout: View {
    let icon: String
    let color: Color
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(MSC.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .fill(color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
}

/// Data for a single label->value row inside a step card.
private struct QSRow {
    let label: String
    let value: String
}

/// A numbered step card with icon, title, subtitle, optional rows, and an optional note.
private struct QSStep: View {
    let number: Int
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let rows: [QSRow]
    let note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {

            // Header row
            HStack(spacing: MSC.Spacing.sm) {
                // Numbered badge
                ZStack {
                    Circle()
                        .fill(color)
                        .frame(width: 26, height: 26)
                    Text("\(number)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }

                // Icon + title
                ZStack {
                    RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                        .fill(color.opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(color)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            // Divider
            Rectangle()
                .fill(Color.secondary.opacity(0.1))
                .frame(height: 1)

            // Rows
            VStack(alignment: .leading, spacing: 6) {
                ForEach(rows.indices, id: \.self) { idx in
                    let row = rows[idx]
                    HStack(alignment: .top, spacing: 8) {
                        // If label is a single digit it's a step number; otherwise it's a key
                        let isNumeric = Int(row.label) != nil
                        if isNumeric {
                            Text(row.label)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 16, height: 16)
                                .background(Circle().fill(color.opacity(0.6)))
                        } else {
                            Text(row.label)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(color)
                                .frame(minWidth: 50, alignment: .leading)
                        }

                        Text(row.value)
                            .font(.system(size: 12))
                            .foregroundStyle(.primary.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            // Optional note callout
            if let note {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.top, 1)
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(MSC.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                        .fill(Color.secondary.opacity(0.06))
                )
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
}

/// Data for a sub-section inside an optional step.
private struct QSOptionalPart {
    let heading: String
    let bullets: [String]
}

/// An optional step card — same shape as QSStep but badged "Optional" and uses sub-sections.
private struct QSOptionalStep: View {
    let number: Int
    let icon: String
    let color: Color
    let title: String
    let parts: [QSOptionalPart]

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {

            // Header
            HStack(spacing: MSC.Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.5))
                        .frame(width: 26, height: 26)
                    Text("\(number)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }

                ZStack {
                    RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                        .fill(color.opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(color)
                }

                Text(title)
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Text("Optional")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(color.opacity(0.1))
                    )
                    .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 0.5))
            }

            Rectangle()
                .fill(Color.secondary.opacity(0.1))
                .frame(height: 1)

            ForEach(parts.indices, id: \.self) { idx in
                let part = parts[idx]

                VStack(alignment: .leading, spacing: 5) {
                    Text(part.heading)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(color)

                    ForEach(part.bullets.indices, id: \.self) { bi in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(color.opacity(0.7))
                                .padding(.top, 2)
                            Text(part.bullets[bi])
                                .font(.system(size: 12))
                                .foregroundStyle(.primary.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if idx < parts.count - 1 {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.08))
                        .frame(height: 1)
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
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
}

#Preview {
    QuickStartView()
        .environmentObject(AppViewModel())
}


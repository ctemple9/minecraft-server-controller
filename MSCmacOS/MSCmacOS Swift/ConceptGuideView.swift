//
//  ConceptGuideView.swift
//  MinecraftServerController
//
//  Visual mental model walkthrough for first-time users.
//  7 pages: server, connections, Java vs Bedrock, worlds, active-world
//  routing (auto-loop), settings separation, and a next-steps CTA.
//

import SwiftUI

// MARK: - Container

struct ConceptGuideView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var currentPage = 0
    private let pageCount = 7

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.08, blue: 0.13),
                    Color(red: 0.10, green: 0.10, blue: 0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                pageContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                bottomNav
            }
        }
        .frame(width: 760, height: 530)
        .preferredColorScheme(.dark)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Text("HOW MSC WORKS")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.28))
                .tracking(1.2)
                .padding(.leading, 24)
            Spacer()
            Button("Skip") { skip() }
                .foregroundStyle(.white.opacity(0.4))
                .font(.system(size: 12))
                .buttonStyle(.plain)
                .padding(.trailing, 24)
        }
        .frame(height: 36)
    }

    // MARK: - Page content

    @ViewBuilder
    private var pageContent: some View {
        ZStack {
            switch currentPage {
            case 0: CGPage1_Server()
            case 1: CGPage2_Connections()
            case 2: CGPage3_JavaBedrock()
            case 3: CGPage4_Worlds()
            case 4: CGPage5_ActiveWorld()
            case 5: CGPage6_Settings()
            default:
                CGPage7_Ready(
                    showsTourButton: viewModel.shouldStartOnboardingAfterConceptGuide,
                    onPrimary: {
                        viewModel.handleConceptGuideDismissed()
                        dismiss()
                    },
                    onHandbook: openHandbook
                )
            }
        }
        .id(currentPage)
        .transition(
            .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal:   .move(edge: .leading).combined(with: .opacity)
            )
        )
    }

    // MARK: - Bottom nav

    private var bottomNav: some View {
        HStack {
            HStack(spacing: 7) {
                ForEach(0..<pageCount, id: \.self) { i in
                    Capsule()
                        .fill(i == currentPage ? Color.white : Color.white.opacity(0.22))
                        .frame(width: i == currentPage ? 18 : 7, height: 7)
                        .animation(.spring(duration: 0.28), value: currentPage)
                }
            }
            .padding(.leading, 24)

            Spacer()

            if currentPage < pageCount - 1 {
                Button(action: advance) {
                    HStack(spacing: 6) {
                        Text("Next")
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 22)
            }
        }
        .frame(height: 52)
    }

    // MARK: - Actions

    private func advance() {
        withAnimation(.easeInOut(duration: 0.28)) { currentPage += 1 }
    }

    private func skip() {
        viewModel.handleConceptGuideDismissed()
        dismiss()
    }

    private func openHandbook() {
        viewModel.handleConceptGuideDismissed()
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            viewModel.isShowingServerHandbook = true
        }
    }
}

// MARK: - Shared layout helpers

private struct CGTwoColumnLayout<D: View, T: View>: View {
    var accentColor: Color
    @ViewBuilder var diagram: () -> D
    @ViewBuilder var textContent: () -> T

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                accentColor.opacity(0.07)
                diagram()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(width: 1)

            textContent()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(28)
        }
    }
}

private struct CGTextBlock: View {
    var eyebrow: String
    var headline: String
    var bodyText: String
    var note: String? = nil
    var noteIcon: String = "quote.bubble"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(eyebrow.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.28))
                .tracking(1.3)

            Text(headline)
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text(bodyText)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)

            if let note {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: noteIcon)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.top, 1)
                    Text(note)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.45))
                        .italic()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Page 1: The Server

private struct CGPage1_Server: View {
    @State private var step = 0

    var body: some View {
        CGTwoColumnLayout(accentColor: .blue) {
            VStack(spacing: 44) {
                CGServerNodeView(size: 130, color: .blue)
                    .opacity(step >= 1 ? 1 : 0)
                    .offset(y: step >= 1 ? 0 : 10)

                HStack(spacing: 10) {
                    CGTagPill(icon: "network", label: "IP Address", color: .blue)
                    CGTagPill(icon: "number", label: "Port", color: .blue)
                    CGTagPill(icon: "antenna.radiowaves.left.and.right", label: "Playit.gg", color: .blue)
                }
                .opacity(step >= 2 ? 1 : 0)
                .offset(y: step >= 2 ? 0 : 8)
            }
        } textContent: {
            CGTextBlock(
                eyebrow: "The Foundation",
                headline: "The server is an address.",
                bodyText: "It runs on your Mac and listens for incoming connections. Your IP address, port, and Playit.gg tunnel all belong to it.",
                note: "Think of it like a phone number. It's how players reach you.",
                noteIcon: "phone.circle"
            )
        }
        .task {
            try? await Task.sleep(nanoseconds: 280_000_000)
            withAnimation(.easeOut(duration: 0.4)) { step = 1 }
            try? await Task.sleep(nanoseconds: 400_000_000)
            withAnimation(.easeOut(duration: 0.38)) { step = 2 }
        }
    }
}

// MARK: - Page 2: How Players Connect

private struct CGPage2_Connections: View {
    @State private var step = 0

    private let nodeSpacing: CGFloat = 64
    private var arrowColor: Color { .white.opacity(0.3) }

    var body: some View {
        CGTwoColumnLayout(accentColor: .blue) {
            VStack(spacing: 0) {
                // Tier 1: Two ways to get a public address
                HStack(spacing: nodeSpacing) {
                    VStack(spacing: 8) {
                        methodNode(icon: "wifi.router", label: "Port\nForward", color: .blue)
                        Image(systemName: "arrow.down.forward")
                            .font(.system(size: 12))
                            .foregroundStyle(arrowColor)
                            .opacity(step >= 2 ? 1 : 0)
                    }
                    VStack(spacing: 8) {
                        methodNode(icon: "cloud.fill", label: "Playit.gg\nTunnel", color: .purple)
                        Image(systemName: "arrow.down.backward")
                            .font(.system(size: 12))
                            .foregroundStyle(arrowColor)
                            .opacity(step >= 2 ? 1 : 0)
                    }
                }
                .opacity(step >= 1 ? 1 : 0)
                .offset(y: step >= 1 ? 0 : -8)

                // IP + Port: convergence point
                CGTagPill(icon: "network", label: "Your IP + Port", color: .cyan)
                    .padding(.top, 6)
                    .padding(.bottom, 6)
                    .opacity(step >= 2 ? 1 : 0)
                    .offset(y: step >= 2 ? 0 : 4)

                // Tier 2: Two ways players receive the address
                HStack(spacing: nodeSpacing) {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.backward")
                            .font(.system(size: 12))
                            .foregroundStyle(arrowColor)
                            .opacity(step >= 3 ? 1 : 0)
                        methodNode(icon: "link", label: "Direct\nShare", color: .teal)
                        Image(systemName: "arrow.down.forward")
                            .font(.system(size: 12))
                            .foregroundStyle(arrowColor)
                            .opacity(step >= 4 ? 1 : 0)
                    }
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.forward")
                            .font(.system(size: 12))
                            .foregroundStyle(arrowColor)
                            .opacity(step >= 3 ? 1 : 0)
                        methodNode(icon: "antenna.radiowaves.left.and.right", label: "Xbox\nBroadcast", color: .green)
                        Image(systemName: "arrow.down.backward")
                            .font(.system(size: 12))
                            .foregroundStyle(arrowColor)
                            .opacity(step >= 4 ? 1 : 0)
                    }
                }
                .opacity(step >= 3 ? 1 : 0)
                .offset(y: step >= 3 ? 0 : 4)

                // Server node
                CGServerNodeView(size: 78, color: .green)
                    .padding(.top, 6)
                    .opacity(step >= 4 ? 1 : 0)
                    .offset(y: step >= 4 ? 0 : 6)
            }
        } textContent: {
            CGTextBlock(
                eyebrow: "Connections",
                headline: "Address first, share second.",
                bodyText: "Port forwarding or Playit.gg gives your server a public address. Players connect through whichever method you shared with them.",
                note: "Xbox Broadcast needs an address to point to. Set up port forwarding or Playit.gg first.",
                noteIcon: "info.circle"
            )
        }
        .task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            withAnimation(.easeOut(duration: 0.38)) { step = 1 }
            try? await Task.sleep(nanoseconds: 420_000_000)
            withAnimation(.easeOut(duration: 0.35)) { step = 2 }
            try? await Task.sleep(nanoseconds: 380_000_000)
            withAnimation(.easeOut(duration: 0.35)) { step = 3 }
            try? await Task.sleep(nanoseconds: 360_000_000)
            withAnimation(.easeOut(duration: 0.32)) { step = 4 }
        }
    }

    private func methodNode(icon: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(color.opacity(0.15))
                    .frame(width: 58, height: 58)
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(width: 90)
                .lineLimit(2)
        }
    }
}

// MARK: - Page 3: Java vs. Bedrock

private struct CGPage3_JavaBedrock: View {
    @State private var step = 0

    var body: some View {
        CGTwoColumnLayout(accentColor: .orange) {
            VStack(spacing: 18) {
                CGServerTypePanel()
                    .padding(.horizontal, 0)
                    .opacity(step >= 1 ? 1 : 0)
                    .offset(y: step >= 1 ? 0 : 10)

                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("Geyser is a free plugin that bridges the two editions.")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                        .italic()
                }
                .opacity(step >= 2 ? 1 : 0)
            }
        } textContent: {
            CGTextBlock(
                eyebrow: "Server Types",
                headline: "Two server types. Different rules.",
                bodyText: "Java Edition servers can host both Java and Bedrock players when the Geyser plugin is installed. Bedrock Edition servers only accept Bedrock players.",
                note: "Not sure which to pick? Java gives you more crossplay flexibility.",
                noteIcon: "lightbulb"
            )
        }
        .task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            withAnimation(.easeOut(duration: 0.42)) { step = 1 }
            try? await Task.sleep(nanoseconds: 520_000_000)
            withAnimation(.easeOut(duration: 0.32)) { step = 2 }
        }
    }
}

// MARK: - Page 4: Worlds

private struct CGPage4_Worlds: View {
    @State private var step = 0

    private let worlds: [(String, Bool)] = [
        ("Survival SMP", true),
        ("Creative Build", false),
        ("Adventure Map", false),
    ]

    var body: some View {
        CGTwoColumnLayout(accentColor: .teal) {
            VStack(spacing: 22) {
                VStack(spacing: 10) {
                    CGServerNodeView(size: 88, color: .teal)
                    Image(systemName: "arrow.down")
                        .font(.system(size: 22))
                        .foregroundStyle(.teal.opacity(0.5))
                }
                .opacity(step >= 1 ? 1 : 0)
                .offset(y: step >= 1 ? 0 : -8)

                VStack(spacing: 8) {
                    ForEach(Array(worlds.enumerated()), id: \.offset) { idx, world in
                        CGWorldSlotCard(name: world.0, isActive: world.1, color: .teal, width: 248)
                            .opacity(step > idx + 1 ? 1 : 0)
                            .offset(y: step > idx + 1 ? 0 : 8)
                    }
                }
            }
        } textContent: {
            CGTextBlock(
                eyebrow: "World Slots",
                headline: "A server holds multiple worlds.",
                bodyText: "Think of world slots like separate save files. Only one is active at a time. Switch it and the next player connection lands in the new world.",
                note: "You can back up, rename, or swap worlds without touching the server's network settings."
            )
        }
        .task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            withAnimation(.easeOut(duration: 0.35)) { step = 1 }
            try? await Task.sleep(nanoseconds: 280_000_000)
            withAnimation(.easeOut(duration: 0.32)) { step = 2 }
            try? await Task.sleep(nanoseconds: 200_000_000)
            withAnimation(.easeOut(duration: 0.32)) { step = 3 }
            try? await Task.sleep(nanoseconds: 200_000_000)
            withAnimation(.easeOut(duration: 0.32)) { step = 4 }
        }
    }
}

// MARK: - Page 5: Active World Routing (auto-loop)

private struct CGPage5_ActiveWorld: View {
    @State private var activeWorldIndex = 0
    @State private var showPlayerArrow = false
    @State private var showWorldArrow = false

    private let worlds = ["Survival SMP", "Creative Build", "Nether Realm"]

    var body: some View {
        CGTwoColumnLayout(accentColor: .orange) {
            VStack(spacing: 0) {
                CGPlayerFigure(label: "Player", color: .orange, size: 60)
                    .padding(.top, 8)

                Image(systemName: "arrow.down")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.orange.opacity(0.6))
                    .frame(height: 40)
                    .opacity(showPlayerArrow ? 1 : 0)
                    .offset(y: showPlayerArrow ? 0 : -5)
                    .animation(.easeInOut(duration: 0.3), value: showPlayerArrow)

                CGServerNodeView(size: 88, color: .orange)

                Image(systemName: "arrow.down")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.orange.opacity(0.6))
                    .frame(height: 40)
                    .opacity(showWorldArrow ? 1 : 0)
                    .offset(y: showWorldArrow ? 0 : -5)
                    .animation(.easeInOut(duration: 0.3), value: showWorldArrow)

                VStack(spacing: 7) {
                    ForEach(Array(worlds.enumerated()), id: \.offset) { idx, name in
                        CGWorldSlotCard(
                            name: name,
                            isActive: idx == activeWorldIndex,
                            color: .orange,
                            width: 240
                        )
                        .animation(.easeInOut(duration: 0.28), value: activeWorldIndex)
                    }
                }
                .padding(.top, 2)
            }
        } textContent: {
            CGTextBlock(
                eyebrow: "Routing",
                headline: "One world is always active.",
                bodyText: "Players connect to the server. The server routes them into whichever world is currently active. Switch it and new connections go there instead.",
                note: "Players already in-game stay put. Only new connections route to the new active world.",
                noteIcon: "info.circle"
            )
        }
        .task {
            while !Task.isCancelled {
                // Reset
                showPlayerArrow = false
                showWorldArrow = false
                withAnimation(.easeInOut(duration: 0.25)) { activeWorldIndex = 0 }

                try? await Task.sleep(nanoseconds: 700_000_000)
                withAnimation(.easeInOut(duration: 0.35)) { showPlayerArrow = true }
                try? await Task.sleep(nanoseconds: 650_000_000)
                withAnimation(.easeInOut(duration: 0.35)) { showWorldArrow = true }
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                withAnimation(.easeInOut(duration: 0.28)) {
                    showPlayerArrow = false
                    showWorldArrow = false
                }
                try? await Task.sleep(nanoseconds: 450_000_000)
                withAnimation(.easeInOut(duration: 0.3)) { activeWorldIndex = 1 }
                try? await Task.sleep(nanoseconds: 700_000_000)
                withAnimation(.easeInOut(duration: 0.35)) { showPlayerArrow = true }
                try? await Task.sleep(nanoseconds: 650_000_000)
                withAnimation(.easeInOut(duration: 0.35)) { showWorldArrow = true }
                try? await Task.sleep(nanoseconds: 1_900_000_000)
            }
        }
    }
}

// MARK: - Page 6: Settings Separation

private struct CGPage6_Settings: View {
    @State private var step = 0

    var body: some View {
        CGTwoColumnLayout(accentColor: .indigo) {
            VStack(spacing: 16) {
                CGSettingsZone(
                    title: "Server Settings",
                    icon: "server.rack",
                    color: .blue,
                    items: ["Port number", "Java / Bedrock version", "Playit.gg tunnel", "Online mode"]
                )
                .opacity(step >= 1 ? 1 : 0)
                .offset(y: step >= 1 ? 0 : -8)

                CGSettingsZone(
                    title: "World Settings",
                    icon: "map.fill",
                    color: .teal,
                    items: ["Game mode", "Difficulty", "World name", "Player data"]
                )
                .opacity(step >= 2 ? 1 : 0)
                .offset(y: step >= 2 ? 0 : 8)
            }
            .padding(.horizontal, 0)
        } textContent: {
            CGTextBlock(
                eyebrow: "Settings",
                headline: "Settings have two homes.",
                bodyText: "Server settings cover the port, version, and network. World settings cover game mode, difficulty, and player data. MSC keeps them in separate tabs.",
                note: "Changing server settings can require a restart. World settings often apply immediately."
            )
        }
        .task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            withAnimation(.easeOut(duration: 0.38)) { step = 1 }
            try? await Task.sleep(nanoseconds: 420_000_000)
            withAnimation(.easeOut(duration: 0.38)) { step = 2 }
        }
    }
}

// MARK: - Page 7: Ready

private struct CGPage7_Ready: View {
    let showsTourButton: Bool
    let onPrimary: () -> Void
    let onHandbook: () -> Void

    @State private var step = 0

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 24) {
                // Hierarchy summary
                HStack(spacing: 12) {
                    summaryNode(icon: "server.rack",       label: "Server",  color: .blue)
                    Image(systemName: "arrow.right").foregroundStyle(.white.opacity(0.3))
                    summaryNode(icon: "square.grid.2x2.fill", label: "Worlds",  color: .teal)
                    Image(systemName: "arrow.right").foregroundStyle(.white.opacity(0.3))
                    summaryNode(icon: "star.fill",         label: "Active",  color: .orange)
                }
                .opacity(step >= 1 ? 1 : 0)
                .scaleEffect(step >= 1 ? 1 : 0.9)

                VStack(spacing: 8) {
                    Text("You've got the model.")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Server → world slots → active world. That's everything MSC manages.")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.58))
                        .multilineTextAlignment(.center)
                }
                .opacity(step >= 1 ? 1 : 0)

                HStack(spacing: 12) {
                    Button(action: onPrimary) {
                        HStack(spacing: 8) {
                            Text(showsTourButton ? "Start the Tour" : "Done")
                                .font(.system(size: 14, weight: .semibold))
                            if showsTourButton {
                                Image(systemName: "arrow.right.circle.fill")
                            }
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.white))
                    }
                    .buttonStyle(.plain)

                    Button(action: onHandbook) {
                        Text("Open Server Handbook")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Color.white.opacity(0.10)))
                            .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .opacity(step >= 2 ? 1 : 0)
                .offset(y: step >= 2 ? 0 : 10)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 60)
            Spacer()
        }
        .task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            withAnimation(.spring(duration: 0.45)) { step = 1 }
            try? await Task.sleep(nanoseconds: 500_000_000)
            withAnimation(.easeOut(duration: 0.38)) { step = 2 }
        }
    }

    private func summaryNode(icon: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(color)
            }
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
        }
    }
}

// MARK: - Preview

#Preview {
    ConceptGuideView()
        .environmentObject(AppViewModel())
}

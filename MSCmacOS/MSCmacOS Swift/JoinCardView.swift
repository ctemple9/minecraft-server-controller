//
//  JoinCardView.swift
//  MinecraftServerController
//
//  Front: safe to share (server name, type, port, protocol — no IP).
//  Back:  eyes-only connection details (address, port, protocol, instructions).
//  Card color: per-server, persisted to ConfigServer.joinCardColorHex.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Preset colors

private struct CardColorPreset: Identifiable {
    let id = UUID()
    let color: Color
    let hex: String
}

private let cardColorPresets: [CardColorPreset] = [
    CardColorPreset(color: Color(red: 0.18, green: 0.40, blue: 0.20), hex: "#2E6633"),   // Forest green (default)
    CardColorPreset(color: Color(red: 0.13, green: 0.30, blue: 0.58), hex: "#214D94"),   // Deep blue
    CardColorPreset(color: Color(red: 0.42, green: 0.18, blue: 0.62), hex: "#6B2D9E"),   // Purple
    CardColorPreset(color: Color(red: 0.58, green: 0.14, blue: 0.16), hex: "#942428"),   // Deep red
    CardColorPreset(color: Color(red: 0.62, green: 0.36, blue: 0.10), hex: "#9E5C1A"),   // Amber
    CardColorPreset(color: Color(red: 0.16, green: 0.28, blue: 0.38), hex: "#294761"),   // Slate
]

private let defaultCardColor = cardColorPresets[0].color
private let defaultCardColorHex = cardColorPresets[0].hex

// MARK: - Sheet

struct JoinCardView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Binding var isPresented: Bool

    @State private var isFlipped: Bool = false
    @State private var rotation: Double = 0
    @State private var showExportHUD: Bool = false
    @State private var exportHUDText: String = ""
    @State private var cardColor: Color = defaultCardColor

    var body: some View {
        VStack(spacing: 0) {
            MSCSheetHeader("Share Join Card", subtitle: selectedServerName) {
                isPresented = false
            }
            .padding(.horizontal, MSC.Spacing.xxl)
            .padding(.top, MSC.Spacing.xxl)

            Divider()
                .padding(.horizontal, MSC.Spacing.xxl)

            ScrollView {
                VStack(spacing: MSC.Spacing.xl) {

                    // ── Flip card ──────────────────────────────────────
                    ZStack {
                        JoinCardFrontView(cardColor: cardColor)
                            .environmentObject(viewModel)
                            .opacity(isFlipped ? 0 : 1)
                            .rotation3DEffect(
                                .degrees(rotation),
                                axis: (x: 0, y: 1, z: 0)
                            )

                        JoinCardBackView()
                            .environmentObject(viewModel)
                            .opacity(isFlipped ? 1 : 0)
                            .rotation3DEffect(
                                .degrees(rotation - 180),
                                axis: (x: 0, y: 1, z: 0)
                            )
                    }
                    .frame(width: 360, height: 200)
                    .onTapGesture { flipCard() }

                    // ── Flip hint ──────────────────────────────────────
                    Text(isFlipped
                         ? "Back side \u{2014} connection details (not exported)"
                         : "Tap card to flip  \u{2022}  Front is what gets exported and shared")
                        .font(MSC.Typography.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    // ── Color picker ───────────────────────────────────
                    colorPickerRow

                    Divider()

                    // ── Action buttons ─────────────────────────────────
                    HStack(spacing: MSC.Spacing.md) {
                        Button {
                            flipCard()
                        } label: {
                            Label(isFlipped ? "Show Front" : "Show Back",
                                  systemImage: "arrow.left.arrow.right")
                        }
                        .buttonStyle(MSCSecondaryButtonStyle())

                        Spacer()

                        Button {
                            exportCardAsPNG()
                        } label: {
                            Label("Export as PNG", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(MSCSecondaryButtonStyle())

                        Button {
                            shareCard()
                        } label: {
                            Label("Share\u{2026}", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(MSCPrimaryButtonStyle())
                    }

                }
                .padding(MSC.Spacing.xxl)
            }
        }
        .frame(minWidth: 500, minHeight: 520)
        .overlay(alignment: .top) {
            if showExportHUD {
                MSCSaveHUD(text: exportHUDText)
                    .padding(.top, MSC.Spacing.xxl)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showExportHUD)
        .onAppear { loadSavedColor() }
    }

    // MARK: - Color picker row

    private var colorPickerRow: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
            Text("Card Color")
                .font(MSC.Typography.cardTitle)
                .foregroundStyle(.secondary)

            HStack(spacing: MSC.Spacing.sm) {
                ForEach(cardColorPresets) { preset in
                    colorSwatch(preset.color, isSelected: colorsMatch(cardColor, preset.color)) {
                        applyColor(preset.color, hex: preset.hex)
                    }
                }

                Rectangle()
                    .fill(MSC.Colors.cardBorder)
                    .frame(width: 1, height: 28)
                    .padding(.horizontal, MSC.Spacing.xs)

                ColorPicker("", selection: $cardColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(MSC.Colors.cardBorder, lineWidth: 1.5))
                    .onChange(of: cardColor) { _, newColor in
                        saveColor(newColor)
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func colorSwatch(_ color: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 28, height: 28)

                if isSelected {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 2)
                        .frame(width: 28, height: 28)
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .overlay(
            Circle()
                .stroke(isSelected ? color : MSC.Colors.cardBorder, lineWidth: isSelected ? 3 : 1)
                .frame(width: 32, height: 32)
        )
    }

    // MARK: - Color persistence

    private func loadSavedColor() {
        guard let server = viewModel.selectedServer,
              let cfg = viewModel.configServer(for: server),
              let hex = cfg.joinCardColorHex,
              let color = Color(hexRGB: hex) else {
            cardColor = defaultCardColor
            return
        }
        cardColor = color
    }

    private func applyColor(_ color: Color, hex: String) {
        cardColor = color
        persistColorHex(hex)
    }

    private func saveColor(_ color: Color) {
        guard let hex = color.hexRGBString() else { return }
        persistColorHex(hex)
    }

    private func persistColorHex(_ hex: String) {
        guard let server = viewModel.selectedServer,
              let idx = viewModel.configManager.config.servers.firstIndex(where: { $0.id == server.id }) else { return }
        viewModel.configManager.config.servers[idx].joinCardColorHex = hex
        viewModel.configManager.save()
    }

    private func colorsMatch(_ a: Color, _ b: Color) -> Bool {
        guard let hexA = a.hexRGBString(), let hexB = b.hexRGBString() else { return false }
        return hexA.lowercased() == hexB.lowercased()
    }

    // MARK: - Helpers

    private var selectedServerName: String {
        viewModel.selectedServer?.name ?? "No server selected"
    }

    private func flipCard() {
        withAnimation(.easeInOut(duration: 0.45)) {
            rotation += 180
            isFlipped.toggle()
        }
    }

    // MARK: - Image rendering (front only — back is never exported)

    private func renderFrontImage() -> NSImage? {
        let view = JoinCardFrontView(cardColor: cardColor)
            .environmentObject(viewModel)
            .frame(width: 360, height: 200)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        return renderer.nsImage
    }

    private func exportCardAsPNG() {
        guard let image = renderFrontImage() else {
            showHUD("Export failed")
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(selectedServerName) - Join Card.png"
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            guard let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else {
                self.showHUD("Export failed")
                return
            }
            do {
                try pngData.write(to: url)
                self.showHUD("Saved to \(url.lastPathComponent)")
            } catch {
                self.showHUD("Export failed")
            }
        }
    }

    private func shareCard() {
        guard let image = renderFrontImage() else {
            showHUD("Share failed")
            return
        }

        let picker = NSSharingServicePicker(items: [image])

        if let window = NSApp.keyWindow,
           let contentView = window.contentView {
            let bounds = contentView.bounds
            let anchor = NSRect(x: bounds.midX - 1, y: bounds.midY - 1, width: 2, height: 2)
            picker.show(relativeTo: anchor, of: contentView, preferredEdge: .minY)
        } else {
            showHUD("Share sheet unavailable")
        }
    }

    private func showHUD(_ text: String) {
        exportHUDText = text
        withAnimation { showExportHUD = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { self.showExportHUD = false }
        }
    }
}

// MARK: - Card Front (safe to share — no IP address)

struct JoinCardFrontView: View {
    @EnvironmentObject var viewModel: AppViewModel
    let cardColor: Color

    private var serverName: String {
        viewModel.selectedServer?.name ?? "My Server"
    }

    private var serverType: ServerType {
        guard let server = viewModel.selectedServer,
              let cfg = viewModel.configServer(for: server) else { return .java }
        return cfg.serverType
    }

    private var typeBadgeColor: Color {
        serverType == .bedrock ? MSC.Colors.success : .blue
    }

    private var typeBadgeLabel: String {
        serverType == .bedrock ? "Bedrock" : "Java"
    }

    private var portDisplay: String {
        if serverType == .bedrock {
            if let p = viewModel.bedrockPortForDisplay { return String(p) }
            if let server = viewModel.selectedServer,
               let cfg = viewModel.configServer(for: server),
               let p = cfg.bedrockPort { return String(p) }
            return "19132"
        } else {
            return viewModel.javaPortForDisplay
        }
    }

    private var protocolLabel: String {
        serverType == .bedrock ? "UDP" : "TCP"
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [cardColor, cardColor.opacity(0.75)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Subtle grid texture
            Canvas { ctx, size in
                let spacing: CGFloat = 24
                var x: CGFloat = 0
                while x < size.width {
                    var y: CGFloat = 0
                    while y < size.height {
                        let rect = CGRect(x: x, y: y, width: spacing - 1, height: spacing - 1)
                        ctx.fill(Path(rect), with: .color(.white.opacity(0.03)))
                        y += spacing
                    }
                    x += spacing
                }
            }

            VStack(alignment: .leading, spacing: 0) {

                // ── Top row ───────────────────────────────────────
                HStack(alignment: .center) {
                    Image(systemName: "cube.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))

                    Spacer()

                    Text(typeBadgeLabel.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(typeBadgeColor)
                        .padding(.horizontal, MSC.Spacing.sm)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(typeBadgeColor.opacity(0.18)))
                        .overlay(Capsule().stroke(typeBadgeColor.opacity(0.45), lineWidth: 0.75))
                }

                Spacer()

                // ── Server name ───────────────────────────────────
                Text(serverName)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                Text("You\u{2019}re invited to join")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.60))
                    .padding(.top, 2)

                Spacer()

                // ── Port + protocol + branding ────────────────────
                HStack(spacing: MSC.Spacing.md) {
                    HStack(spacing: 4) {
                        Image(systemName: "network")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                        Text("Port \(portDisplay)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(.horizontal, MSC.Spacing.sm)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.20), lineWidth: 0.75))

                    HStack(spacing: 4) {
                        Circle()
                            .fill(typeBadgeColor)
                            .frame(width: 5, height: 5)
                        Text(protocolLabel)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(.horizontal, MSC.Spacing.sm)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.20), lineWidth: 0.75))

                    Spacer()

                    Text("Hosted with MSC")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.30))
                }
            }
            .padding(MSC.Spacing.xl)
        }
        .clipShape(RoundedRectangle(cornerRadius: MSC.Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MSC.Radius.xl, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
    }
}

// MARK: - Card Back (eyes-only — never exported)

struct JoinCardBackView: View {
    @EnvironmentObject var viewModel: AppViewModel

    private var hostAddress: String {
        let duck = viewModel.duckdnsInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !duck.isEmpty { return duck }
        if let pub = viewModel.cachedPublicIPAddress { return pub }
        return viewModel.javaAddressForDisplay
    }

    private var serverType: ServerType {
        guard let server = viewModel.selectedServer,
              let cfg = viewModel.configServer(for: server) else { return .java }
        return cfg.serverType
    }

    private var portDisplay: String {
        if serverType == .bedrock {
            if let p = viewModel.bedrockPortForDisplay { return String(p) }
            if let server = viewModel.selectedServer,
               let cfg = viewModel.configServer(for: server),
               let p = cfg.bedrockPort { return String(p) }
            return "19132"
        } else {
            return viewModel.javaPortForDisplay
        }
    }

    private var protocolLabel: String { serverType == .bedrock ? "UDP" : "TCP" }
    private var protocolColor: Color { serverType == .bedrock ? MSC.Colors.success : .blue }

    private var instructionText: String {
        serverType == .bedrock
            ? "Minecraft \u{2192} Play \u{2192} Friends \u{2192} Add Server"
            : "Multiplayer \u{2192} Add Server \u{2192} Paste address"
    }

    private var serverName: String { viewModel.selectedServer?.name ?? "My Server" }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.12, blue: 0.18),
                    Color(red: 0.07, green: 0.09, blue: 0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 0) {

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CONNECTION DETAILS")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.5)
                            .foregroundStyle(.white.opacity(0.35))
                        Text(serverName)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.90))
                            .lineLimit(1)
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.40))
                        Text("Not exported")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.40))
                    }
                    .padding(.horizontal, MSC.Spacing.sm)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.07)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.75))
                }

                Divider()
                    .background(Color.white.opacity(0.12))
                    .padding(.vertical, MSC.Spacing.sm)

                HStack(spacing: MSC.Spacing.md) {
                    connectionField(label: "ADDRESS", value: hostAddress)
                    connectionField(label: "PORT", value: portDisplay)
                    connectionField(label: "PROTOCOL", value: protocolLabel)
                }

                Spacer()

                HStack(spacing: MSC.Spacing.xs) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.35))
                    Text(instructionText)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(MSC.Spacing.xl)
        }
        .clipShape(RoundedRectangle(cornerRadius: MSC.Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MSC.Radius.xl, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
    }

    @ViewBuilder
    private func connectionField(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(.white.opacity(0.35))
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.90))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, MSC.Spacing.sm)
        .padding(.vertical, MSC.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.75)
        )
    }
}


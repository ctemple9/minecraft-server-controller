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

                        JoinCardBackView(cardColor: cardColor)
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
                         ? "Back \u{2014} Java direct connect (IP + port)"
                         : "Front \u{2014} Bedrock friends method (no IP)")
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

    // MARK: - Image rendering (both sides exported)

    private func renderFrontImage() -> NSImage? {
        let view = JoinCardFrontView(cardColor: cardColor)
            .environmentObject(viewModel)
            .frame(width: 360, height: 200)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        return renderer.nsImage
    }

    private func renderBackImage() -> NSImage? {
        let view = JoinCardBackView(cardColor: cardColor)
            .environmentObject(viewModel)
            .frame(width: 360, height: 200)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        return renderer.nsImage
    }

    private func exportCardAsPNG() {
        guard let front = renderFrontImage(), let back = renderBackImage() else {
            showHUD("Export failed")
            return
        }

        // Combine front + back vertically into one PNG
        let combined = combinedImage(top: front, bottom: back)

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(selectedServerName) - Join Card.png"
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            guard let tiff = combined.tiffRepresentation,
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
        guard let front = renderFrontImage(), let back = renderBackImage() else {
            showHUD("Share failed")
            return
        }

        let picker = NSSharingServicePicker(items: [front, back])

        if let window = NSApp.keyWindow,
           let contentView = window.contentView {
            let bounds = contentView.bounds
            let anchor = NSRect(x: bounds.midX - 1, y: bounds.midY - 1, width: 2, height: 2)
            picker.show(relativeTo: anchor, of: contentView, preferredEdge: .minY)
        } else {
            showHUD("Share sheet unavailable")
        }
    }

    /// Stacks two NSImages vertically with a small gap into a single NSImage.
    private func combinedImage(top: NSImage, bottom: NSImage, gap: CGFloat = 16) -> NSImage {
        let w = max(top.size.width, bottom.size.width)
        let h = top.size.height + gap + bottom.size.height
        let result = NSImage(size: NSSize(width: w, height: h))
        result.lockFocus()
        top.draw(in: NSRect(x: 0, y: bottom.size.height + gap, width: top.size.width, height: top.size.height))
        bottom.draw(in: NSRect(x: 0, y: 0, width: bottom.size.width, height: bottom.size.height))
        result.unlockFocus()
        return result
    }

    private func showHUD(_ text: String) {
        exportHUDText = text
        withAnimation { showExportHUD = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { self.showExportHUD = false }
        }
    }
}

// MARK: - Card Front (Friends / Xbox join — safe to share, no IP)

struct JoinCardFrontView: View {
    @EnvironmentObject var viewModel: AppViewModel
    let cardColor: Color

    private var serverName: String { viewModel.selectedServer?.name ?? "My Server" }

    private var serverType: ServerType {
        guard let server = viewModel.selectedServer,
              let cfg = viewModel.configServer(for: server) else { return .java }
        return cfg.serverType
    }

    private var isBedrock: Bool { serverType == .bedrock }

    private var xboxGamertag: String? {
        guard let server = viewModel.selectedServer else { return nil }
        let tag = viewModel.configServer(for: server)?.xboxBroadcastAltGamertag ?? ""
        return tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : tag.trimmingCharacters(in: .whitespacesAndNewlines)
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

                // ── Top row: icon + branding ─────────────────────
                HStack {
                    Image(systemName: "cube.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    Text("Hosted with MSC")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.30))
                }

                Spacer()

                // ── Server name + subtitle ────────────────────────
                Text(serverName)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(isBedrock ? "Bedrock Server" : "Java Server")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.top, 2)

                Divider()
                    .background(Color.white.opacity(0.20))
                    .padding(.vertical, 8)

                // ── Gamertag box ──────────────────────────────────
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(xboxGamertag.map { "Add \u{201C}\($0)\u{201D} as a friend" } ?? "Set gamertag in server settings")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white.opacity(0.95))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text("The server will appear in your Worlds tab")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                }
                .padding(.horizontal, MSC.Spacing.sm)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.75)
                )

                Spacer()

                // ── Bottom instruction ────────────────────────────
                HStack(spacing: 4) {
                    Image(systemName: "gamecontroller")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.50))
                    Text("Console: Friends tab \u{2192} Add Friend \u{2192} server appears in Worlds")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.60))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
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

// MARK: - Card Back (Java direct connect — public IP + port)

struct JoinCardBackView: View {
    @EnvironmentObject var viewModel: AppViewModel
    let cardColor: Color

    private var hostAddress: String {
        let duck = viewModel.duckdnsInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !duck.isEmpty { return duck }
        if let pub = viewModel.cachedPublicIPAddress { return pub }
        return viewModel.javaAddressForDisplay
    }

    private var portDisplay: String { viewModel.javaPortForDisplay }
    private var serverName: String { viewModel.selectedServer?.name ?? "My Server" }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [cardColor, cardColor.opacity(0.75)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Subtle grid texture (matches front)
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

                // ── Top row: app icon + branding ──────────────────
                HStack {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 32, height: 32)
                    Spacer()
                    Text("Hosted with MSC")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.30))
                }

                Spacer()

                // ── Server name + subtitle ────────────────────────
                Text(serverName)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("DIRECT CONNECT")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.top, 2)

                Divider()
                    .background(Color.white.opacity(0.20))
                    .padding(.vertical, 8)

                // ── Combined address:port field ───────────────────
                HStack(spacing: 8) {
                    Image(systemName: "network")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(hostAddress):\(portDisplay)")
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.95))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                        Text("Enter in the Add Server screen")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                }
                .padding(.horizontal, MSC.Spacing.sm)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.75)
                )

                Spacer()

                // ── Bottom instruction ────────────────────────────
                HStack(spacing: MSC.Spacing.xs) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.50))
                    Text("Multiplayer \u{2192} Add Server \u{2192} Paste address")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.60))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
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


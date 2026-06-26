//
//  PlayerProfileCardView.swift
//  MinecraftServerController
//
//  Individual player card for the Player Profiles grid.
//  Fetches the player's head from mc-heads.net using their UUID (no username needed).
//

import SwiftUI
import AppKit

// MARK: - Player Head Image (async, identifier-based)

struct PlayerHeadView: View {
    /// UUID string without dashes, lowercase. For Java: Mojang UUID. For Bedrock: Floodgate UUID.
    let identifier: String
    let size: CGFloat
    var customSkinURL: URL? = nil

    @State private var image: NSImage? = nil

    var body: some View {
        Group {
            if let img = image {
                // Fill (not fit) so non-square / padded avatars still render at a
                // uniform size — fit can letterbox an odd image and make it look smaller.
                Image(nsImage: img)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.15, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: size * 0.15, style: .continuous)
                    .fill(MSC.Colors.subtleBackground)
                    .frame(width: size, height: size)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: size * 0.45))
                            .foregroundStyle(MSC.Colors.tertiary)
                    }
            }
        }
        .task(id: identifier + (customSkinURL?.path ?? "")) { await loadHead() }
    }

    private func loadHead() async {
        image = nil

        // Custom skin file — extract face locally, no network needed.
        if let skinURL = customSkinURL, let skinImg = NSImage(contentsOf: skinURL) {
            let face = PlayerSkinRenderer.extractFace(from: skinImg) ?? skinImg
            let trimmed = PlayerImageTrim.croppedToOpaqueBounds(face) ?? face
            await MainActor.run { image = trimmed }
            return
        }

        let px = Int(size * 2)   // 2× for retina

        // Bedrock gamertag (dot prefix): resolve via GeyserMC → Floodgate UUID,
        // matching the same chain PlayerAvatarView uses for the sidebar avatar.
        if identifier.hasPrefix(".") {
            if let img = await BedrockSkinFetcher.fetchAvatar(gamertag: identifier, size: px) {
                await MainActor.run { image = PlayerImageTrim.croppedToOpaqueBounds(img) ?? img }
            }
            return
        }

        // Standard Java UUID / username — hit mc-heads.net directly.
        guard let url = URL(string: "https://mc-heads.net/avatar/\(identifier)/\(px)") else { return }
        var req = URLRequest(url: url)
        req.setValue("MinecraftServerController/1.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let img = NSImage(data: data) else { return }
        let finalImage = PlayerImageTrim.croppedToOpaqueBounds(img) ?? img
        await MainActor.run { image = finalImage }
    }
}

// MARK: - Transparent-margin trimming

enum PlayerImageTrim {
    /// Crops fully/near-transparent margins off an avatar so its visible content
    /// fills the frame. Returns nil (caller falls back to the original) when the
    /// image has no usable alpha or is already tight.
    static func croppedToOpaqueBounds(_ image: NSImage) -> NSImage? {
        let sz = image.size
        let w = Int(sz.width); let h = Int(sz.height)
        guard w > 0, h > 0 else { return nil }

        // Render into a fresh RGBA bitmap instead of going through tiffRepresentation,
        // which can silently drop the alpha channel on some NSImage sources and cause
        // the guard below to bail out on every Bedrock/Floodgate avatar.
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: w, pixelsHigh: h,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 32
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()

        // Alpha is always byte 3 (RGBA) in the bitmap we just created.
        guard let cg = bitmap.cgImage,
              let pixelData = cg.dataProvider?.data,
              let ptr = CFDataGetBytePtr(pixelData) else { return nil }

        let stride = bitmap.bytesPerRow
        let threshold: UInt8 = 12
        var minX = w, minY = h, maxX = -1, maxY = -1

        for y in 0..<h {
            let row = y * stride
            for x in 0..<w {
                if ptr[row + x * 4 + 3] > threshold {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }

        guard maxX >= minX, maxY >= minY else { return nil }
        let cropW = maxX - minX + 1
        let cropH = maxY - minY + 1
        // Already effectively tight — keep the original.
        if cropW >= w - 2, cropH >= h - 2 { return nil }

        let rect = CGRect(x: minX, y: minY, width: cropW, height: cropH)
        guard let cropped = cg.cropping(to: rect) else { return nil }
        return NSImage(cgImage: cropped, size: NSSize(width: cropW, height: cropH))
    }
}

// MARK: - Player Full Body Image (async, identifier-based)

struct PlayerBodyView: View {
    /// UUID string without dashes, lowercase. For Java: Mojang UUID. For Bedrock: Floodgate UUID.
    let identifier: String
    let height: CGFloat
    var customSkinURL: URL? = nil

    @State private var image: NSImage? = nil
    @State private var swayAngle: Double = -7

    var body: some View {
        Group {
            if let img = image {
                Image(nsImage: img)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: height)
                    .rotationEffect(.degrees(swayAngle))
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                            swayAngle = 7
                        }
                    }
            } else {
                VStack(spacing: MSC.Spacing.sm) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Loading skin…")
                        .font(.caption2)
                        .foregroundStyle(MSC.Colors.tertiary)
                }
                .frame(height: height)
            }
        }
        .task(id: identifier + (customSkinURL?.path ?? "")) { await loadBody() }
    }

    private func loadBody() async {
        image = nil

        // Custom skin file — render 2D front view locally, no network needed.
        if let skinURL = customSkinURL, let skinImg = NSImage(contentsOf: skinURL) {
            let body = PlayerSkinRenderer.renderFrontView(skin: skinImg) ?? skinImg
            await MainActor.run { image = body }
            return
        }

        // Bedrock gamertag (dot prefix): use GeyserMC resolution chain, same as PlayerAvatarView.
        if identifier.hasPrefix(".") {
            if let img = await BedrockSkinFetcher.fetchBody(gamertag: identifier) {
                await MainActor.run { image = img }
            }
            return
        }

        guard let url = URL(string: "https://mc-heads.net/body/\(identifier)/160") else { return }
        var req = URLRequest(url: url)
        req.setValue("MinecraftServerController/1.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let img = NSImage(data: data) else { return }
        await MainActor.run { image = img }
    }
}

// MARK: - Player Profile Card (grid cell)

struct PlayerProfileCardView: View {
    let profile: PlayerProfile
    @Binding var selectedProfile: PlayerProfile?
    @EnvironmentObject var viewModel: AppViewModel

    private var borderColor: Color {
        profile.isOnline
            ? MSC.Colors.success.opacity(0.5)
            : MSC.Colors.contentBorder
    }

    private var appearance: (identifier: String, skinURL: URL?) {
        guard let cfg = viewModel.selectedServer.flatMap({ viewModel.configServer(for: $0) }) else {
            return (profile.imageIdentifier, nil)
        }
        return PlayerSkinStore.resolveAppearance(for: profile, serverDir: cfg.serverDir)
    }

    var body: some View {
        Button { selectedProfile = profile } label: {
            VStack(spacing: MSC.Spacing.sm) {

                // Head + online indicator
                ZStack(alignment: .topTrailing) {
                    PlayerHeadView(identifier: appearance.identifier, size: 48, customSkinURL: appearance.skinURL)

                    if profile.isOnline {
                        Circle()
                            .fill(MSC.Colors.success)
                            .frame(width: 11, height: 11)
                            .overlay(Circle().stroke(MSC.Colors.tierContent, lineWidth: 2))
                            .offset(x: 3, y: -3)
                    }
                }

                // Name + op badge + last seen
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Text(profile.displayName)
                            .font(MSC.Typography.captionBold)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if profile.isOp {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(Color.yellow.opacity(0.85))
                        }
                    }

                    Text(profile.lastModified, style: .relative)
                        .font(.system(size: 9))
                        .foregroundStyle(MSC.Colors.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, MSC.Spacing.sm)
            .padding(.horizontal, MSC.Spacing.xs)
            .frame(minWidth: 80, maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                    .fill(MSC.Colors.tierContent)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(profile.xuid.map { "XUID: \($0)" } ?? profile.uuid.uuidString)
    }
}

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
        .task(id: identifier) { await loadHead() }
    }

    private func loadHead() async {
        image = nil
        let px = Int(size * 2)   // 2× for retina
        guard let url = URL(string: "https://mc-heads.net/avatar/\(identifier)/\(px)") else { return }
        var req = URLRequest(url: url)
        req.setValue("MinecraftServerController/1.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let img = NSImage(data: data) else { return }
        // Some avatars (notably Bedrock/Floodgate skins) come back with a
        // transparent border, which makes the face look small once it fills the
        // tile. Trim the transparent margin so every head renders edge-to-edge.
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
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let cg = bitmap.cgImage else { return nil }

        let alpha = cg.alphaInfo
        let alphaLast  = (alpha == .last || alpha == .premultipliedLast)
        let alphaFirst = (alpha == .first || alpha == .premultipliedFirst)
        guard alphaLast || alphaFirst else { return nil }  // no alpha → already opaque

        let w = cg.width, h = cg.height
        guard w > 0, h > 0,
              let pixelData = cg.dataProvider?.data,
              let ptr = CFDataGetBytePtr(pixelData) else { return nil }

        let bpp = cg.bitsPerPixel / 8
        let stride = cg.bytesPerRow
        let threshold: UInt8 = 12

        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            let row = y * stride
            for x in 0..<w {
                let idx = row + x * bpp
                let a = alphaFirst ? ptr[idx] : ptr[idx + bpp - 1]
                if a > threshold {
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
        .task(id: identifier) { await loadBody() }
    }

    private func loadBody() async {
        image = nil
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

    private var borderColor: Color {
        profile.isOnline
            ? MSC.Colors.success.opacity(0.5)
            : MSC.Colors.contentBorder
    }

    var body: some View {
        Button { selectedProfile = profile } label: {
            VStack(spacing: MSC.Spacing.sm) {

                // Head + online indicator
                ZStack(alignment: .topTrailing) {
                    PlayerHeadView(identifier: profile.imageIdentifier, size: 48)

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

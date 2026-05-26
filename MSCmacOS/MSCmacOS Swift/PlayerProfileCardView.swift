//
//  PlayerProfileCardView.swift
//  MinecraftServerController
//
//  Individual player card for the Player Profiles grid.
//  Fetches the player's head from mc-heads.net using their UUID (no username needed).
//

import SwiftUI
import AppKit

// MARK: - Player Head Image (async, UUID-based)

struct PlayerHeadView: View {
    let uuid: UUID
    let size: CGFloat

    @State private var image: NSImage? = nil

    var body: some View {
        Group {
            if let img = image {
                Image(nsImage: img)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
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
        .onAppear { loadHead() }
        .onChange(of: uuid) { _ in loadHead() }
    }

    private func loadHead() {
        image = nil
        Task {
            let uuidNoDashes = uuid.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            let px = Int(size * 2)   // 2× for retina
            guard let url = URL(string: "https://mc-heads.net/avatar/\(uuidNoDashes)/\(px)") else { return }
            var req = URLRequest(url: url)
            req.setValue("MinecraftServerController/1.0", forHTTPHeaderField: "User-Agent")
            req.timeoutInterval = 10
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let img = NSImage(data: data) else { return }
            await MainActor.run { image = img }
        }
    }
}

// MARK: - Player Full Body Image (async, UUID-based)

struct PlayerBodyView: View {
    let uuid: UUID
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
        .onAppear { loadBody() }
        .onChange(of: uuid) { _ in loadBody() }
    }

    private func loadBody() {
        image = nil
        Task {
            let uuidNoDashes = uuid.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            guard let url = URL(string: "https://mc-heads.net/body/\(uuidNoDashes)/160") else { return }
            var req = URLRequest(url: url)
            req.setValue("MinecraftServerController/1.0", forHTTPHeaderField: "User-Agent")
            req.timeoutInterval = 15
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let img = NSImage(data: data) else { return }
            await MainActor.run { image = img }
        }
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
                    PlayerHeadView(uuid: profile.uuid, size: 48)

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
        .help(profile.uuid.uuidString)
    }
}

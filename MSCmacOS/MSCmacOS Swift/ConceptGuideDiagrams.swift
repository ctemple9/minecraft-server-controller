//
//  ConceptGuideDiagrams.swift
//  MinecraftServerController
//
//  Reusable diagram primitives for the Concept Guide mental-model walkthrough.
//

import SwiftUI

// MARK: - Server Node

struct CGServerNodeView: View {
    var size: CGFloat = 56
    var color: Color = .blue
    var label: String = "Server"
    var showLabel: Bool = true

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.18))
                    .frame(width: size, height: size)
                Circle()
                    .strokeBorder(color.opacity(0.45), lineWidth: 1.5)
                    .frame(width: size, height: size)
                Image(systemName: "server.rack")
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(color)
            }
            if showLabel {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
    }
}

// MARK: - World Slot Card

struct CGWorldSlotCard: View {
    var name: String
    var isActive: Bool = false
    var color: Color = .teal
    var width: CGFloat = 160

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "map.fill")
                .font(.system(size: 11))
                .foregroundStyle(isActive ? color : .white.opacity(0.35))
            Text(name)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? .white : .white.opacity(0.45))
                .lineLimit(1)
            Spacer(minLength: 0)
            if isActive {
                Text("ACTIVE")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(color.opacity(0.2)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(width: width)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isActive ? Color.white.opacity(0.10) : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isActive ? color.opacity(0.55) : Color.white.opacity(0.1),
                        lineWidth: isActive ? 1.5 : 0.5)
        )
    }
}

// MARK: - Player Figure

struct CGPlayerFigure: View {
    var label: String
    var color: Color = .white
    var size: CGFloat = 30

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: size, height: size)
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.46))
                    .foregroundStyle(color.opacity(0.9))
            }
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .frame(width: 62)
                .lineLimit(2)
        }
    }
}

// MARK: - Tag Pill

struct CGTagPill: View {
    var icon: String
    var label: String
    var color: Color = .blue

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(color.opacity(0.32), lineWidth: 1)
        )
    }
}

// MARK: - Server Type Panel (Java / Bedrock side-by-side)

struct CGServerTypePanel: View {
    var body: some View {
        HStack(spacing: 0) {
            // Java side
            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 68, height: 68)
                    Image(systemName: "server.rack")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.orange)
                }
                Text("Java")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.orange)

                VStack(spacing: 5) {
                    playerCompatRow(icon: "j.circle.fill", label: "Java players", color: .orange)
                    playerCompatRow(icon: "cube.fill", label: "Bedrock players", color: .orange)
                    Text("with Geyser plugin")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.4))
                        .italic()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.orange.opacity(0.07))

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)

            // Bedrock side
            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 68, height: 68)
                    Image(systemName: "cube.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.green)
                }
                Text("Bedrock")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.green)

                VStack(spacing: 5) {
                    playerCompatRow(icon: "cube.fill", label: "Bedrock players", color: .green)
                    HStack(spacing: 5) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.25))
                        Text("Java players")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.25))
                    }
                    Text("Bedrock only")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.4))
                        .italic()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.green.opacity(0.07))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func playerCompatRow(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(color.opacity(0.8))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

// MARK: - Settings Zone (server-level or world-level column)

struct CGSettingsZone: View {
    var title: String
    var icon: String
    var color: Color
    var items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 7) {
                ForEach(items, id: \.self) { item in
                    HStack(spacing: 7) {
                        Circle()
                            .fill(color.opacity(0.5))
                            .frame(width: 4, height: 4)
                        Text(item)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(color.opacity(0.25), lineWidth: 1)
        )
    }
}

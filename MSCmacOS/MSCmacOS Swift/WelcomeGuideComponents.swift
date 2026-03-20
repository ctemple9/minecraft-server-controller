//
//  WelcomeGuideComponents.swift
//  MinecraftServerController
//

import SwiftUI

// MARK: - Reusable Guide Components

/// A callout card for tips, warnings, or pitfalls.
struct GuideCallout: View {
    enum Style { case tip, warning, pitfall, note }

    let style: Style
    let text: String

    private var icon: String {
        switch style {
        case .tip:     return "lightbulb.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .pitfall: return "xmark.octagon.fill"
        case .note:    return "info.circle.fill"
        }
    }

    private var color: Color {
        switch style {
        case .tip:     return .blue
        case .warning: return .orange
        case .pitfall: return .red
        case .note:    return .secondary
        }
    }

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
        }
        .padding(MSC.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
}

/// A top-level section header with icon.
struct GuideTopicHeader: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(spacing: MSC.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Analogy box — visual "think of it like this" block.
struct AnalogyBox: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "quote.bubble.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.purple)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.purple)
                    .tracking(0.2)
            }
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(MSC.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .fill(Color.purple.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .stroke(Color.purple.opacity(0.18), lineWidth: 1)
        )
    }
}

/// "In this app" section block.
struct InAppBox: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "macwindow")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.blue)
                Text("In this app")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.blue)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.blue.opacity(0.7))
                            .padding(.top, 2)
                        Text(item)
                            .font(.system(size: 12))
                            .foregroundStyle(.primary.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(MSC.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .fill(Color.blue.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .stroke(Color.blue.opacity(0.18), lineWidth: 1)
        )
    }
}

/// Expandable "Advanced Details" section.
struct AdvancedSection: View {
    let content: String
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(
            isExpanded: $isExpanded,
            content: {
                Text(content)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            },
            label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .rotationEffect(isExpanded ? .degrees(90) : .zero)
                        .animation(.easeInOut(duration: 0.2), value: isExpanded)
                    Text("Advanced details")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        )
        .padding(MSC.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .fill(Color.secondary.opacity(0.05))
        )
    }
}

/// A checklist step row.
struct ChecklistStep: View {
    let number: Int
    let title: String
    let detail: String

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

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Divider with label.
struct LabeledDivider: View {
    let label: String
    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1)
        }
    }
}

// MARK: - Layout Helpers

/// Wraps topic content in consistent vertical spacing.
struct GuideSection<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
            content
        }
    }
}

/// Standard body text with markdown support.
struct GuideBodyText: View {
    let text: LocalizedStringKey

    init(_ text: String) {
        self.text = LocalizedStringKey(text)
    }

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.primary.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Consistent bullet list.
struct BulletList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("\u{2022}")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text(item)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// RAM recommendation table.
struct RamGuideTable: View {
    let rows: [(String, String, String)] = [
        ("1\u{2013}2 players",  "2 GB",  "4 GB"),
        ("3\u{2013}5 players",  "2 GB",  "6 GB"),
        ("6\u{2013}10 players", "4 GB",  "8 GB"),
        ("Plugins/mods", "+1 GB", "+2 GB"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Players").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                Text("Min RAM").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).frame(width: 70, alignment: .center)
                Text("Max RAM").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).frame(width: 70, alignment: .center)
            }
            .padding(.horizontal, MSC.Spacing.md)
            .padding(.vertical, MSC.Spacing.sm)
            .background(Color.secondary.opacity(0.08))

            ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                HStack {
                    Text(row.0).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.1).font(.system(size: 12, design: .monospaced)).frame(width: 70, alignment: .center)
                    Text(row.2).font(.system(size: 12, design: .monospaced)).frame(width: 70, alignment: .center)
                }
                .padding(.horizontal, MSC.Spacing.md)
                .padding(.vertical, 7)
                .background(idx.isMultiple(of: 2) ? Color.clear : Color.secondary.opacity(0.03))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
}


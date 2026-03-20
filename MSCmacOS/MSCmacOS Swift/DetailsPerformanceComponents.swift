//
//  DetailsPerformanceComponents.swift
//  MinecraftServerController
//
//  Extracted from DetailsView.swift (Performance tab UI components).
//

import SwiftUI

// MARK: - Performance Tab Components

extension DetailsPerformanceTabView {

    // MARK: - TPS helpers

    func tpsColor(for t: Double) -> Color {
        switch t {
        case 19.5...:
            return .green
        case 18.0..<19.5:
            return .yellow
        default:
            return .red
        }
    }

    // Simple formatter for the At-a-glance tile
    func formatTPS(_ value: Double?) -> String {
        guard let v = value else { return "--" }
        return String(format: "%.2f", v)
    }
    func formatPercent(_ value: Double?) -> String {
        guard let v = value else { return "--" }
        return String(format: "%.0f%%", v)
    }

    func formatRam(_ mb: Double?, maxGB: Int?) -> String {
        guard let mb = mb else { return "--" }

        if let maxGB = maxGB {
            let maxMB = Double(maxGB) * 1024.0
            return String(format: "%.1f / %.0f MB", mb, maxMB)
        } else {
            return String(format: "%.1f MB", mb)
        }
    }

    @ViewBuilder
    func metricTile(
        title: String,
        value: String,
        subtitle: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
            Text(title)
                .font(MSC.Typography.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))

            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(MSC.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.sm)
                .fill(MSC.Colors.tierContent)
        )
    }

    // MARK: - Performance Tab: Enhanced Components

    @ViewBuilder
    func enhancedMetricTile(
        title: String,
        value: String,
        status: MetricStatus,
        subtitle: String,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: status.icon)
                    .font(.caption2)
                    .foregroundStyle(status.color)
            }

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(status == .neutral ? .primary : status.color)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(MSC.Colors.tierContent)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(status.color.opacity(0.3), lineWidth: status == .neutral ? 0 : 1)
        )
    }

    @ViewBuilder
    func compactInfoTile(
        icon: String,
        label: String,
        value: String,
        subtitle: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.body, design: .rounded))
                    .bold()
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(MSC.Colors.tierContent)
        )
    }

    @ViewBuilder
    func emptyChartPlaceholder(message: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(height: 120)
        .frame(maxWidth: .infinity)
    }

}

//
//  DetailsPerformanceHelpers.swift
//  MinecraftServerController
//

import SwiftUI

enum MetricStatus {
    case good, warning, critical, neutral

    var color: Color {
        switch self {
        case .good: return .green
        case .warning: return .yellow
        case .critical: return .red
        case .neutral: return .secondary
        }
    }

    var icon: String {
        switch self {
        case .good: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.circle.fill"
        case .neutral: return "circle.fill"
        }
    }
}

extension DetailsPerformanceTabView {

    @ViewBuilder
    var performanceHealthSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isBedrock {
                healthSummaryRow(
                    label: "Load",
                    status: cpuHealthStatus(viewModel.bedrockLoad1mAverage)
                )
            } else {
                healthSummaryRow(
                    label: "TPS",
                    status: tpsHealthStatus(viewModel.latestTps1m)
                )
            }

            healthSummaryRow(
                label: "CPU",
                status: cpuHealthStatus(viewModel.performanceCpuPercentForSelectedServer)
            )

            healthSummaryRow(
                label: "Memory",
                status: ramHealthStatus(
                    viewModel.performanceRamMBForSelectedServer,
                    maxGB: viewModel.performanceRamLimitGBForSelectedServer
                )
            )
        }
        .font(.caption)
    }

    @ViewBuilder
    func healthSummaryRow(label: String, status: MetricStatus) -> some View {
        HStack(spacing: 6) {
            Image(systemName: status.icon)
                .foregroundStyle(status.color)
                .font(.caption2)

            Text(label)
                .foregroundStyle(.secondary)

            Spacer()

            Text(statusLabel(status))
                .foregroundStyle(status.color)
                .bold()
        }
    }

    func statusLabel(_ status: MetricStatus) -> String {
        switch status {
        case .good: return "Good"
        case .warning: return "Warning"
        case .critical: return "Critical"
        case .neutral: return "—"
        }
    }

    func tpsHealthStatus(_ tps: Double?) -> MetricStatus {
        guard let tps = tps else { return .neutral }
        switch tps {
        case 19.5...: return .good
        case 18.0..<19.5: return .warning
        default: return .critical
        }
    }

    func cpuHealthStatus(_ cpu: Double?) -> MetricStatus {
        guard let cpu = cpu else { return .neutral }
        switch cpu {
        case 0..<70: return .good
        case 70..<90: return .warning
        default: return .critical
        }
    }

    func ramHealthStatus(_ ramMB: Double?, maxGB: Int?) -> MetricStatus {
        guard let ramMB = ramMB, let maxGB = maxGB else { return .neutral }
        let maxMB = Double(maxGB) * 1024.0
        let usagePercent = (ramMB / maxMB) * 100.0

        switch usagePercent {
        case 0..<75: return .good
        case 75..<90: return .warning
        default: return .critical
        }
    }

    func formatRamCompact(_ mb: Double?, maxGB: Int?) -> String {
        guard let mb = mb else { return "—" }
        let usedGB = mb / 1024.0
        return String(format: "%.1f GB", usedGB)
    }
}


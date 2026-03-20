//
//  DetailsPerformanceCharts.swift
//  MinecraftServerController
//
//  Extracted from DetailsView.swift (Performance tab charts).
//

import SwiftUI
import Charts

// MARK: - Chart Data

private struct IndexedSample: Identifiable {
    let id = UUID()
    let index: Int
    let value: Double
}

// MARK: - Performance Tab Charts

extension DetailsPerformanceTabView {

    // MARK: - TPS chart (Java only)

    var enhancedTMSChart: some View {
        let samples = viewModel.tpsHistory1m.enumerated().map {
            IndexedSample(index: $0.offset, value: $0.element)
        }

        return Chart(samples) { sample in
            LineMark(
                x: .value("Time", sample.index),
                y: .value("TPS", sample.value)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(
                LinearGradient(
                    colors: [.green, .yellow, .red],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // Reference line at TPS 20
            RuleMark(y: .value("Target", 20))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(.secondary.opacity(0.3))
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(String(format: "%.0f", v))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartYScale(domain: 0...22)
        .frame(height: 120)
    }

    // MARK: - Bedrock CPU chart (Docker only)

    var enhancedBedrockCPUChart: some View {
        let samples = viewModel.bedrockCpuHistory.enumerated().map {
            IndexedSample(index: $0.offset, value: $0.element)
        }

        // Y-axis ceiling: at least 25%, or actual max rounded up to nearest 25
        let maxVal = viewModel.bedrockCpuHistory.max() ?? 0
        let ceiling = max(25.0, (ceil(maxVal / 25.0) * 25.0))

        return Chart(samples) { sample in
            AreaMark(
                x: .value("Time", sample.index),
                y: .value("CPU%", sample.value)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(
                LinearGradient(
                    colors: [.orange.opacity(0.5), .orange.opacity(0.1)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            LineMark(
                x: .value("Time", sample.index),
                y: .value("CPU%", sample.value)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(.orange)

            // Warning threshold at 70%
            RuleMark(y: .value("Warning", 70))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(.yellow.opacity(0.4))
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(String(format: "%.0f%%", v))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartYScale(domain: 0...ceiling)
        .frame(height: 120)
    }

    // MARK: - Player count chart (Java + Bedrock)

    var enhancedPlayerChart: some View {
        let samples = viewModel.playerCountHistory.enumerated().map {
            IndexedSample(index: $0.offset, value: Double($0.element))
        }

        let maxPlayers = max(Double(viewModel.playerCountHistory.max() ?? 6), 6.0)

        return Chart(samples) { sample in
            AreaMark(
                x: .value("Time", sample.index),
                y: .value("Players", sample.value)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(
                LinearGradient(
                    colors: [.blue.opacity(0.6), .blue.opacity(0.2)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            LineMark(
                x: .value("Time", sample.index),
                y: .value("Players", sample.value)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(.blue)
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(String(format: "%.0f", v))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartYScale(domain: 0...maxPlayers)
        .frame(height: 120)
    }

}

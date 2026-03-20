//
//  DetailsPerformanceTabContent.swift
//  MinecraftServerController
//

import SwiftUI

extension DetailsPerformanceTabView {

    var body: some View {
        performanceContent
    }

    private var performanceContent: some View {
        HStack(alignment: .top, spacing: 0) {

            // MARK: — Main content (centred, capped width)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ],
                        spacing: 12
                    ) {
                        if isBedrock {
                            enhancedMetricTile(
                                title: "Load (1m)",
                                value: formatPercent(viewModel.bedrockLoad1mAverage),
                                status: cpuHealthStatus(viewModel.bedrockLoad1mAverage),
                                subtitle: "Rolling average",
                                icon: "gauge.medium"
                            )

                            enhancedMetricTile(
                                title: "Load (5m avg)",
                                value: formatPercent(viewModel.bedrockLoad5mAverage),
                                status: cpuHealthStatus(viewModel.bedrockLoad5mAverage),
                                subtitle: "Medium-term",
                                icon: "chart.line.uptrend.xyaxis"
                            )

                            enhancedMetricTile(
                                title: "Load (15m avg)",
                                value: formatPercent(viewModel.bedrockLoad15mAverage),
                                status: cpuHealthStatus(viewModel.bedrockLoad15mAverage),
                                subtitle: "Long-term health",
                                icon: "chart.bar"
                            )
                        } else {
                            enhancedMetricTile(
                                title: "TPS (1m)",
                                value: formatTPS(viewModel.latestTps1m),
                                status: tpsHealthStatus(viewModel.latestTps1m),
                                subtitle: "Target: 20.00",
                                icon: "gauge.medium"
                            )

                            enhancedMetricTile(
                                title: "TPS (5m avg)",
                                value: formatTPS(viewModel.latestTps5m),
                                status: tpsHealthStatus(viewModel.latestTps5m),
                                subtitle: "Medium-term",
                                icon: "chart.line.uptrend.xyaxis"
                            )

                            enhancedMetricTile(
                                title: "TPS (15m avg)",
                                value: formatTPS(viewModel.latestTps15m),
                                status: tpsHealthStatus(viewModel.latestTps15m),
                                subtitle: "Long-term health",
                                icon: "chart.bar"
                            )
                        }

                        enhancedMetricTile(
                            title: "Players",
                            value: "\(viewModel.onlinePlayers.count)",
                            status: .neutral,
                            subtitle: "Currently online",
                            icon: "person.2"
                        )

                        let cpuValue = viewModel.performanceCpuPercentForSelectedServer
                        enhancedMetricTile(
                            title: "CPU Usage",
                            value: formatPercent(cpuValue),
                            status: cpuHealthStatus(cpuValue),
                            subtitle: isBedrock ? "Docker container" : "Java process",
                            icon: "cpu"
                        )

                        let ramMB = viewModel.performanceRamMBForSelectedServer
                        let maxRamGB = viewModel.performanceRamLimitGBForSelectedServer
                        enhancedMetricTile(
                            title: "Memory",
                            value: formatRamCompact(ramMB, maxGB: maxRamGB),
                            status: ramHealthStatus(ramMB, maxGB: maxRamGB),
                            subtitle: isBedrock
                                ? (maxRamGB.map { "of \($0) GB Docker limit" } ?? "Docker container")
                                : (maxRamGB.map { "of \($0) GB" } ?? "Heap"),
                            icon: "memorychip"
                        )
                    }

                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(
                                    isBedrock ? "CPU Over Time" : "TPS Over Time",
                                    systemImage: "waveform.path.ecg"
                                )
                                .font(.headline)

                                Spacer()

                                if isBedrock {
                                    if let latest = viewModel.performanceCpuPercentForSelectedServer {
                                        Text(formatPercent(latest))
                                            .font(.system(.title3, design: .rounded))
                                            .bold()
                                            .foregroundStyle(cpuHealthStatus(latest).color)
                                    }
                                } else if let latest = viewModel.latestTps1m {
                                    Text(String(format: "%.2f", latest))
                                        .font(.system(.title3, design: .rounded))
                                        .bold()
                                        .foregroundStyle(tpsColor(for: latest))
                                }
                            }

                            if isBedrock {
                                if viewModel.bedrockCpuHistory.isEmpty {
                                    emptyChartPlaceholder(
                                        message: "Start server to collect Docker metrics",
                                        icon: "chart.xyaxis.line"
                                    )
                                } else {
                                    enhancedBedrockCPUChart
                                }
                            } else {
                                if viewModel.tpsHistory1m.isEmpty {
                                    emptyChartPlaceholder(
                                        message: "Start server to collect TPS data",
                                        icon: "chart.xyaxis.line"
                                    )
                                } else {
                                    enhancedTMSChart
                                }
                            }
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(MSC.Colors.tierContent)
                        )

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("Player Activity", systemImage: "person.3")
                                    .font(.headline)
                                Spacer()
                                Text("\(viewModel.onlinePlayers.count)")
                                    .font(.system(.title3, design: .rounded))
                                    .bold()
                                    .foregroundStyle(.blue)
                            }

                            if viewModel.playerCountHistory.isEmpty {
                                emptyChartPlaceholder(
                                    message: "Collecting player activity data",
                                    icon: "person.2.wave.2"
                                )
                            } else {
                                enhancedPlayerChart
                            }
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(MSC.Colors.tierContent)
                        )
                    }

                    HStack(spacing: 12) {
                        compactInfoTile(
                            icon: "globe",
                            label: "World Size",
                            value: viewModel.worldSizeDisplay ?? "Unknown",
                            subtitle: "3 dimensions"
                        )

                        compactInfoTile(
                            icon: "clock",
                            label: "Uptime",
                            value: viewModel.serverUptimeDisplay ?? "Offline",
                            subtitle: viewModel.isServerRunning ? "Since start" : ""
                        )

                        compactInfoTile(
                            icon: viewModel.isServerRunning ? "checkmark.circle.fill" : "xmark.circle.fill",
                            label: "Status",
                            value: viewModel.isServerRunning ? "Online" : "Offline",
                            subtitle: viewModel.isServerRunning
                                ? (isBedrock ? "Container running" : "Accepting connections")
                                : ""
                        )
                        .foregroundStyle(viewModel.isServerRunning ? .green : .secondary)
                    }

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 4)
                .padding(.bottom, MSC.Spacing.md)
                // When the sidebar is collapsed, allow the grid to expand
                                // further to fill the reclaimed space.
                                .frame(maxWidth: sidebarCollapsed ? 1300 : 1200)
                                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // MARK: — Right panel (collapsible)
            rightSidePanel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Right sidebar

    @ViewBuilder
    private var rightSidePanel: some View {
        VStack(alignment: .trailing, spacing: 0) {
            // Collapse / expand toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    sidebarCollapsed.toggle()
                }
            } label: {
                Image(systemName: sidebarCollapsed ? "sidebar.right" : "sidebar.right")
                    .symbolVariant(sidebarCollapsed ? .none : .fill)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(MSC.Colors.tierContent)
                    )
            }
            .buttonStyle(.plain)
            .help(sidebarCollapsed ? "Show panel" : "Hide panel")
            .padding(.top, 4)
            .padding(.trailing, sidebarCollapsed ? 4 : 0)

            if !sidebarCollapsed {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Monitoring", systemImage: "chart.xyaxis.line")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)

                            MSCStatusDot(
                                color: viewModel.isServerRunning
                                    ? (viewModel.isMetricsPaused ? MSC.Colors.warning : MSC.Colors.success)
                                    : MSC.Colors.error,
                                label: viewModel.isServerRunning
                                    ? (viewModel.isMetricsPaused ? "Paused" : "Active (5s)")
                                    : "Offline"
                            )
                            .font(.caption)

                            Button(viewModel.isMetricsPaused ? "Resume" : "Pause") {
                                viewModel.toggleMetricsMonitoring()
                            }
                            .buttonStyle(MSCSecondaryButtonStyle())
                            .controlSize(.small)
                            .disabled(!viewModel.isServerRunning)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 10) {
                            Label("Quick Actions", systemImage: "bolt")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)

                            Button(action: { viewModel.refreshWorldSize() }) {
                                Label("Refresh World Size", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(MSCSecondaryButtonStyle())
                            .controlSize(.small)
                            .disabled(!viewModel.isServerRunning)

                            Button(action: { isShowingPerformanceHelp = true }) {
                                Label("Explain Metrics", systemImage: "questionmark.circle")
                            }
                            .buttonStyle(MSCSecondaryButtonStyle())
                            .controlSize(.small)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Label("Health Summary", systemImage: "heart.text.square")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)

                            performanceHealthSummary
                        }
                    }
                    .frame(width: 190, alignment: .topLeading)
                    .padding(.vertical, 8)
                    .padding(.leading, 8)
                }
                .frame(width: 198)
                .frame(maxHeight: .infinity, alignment: .top)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

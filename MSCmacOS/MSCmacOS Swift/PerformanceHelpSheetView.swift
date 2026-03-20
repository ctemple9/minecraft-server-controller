//
//  PerformanceHelpSheetView.swift
//  MinecraftServerController
//
//  Redesigned to match the WelcomeGuide / QuickStart visual language:
//  card-based metric rows, coloured callout boxes, GuideTopicHeader-style
//  header, and MSCStyles tokens throughout.
//

import SwiftUI

struct PerformanceHelpSheetView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Binding var isShowingPerformanceHelp: Bool

    private var isBedrock: Bool {
        guard let server = viewModel.selectedServer else { return false }
        return viewModel.configServer(for: server)?.isBedrock ?? false
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ────────────────────────────────────────────────────
            HStack(spacing: MSC.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                        .fill(Color.blue.opacity(0.14))
                        .frame(width: 44, height: 44)
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.blue)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reading the Performance Panel")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(isBedrock
                         ? "What the Docker container metrics mean for your Bedrock server."
                         : "What the metrics mean for your Java server.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    isShowingPerformanceHelp = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(Circle().fill(Color.secondary.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, MSC.Spacing.xl)
            .padding(.top, MSC.Spacing.xl)
            .padding(.bottom, MSC.Spacing.lg)

            Divider()

            // ── Scrollable metric cards ───────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: MSC.Spacing.md) {

                    // TPS card — Java only
                    if !isBedrock {
                        PHMetricCard(
                            icon: "gauge.with.needle.fill",
                            color: .green,
                            title: "TPS — Ticks Per Second",
                            description: "20 TPS is perfect. If it dips below ~18 regularly, players will start to feel lag — blocks popping back, mobs stuttering, actions not registering.",
                            note: "A sustained drop to 15 TPS or below means the server is overloaded. Try reducing view distance or removing heavy plugins."
                        )
                    }

                    // Load card — Bedrock only
                    if isBedrock {
                        PHMetricCard(
                            icon: "waveform.path.ecg",
                            color: .orange,
                            title: "Load — 1m / 5m / 15m",
                            description: "These rolling averages are based on Docker CPU usage for the Bedrock container. Higher values mean the server is working harder over time. A 1m spike is normal; a high 15m average means sustained load.",
                            note: nil
                        )
                    }

                    // CPU card
                    PHMetricCard(
                        icon: "cpu.fill",
                        color: .blue,
                        title: "CPU",
                        description: isBedrock
                            ? "The percentage of CPU used by the Bedrock Docker container. Very high values mean the server is handling a lot of players, world simulation, or entity activity."
                            : "The percentage of CPU used by the Java server process. Very high values usually mean lots of entities, complex redstone, or heavy plugin activity.",
                        note: isBedrock
                            ? "Docker shares CPU with your Mac. If performance feels sluggish, check whether other apps are competing for CPU."
                            : "Short CPU spikes are normal. If CPU is consistently above 90%, reduce player count or optimise your plugin stack."
                    )

                    // RAM card
                    PHMetricCard(
                        icon: "memorychip.fill",
                        color: .purple,
                        title: "RAM",
                        description: isBedrock
                            ? "How much memory the Bedrock Docker container is currently using. If it stays close to the container memory limit, reduce load or raise the container memory cap if applicable."
                            : "How much of the Java heap is currently in use. If it consistently sits near the maximum you configured, consider raising the max or reducing plugin and chunk-load overhead.",
                        note: isBedrock
                            ? nil
                            : "Tip: set Min RAM = Max RAM to avoid GC pauses from heap resizing. 4 GB max is a solid starting point for a small server."
                    )

                    // World size card
                    PHMetricCard(
                        icon: "externaldrive.fill",
                        color: .orange,
                        title: "World Size",
                        description: "The total disk size of the overworld, Nether, and End folders. Very large worlds can slow backups and take longer to copy, move, or restore.",
                        note: "Trim unused chunks with a tool like Chunky if your world has grown unexpectedly large from exploration."
                    )

                    // Quick tip callout
                    PHCallout(
                        icon: "lightbulb.fill",
                        color: .teal,
                        text: "All metrics update live while the server is running. Hover over any chart point to see its exact value and timestamp."
                    )

                }
                .padding(MSC.Spacing.xl)
            }

            // ── Footer ────────────────────────────────────────────────────
            Divider()
            HStack {
                Spacer()
                Button("Done") {
                    isShowingPerformanceHelp = false
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(MSCPrimaryButtonStyle())
            }
            .padding(.horizontal, MSC.Spacing.xl)
            .padding(.vertical, MSC.Spacing.md)
        }
        .frame(minWidth: 480, idealWidth: 500, minHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Metric Card

/// A labelled metric explanation card — matches the QSStep visual grammar.
private struct PHMetricCard: View {
    let icon: String
    let color: Color
    let title: String
    let description: String
    let note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {

            // Title row
            HStack(spacing: MSC.Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                        .fill(color.opacity(0.13))
                        .frame(width: 30, height: 30)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(color)
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            Rectangle()
                .fill(Color.secondary.opacity(0.1))
                .frame(height: 1)

            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            if let note {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.top, 1)
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(MSC.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                        .fill(Color.secondary.opacity(0.06))
                )
            }
        }
        .padding(MSC.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.lg, style: .continuous)
                .fill(MSC.Colors.cardBackground.opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MSC.Radius.lg, style: .continuous)
                .stroke(MSC.Colors.cardBorder, lineWidth: 1)
        )
    }
}

// MARK: - Callout

/// Tinted callout — mirrors GuideCallout / QSCallout.
private struct PHCallout: View {
    let icon: String
    let color: Color
    let text: String

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


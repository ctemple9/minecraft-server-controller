//
//  DetailsOverviewTabView.swift
//  MinecraftServerController
//
//  Redesigned: isShowingBackups binding removed (backups now live in Worlds tab).
//  Join Card now opens from Connection Info as a dedicated share sheet.
//  Zone layout:
//    Zone 1  Alert banners (EULA, DuckDNS)
//    Zone 2  Server status bar
//    Zone 3  Connection + live stats side-by-side
//    Zone 4  Server Health grid
//    Zone 5  Notes
//
//  replaced with MSCOverline labels for lighter visual weight.
//
//  Visual update: uptime row removed from live stats footer (uptime is
//  shown in the status bar). Gauge track color matches connection card
//  column cells. Tick marks added to gauges for readability when empty.
//

import SwiftUI

struct DetailsOverviewTabView: View {
    @EnvironmentObject var viewModel: AppViewModel

    @Binding var isEditingDuckDNS: Bool
    @Binding var showCopiedHUD: Bool
    @Binding var copiedHUDText: String
    @Binding var showAddresses: Bool
    @Binding var hasSavedDuckDNS: Bool
    @Binding var selectedPlayerName: String?
    @Binding var serverNotesText: String
    @Binding var messageTarget: OnlinePlayer?
    @Binding var messageText: String

    var onOpenComponentsTab: (() -> Void)? = nil

    private var isBedrock: Bool {
        guard let s = viewModel.selectedServer else { return false }
        return viewModel.configServer(for: s)?.isBedrock ?? false
    }

    var body: some View {
        overviewContent
    }

    private var overviewContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: MSC.Spacing.md) {

                // Zone 1: Alert banners
                OverviewAlertBannersView(
                    hasSavedDuckDNS: $hasSavedDuckDNS,
                    isEditingDuckDNS: $isEditingDuckDNS
                )

                if isEditingDuckDNS {
                    OverviewDuckDNSSectionView(
                        hasSavedDuckDNS: $hasSavedDuckDNS,
                        isEditingDuckDNS: $isEditingDuckDNS
                    )
                }

                // Zone 3: Connection + live stats — fixed minimum height forces both cards equal
                                HStack(alignment: .top, spacing: MSC.Spacing.md) {
                    OverviewConnectionCardView(
                        showAddresses: $showAddresses,
                        hasSavedDuckDNS: $hasSavedDuckDNS,
                        isEditingDuckDNS: $isEditingDuckDNS,
                        copyToPasteboard: { DetailsClipboardAndHUDHelpers.copyToPasteboard($0) },
                        showHUDMessage: {
                            DetailsClipboardAndHUDHelpers.showHUDMessage(
                                $0,
                                copiedHUDText: $copiedHUDText,
                                showCopiedHUD: $showCopiedHUD
                            )
                        }
                    )

                                    OverviewJavaLivePanel(isBedrock: isBedrock)
                                                    }
                                                    .frame(minHeight: 200)

                                                    // Zone 4: Server Health grid
                HealthCardsGridView(onOpenComponentsTab: onOpenComponentsTab)

                // Zone 5: Notes
                ServerNotesSectionView(serverNotesText: $serverNotesText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
        }
        .overlay(alignment: .top) {
            if showCopiedHUD {
                MSCSaveHUD(text: copiedHUDText)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 4)
                    .allowsHitTesting(false)
            }
        }
        .animation(.spring(duration: 0.25), value: showCopiedHUD)
        .task {
            viewModel.checkComponentsOnline()
        }
        .onAppear {
            serverNotesText = viewModel.selectedServerNotes
        }
        .onChange(of: viewModel.selectedServer) { _ in
            serverNotesText = viewModel.selectedServerNotes
        }
    }
}

// MARK: - Java live panel

private struct OverviewJavaLivePanel: View {
    @EnvironmentObject var viewModel: AppViewModel

    let isBedrock: Bool

    private var ramFraction: Double? {
        if isBedrock {
            guard let usedMB = viewModel.bedrockMemoryUsedMB,
                  let limitMB = viewModel.bedrockMemoryLimitMB,
                  limitMB > 0 else { return nil }
            return min(max(usedMB / limitMB, 0), 1)
        }
        return viewModel.serverRamFractionOfMax
    }

    private var cpuValue: Double? {
        isBedrock ? viewModel.bedrockCpuPercent : viewModel.serverCpuPercent
    }

    private var ramValueMB: Double? {
        isBedrock ? viewModel.bedrockMemoryUsedMB : viewModel.serverRamMB
    }

    private var thirdMetricFraction: Double? {
        if isBedrock {
            return viewModel.bedrockLoad1mAverage.map { min(max($0 / 100.0, 0), 1) }
        }
        return viewModel.latestTps1m.map { min($0 / 20.0, 1.0) }
    }

    private var thirdMetricValueLabel: String {
        if isBedrock {
            return viewModel.bedrockLoad1mAverage.map { String(format: "%.0f%%", $0) } ?? "--"
        }
        return viewModel.latestTps1m.map { String(format: "%.1f", $0) } ?? "--"
    }

    private var thirdMetricLabel: String {
        isBedrock ? "LOAD" : "TPS"
    }

    private var thirdMetricColor: Color {
        if isBedrock {
            return cpuColor(for: viewModel.bedrockLoad1mAverage ?? 0)
        }
        return tpsColor(for: viewModel.latestTps1m ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {

            // Overline
            HStack(spacing: MSC.Spacing.xs) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(MSC.Colors.tertiary)
                MSCOverline("Live Stats")
            }

            // Gauges — fill all available vertical space
            HStack(alignment: .top, spacing: MSC.Spacing.sm) {
                LiveGauge(
                    fraction: cpuValue.map { min(max($0 / 100.0, 0), 1) } ?? 0,
                    hasData: cpuValue != nil,
                    color: cpuColor(for: cpuValue ?? 0),
                    valueLabel: cpuValue.map { String(format: "%.0f%%", $0) } ?? "--",
                    metricLabel: "CPU"
                )

                LiveGauge(
                    fraction: ramFraction ?? 0,
                    hasData: ramFraction != nil,
                    color: ramColor(for: ramFraction ?? 0),
                    valueLabel: ramValueMB.map { ramLabel(mb: $0) } ?? "--",
                    metricLabel: "RAM"
                )

                LiveGauge(
                    fraction: thirdMetricFraction ?? 0,
                    hasData: thirdMetricFraction != nil,
                    color: thirdMetricColor,
                    valueLabel: thirdMetricValueLabel,
                    metricLabel: thirdMetricLabel
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(MSC.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .fill(MSC.Colors.tierContent)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .stroke(MSC.Colors.contentBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 6, x: 0, y: 3)
    }

    // MARK: - Color thresholds

    private func cpuColor(for pct: Double) -> Color {
        switch pct {
        case ..<50:  return MSC.Colors.success
        case ..<80:  return MSC.Colors.warning
        default:     return MSC.Colors.error
        }
    }

    private func ramColor(for fraction: Double) -> Color {
        switch fraction {
        case ..<0.70: return MSC.Colors.success
        case ..<0.85: return MSC.Colors.warning
        default:      return MSC.Colors.error
        }
    }

    private func tpsColor(for t: Double) -> Color {
        switch t {
        case 19.5...: return MSC.Colors.success
        case 18.0..<19.5: return MSC.Colors.warning
        default:      return MSC.Colors.error
        }
    }

    private func ramLabel(mb: Double) -> String {
        mb >= 1024
            ? String(format: "%.1f GB", mb / 1024)
            : String(format: "%.0f MB", mb)
    }
}

// MARK: - Vertical gauge component

private struct LiveGauge: View {
    let fraction: Double      // 0.0 – 1.0
    let hasData: Bool
    let color: Color
    let valueLabel: String
    let metricLabel: String

    private let trackColor = Color.white.opacity(0.04)
    private let cornerRadius: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Track fill
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(trackColor)

                // Fill — animates from bottom up
                if hasData && fraction > 0 {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.7), color],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(height: geo.size.height * CGFloat(fraction))
                        .animation(.easeInOut(duration: 0.4), value: fraction)
                }

                // Tick marks — 3 evenly spaced hairlines, always visible
                VStack(spacing: 0) {
                    Spacer()
                    Rectangle()
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 0.5)
                    Spacer()
                    Rectangle()
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 0.5)
                    Spacer()
                    Rectangle()
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 0.5)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Value + label overlaid inside track, pinned to bottom
                                VStack(spacing: 3) {
                                    Text(valueLabel)
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                    Text(metricLabel)
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.6))
                                        .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
                                        .textCase(.uppercase)
                                        .tracking(0.5)
                                }
                                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

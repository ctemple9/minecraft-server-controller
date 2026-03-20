//
//  QuickCommandsView.swift
//  MinecraftServerController
//

import SwiftUI

// MARK: - Supporting Enums

enum TimeOfDayPreset: String, CaseIterable, Identifiable {
    case day      = "1000"
    case night    = "13000"
    case midnight = "18000"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day:      return "Dawn"
        case .night:    return "Dusk"
        case .midnight: return "Night"
        }
    }

    var icon: String {
        switch self {
        case .day:      return "sunrise.fill"
        case .night:    return "sunset.fill"
        case .midnight: return "moon.stars.fill"
        }
    }

    var color: Color {
        switch self {
        case .day:      return .orange
        case .night:    return .orange.opacity(0.7)
        case .midnight: return .indigo
        }
    }
}

enum WeatherPreset: String, CaseIterable, Identifiable {
    case clear   = "clear"
    case rain    = "rain"
    case thunder = "thunder"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .clear:   return "Clear"
        case .rain:    return "Rain"
        case .thunder: return "Storm"
        }
    }

    var icon: String {
        switch self {
        case .clear:   return "sun.max.fill"
        case .rain:    return "cloud.rain.fill"
        case .thunder: return "cloud.bolt.rain.fill"
        }
    }

    var color: Color {
        switch self {
        case .clear:   return .yellow
        case .rain:    return .blue
        case .thunder: return .purple
        }
    }
}

// MARK: - QuickCommandsView

struct QuickCommandsView: View {
    @EnvironmentObject var viewModel: AppViewModel

    let controlsAnchorID: String?
    let runningStateAnchorID: String?

    @State private var difficulty: ServerDifficulty = .normal
    @State private var gamemode: ServerGamemode = .survival
    @State private var whitelistEnabled: Bool = false

    init(
        controlsAnchorID: String? = nil,
        runningStateAnchorID: String? = nil
    ) {
        self.controlsAnchorID = controlsAnchorID
        self.runningStateAnchorID = runningStateAnchorID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {

//            Text("Quick Commandsjj")
//                .font(MSC.Typography.sectionHeader)

            if viewModel.selectedServer == nil {
                Text("Select a server to use quick commands.")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(.secondary)
            } else {

                // Live stat strip — only visible when server is running
                if viewModel.isServerRunning {
                    HStack(spacing: MSC.Spacing.sm) {
                        MSCStatChip(
                            icon: "person.2.fill",
                            value: "\(viewModel.onlinePlayers.count)",
                            label: "online",
                            color: .green
                        )

                        if let tps = viewModel.latestTps1m {
                            MSCStatChip(
                                icon: "speedometer",
                                value: String(format: "%.1f", tps),
                                label: "TPS",
                                color: tps >= 18 ? .green : tps >= 14 ? .orange : .red
                            )
                        }
                    }
                    .padding(.bottom, MSC.Spacing.xxs)
                    .contextualHelpAnchor(runningStateAnchorID)
                    .id(runningStateAnchorID)
                }

                VStack(alignment: .leading, spacing: MSC.Spacing.md) {

                    // MARK: World Controls
                    MSCOverline("World")

                    VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                        Text("Time of Day")
                            .font(MSC.Typography.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: MSC.Spacing.xs) {
                            ForEach(TimeOfDayPreset.allCases) { preset in
                                WorldControlButton(
                                    icon: preset.icon,
                                    label: preset.label,
                                    color: preset.color
                                ) {
                                    viewModel.setTimeOfDay(preset)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                        Text("Weather")
                            .font(MSC.Typography.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: MSC.Spacing.xs) {
                            ForEach(WeatherPreset.allCases) { preset in
                                WorldControlButton(
                                    icon: preset.icon,
                                    label: preset.label,
                                    color: preset.color
                                ) {
                                    viewModel.setWeather(preset)
                                }
                            }
                        }
                    }

                    Divider()

                    // MARK: Server Settings
                    MSCOverline("Settings")

                    HStack {
                        Text("Difficulty")
                            .font(MSC.Typography.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 62, alignment: .leading)

                        Picker("", selection: Binding(
                            get: { difficulty },
                            set: { newValue in
                                difficulty = newValue
                                viewModel.applyDifficulty(newValue)
                            }
                        )) {
                            ForEach(ServerDifficulty.allCases) { diff in
                                Text(diff.displayName).tag(diff)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack {
                        Text("Gamemode")
                            .font(MSC.Typography.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 62, alignment: .leading)

                        Picker("", selection: Binding(
                            get: { gamemode },
                            set: { newValue in
                                gamemode = newValue
                                viewModel.applyGamemode(newValue)
                            }
                        )) {
                            ForEach(ServerGamemode.allCases) { gm in
                                Text(gm.displayName).tag(gm)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Toggle(isOn: Binding(
                        get: { whitelistEnabled },
                        set: { newValue in
                            whitelistEnabled = newValue
                            viewModel.setWhitelistEnabled(newValue)
                        }
                    )) {
                        Text("Whitelist")
                            .font(MSC.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)

                    Divider()

                    // MARK: Actions
                    MSCOverline("Actions")

                    HStack(spacing: MSC.Spacing.sm) {
                        ActionButton(icon: "arrow.down.doc", label: "Save All") {
                            viewModel.runSaveAll()
                        }
                        ActionButton(icon: "arrow.clockwise", label: "Reload") {
                            viewModel.runReload()
                        }
                    }
                }
                .disabled(!viewModel.isServerRunning)
                .contextualHelpAnchor(controlsAnchorID)
                .id(controlsAnchorID)

                if !viewModel.isServerRunning {
                    Text("Start the server to use Quick Commands.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, MSC.Spacing.xxs)
                        .contextualHelpAnchor(runningStateAnchorID)
                        .id(runningStateAnchorID)
                }
            }
        }
        .onAppear { refreshFromProperties() }
        .onChange(of: viewModel.selectedServer?.id) { _ in refreshFromProperties() }
    }

    private func refreshFromProperties() {
        guard let (model, _) = viewModel.quickCommandsModelForSelectedServer() else { return }
        difficulty = model.difficulty
        gamemode = model.gamemode
        whitelistEnabled = model.whitelistEnabled
    }
}

// MARK: - Sub-views (WorldControlButton and ActionButton remain local)

private struct WorldControlButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, MSC.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                    .fill(color.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                    .stroke(color.opacity(0.18), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: MSC.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
        }
        .buttonStyle(MSCCompactButtonStyle())
    }
}

// StatChip is now MSCStatChip in MSCStyles.swift

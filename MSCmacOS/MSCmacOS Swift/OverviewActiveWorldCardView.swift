//
//  OverviewActiveWorldCardView.swift
//  MinecraftServerController
//
//  Overview tab — "Active World" card. Shows the currently active world's
//  name, a picture (custom thumbnail when present, otherwise a generated
//  placeholder), and quick facts read from server.properties / Bedrock
//  properties. In-game day & time-of-day are intentionally deferred to a
//  future phase (needs level.dat DayTime parsing).
//

import SwiftUI
import AppKit

// MARK: - World info model

struct OverviewWorldInfo {
    var name: String
    var isBedrock: Bool
    var difficulty: String      // display-ready, capitalized
    var gamemode: String        // display-ready, capitalized
    var maxPlayers: Int
    /// Last-saved day count from level.dat — fallback for when the server is off.
    var savedDayNumber: Int?
    /// Last-saved time-of-day (0–23999) from level.dat — fallback when off.
    var savedTimeTicks: Int?
    var seed: String?
    var thumbnailURL: URL?
}

// MARK: - VM helper

extension AppViewModel {

    /// Builds a snapshot of the active world's display facts for the Overview card.
    /// Reads from disk (server.properties / Bedrock properties + the active world
    /// slot), so callers should invoke this from `.onAppear` / `.task`, not inside
    /// a SwiftUI `body`.
    func overviewActiveWorldInfo() -> OverviewWorldInfo? {
        guard let server = selectedServer,
              let cfg = configServer(for: server) else { return nil }

        let activeSlot = WorldSlotManager.activeSlot(forServerDir: cfg.serverDir)
        let name = activeSlot?.name
            ?? WorldSlotManager.currentLevelName(for: cfg)

        // Optional custom thumbnail (future "custom photo" feature already has a slot).
        var thumbnailURL: URL? = nil
        if let slot = activeSlot, let file = slot.thumbnailFileName, !file.isEmpty {
            let url = WorldSlotManager.slotDirectory(slot: slot, serverDir: cfg.serverDir)
                .appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: url.path) { thumbnailURL = url }
        }

        // Last-saved day/time from the live world's level.dat (fallback for when off).
        let (savedDay, savedTicks) = savedDayTime(for: cfg)

        if cfg.isBedrock {
            let model = BedrockPropertiesManager.readModel(serverDir: cfg.serverDir)
            return OverviewWorldInfo(
                name: name,
                isBedrock: true,
                difficulty: model.difficulty.rawValue.capitalized,
                gamemode: model.gamemode.rawValue.capitalized,
                maxPlayers: model.maxPlayers,
                savedDayNumber: savedDay,
                savedTimeTicks: savedTicks,
                seed: activeSlot?.worldSeed,
                thumbnailURL: thumbnailURL
            )
        } else {
            let dict = ServerPropertiesManager.readProperties(serverDir: cfg.serverDir)
            let model = ServerPropertiesModel(from: dict, fallbackMotd: cfg.displayName)
            return OverviewWorldInfo(
                name: name,
                isBedrock: false,
                difficulty: model.difficulty.rawValue.capitalized,
                gamemode: model.gamemode.rawValue.capitalized,
                maxPlayers: model.maxPlayers,
                savedDayNumber: savedDay,
                savedTimeTicks: savedTicks,
                seed: activeSlot?.worldSeed,
                thumbnailURL: thumbnailURL
            )
        }
    }

    /// Reads the live world folder's level.dat for the last-saved day & time-of-day.
    private func savedDayTime(for cfg: ConfigServer) -> (day: Int?, ticks: Int?) {
        let serverDirURL = URL(fileURLWithPath: cfg.serverDir, isDirectory: true)
        let levelName = WorldSlotManager.currentLevelName(for: cfg)

        let candidateFolders: [URL]
        if cfg.isBedrock {
            let worlds = serverDirURL.appendingPathComponent("worlds", isDirectory: true)
            candidateFolders = [worlds.appendingPathComponent(levelName, isDirectory: true), worlds]
        } else {
            candidateFolders = [serverDirURL.appendingPathComponent(levelName, isDirectory: true)]
        }

        for folder in candidateFolders {
            guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("level.dat").path) else { continue }
            let meta = WorldSlotManager.importedWorldMetadata(fromFolder: folder, serverType: cfg.serverType)
            if let dt = meta.dayTime {
                let day = Int(dt / 24000)
                let ticks = Int(((dt % 24000) + 24000) % 24000)
                return (day, ticks)
            }
        }
        return (nil, nil)
    }
}

// MARK: - Card

struct OverviewActiveWorldCardView: View {
    @EnvironmentObject var viewModel: AppViewModel

    /// Jump to the Worlds tab (wired by DetailsView).
    var onOpenWorldsTab: (() -> Void)? = nil

    @State private var info: OverviewWorldInfo? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {

            // Header
            HStack(spacing: MSC.Spacing.xs) {
                Image(systemName: "globe.americas.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(MSC.Colors.tertiary)
                MSCOverline("Active World")
                Spacer()
            }

            if let info {
                content(info)
            } else {
                emptyState
            }

            Spacer(minLength: 0)
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
        .onAppear { reload() }
        .onChange(of: viewModel.selectedServer) { _ in reload() }
        .onChange(of: viewModel.activePlayerDataWorldName) { _ in reload() }
        .onChange(of: viewModel.isServerRunning) { _ in reload() }
    }

    private func reload() {
        info = viewModel.overviewActiveWorldInfo()
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ info: OverviewWorldInfo) -> some View {
        HStack(alignment: .top, spacing: MSC.Spacing.md) {

            worldThumbnail(info)
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                        .stroke(MSC.Colors.contentBorder, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                Text(info.name)
                    .font(MSC.Typography.cardTitle)
                    .foregroundStyle(MSC.Colors.heading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(info.isBedrock ? "Bedrock" : "Java")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(MSC.Colors.tertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }

        // Live values when running, last-saved level.dat values when off.
        let day = (viewModel.isServerRunning ? viewModel.worldDayNumber : nil) ?? info.savedDayNumber
        let ticks = (viewModel.isServerRunning ? viewModel.worldTimeOfDayTicks : nil) ?? info.savedTimeTicks
        let isLive = viewModel.isServerRunning && viewModel.worldTimeOfDayTicks != nil

        // Quick facts grid
        factGrid(info, day: day)

        // Digital world clock (hidden when no time is available)
        if let ticks {
            clockBlock(ticks: ticks, isLive: isLive)
        }

        Divider().opacity(0.5)

        // Quick actions — equal-width, filling the card
        HStack(spacing: MSC.Spacing.sm) {
            Button {
                onOpenWorldsTab?()
            } label: {
                Label("Switch", systemImage: "rectangle.2.swap")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(MSCSecondaryButtonStyle())
            .controlSize(.mini)
            .disabled(viewModel.selectedServer == nil)

            Button {
                viewModel.createBackupForSelectedServer()
            } label: {
                Label("Backup", systemImage: "externaldrive.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(MSCSecondaryButtonStyle())
            .controlSize(.mini)
            .disabled(viewModel.selectedServer == nil)
        }
        .frame(maxWidth: .infinity)
    }

    private func factGrid(_ info: OverviewWorldInfo, day: Int?) -> some View {
        let cols = [GridItem(.flexible(), alignment: .leading),
                    GridItem(.flexible(), alignment: .leading)]
        return LazyVGrid(columns: cols, alignment: .leading, spacing: MSC.Spacing.xs) {
            factRow(icon: "speedometer", key: "Diff", value: info.difficulty)
            factRow(icon: "gamecontroller", key: "Mode", value: info.gamemode)
            factRow(icon: "person.2.fill", key: "Max", value: "\(info.maxPlayers)")
            factRow(icon: "calendar", key: "Day #", value: day.map { "\($0)" } ?? "—")
        }
    }

    // MARK: Digital clock

    private func clockBlock(ticks: Int, isLive: Bool) -> some View {
        HStack(spacing: MSC.Spacing.sm) {
            Image(systemName: isDay(ticks) ? "sun.max.fill" : "moon.stars.fill")
                .font(.system(size: 15))
                .foregroundStyle(isDay(ticks) ? Color.yellow.opacity(0.9) : Color.purple.opacity(0.85))

            Text(clockString(ticks))
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundStyle(MSC.Colors.heading)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Circle()
                    .fill(isLive ? MSC.Colors.success : MSC.Colors.neutral)
                    .frame(width: 5, height: 5)
                Text(isLive ? "Live" : "Last saved")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(MSC.Colors.tertiary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, MSC.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
    }

    /// Converts Minecraft day-time ticks (0 = 06:00) to a 24-hour HH:MM string.
    private func clockString(_ ticks: Int) -> String {
        let hour = (ticks / 1000 + 6) % 24
        let minute = (ticks % 1000) * 60 / 1000
        return String(format: "%02d:%02d", hour, minute)
    }

    /// Daytime is roughly ticks 0–12000 (and the dawn tail ≥23000).
    private func isDay(_ ticks: Int) -> Bool { ticks < 12000 || ticks >= 23000 }

    private func factRow(icon: String, key: String, value: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(MSC.Colors.tertiary)
                .frame(width: 12)
            Text(key)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(MSC.Colors.tertiary)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MSC.Colors.body)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    // MARK: Thumbnail

    @ViewBuilder
    private func worldThumbnail(_ info: OverviewWorldInfo) -> some View {
        if let url = info.thumbnailURL, let img = NSImage(contentsOf: url) {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            placeholderThumbnail(seedText: info.name)
        }
    }

    /// Deterministic gradient placeholder keyed off the world name, with a glyph.
    private func placeholderThumbnail(seedText: String) -> some View {
        let hue = Double(abs(seedText.hashValue) % 360) / 360.0
        let top = Color(hue: hue, saturation: 0.45, brightness: 0.55)
        let bottom = Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1.0),
                           saturation: 0.55, brightness: 0.30)
        return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
            .overlay(
                Image(systemName: "mountain.2.fill")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            )
    }

    // MARK: Empty

    private var emptyState: some View {
        HStack(spacing: MSC.Spacing.sm) {
            Image(systemName: "globe")
                .font(.system(size: 18))
                .foregroundStyle(MSC.Colors.tertiary)
            Text("No active world yet.")
                .font(MSC.Typography.caption)
                .foregroundStyle(MSC.Colors.caption)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, MSC.Spacing.sm)
    }
}

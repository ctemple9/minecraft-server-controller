import SwiftUI
import AppKit

struct ServerEditorSidebarView: View {
    @EnvironmentObject var viewModel: AppViewModel
    let data: ServerEditorData
    let editingConfigServer: ConfigServer?

    @State private var eulaAccepted: Bool? = nil

    private var isRunning: Bool { viewModel.isServerRunning }

    private var activeWorldName: String? {
        guard let cfg = editingConfigServer else { return nil }
        guard let id = viewModel.activeWorldSlotId(forServerDir: cfg.serverDir) else { return nil }
        return viewModel.worldSlots.first(where: { $0.id == id })?.name
    }

    /// On-disk thumbnail of the active world slot (the photo set in the World tab),
    /// or nil when none is set — in which case the procedural placeholder is drawn.
    private var activeWorldThumbnailURL: URL? {
        guard let cfg = editingConfigServer,
              let id = viewModel.activeWorldSlotId(forServerDir: cfg.serverDir),
              let slot = viewModel.worldSlots.first(where: { $0.id == id }) else { return nil }
        return WorldSlotManager.thumbnailURL(forSlot: slot, serverDir: cfg.serverDir)
    }

    private var backupSummary: String {
        guard let cfg = editingConfigServer else { return "Off" }
        guard cfg.autoBackupEnabled else { return "Off" }
        let m = cfg.autoBackupIntervalMinutes
        return m < 60 ? "Every \(m) min" : "Every \(m / 60)h"
    }

    private var crossPlayInfo: (label: String, color: Color) {
        guard let cfg = editingConfigServer, cfg.isJava else { return ("", .secondary) }
        let fm = FileManager.default
        let pluginsDir = URL(fileURLWithPath: cfg.serverDir)
            .appendingPathComponent("plugins", isDirectory: true)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: pluginsDir.path, isDirectory: &isDir), isDir.boolValue else {
            return ("Disabled", .secondary)
        }
        guard let contents = try? fm.contentsOfDirectory(at: pluginsDir,
                                                          includingPropertiesForKeys: nil,
                                                          options: [.skipsHiddenFiles]) else {
            return ("Unknown", .secondary)
        }
        let names = contents.filter { $0.pathExtension.lowercased() == "jar" }
            .map { $0.lastPathComponent.lowercased() }
        let hasGeyser    = names.contains { $0.contains("geyser") }
        let hasFloodgate = names.contains { $0.contains("floodgate") }
        switch (hasGeyser, hasFloodgate) {
        case (true, true):  return ("Enabled", .green)
        case (true, false): return ("Partial", .orange)
        default:            return ("Disabled", .secondary)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    thumbnailView
                        .padding(.bottom, MSC.Spacing.sm)

                    Text(data.displayName.isEmpty ? "Untitled" : data.displayName)
                        .font(.system(size: 12, weight: .bold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity)

                    Text(data.serverType == .java ? "Java Edition" : "Bedrock Edition")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, MSC.Spacing.sm)

                    Divider().opacity(0.4).padding(.bottom, 6)

                    sbRow("Status") {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(isRunning ? Color.green : Color.secondary.opacity(0.4))
                                .frame(width: 6, height: 6)
                            Text(isRunning ? "Running" : "Stopped")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(isRunning ? Color.green : Color.secondary)
                        }
                    }

                    if data.serverType == .java {
                        sbRow("EULA") {
                            Text(eulaAccepted == true ? "✓ Accepted" : "Needed")
                                .font(.system(size: 10))
                                .foregroundStyle(eulaAccepted == true ? Color.green : Color.orange)
                        }
                    }

                    sbRow("RAM") {
                        Text("\(data.minRamGB)–\(data.maxRamGB) GB")
                            .font(.system(size: 10))
                            .foregroundStyle(.primary)
                    }

                    if let worldName = activeWorldName {
                        sbRow("World") {
                            Text(worldName)
                                .font(.system(size: 10))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    let (crossLabel, crossColor) = crossPlayInfo
                    if data.serverType == .java, !crossLabel.isEmpty {
                        sbRow("Cross-play") {
                            Text(crossLabel)
                                .font(.system(size: 10))
                                .foregroundStyle(crossColor)
                        }
                    }

                    Divider().opacity(0.4).padding(.vertical, 6)

                    if data.serverType == .java, let cfg = editingConfigServer {
                        if cfg.isModded {
                            let isInstalled: Bool = {
                                let dir = URL(fileURLWithPath: cfg.serverDir, isDirectory: true)
                                let fm = FileManager.default
                                switch cfg.javaFlavor {
                                case .fabric: return fm.fileExists(atPath: dir.appendingPathComponent("fabric-server-launch.jar").path)
                                case .quilt:  return fm.fileExists(atPath: dir.appendingPathComponent("quilt-server-launch.jar").path)
                                default:      return fm.fileExists(atPath: dir.appendingPathComponent("run.sh").path)
                                                  || fm.fileExists(atPath: dir.appendingPathComponent("libraries").path)
                                }
                            }()
                            sbRow("Server") {
                                Text(isInstalled ? "✓ Installed" : "Not installed")
                                    .font(.system(size: 10))
                                    .foregroundStyle(isInstalled ? Color.green : Color.orange)
                            }
                        } else {
                            let summary = viewModel.jarSummary(for: cfg)
                            sbRow("JARs") {
                                Text(summary.paperFilename != nil ? "✓ Found" : "Missing")
                                    .font(.system(size: 10))
                                    .foregroundStyle(summary.paperFilename != nil ? Color.green : Color.orange)
                            }
                        }
                    }

                    sbRow("Auto-backup") {
                        Text(backupSummary)
                            .font(.system(size: 10))
                            .foregroundStyle(.primary)
                    }

                    sbRow("Worlds") {
                        let count = viewModel.worldSlots.count
                        Text("\(count) slot\(count == 1 ? "" : "s")")
                            .font(.system(size: 10))
                            .foregroundStyle(.primary)
                    }
                }
                .padding(MSC.Spacing.md)
            }

            Divider().opacity(0.3)
            Text(data.serverDir.isEmpty
                 ? "No directory set"
                 : URL(fileURLWithPath: data.serverDir).lastPathComponent)
                .font(.system(size: 9))
                .foregroundStyle(MSC.Colors.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, MSC.Spacing.sm)
                .padding(.vertical, MSC.Spacing.sm)
        }
        .frame(width: 190)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        .onAppear { refreshEULA() }
        .onChange(of: data.serverDir) { _, _ in refreshEULA() }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let url = activeWorldThumbnailURL, let img = NSImage(contentsOf: url) {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: [
                            Color(hue: 0.57, saturation: 0.60, brightness: 0.85),
                            Color(hue: 0.57, saturation: 0.45, brightness: 0.65)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .overlay(
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(Color(hue: 0.33, saturation: 0.55, brightness: 0.42))
                                .frame(height: 6)
                            Rectangle()
                                .fill(Color(hue: 0.07, saturation: 0.45, brightness: 0.35))
                                .frame(height: 12)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    )
                }
            }
            .aspectRatio(16/9, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous))

            if isRunning {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                    .shadow(color: Color.green.opacity(0.5), radius: 3)
                    .padding(5)
            }
        }
    }

    @ViewBuilder
    private func sbRow<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        HStack(alignment: .center, spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(minWidth: 62, alignment: .leading)
            Spacer(minLength: 2)
            content()
        }
        .padding(.vertical, 3)
    }

    private func refreshEULA() {
        let trimmed = data.serverDir.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { eulaAccepted = nil; return }
        eulaAccepted = EULAManager.readEULA(in: trimmed)
    }
}

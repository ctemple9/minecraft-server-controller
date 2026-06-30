//
//  AppViewModel+ClientExport.swift
//  MinecraftServerController
//
//  Builds the client-side mod/plugin export list for a server and produces the
//  deliverable: a ZIP of JAR files for modded servers, or a Modrinth link list
//  for Paper/Purpur (where server plugin JARs differ from client builds).
//

import AppKit
import Foundation
import UniformTypeIdentifiers

// MARK: - Models

/// Whether a mod or plugin needs to be present on the client.
enum ClientSideStatus: Equatable {
    case required   // client must install to connect / use content
    case optional   // enhances experience, client can connect without it
    case serverOnly // pure server-side; client needs nothing
    case unknown    // no signal — default to required (safe)

    /// Whether the item should be checked in the export sheet by default.
    var isSelectedByDefault: Bool {
        switch self {
        case .required, .optional, .unknown: return true
        case .serverOnly:                    return false
        }
    }

    var displayLabel: String {
        switch self {
        case .required:   return "Required"
        case .optional:   return "Optional"
        case .serverOnly: return "Server-only"
        case .unknown:    return "Unknown"
        }
    }
}

struct ClientExportItem: Identifiable {
    var id: String { jarStem }

    let jarStem: String
    let fileName: String
    let displayName: String
    let iconURL: String?
    let projectId: String?
    let slug: String?
    let clientStatus: ClientSideStatus
    /// Human-readable source of the classification ("Modrinth", "mod manifest", "assumed").
    let statusSource: String
    var isSelected: Bool
    let jarURL: URL

    var modrinthURL: URL? {
        guard let slug = slug ?? projectId else { return nil }
        return URL(string: "https://modrinth.com/project/\(slug)")
    }
}

// MARK: - ViewModel extension

extension AppViewModel {

    /// Builds the client export item list for the given server. Safe to call off main.
    /// For modded servers: all mods classified by Modrinth metadata + fabric.mod.json.
    /// For Paper/Purpur: only plugins Modrinth says have a client component.
    func buildClientExportItems(for cfg: ConfigServer) -> [ClientExportItem] {
        guard let addOnKind = cfg.javaFlavor.addOnKind else { return [] }

        let folder = URL(fileURLWithPath: cfg.serverDir, isDirectory: true)
            .appendingPathComponent(addOnKind.folderName, isDirectory: true)
        let fm = FileManager.default

        let urls: [URL] = ((try? fm.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
            .filter {
                let n = $0.lastPathComponent.lowercased()
                return n.hasSuffix(".jar") || n.hasSuffix(".jar.disabled")
            }
        guard !urls.isEmpty else { return [] }

        var items: [ClientExportItem] = []
        for url in urls {
            let filename  = url.lastPathComponent
            let isEnabled = !filename.lowercased().hasSuffix(".jar.disabled")
            let jarStem   = isEnabled
                ? url.deletingPathExtension().lastPathComponent
                : String(filename.dropLast(".jar.disabled".count))

            // Managed plugins (Geyser/Floodgate): skip — bedrock compat, not client mods.
            let stemLower = jarStem.lowercased()
            if stemLower.contains("geyser") || stemLower.contains("floodgate") { continue }

            // Find a persisted Modrinth link by filename.
            let link = cfg.addonLinks?.values.first { $0.installedFileName == filename }
                ?? cfg.addonLinks?.values.first { $0.installedFileName == jarStem + ".jar" }

            let (status, source): (ClientSideStatus, String)
            if let cs = link?.clientSide {
                status = clientSideStatus(from: cs)
                source = "Modrinth"
            } else {
                // Try fabric.mod.json environment for unlinked Fabric mods.
                let meta = ModJarMetadataParser.parse(jarURL: url)
                if let env = meta?.environment {
                    status = clientSideStatus(fromEnvironment: env)
                    source = "mod manifest"
                } else {
                    status = .unknown
                    source = "assumed"
                }
            }

            // For Paper/Purpur, only include items Modrinth explicitly marks as client-needed.
            // Unknown/unlinked plugins are almost always server-only, so we don't show them.
            if addOnKind == .plugin, status == .serverOnly || status == .unknown { continue }

            let displayName = link?.title
                ?? ModJarMetadataParser.parseAny(jarURL: url)?.displayName
                ?? PluginNameParser.extractDisplayName(from: jarStem)

            items.append(ClientExportItem(
                jarStem: jarStem,
                fileName: filename,
                displayName: displayName,
                iconURL: link?.iconURL,
                projectId: link?.projectId,
                slug: link?.slug,
                clientStatus: status,
                statusSource: source,
                isSelected: status.isSelectedByDefault,
                jarURL: url
            ))
        }

        items.sort { a, b in
            let rank: [ClientSideStatus] = [.required, .optional, .unknown, .serverOnly]
            let ra = rank.firstIndex(of: a.clientStatus) ?? 3
            let rb = rank.firstIndex(of: b.clientStatus) ?? 3
            if ra != rb { return ra < rb }
            return a.displayName.lowercased() < b.displayName.lowercased()
        }
        return items
    }

    /// Creates a ZIP of the selected mod JARs and presents a save panel. Modded servers only.
    func exportClientModsAsZip(items: [ClientExportItem], for cfg: ConfigServer) {
        let selected = items.filter { $0.isSelected }
        guard !selected.isEmpty else { return }

        let serverName = cfg.displayName ?? "Server"
        let mcVersion  = cfg.minecraftVersion ?? "mods"
        let zipName    = "\(serverName)-client-\(mcVersion).zip"
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "")

        let panel = NSSavePanel()
        panel.nameFieldStringValue = zipName
        panel.allowedContentTypes  = [UTType.zip]
        panel.begin { [weak self] response in
            guard response == .OK, let dest = panel.url else { return }
            self?.writeZip(items: selected, to: dest, cfg: cfg)
        }
    }

    private func writeZip(items: [ClientExportItem], to dest: URL, cfg: ConfigServer) {
        Task.detached {
            let fm = FileManager.default
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("msc-client-export-\(UUID().uuidString)", isDirectory: true)
            do {
                try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
                for item in items {
                    let target = tmp.appendingPathComponent(item.fileName)
                    try? fm.copyItem(at: item.jarURL, to: target)
                }

                // zip -j: junk paths so JARs are flat in the archive root.
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                process.arguments = ["-j", dest.path] + items.map { tmp.appendingPathComponent($0.fileName).path }
                try process.run()
                process.waitUntilExit()

                try? fm.removeItem(at: tmp)

                if process.terminationStatus == 0 {
                    await MainActor.run {
                        NSWorkspace.shared.activateFileViewerSelecting([dest])
                    }
                } else {
                    await MainActor.run {
                        self.logAppMessage("[Export] zip exited with status \(process.terminationStatus)")
                    }
                }
            } catch {
                try? fm.removeItem(at: tmp)
                await MainActor.run {
                    self.logAppMessage("[Export] Failed to create client mod ZIP: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Copies a plain-text link list to the clipboard. For Paper servers.
    func copyClientLinksToClipboard(items: [ClientExportItem]) {
        let lines = items.filter { $0.isSelected }.map { item -> String in
            let url = item.modrinthURL.map { $0.absoluteString } ?? "(no link)"
            return "• \(item.displayName): \(url)"
        }
        guard !lines.isEmpty else { return }
        let text = lines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Classification helpers

    private func clientSideStatus(from modrinthValue: String) -> ClientSideStatus {
        switch modrinthValue {
        case "required":    return .required
        case "optional":    return .optional
        case "unsupported": return .serverOnly
        default:            return .unknown
        }
    }

    private func clientSideStatus(fromEnvironment env: String) -> ClientSideStatus {
        switch env {
        case "server": return .serverOnly
        case "client": return .required   // shouldn't be server-side, but include for client
        case "*":      return .required
        default:       return .unknown
        }
    }
}

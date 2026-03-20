//
//  AppModels.swift
//  MinecraftServerController
//
//

import Foundation

// MARK: - Models

struct BroadcastAuthPrompt: Identifiable {
    let id = UUID()
    let linkURL: URL
    let code: String
}

/// One-time UX message shown after the very first successful start of a server.
struct FirstStartNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// A user-visible error alert surfaced from any operation that fails silently in the console.
/// Conforms to `Identifiable` so SwiftUI's `alert(item:)` modifier can manage presentation automatically.
struct AppError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

// MARK: - Components (Paper / Cross-play / Broadcast) version tracking

struct ComponentVersionInfo: Equatable {
    var local: String? = nil
    var template: String? = nil
    var online: String? = nil
}

struct ComponentsVersionSnapshot: Equatable {
    var paper: ComponentVersionInfo = ComponentVersionInfo()
    var geyser: ComponentVersionInfo = ComponentVersionInfo()
    var floodgate: ComponentVersionInfo = ComponentVersionInfo()
    var broadcast: ComponentVersionInfo = ComponentVersionInfo()
    var bedrockConnect: ComponentVersionInfo = ComponentVersionInfo()
}

// MARK: - Backup sidecar metadata

/// Codable sidecar written alongside each backup ZIP as <filename>.meta.json.
/// The sidecar is optional — old backups without one are treated as unassociated.
struct BackupMeta: Codable {
    var serverId: String?
    var serverDisplayName: String?
    var slotId: String?
    var slotName: String?
    var worldSeed: String?
    var triggerReason: String
}

struct BackupItem: Identifiable, Hashable {
    let url: URL
    let displayName: String
    let fileSize: Int64?
    let modificationDate: Date?

    // Server + slot association — populated from the sidecar .meta.json when present.
    // Defaults keep all existing init sites source-compatible.
    var serverId: String? = nil
    var serverDisplayName: String? = nil
    var slotId: String? = nil
    var slotName: String? = nil
    /// Reason this backup was created: "auto", "manual", "pre-activation", "pre-replace", etc.
    var triggerReason: String = "manual"

    var id: String { url.path }
    var filename: String { url.lastPathComponent }

    /// Derived from triggerReason for backwards compatibility.
    /// Previously derived from the filename token; now authoritative from triggerReason.
    /// Falls back to filename sniffing for old backups that have no sidecar.
    var isAutomatic: Bool { triggerReason == "auto" }
}

struct PluginTemplateItem: Identifiable, Hashable {
    let url: URL

    var id: String { url.path }
    var filename: String { url.lastPathComponent }
}

struct PaperTemplateItem: Identifiable, Hashable {
    let url: URL

    var id: String { url.path }
    var filename: String { url.lastPathComponent }
}

/// Represents one JAR in the XboxBroadcast or BedrockConnect library folder.
/// The version label is extracted from the filename by splitting on the last "-".
/// e.g. "MCXboxBroadcastStandalone-v3.0.2.jar" → versionLabel = "v3.0.2"
///      "BedrockConnect-1.62.jar"               → versionLabel = "1.62"
struct JarLibraryItem: Identifiable, Hashable {
    let url: URL

    var id: String { url.path }
    var filename: String { url.lastPathComponent }

    /// The version tag extracted from the filename, or nil if unparseable.
    var versionLabel: String? {
        let base = url.deletingPathExtension().lastPathComponent
        guard let dashRange = base.range(of: "-", options: .backwards) else { return nil }
        let version = String(base[base.index(after: dashRange.lowerBound)...])
        return version.isEmpty ? nil : version
    }

    /// Human-readable display title for the UI list row.
    var displayTitle: String {
        versionLabel ?? filename
    }
}


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

// MARK: - Plugin management

/// Which tier of management a discovered plugin has.
enum PluginTier: Int, Comparable {
    case managed    = 0   // Geyser, Floodgate — app knows source natively
    case userSourced = 1  // user has attached a source URL
    case unmanaged  = 2   // JAR on disk, no source

    static func < (lhs: PluginTier, rhs: PluginTier) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Where updates are fetched from for a user-sourced plugin.
enum PluginSourceType: String, Codable, CaseIterable {
    case github    = "github"
    case modrinth  = "modrinth"
    case hangar    = "hangar"
    case direct    = "direct"

    var displayName: String {
        switch self {
        case .github:   return "GitHub Releases"
        case .modrinth: return "Modrinth"
        case .hangar:   return "Hangar"
        case .direct:   return "Direct URL"
        }
    }

    /// SF Symbol for badge icon
    var symbolName: String {
        switch self {
        case .github:   return "chevron.left.forwardslash.chevron.right"
        case .modrinth: return "hexagon"
        case .hangar:   return "shippingbox"
        case .direct:   return "link"
        }
    }
}

/// Persisted source configuration for a user-linked plugin.
struct PluginSourceConfig: Codable, Equatable {
    let url: String
    let type: PluginSourceType
}

/// One plugin JAR discovered on disk (or managed by the app).
struct PluginEntry: Identifiable, Equatable {
    /// Stable key: filename stem with `.disabled` stripped.
    var id: String { jarStem }

    /// Actual filename on disk, e.g. `LuckPerms-Bukkit-5.4.141.jar` or `VaultAPI.jar.disabled`
    let filename: String
    /// Filename without extension and without `.disabled`, e.g. `LuckPerms-Bukkit-5.4.141`
    let jarStem: String
    /// Human-readable name with version stripped, e.g. `LuckPerms-Bukkit`
    let displayName: String
    /// Whether the JAR is active (`.jar`) vs disabled (`.jar.disabled`)
    let isEnabled: Bool
    /// Version parsed from filename, if extractable
    let parsedVersion: String?
    let tier: PluginTier
    var sourceConfig: PluginSourceConfig?
    /// Online version string fetched from the source API
    var onlineVersion: String?
    /// Direct download URL for the latest release (set after online check)
    var onlineDownloadURL: URL?
    var isCheckingOnline: Bool = false
    var isDownloading: Bool = false

    // For managed plugins: mirror of ComponentVersionInfo fields
    var localVersion: String?    // set from componentsSnapshot after refresh
    var templateVersion: String? // set from componentsSnapshot after refresh
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

/// Represents one JAR in the XboxBroadcast library folder.
/// The version label is extracted from the filename by splitting on the last "-".
/// e.g. "MCXboxBroadcastStandalone-v3.0.2.jar" → versionLabel = "v3.0.2"
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


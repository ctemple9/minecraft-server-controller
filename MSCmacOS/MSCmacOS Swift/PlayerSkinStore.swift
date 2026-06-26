// PlayerSkinStore.swift
import AppKit
import Foundation

struct PlayerSkinOverride: Codable {
    var lookupIdentifier: String?   // override for mc-heads.net lookup
    var skinFileName: String?       // filename in player_skins/ dir
}

enum PlayerSkinStore {

    // MARK: - Paths

    static func skinsDirectory(serverDir: String) -> URL {
        URL(fileURLWithPath: serverDir, isDirectory: true)
            .appendingPathComponent("player_skins", isDirectory: true)
    }

    static func overridesFileURL(serverDir: String) -> URL {
        URL(fileURLWithPath: serverDir, isDirectory: true)
            .appendingPathComponent("player_overrides.json")
    }

    // MARK: - Persistence

    static func loadOverrides(serverDir: String) -> [String: PlayerSkinOverride] {
        let url = overridesFileURL(serverDir: serverDir)
        guard let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: PlayerSkinOverride].self, from: data) else {
            return [:]
        }
        return dict
    }

    static func saveOverrides(_ dict: [String: PlayerSkinOverride], serverDir: String) {
        let url = overridesFileURL(serverDir: serverDir)
        guard let data = try? JSONEncoder().encode(dict) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Skin file management

    static func skinFileURL(profileID: String, serverDir: String) -> URL? {
        // Use sanitized profile ID as filename (UUIDs and xuid_ prefixes are already safe)
        let safe = profileID.replacingOccurrences(of: "/", with: "_")
                            .replacingOccurrences(of: ":", with: "_")
        let url = skinsDirectory(serverDir: serverDir).appendingPathComponent("\(safe).png")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Saves the skin image as PNG and returns the filename.
    @discardableResult
    static func saveSkin(_ image: NSImage, profileID: String, serverDir: String) throws -> String {
        let dir = skinsDirectory(serverDir: serverDir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = profileID.replacingOccurrences(of: "/", with: "_")
                            .replacingOccurrences(of: ":", with: "_")
        let filename = "\(safe).png"
        let dest = dir.appendingPathComponent(filename)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "PlayerSkinStore", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not encode skin as PNG."])
        }
        try png.write(to: dest, options: .atomic)
        return filename
    }

    static func deleteSkin(profileID: String, serverDir: String) {
        guard let url = skinFileURL(profileID: profileID, serverDir: serverDir) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Override management

    static func setOverride(_ override: PlayerSkinOverride, profileID: String, serverDir: String) {
        var dict = loadOverrides(serverDir: serverDir)
        dict[profileID] = override
        saveOverrides(dict, serverDir: serverDir)
    }

    static func clearOverride(profileID: String, serverDir: String) {
        var dict = loadOverrides(serverDir: serverDir)
        dict.removeValue(forKey: profileID)
        saveOverrides(dict, serverDir: serverDir)
        deleteSkin(profileID: profileID, serverDir: serverDir)
    }

    // MARK: - Appearance resolution

    /// Returns (effectiveIdentifier, customSkinURL).
    /// customSkinURL takes priority over the lookup identifier override.
    static func resolveAppearance(
        for profile: PlayerProfile,
        serverDir: String
    ) -> (identifier: String, skinURL: URL?) {
        let overrides = loadOverrides(serverDir: serverDir)
        let override = overrides[profile.id]

        // Skin file wins over lookup identifier
        if let skinURL = skinFileURL(profileID: profile.id, serverDir: serverDir) {
            return (profile.imageIdentifier, skinURL)
        }

        if let lookup = override?.lookupIdentifier, !lookup.isEmpty {
            return (lookup, nil)
        }

        return (profile.imageIdentifier, nil)
    }

    static func currentOverride(profileID: String, serverDir: String) -> PlayerSkinOverride? {
        loadOverrides(serverDir: serverDir)[profileID]
    }
}

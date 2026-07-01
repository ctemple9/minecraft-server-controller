//
//  PlayitBinaryManager.swift
//  MinecraftServerController
//
//  Downloads and caches the playitd binary hosted on MSC's own GitHub releases
//  (built from Rust source, signed + notarized). Also writes the playit secret
//  to a chmod-600 file for use with `playitd --secret-path`.
//

import Foundation

enum PlayitBinaryError: LocalizedError {
    case githubAPIFailed(String)
    case noAssetInRelease
    case downloadFailed(String)
    case couldNotSetPermissions(String)

    var errorDescription: String? {
        switch self {
        case .githubAPIFailed(let detail):
            return "Could not reach GitHub to download playitd: \(detail)"
        case .noAssetInRelease:
            return "No 'playitd' asset found in the latest MSC GitHub release. Make sure the release has been published."
        case .downloadFailed(let detail):
            return "playitd download failed: \(detail)"
        case .couldNotSetPermissions(let detail):
            return "Could not make playitd executable: \(detail)"
        }
    }
}

struct PlayitBinaryManager {

    // The MSC GitHub repo where the developer uploads the signed+notarized universal
    // playitd binary (built with `cargo build --release` for aarch64 + x86_64 apple-darwin,
    // then `lipo`d into one universal binary).
    private static let githubOwner = "ctemple9"
    private static let githubRepo  = "minecraft-server-controller"
    private static let assetName   = "playitd"

    // MARK: - Paths

    static var cachedBinaryURL: URL {
        appSupportDir.appendingPathComponent("playitd")
    }

    static var secretFileURL: URL {
        appSupportDir.appendingPathComponent("playit-secret")
    }

    private static var appSupportDir: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MinecraftServerController", isDirectory: true)
    }

    // MARK: - Binary

    /// Returns a ready-to-use `playitd` binary URL, downloading it if not already cached.
    static func ensureBinary() async throws -> URL {
        let dest = cachedBinaryURL
        if FileManager.default.fileExists(atPath: dest.path) {
            return dest
        }
        return try await downloadBinary(to: dest)
    }

    /// Force-replaces the cached binary with the latest version from GitHub.
    static func updateBinary() async throws -> URL {
        let dest = cachedBinaryURL
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        return try await downloadBinary(to: dest)
    }

    private static func downloadBinary(to dest: URL) async throws -> URL {
        let assetURL = try await resolveAssetURL()

        let (tempURL, response): (URL, URLResponse)
        do {
            (tempURL, response) = try await URLSession.shared.download(from: assetURL)
        } catch {
            throw PlayitBinaryError.downloadFailed(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw PlayitBinaryError.downloadFailed("HTTP \(code)")
        }

        let fm = FileManager.default
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.moveItem(at: tempURL, to: dest)

        do {
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
        } catch {
            throw PlayitBinaryError.couldNotSetPermissions(error.localizedDescription)
        }

        return dest
    }

    private static func resolveAssetURL() async throws -> URL {
        guard let apiURL = URL(string: "https://api.github.com/repos/\(githubOwner)/\(githubRepo)/releases/latest") else {
            throw PlayitBinaryError.githubAPIFailed("Invalid API URL")
        }
        var req = URLRequest(url: apiURL)
        req.setValue("MinecraftServerController/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw PlayitBinaryError.githubAPIFailed(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw PlayitBinaryError.githubAPIFailed("HTTP \(code)")
        }

        struct Release: Decodable {
            struct Asset: Decodable {
                let name: String
                let browser_download_url: String
            }
            let assets: [Asset]
        }

        let release: Release
        do {
            release = try JSONDecoder().decode(Release.self, from: data)
        } catch {
            throw PlayitBinaryError.githubAPIFailed("Could not parse release JSON: \(error.localizedDescription)")
        }

        guard let asset = release.assets.first(where: { $0.name == assetName }),
              let url = URL(string: asset.browser_download_url) else {
            throw PlayitBinaryError.noAssetInRelease
        }
        return url
    }

    // MARK: - Secret file

    /// Writes the playit secret key to a chmod-600 file and returns its URL.
    /// The file is passed to `playitd --secret-path <file>`.
    static func writeSecretFile(_ secret: String) throws -> URL {
        let fileURL = secretFileURL
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = Data((secret.trimmingCharacters(in: .whitespacesAndNewlines) + "\n").utf8)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        return fileURL
    }
}

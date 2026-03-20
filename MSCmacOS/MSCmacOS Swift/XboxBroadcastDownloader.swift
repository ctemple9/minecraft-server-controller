//
//  XboxBroadcastDownloader.swift
//  MinecraftServerController
//
//  Downloads MCXboxBroadcastStandalone.jar from GitHub releases.
//

import Foundation

enum XboxBroadcastDownloadError: LocalizedError {
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let message):
            return message
        }
    }
}

struct XboxBroadcastDownloader {

    /// Latest MCXboxBroadcastStandalone.jar from GitHub releases.
    /// See: https://github.com/MCXboxBroadcast/Broadcaster
    /// Pattern: /releases/latest/download/MCXboxBroadcastStandalone.jar
    private static let downloadURL = URL(
        string: "https://github.com/MCXboxBroadcast/Broadcaster/releases/latest/download/MCXboxBroadcastStandalone.jar"
    )!

    /// Download or update the standalone JAR to `destinationURL`.
    ///
    /// - destinationURL example:
    ///   ~/Library/Application Support/MinecraftServerController/MCXboxBroadcastStandalone.jar
    static func downloadStandaloneJar(to destinationURL: URL) async throws -> String? {
        let fm = FileManager.default

        // Ensure destination directory exists
        let destDir = destinationURL.deletingLastPathComponent()
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

        // 1) Ask GitHub "releases/latest" for tag + asset URL (so we KNOW the version)
        struct LatestRelease: Decodable {
            struct Asset: Decodable {
                let name: String
                let browser_download_url: String
            }
            let tag_name: String
            let assets: [Asset]
        }

        let apiURL = URL(string: "https://api.github.com/repos/MCXboxBroadcast/Broadcaster/releases/latest")!

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(from: apiURL)
        } catch {
            throw XboxBroadcastDownloadError.invalidResponse("GitHub API request failed: \(error.localizedDescription)")
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw XboxBroadcastDownloadError.invalidResponse("GitHub API HTTP status \(code)")
        }

        let decoded: LatestRelease
        do {
            decoded = try JSONDecoder().decode(LatestRelease.self, from: data)
        } catch {
            throw XboxBroadcastDownloadError.invalidResponse("Failed to decode GitHub release JSON: \(error.localizedDescription)")
        }

        let tag = decoded.tag_name.trimmingCharacters(in: .whitespacesAndNewlines)
        let assetURL: URL = {
            if let asset = decoded.assets.first(where: { $0.name == "MCXboxBroadcastStandalone.jar" }),
               let url = URL(string: asset.browser_download_url) {
                return url
            }
            // Fallback (should rarely happen)
            return downloadURL
        }()

        // 2) Download the jar
        let (tempURL, jarResponse) = try await URLSession.shared.download(from: assetURL)
        guard let jarHTTP = jarResponse as? HTTPURLResponse,
              (200..<300).contains(jarHTTP.statusCode) else {
            let code = (jarResponse as? HTTPURLResponse)?.statusCode ?? -1
            throw XboxBroadcastDownloadError.invalidResponse("JAR download HTTP status \(code)")
        }

        // Replace any existing file
        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }

        try fm.moveItem(at: tempURL, to: destinationURL)

        return tag.isEmpty ? nil : tag
    }
}


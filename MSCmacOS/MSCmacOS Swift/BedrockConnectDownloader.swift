//
//  BedrockConnectDownloader.swift
//  MinecraftServerController
//
//  Downloads BedrockConnect.jar from GitHub releases.
//  https://github.com/Pugmatt/BedrockConnect/releases
//

import Foundation

enum BedrockConnectDownloadError: LocalizedError {
    case invalidResponse(String)
    case noJarAssetFound

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let message):
            return message
        case .noJarAssetFound:
            return "No .jar asset found in the latest BedrockConnect release."
        }
    }
}

struct BedrockConnectDownloader {

    private static let apiURL = URL(
        string: "https://api.github.com/repos/Pugmatt/BedrockConnect/releases/latest"
    )!

    /// Download the latest BedrockConnect JAR to `destinationURL`.
    /// Returns the release tag string (e.g. "1.62") on success, or nil if unavailable.
    static func downloadLatestJar(to destinationURL: URL) async throws -> String? {
        let fm = FileManager.default

        // Ensure destination directory exists
        let destDir = destinationURL.deletingLastPathComponent()
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

        // 1) Fetch latest release metadata from GitHub
        struct LatestRelease: Decodable {
            struct Asset: Decodable {
                let name: String
                let browser_download_url: String
            }
            let tag_name: String
            let assets: [Asset]
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(from: apiURL)
        } catch {
            throw BedrockConnectDownloadError.invalidResponse(
                "GitHub API request failed: \(error.localizedDescription)"
            )
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw BedrockConnectDownloadError.invalidResponse("GitHub API HTTP status \(code)")
        }

        let decoded: LatestRelease
        do {
            decoded = try JSONDecoder().decode(LatestRelease.self, from: data)
        } catch {
            throw BedrockConnectDownloadError.invalidResponse(
                "Failed to decode GitHub release JSON: \(error.localizedDescription)"
            )
        }

        let tag = decoded.tag_name.trimmingCharacters(in: .whitespacesAndNewlines)

        // 2) Find the first .jar asset in the release
        guard let jarAsset = decoded.assets.first(where: { $0.name.hasSuffix(".jar") }),
              let assetURL = URL(string: jarAsset.browser_download_url) else {
            throw BedrockConnectDownloadError.noJarAssetFound
        }

        // 3) Download the JAR
        let (tempURL, jarResponse) = try await URLSession.shared.download(from: assetURL)
        guard let jarHTTP = jarResponse as? HTTPURLResponse,
              (200..<300).contains(jarHTTP.statusCode) else {
            let code = (jarResponse as? HTTPURLResponse)?.statusCode ?? -1
            throw BedrockConnectDownloadError.invalidResponse("JAR download HTTP status \(code)")
        }

        // Replace any existing file at the destination
        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }
        try fm.moveItem(at: tempURL, to: destinationURL)

        return tag.isEmpty ? nil : tag
    }
}

//
//  PluginDownloader.swift
//  MinecraftServerController
//
//  Downloads the latest Geyser / Floodgate Spigot builds directly into a
//  destination URL. No metadata JSON parsing – it just grabs "latest".
//

import Foundation

enum PluginDownloadError: Error {
    case networkError(String)
    case cannotCreateFile
}

struct PluginDownloadResult {
    let version: String   // we don't know the exact version; "latest"
    let build: Int        // we don't know the build; 0 as a placeholder
}

/// Download the latest Geyser Spigot JAR to `destURL`.
/// Uses the public "latest" endpoint and streams the file straight to disk.
enum PluginDownloader {
    
    // Metadata for the "latest" build of a plugin
    private static func fetchLatestBuildInfo(project: String) async throws -> PluginDownloadResult {
        guard let metaURL = URL(string: "https://download.geysermc.org/v2/projects/\(project)/versions/latest/builds/latest") else {
            throw PluginDownloadError.networkError("Invalid metadata URL for \(project).")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(from: metaURL)
        } catch {
            throw PluginDownloadError.networkError("Network error while loading \(project) metadata: \(error.localizedDescription)")
        }

        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw PluginDownloadError.networkError("Server returned status \(code) for \(project) metadata.")
        }

        struct LatestBuildResponse: Decodable {
            let version: String
            let build: Int
        }

        do {
            let info = try JSONDecoder().decode(LatestBuildResponse.self, from: data)
            return PluginDownloadResult(version: info.version, build: info.build)
        } catch {
            throw PluginDownloadError.networkError("Failed to decode \(project) metadata: \(error.localizedDescription)")
        }
    }

    // MARK: - Metadata-only helpers (no download)

    static func fetchLatestGeyserBuildInfo() async throws -> PluginDownloadResult {
        try await fetchLatestBuildInfo(project: "geyser")
    }

    static func fetchLatestFloodgateBuildInfo() async throws -> PluginDownloadResult {
        try await fetchLatestBuildInfo(project: "floodgate")
    }

    static func downloadLatestGeyser(to destURL: URL) async throws -> PluginDownloadResult {
        // 1) Ask API what the latest version + build are
        let info = try await fetchLatestBuildInfo(project: "geyser")

        // 2) Download that specific build
        guard let url = URL(string: "https://download.geysermc.org/v2/projects/geyser/versions/\(info.version)/builds/\(info.build)/downloads/spigot") else {
            throw PluginDownloadError.networkError("Invalid Geyser download URL.")
        }

        try await downloadPlugin(from: url,
                                 to: destURL,
                                 pluginName: "Geyser")

        // 3) Return real version/build to the caller
        return info
    }

    

    /// Download the latest Floodgate Spigot JAR to `destURL`.
    static func downloadLatestFloodgate(to destURL: URL) async throws -> PluginDownloadResult {
        let info = try await fetchLatestBuildInfo(project: "floodgate")

        guard let url = URL(string: "https://download.geysermc.org/v2/projects/floodgate/versions/\(info.version)/builds/\(info.build)/downloads/spigot") else {
            throw PluginDownloadError.networkError("Invalid Floodgate download URL.")
        }

        try await downloadPlugin(from: url,
                                 to: destURL,
                                 pluginName: "Floodgate")

        return info
    }

    // MARK: - Internal helper
    private static func downloadPlugin(
        from url: URL,
        to destURL: URL,
        pluginName: String
    ) async throws {

        let (tempLocation, response): (URL, URLResponse)
        do {
            (tempLocation, response) = try await URLSession.shared.download(from: url)
        } catch {
            throw PluginDownloadError.networkError("Network error while downloading \(pluginName): \(error.localizedDescription)")
        }

        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw PluginDownloadError.networkError("Server returned status \(code) for \(pluginName) download.")
        }

        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: destURL.path) {
                try fm.removeItem(at: destURL)
            }
            try fm.moveItem(at: tempLocation, to: destURL)
        } catch {
            throw PluginDownloadError.cannotCreateFile
        }
    }

    
}


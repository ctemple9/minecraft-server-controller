//
//  ModrinthAPI.swift
//  MinecraftServerController
//
//  Fetches the latest plugin version and download URL from Modrinth.
//  API docs: https://docs.modrinth.com
//

import Foundation

enum ModrinthAPIError: Error, LocalizedError {
    case invalidURL
    case networkError(String)
    case noCompatibleVersion
    case noJarAsset
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:               return "Invalid Modrinth URL."
        case .networkError(let m):      return m
        case .noCompatibleVersion:      return "No compatible version found on Modrinth."
        case .noJarAsset:               return "Modrinth release has no JAR download."
        case .decodingError(let m):     return "Modrinth response error: \(m)"
        }
    }
}

enum ModrinthAPI {

    /// Fetches the latest Paper-compatible release for a Modrinth project.
    /// - Parameters:
    ///   - slug:      Modrinth project slug or ID, e.g. "luckperms"
    ///   - mcVersion: Minecraft version string, e.g. "1.21.4"
    static func fetchLatest(
        slug: String,
        mcVersion: String
    ) async throws -> (version: String, downloadURL: URL) {

        // Build query: Paper loader, specific MC version, release channel, latest first
        var components = URLComponents(string: "https://api.modrinth.com/v2/project/\(slug)/version")!
        components.queryItems = [
            URLQueryItem(name: "loaders",       value: "[\"paper\",\"spigot\",\"bukkit\"]"),
            URLQueryItem(name: "game_versions", value: "[\"\(mcVersion)\"]"),
        ]

        guard let url = components.url else { throw ModrinthAPIError.invalidURL }

        let (data, response): (Data, URLResponse)
        do {
            var request = URLRequest(url: url)
            request.setValue("MinecraftServerController/1.0", forHTTPHeaderField: "User-Agent")
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ModrinthAPIError.networkError("Network error fetching Modrinth versions: \(error.localizedDescription)")
        }

        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ModrinthAPIError.networkError("Modrinth returned status \(code) for \(slug).")
        }

        struct ModrinthVersion: Decodable {
            let versionNumber: String
            struct File: Decodable {
                let url: String
                let filename: String
                let primary: Bool
            }
            let files: [File]

            enum CodingKeys: String, CodingKey {
                case versionNumber = "version_number"
                case files
            }
        }

        let versions: [ModrinthVersion]
        do {
            versions = try JSONDecoder().decode([ModrinthVersion].self, from: data)
        } catch {
            throw ModrinthAPIError.decodingError(error.localizedDescription)
        }

        guard let latest = versions.first else {
            throw ModrinthAPIError.noCompatibleVersion
        }

        // Prefer primary file, fall back to first JAR
        let jarFile = latest.files.first(where: { $0.primary && $0.filename.hasSuffix(".jar") })
            ?? latest.files.first(where: { $0.filename.hasSuffix(".jar") })

        guard let file = jarFile, let downloadURL = URL(string: file.url) else {
            throw ModrinthAPIError.noJarAsset
        }

        return (version: latest.versionNumber, downloadURL: downloadURL)
    }
}

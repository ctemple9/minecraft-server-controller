//
//  HangarAPI.swift
//  MinecraftServerController
//
//  Fetches the latest plugin version and download URL from PaperMC's Hangar repository.
//  API docs: https://hangar.papermc.io/api-docs
//

import Foundation

enum HangarAPIError: Error, LocalizedError {
    case invalidURL
    case networkError(String)
    case noCompatibleVersion
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:               return "Invalid Hangar URL."
        case .networkError(let m):      return m
        case .noCompatibleVersion:      return "No compatible version found on Hangar."
        case .decodingError(let m):     return "Hangar response error: \(m)"
        }
    }
}

enum HangarAPI {

    /// Fetches the latest release version and a direct JAR download URL for a Hangar plugin.
    /// - Parameters:
    ///   - author:    Hangar author/namespace, e.g. "EssentialsX"
    ///   - slug:      Hangar project slug, e.g. "Essentials"
    ///   - mcVersion: Minecraft version string for compatibility filtering, e.g. "1.21.4"
    static func fetchLatest(
        author: String,
        slug: String,
        mcVersion: String
    ) async throws -> (version: String, downloadURL: URL) {

        // 1. Fetch version list filtered by MC version and Paper platform
        let escapedMC = mcVersion.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? mcVersion
        let listURLString = "https://hangar.papermc.io/api/v1/projects/\(author)/\(slug)/versions"
            + "?platform=PAPER&platformVersion=\(escapedMC)&channel=Release&limit=1&offset=0"

        guard let listURL = URL(string: listURLString) else { throw HangarAPIError.invalidURL }

        let (listData, listResponse): (Data, URLResponse)
        do {
            (listData, listResponse) = try await URLSession.shared.data(from: listURL)
        } catch {
            throw HangarAPIError.networkError("Network error fetching Hangar versions: \(error.localizedDescription)")
        }

        guard let httpList = listResponse as? HTTPURLResponse,
              (200..<300).contains(httpList.statusCode) else {
            let code = (listResponse as? HTTPURLResponse)?.statusCode ?? -1
            throw HangarAPIError.networkError("Hangar returned status \(code) for \(author)/\(slug).")
        }

        struct HangarVersionsResponse: Decodable {
            struct VersionEntry: Decodable {
                let name: String
                struct PlatformDownload: Decodable {
                    struct DownloadInfo: Decodable {
                        let downloadUrl: String?
                    }
                    let PAPER: DownloadInfo?
                }
                let downloads: PlatformDownload
            }
            let result: [VersionEntry]
        }

        let parsed: HangarVersionsResponse
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .useDefaultKeys
            parsed = try decoder.decode(HangarVersionsResponse.self, from: listData)
        } catch {
            throw HangarAPIError.decodingError(error.localizedDescription)
        }

        guard let first = parsed.result.first else {
            throw HangarAPIError.noCompatibleVersion
        }

        // 2. Resolve download URL — use the API-provided URL if available,
        //    otherwise fall back to the standard download endpoint.
        let downloadURLString: String
        if let apiURL = first.downloads.PAPER?.downloadUrl, !apiURL.isEmpty {
            downloadURLString = apiURL
        } else {
            let encodedVersion = first.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? first.name
            downloadURLString = "https://hangar.papermc.io/api/v1/projects/\(author)/\(slug)/versions/\(encodedVersion)/PAPER/download"
        }

        guard let downloadURL = URL(string: downloadURLString) else {
            throw HangarAPIError.invalidURL
        }

        return (version: first.name, downloadURL: downloadURL)
    }
}

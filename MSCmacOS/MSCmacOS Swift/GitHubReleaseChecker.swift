//  GitHubReleaseChecker.swift
//  MinecraftServerController
//
//  Small helper for on-demand "Check Online" version lookups.

import Foundation

enum GitHubReleaseCheckerError: LocalizedError {
    case invalidURL
    case networkError(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid GitHub API URL."
        case .networkError(let message):
            return "Network error while talking to GitHub: \(message)"
        case .invalidResponse(let message):
            return "Invalid response from GitHub: \(message)"
        }
    }
}

struct GitHubReleaseChecker {

    // MARK: - Shared fetch helper

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
            let content_type: String
        }
    }

    private static func fetchRelease(owner: String, repo: String) async throws -> GitHubRelease {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest") else {
            throw GitHubReleaseCheckerError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("MinecraftServerController/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw GitHubReleaseCheckerError.networkError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw GitHubReleaseCheckerError.invalidResponse("No HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GitHubReleaseCheckerError.invalidResponse("HTTP \(http.statusCode)")
        }

        do {
            return try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            throw GitHubReleaseCheckerError.invalidResponse("Could not decode JSON: \(error.localizedDescription)")
        }
    }

    // MARK: - Public API

    /// Fetches the latest GitHub release tag for the repo.
    /// Example: owner="MCXboxBroadcast", repo="Broadcaster" → "v1.2.3"
    static func fetchLatestReleaseTag(owner: String, repo: String) async throws -> String {
        let release = try await fetchRelease(owner: owner, repo: repo)
        return release.tag_name
    }

    /// Fetches the latest release tag AND the download URL of the first JAR asset found.
    /// - Returns: `(tag, jarDownloadURL)` where `jarDownloadURL` is nil if no JAR asset exists.
    static func fetchLatestRelease(
        owner: String,
        repo: String
    ) async throws -> (tag: String, jarDownloadURL: URL?) {
        let release = try await fetchRelease(owner: owner, repo: repo)

        let jarAsset = release.assets.first(where: { asset in
            asset.name.lowercased().hasSuffix(".jar")
        })

        let downloadURL = jarAsset.flatMap { URL(string: $0.browser_download_url) }
        return (tag: release.tag_name, jarDownloadURL: downloadURL)
    }
}

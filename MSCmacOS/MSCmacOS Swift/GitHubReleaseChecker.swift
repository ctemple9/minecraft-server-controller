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

    /// Fetches the latest GitHub release tag for the repo.
    /// Example: owner="MCXboxBroadcast", repo="Broadcaster" → "v1.2.3"
    static func fetchLatestReleaseTag(owner: String, repo: String) async throws -> String {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest") else {
            throw GitHubReleaseCheckerError.invalidURL
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(from: url)
        } catch {
            throw GitHubReleaseCheckerError.networkError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw GitHubReleaseCheckerError.invalidResponse("No HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GitHubReleaseCheckerError.invalidResponse("HTTP \(http.statusCode)")
        }

        struct LatestReleaseResponse: Decodable {
            let tag_name: String
        }

        do {
            let decoded = try JSONDecoder().decode(LatestReleaseResponse.self, from: data)
            return decoded.tag_name
        } catch {
            throw GitHubReleaseCheckerError.invalidResponse("Could not decode JSON: \(error.localizedDescription)")
        }
    }
}

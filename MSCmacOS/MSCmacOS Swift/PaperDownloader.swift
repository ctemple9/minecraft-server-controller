//
//  PaperDownloader.swift
//

import Foundation

struct PaperDownloadResult {
    let localURL: URL
    let version: String
    let build: Int
}

enum PaperDownloadError: LocalizedError {
    case networkError(String)
    case invalidResponse(String)
    case cannotCreateFile(String)

    var errorDescription: String? {
        switch self {
        case .networkError(let msg):
            return "Network error while talking to PaperMC API: \(msg)"
        case .invalidResponse(let msg):
            return "Invalid response from PaperMC API: \(msg)"
        case .cannotCreateFile(let msg):
            return "Could not save downloaded Paper JAR: \(msg)"
        }
    }
}

struct PaperDownloader {

    /// Fetches the latest *stable* Paper version + build metadata.
    /// Uses PaperMC's Downloads Service (Fill) v3 API:
    ///   - GET https://fill.papermc.io/v3/projects/paper
    ///   - GET https://fill.papermc.io/v3/projects/paper/versions/{version}/builds
    static func fetchLatestMetadata() async throws -> (version: String, build: Int, downloadURL: URL) {
        do {
            // 1) Get all versions (flattened across version groups)
            let versionsURL = URL(string: "https://fill.papermc.io/v3/projects/paper")!
            let (data, response) = try await URLSession.shared.data(from: versionsURL)

            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw PaperDownloadError.networkError("Versions request failed with status \(http.statusCode).")
            }

            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw PaperDownloadError.invalidResponse("Projects JSON root was not a dictionary.")
            }

            // Fill v3 returns versions grouped (object of arrays). Flatten those into a single list.
            var allVersions: [String] = []
            if let versionsByGroup = root["versions"] as? [String: Any] {
                for (_, listAny) in versionsByGroup {
                    if let list = listAny as? [Any] {
                        allVersions.append(contentsOf: list.compactMap { $0 as? String })
                    }
                }
            }

            // Fallback: some responses may include a flat `versions` array.
            if allVersions.isEmpty, let flat = root["versions"] as? [Any] {
                allVersions = flat.compactMap { $0 as? String }
            }

            guard !allVersions.isEmpty else {
                throw PaperDownloadError.invalidResponse("Missing or empty 'versions' list.")
            }

            // Prefer latest stable version: digits + dots only.
            let stableVersions: [String] = allVersions.filter { v in
                v.range(of: #"^[0-9]+(\.[0-9]+)*$"#, options: .regularExpression) != nil
            }

            guard !stableVersions.isEmpty else {
                throw PaperDownloadError.invalidResponse("No stable (numeric) versions were returned.")
            }

            // Pick the numerically highest semantic-ish version.
            let chosenVersion = stableVersions.max(by: { lhs, rhs in
                compareMinecraftVersions(lhs, rhs) == .orderedAscending
            }) ?? stableVersions.last!

            // 2) Get builds for that version (Fill v3)
            let buildsURL = URL(string: "https://fill.papermc.io/v3/projects/paper/versions/\(chosenVersion)/builds")!
            let (buildData, buildResponse) = try await URLSession.shared.data(from: buildsURL)

            if let http = buildResponse as? HTTPURLResponse, http.statusCode != 200 {
                throw PaperDownloadError.networkError("Builds request for \(chosenVersion) failed with status \(http.statusCode).")
            }

            guard let buildsAny = try JSONSerialization.jsonObject(with: buildData) as? [Any], !buildsAny.isEmpty else {
                throw PaperDownloadError.invalidResponse("Missing or empty builds list for version \(chosenVersion).")
            }

            // Find latest STABLE build.
            var bestStableBuildId: Int?
            var bestStableURL: URL?

            for entryAny in buildsAny {
                guard let entry = entryAny as? [String: Any] else { continue }
                guard let channel = entry["channel"] as? String, channel.uppercased() == "STABLE" else { continue }

                let id: Int?
                if let i = entry["id"] as? Int {
                    id = i
                } else if let n = entry["id"] as? NSNumber {
                    id = n.intValue
                } else {
                    id = nil
                }
                guard let buildId = id else { continue }

                // Pull URL if provided.
                var candidateURL: URL?
                if let downloads = entry["downloads"] as? [String: Any],
                   let serverDefault = downloads["server:default"] as? [String: Any],
                   let urlString = serverDefault["url"] as? String,
                   let u = URL(string: urlString) {
                    candidateURL = u
                }

                if bestStableBuildId == nil || buildId > bestStableBuildId! {
                    bestStableBuildId = buildId
                    bestStableURL = candidateURL
                }
            }

            guard let latestBuild = bestStableBuildId else {
                let snippet = String(data: buildData, encoding: .utf8) ?? "<non-UTF8>"
                throw PaperDownloadError.invalidResponse("Could not find a STABLE build entry for version \(chosenVersion). Raw: \(snippet)")
            }

            // If the API didn't include a direct URL (should, but be defensive), fall back to the v2 style URL.
            let downloadURL: URL
            if let u = bestStableURL {
                downloadURL = u
            } else {
                let fileName = "paper-\(chosenVersion)-\(latestBuild).jar"
                downloadURL = URL(string: "https://api.papermc.io/v2/projects/paper/versions/\(chosenVersion)/builds/\(latestBuild)/downloads/\(fileName)")!
            }

            return (version: chosenVersion, build: latestBuild, downloadURL: downloadURL)
        } catch let error as PaperDownloadError {
            throw error
        } catch {
            throw PaperDownloadError.networkError(error.localizedDescription)
        }
    }

    /// Downloads the latest Paper JAR to the given destination URL.
    static func downloadLatestPaper(to destination: URL) async throws -> PaperDownloadResult {
        let meta = try await fetchLatestMetadata()

        do {
            let (data, response) = try await URLSession.shared.data(from: meta.downloadURL)

            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw PaperDownloadError.networkError("Download request failed with status \(http.statusCode) for \(meta.version) build \(meta.build).")
            }

            do {
                try data.write(to: destination, options: [.atomic])
            } catch {
                throw PaperDownloadError.cannotCreateFile(error.localizedDescription)
            }

            return PaperDownloadResult(
                localURL: destination,
                version: meta.version,
                build: meta.build
            )
        } catch let error as PaperDownloadError {
            throw error
        } catch {
            throw PaperDownloadError.networkError(error.localizedDescription)
        }
    }
}

// MARK: - Version comparison

private func compareMinecraftVersions(_ a: String, _ b: String) -> ComparisonResult {
    // Compare versions like "1.21.11" by numeric components.
    let aParts = a.split(separator: ".").compactMap { Int($0) }
    let bParts = b.split(separator: ".").compactMap { Int($0) }

    let maxCount = max(aParts.count, bParts.count)
    for i in 0..<maxCount {
        let av = i < aParts.count ? aParts[i] : 0
        let bv = i < bParts.count ? bParts[i] : 0
        if av < bv { return .orderedAscending }
        if av > bv { return .orderedDescending }
    }
    return .orderedSame
}


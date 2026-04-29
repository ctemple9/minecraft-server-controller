//
//  PaperDownloader.swift
//

import Foundation

// MARK: - Version Option

/// A specific Paper build available for download, shown in the Components tab version list.
struct PaperVersionOption: Identifiable, Equatable {
    var id: String { "\(version)-\(build)" }
    let version: String         // e.g. "1.21.11" or "26.1.2"
    let build: Int              // e.g. 127
    let channel: String         // "STABLE", "BETA", or "ALPHA"
    let downloadURL: URL
    let formattedDate: String?  // e.g. "Apr 24, 2026"

    var displayString: String { "\(version) (build \(build))" }
    var isStable: Bool { channel.uppercased() == "STABLE" }
}

// MARK: - Download Result

struct PaperDownloadResult {
    let localURL: URL
    let version: String
    let build: Int
}

// MARK: - Errors

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

// MARK: - Downloader

struct PaperDownloader {

    // MARK: - Public API

    /// Returns up to `limit` available Paper builds for the requested track, sorted
    /// newest-first.
    ///
    /// - When `includeExperimental` is `false` (default): only STABLE channel builds are
    ///   returned — these are the standard 1.x.x Minecraft release versions.
    /// - When `includeExperimental` is `true`: only BETA and ALPHA builds are returned —
    ///   these are snapshot/development versions such as 26.x.x. Required for console
    ///   crossplay when the Bedrock client is on the latest Minecraft snapshot.
    ///
    /// Versions are walked highest-to-lowest numerically. The first qualifying build found
    /// for each version is collected until `limit` results are gathered or candidates run
    /// out. This means if a high version number (e.g. 26.x.x) has no STABLE builds, the
    /// selector automatically falls back to the next lower version (e.g. 1.21.11), fixing
    /// the crash that occurred when PaperMC added 26.x.x to their API.
    static func fetchAvailableVersions(
        includeExperimental: Bool,
        limit: Int = 5
    ) async throws -> [PaperVersionOption] {
        let sortedVersions = try await fetchAllVersionsSorted()

                // For the experimental track, only versions numerically above the current
                // stable ceiling qualify. This excludes old abandoned pre-release dev builds
                // (e.g. a 1.21.9-rc that never shipped a STABLE build) which would otherwise
                // pass the "no STABLE build" filter but are not useful experimental targets.
                let candidates: [String]
                if includeExperimental {
                    let stableCeiling = try await findStableCeiling(from: sortedVersions)
                    if let ceiling = stableCeiling {
                        candidates = sortedVersions.filter {
                            compareMinecraftVersions($0, ceiling) == .orderedDescending
                        }
                    } else {
                        candidates = sortedVersions
                    }
                } else {
                    candidates = sortedVersions
                }

                var results: [PaperVersionOption] = []
                let maxCandidates = 20
                var tried = 0

                for version in candidates {
            guard tried < maxCandidates, results.count < limit else { break }
            tried += 1

            if let option = try await fetchBestBuild(
                forVersion: version,
                includeExperimental: includeExperimental
            ) {
                results.append(option)
            }
        }

        return results
    }

    /// Returns metadata for the single latest stable Paper build.
    /// Used by the Create Server wizard and template-download flows.
    static func fetchLatestMetadata() async throws -> (version: String, build: Int, downloadURL: URL) {
        let versions = try await fetchAvailableVersions(includeExperimental: false, limit: 1)
        guard let first = versions.first else {
            throw PaperDownloadError.invalidResponse("No stable Paper builds found.")
        }
        return (version: first.version, build: first.build, downloadURL: first.downloadURL)
    }

    /// Downloads a specific Paper build to the given destination URL.
    /// Used by the Components tab version picker.
    static func downloadPaper(
        option: PaperVersionOption,
        to destination: URL
    ) async throws -> PaperDownloadResult {
        do {
            let (data, response) = try await URLSession.shared.data(from: option.downloadURL)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw PaperDownloadError.networkError(
                    "Download failed with status \(http.statusCode) for \(option.version) build \(option.build)."
                )
            }
            do {
                try data.write(to: destination, options: [.atomic])
            } catch {
                throw PaperDownloadError.cannotCreateFile(error.localizedDescription)
            }
            return PaperDownloadResult(
                localURL: destination,
                version: option.version,
                build: option.build
            )
        } catch let e as PaperDownloadError { throw e }
        catch { throw PaperDownloadError.networkError(error.localizedDescription) }
    }

    /// Downloads the latest stable Paper JAR to the given destination URL.
    /// Used by template-download and Create Server flows.
    static func downloadLatestPaper(to destination: URL) async throws -> PaperDownloadResult {
        let versions = try await fetchAvailableVersions(includeExperimental: false, limit: 1)
        guard let latest = versions.first else {
            throw PaperDownloadError.invalidResponse("No stable Paper builds found.")
        }
        return try await downloadPaper(option: latest, to: destination)
    }

    // MARK: - Private Helpers

    /// Fetches all available Paper versions from the PaperMC API and returns them sorted
    /// highest-to-lowest (numerically by version components).
    private static func fetchAllVersionsSorted() async throws -> [String] {
        let url = URL(string: "https://fill.papermc.io/v3/projects/paper")!
        let (data, response) = try await URLSession.shared.data(from: url)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw PaperDownloadError.networkError(
                "Versions request failed with status \(http.statusCode)."
            )
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PaperDownloadError.invalidResponse("Projects JSON root was not a dictionary.")
        }

        var allVersions: [String] = []
        if let versionsByGroup = root["versions"] as? [String: Any] {
            for (_, listAny) in versionsByGroup {
                if let list = listAny as? [Any] {
                    allVersions.append(contentsOf: list.compactMap { $0 as? String })
                }
            }
        }
        if allVersions.isEmpty, let flat = root["versions"] as? [Any] {
            allVersions = flat.compactMap { $0 as? String }
        }

        guard !allVersions.isEmpty else {
            throw PaperDownloadError.invalidResponse("Missing or empty 'versions' list.")
        }

        return allVersions.sorted { compareMinecraftVersions($0, $1) == .orderedDescending }
    }

    /// Fetches builds for a single version and returns the best qualifying build, or `nil`
    /// if no builds on the requested track exist for this version.
    ///
    /// Non-200 HTTP responses are treated as "skip this version" rather than errors, so a
    /// bad version in the list doesn't abort the whole fetch.
    private static func fetchBestBuild(
        forVersion version: String,
        includeExperimental: Bool
    ) async throws -> PaperVersionOption? {
        let url = URL(string: "https://fill.papermc.io/v3/projects/paper/versions/\(version)/builds")!

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(from: url)
        } catch {
            throw PaperDownloadError.networkError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }

        guard let buildsAny = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return nil
        }

        var hasStableBuild = false
                var bestId: Int? = nil
                var bestOption: PaperVersionOption? = nil

                for entryAny in buildsAny {
                    guard let entry = entryAny as? [String: Any],
                          let channel = entry["channel"] as? String else { continue }

                    let channelUpper = channel.uppercased()
                    if channelUpper == "STABLE" { hasStableBuild = true }

                    let qualifies: Bool = includeExperimental
                ? (channelUpper == "BETA" || channelUpper == "ALPHA")
                : (channelUpper == "STABLE")
            guard qualifies else { continue }

            let buildId: Int
            if let i = entry["id"] as? Int { buildId = i }
            else if let n = entry["id"] as? NSNumber { buildId = n.intValue }
            else { continue }

            guard let downloads = entry["downloads"] as? [String: Any],
                  let serverDefault = downloads["server:default"] as? [String: Any],
                  let urlString = serverDefault["url"] as? String,
                  let downloadURL = URL(string: urlString) else { continue }

            let formattedDate = (entry["time"] as? String).flatMap { formatBuildDate($0) }

            if bestId == nil || buildId > bestId! {
                bestId = buildId
                bestOption = PaperVersionOption(
                    version: version,
                    build: buildId,
                    channel: channelUpper,
                    downloadURL: downloadURL,
                    formattedDate: formattedDate
                )
            }
        }

        // For the experimental track, skip any version that also has STABLE builds.
                // Release versions (e.g. 1.21.x) had BETA/ALPHA builds during development
                // but also have STABLE builds. True experimental versions (e.g. 26.x.x)
                // have never shipped a STABLE build.
                if includeExperimental && hasStableBuild {
                    return nil
                }

                return bestOption
            }

    /// Returns the highest version string that has at least one STABLE build.
        /// Used as a ceiling when filtering the experimental track — true experimental
        /// versions sit numerically above this ceiling.
        private static func findStableCeiling(from sortedVersions: [String]) async throws -> String? {
            for version in sortedVersions.prefix(15) {
                if let option = try await fetchBestBuild(
                    forVersion: version,
                    includeExperimental: false
                ) {
                    return option.version
                }
            }
            return nil
        }

    private static func formatBuildDate(_ iso: String) -> String? {
            let withFractional = ISO8601DateFormatter()
            withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            let withoutFractional = ISO8601DateFormatter()
            withoutFractional.formatOptions = [.withInternetDateTime]

            guard let date = withFractional.date(from: iso) ?? withoutFractional.date(from: iso)
            else { return nil }

            let display = DateFormatter()
            display.dateStyle = .medium
            display.timeStyle = .none
            return display.string(from: date)
        }
}

// MARK: - Version Comparison

private func compareMinecraftVersions(_ a: String, _ b: String) -> ComparisonResult {
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

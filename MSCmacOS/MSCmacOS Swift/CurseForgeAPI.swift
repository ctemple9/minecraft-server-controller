//
//  CurseForgeAPI.swift
//  MinecraftServerController
//
//  P7.10: minimal client for the OFFICIAL CurseForge API (api.curseforge.com).
//  Used only during CurseForge modpack import to resolve projectID/fileID pairs into
//  real download URLs and, for distribution-blocked files, project names + page links.
//
//  The API key is USER-SUPPLIED and lives in the Keychain (never in JSON). We never route
//  through unofficial proxy mirrors. Endpoints used:
//    • POST /v1/mods/files  — batch file metadata (downloadUrl, fileName) by fileId
//    • POST /v1/mods        — batch project metadata (name, slug, links) by modId
//

import Foundation

// MARK: - Response DTOs

struct CFFilesResponse: Codable { let data: [CFFile] }

struct CFFile: Codable {
    let id: Int
    let modId: Int
    let displayName: String?
    let fileName: String
    /// Null when the author opted out of API distribution — surfaced as a manual download.
    let downloadUrl: String?
}

struct CFModsResponse: Codable { let data: [CFMod] }

struct CFMod: Codable {
    let id: Int
    let name: String
    let slug: String?
    let links: CFModLinks?
}

struct CFModLinks: Codable {
    let websiteUrl: String?
}

// MARK: - Errors

enum CurseForgeAPIError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case network(String)
    case unauthorized
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No CurseForge API key is configured."
        case .invalidURL:
            return "Invalid CurseForge API URL."
        case .network(let m):
            return "CurseForge API network error: \(m)"
        case .unauthorized:
            return "CurseForge rejected the API key (401/403). Check the key in Preferences."
        case .decoding(let m):
            return "CurseForge API response error: \(m)"
        }
    }
}

// MARK: - Client

enum CurseForgeAPI {

    static let baseURL = "https://api.curseforge.com"

    /// CF endpoints accept large id batches, but we chunk defensively.
    private static let batchSize = 200

    /// Batch-resolves file metadata (including `downloadUrl`) for the given file ids.
    /// Files the API omits are simply absent from the result.
    static func files(fileIds: [Int], apiKey: String) async throws -> [CFFile] {
        try await batched(fileIds) { chunk in
            let data = try await post("/v1/mods/files", body: ["fileIds": chunk], apiKey: apiKey)
            do { return try JSONDecoder().decode(CFFilesResponse.self, from: data).data }
            catch { throw CurseForgeAPIError.decoding(error.localizedDescription) }
        }
    }

    /// Batch-resolves project (mod) metadata — name, slug, website link — for the given
    /// mod ids. Used to build the manual-download list for distribution-blocked files.
    static func mods(modIds: [Int], apiKey: String) async throws -> [CFMod] {
        try await batched(modIds) { chunk in
            let data = try await post("/v1/mods", body: ["modIds": chunk], apiKey: apiKey)
            do { return try JSONDecoder().decode(CFModsResponse.self, from: data).data }
            catch { throw CurseForgeAPIError.decoding(error.localizedDescription) }
        }
    }

    // MARK: - Plumbing

    private static func batched<T>(
        _ ids: [Int],
        _ fetch: ([Int]) async throws -> [T]
    ) async throws -> [T] {
        let unique = Array(Set(ids)).sorted()
        guard !unique.isEmpty else { return [] }
        var out: [T] = []
        var i = 0
        while i < unique.count {
            let end = min(i + batchSize, unique.count)
            out.append(contentsOf: try await fetch(Array(unique[i..<end])))
            i = end
        }
        return out
    }

    private static func post(_ path: String, body: [String: Any], apiKey: String) async throws -> Data {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw CurseForgeAPIError.missingAPIKey }
        guard let url = URL(string: baseURL + path) else { throw CurseForgeAPIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(MSCHTTP.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw CurseForgeAPIError.network(error.localizedDescription) }

        guard let http = response as? HTTPURLResponse else {
            throw CurseForgeAPIError.network("No HTTP response from CurseForge.")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw CurseForgeAPIError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CurseForgeAPIError.network("CurseForge returned status \(http.statusCode).")
        }
        return data
    }
}

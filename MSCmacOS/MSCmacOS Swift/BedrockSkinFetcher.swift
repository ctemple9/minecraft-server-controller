// BedrockSkinFetcher.swift
// MinecraftServerController
//
// Shared Bedrock skin resolution used by PlayerHeadView and PlayerBodyView
// when the identifier has a dot prefix (e.g. ".camkage").
//
// Resolution chain:
//   1. GeyserMC join-cache (bedrock_or_java) → Floodgate UUID → mc-heads.net/{UUID}
//   2. Live Xbox Live lookup (xbox/xuid) → XUID → Floodgate UUID → mc-heads.net/{UUID}
//      Geyser sanitizes spaces in a gamertag into underscores for the Java-side
//      username, so when the as-typed name misses we also retry with underscores
//      swapped back to spaces (Xbox gamertags never contain underscores).
//   3. Fallback → mc-heads.net/{.gamertag}        (avatar)
//                  api.mcheads.org/{.gamertag}    (body)
//
// Resolved UUIDs are cached for the session; failures are negatively cached with
// a short TTL so the rate-limited live endpoint isn't hammered on every render.

import AppKit

enum BedrockSkinFetcher {

    // MARK: - Avatar (head tile)

    static func fetchAvatar(gamertag: String, size: Int) async -> NSImage? {
        let dotted = gamertag.hasPrefix(".") ? gamertag : ".\(gamertag)"
        let encoded = dotted.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? dotted

        // 1. GeyserMC → Floodgate UUID → mc-heads.net avatar
        if let uuid = await resolveFloodgateUUID(gamertag: dotted) {
            let uuidStr = uuid.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            if let img = await fetch("https://mc-heads.net/avatar/\(uuidStr)/\(size)") {
                return img
            }
        }

        // 2. Direct dotted-name avatar
        return await fetch("https://mc-heads.net/avatar/\(encoded)/\(size)")
    }

    // MARK: - Body render

    static func fetchBody(gamertag: String) async -> NSImage? {
        let dotted = gamertag.hasPrefix(".") ? gamertag : ".\(gamertag)"
        let encoded = dotted.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? dotted

        // 1. GeyserMC → Floodgate UUID → mc-heads.net body
        if let uuid = await resolveFloodgateUUID(gamertag: dotted) {
            let uuidStr = uuid.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            if let img = await fetch("https://mc-heads.net/body/\(uuidStr)/160") {
                return img
            }
        }

        // 2. Fallback: api.mcheads.org with dotted gamertag (mirrors PlayerAvatarView)
        return await fetch("https://api.mcheads.org/body/\(encoded)/160")
    }

    // MARK: - Private helpers

    private struct GeyserResponse: Decodable { let id: String }
    private struct XboxXUIDResponse: Decodable { let xuid: Int64 }

    /// Session-scoped cache so we don't re-resolve (and re-hit the rate-limited
    /// live endpoint) on every avatar render. Failures are remembered briefly so
    /// a transient miss recovers on its own without polling.
    private actor ResolutionCache {
        static let shared = ResolutionCache()
        private var resolved: [String: UUID] = [:]
        private var failures: [String: Date] = [:]
        private let failureTTL: TimeInterval = 120

        func cachedUUID(for key: String) -> UUID? { resolved[key] }

        func shouldSkip(_ key: String) -> Bool {
            guard let when = failures[key] else { return false }
            if Date().timeIntervalSince(when) < failureTTL { return true }
            failures.removeValue(forKey: key)
            return false
        }

        func store(_ uuid: UUID, for key: String) {
            resolved[key] = uuid
            failures.removeValue(forKey: key)
        }

        func markFailure(_ key: String) { failures[key] = Date() }
    }

    private static func resolveFloodgateUUID(gamertag: String) async -> UUID? {
        let cacheKey = gamertag.lowercased()

        if let cached = await ResolutionCache.shared.cachedUUID(for: cacheKey) { return cached }
        if await ResolutionCache.shared.shouldSkip(cacheKey) { return nil }

        // 1. GeyserMC join-cache: fast and free for players who've connected to a
        //    Geyser server tracked by the global API.
        if let uuid = await resolveViaJoinCache(dottedGamertag: gamertag) {
            await ResolutionCache.shared.store(uuid, for: cacheKey)
            return uuid
        }

        // 2. Live Xbox Live lookup. The xbox/xuid endpoint wants the raw gamertag
        //    with no Floodgate dot prefix.
        let raw = gamertag.hasPrefix(".") ? String(gamertag.dropFirst()) : gamertag
        var candidates = [raw]
        if raw.contains("_") {
            candidates.append(raw.replacingOccurrences(of: "_", with: " "))
        }
        for candidate in candidates {
            if let uuid = await resolveViaXboxLive(rawGamertag: candidate) {
                await ResolutionCache.shared.store(uuid, for: cacheKey)
                return uuid
            }
        }

        await ResolutionCache.shared.markFailure(cacheKey)
        return nil
    }

    /// GeyserMC global API join-cache lookup, keyed by the dotted gamertag.
    private static func resolveViaJoinCache(dottedGamertag: String) async -> UUID? {
        let encoded = dottedGamertag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? dottedGamertag
        guard var components = URLComponents(string: "https://api.geysermc.org/v2/utils/uuid/bedrock_or_java/\(encoded)") else {
            return nil
        }
        components.queryItems = [URLQueryItem(name: "prefix", value: ".")]
        guard let url = components.url else { return nil }

        var req = URLRequest(url: url)
        req.setValue("MinecraftServerController/1.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 8

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let resolved = try? JSONDecoder().decode(GeyserResponse.self, from: data),
              let uuid = UUID(uuidString: resolved.id) else { return nil }
        return uuid
    }

    /// Live Xbox Live gamertag → XUID lookup, converted to a Floodgate UUID locally.
    private static func resolveViaXboxLive(rawGamertag: String) async -> UUID? {
        let encoded = rawGamertag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? rawGamertag
        guard let url = URL(string: "https://api.geysermc.org/v2/xbox/xuid/\(encoded)") else { return nil }

        var req = URLRequest(url: url)
        req.setValue("MinecraftServerController/1.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 8

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let parsed = try? JSONDecoder().decode(XboxXUIDResponse.self, from: data) else { return nil }
        return floodgateUUID(fromXUID: parsed.xuid)
    }

    /// Builds the Floodgate UUID for an XUID: all-zero high bits with the 64-bit
    /// XUID in the low half (e.g. 2535443338451450 → 00000000-0000-0000-0009-01f8e78959fa).
    private static func floodgateUUID(fromXUID xuid: Int64) -> UUID? {
        let hex = String(format: "%016llx", xuid)
        let uuidString = "00000000-0000-0000-\(hex.prefix(4))-\(hex.dropFirst(4))"
        return UUID(uuidString: uuidString)
    }

    private static func fetch(_ urlString: String) async -> NSImage? {
        guard let url = URL(string: urlString) else { return nil }
        var req = URLRequest(url: url)
        req.setValue("MinecraftServerController/1.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let img = NSImage(data: data) else { return nil }
        return img
    }
}

// BedrockSkinFetcher.swift
// MinecraftServerController
//
// Shared Bedrock skin resolution used by PlayerHeadView and PlayerBodyView
// when the identifier has a dot prefix (e.g. ".camkage").
//
// Resolution chain (mirrors PlayerAvatarView's Bedrock path):
//   1. GeyserMC API → Floodgate UUID → mc-heads.net/{UUID}
//   2. Fallback → mc-heads.net/{.gamertag}        (avatar)
//                  api.mcheads.org/{.gamertag}    (body)

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

    private static func resolveFloodgateUUID(gamertag: String) async -> UUID? {
        let encoded = gamertag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? gamertag
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

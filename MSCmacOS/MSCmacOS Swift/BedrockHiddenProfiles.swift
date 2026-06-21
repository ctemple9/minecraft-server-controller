//
//  BedrockHiddenProfiles.swift
//  MinecraftServerController
//
//  Persists a set of Bedrock player XUIDs that the user has chosen to hide
//  from the player profiles list. Hidden profiles can be revealed and unhidden
//  at any time from the player list header.
//
//  File: bedrock_hidden.json  (array of XUID strings)
//

import Foundation

enum BedrockHiddenProfiles {

    private static func url(serverDir: String) -> URL {
        URL(fileURLWithPath: serverDir).appendingPathComponent("bedrock_hidden.json")
    }

    static func load(serverDir: String) -> Set<String> {
        let u = url(serverDir: serverDir)
        guard let data = try? Data(contentsOf: u),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(arr)
    }

    static func hide(xuid: String, serverDir: String) {
        var set = load(serverDir: serverDir)
        set.insert(xuid)
        save(set, serverDir: serverDir)
    }

    static func unhide(xuid: String, serverDir: String) {
        var set = load(serverDir: serverDir)
        set.remove(xuid)
        save(set, serverDir: serverDir)
    }

    private static func save(_ set: Set<String>, serverDir: String) {
        guard let data = try? JSONEncoder().encode(Array(set)) else { return }
        try? data.write(to: url(serverDir: serverDir), options: .atomic)
    }
}

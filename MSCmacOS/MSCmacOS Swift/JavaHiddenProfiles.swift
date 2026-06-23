//
//  JavaHiddenProfiles.swift
//  MinecraftServerController
//
//  Persists a set of Java player UUIDs that the user has chosen to hide from the
//  player profiles list. Mirrors BedrockHiddenProfiles (which is keyed by XUID).
//  Hidden profiles can be revealed and unhidden at any time.
//
//  File: java_hidden.json  (array of UUID strings)
//

import Foundation

enum JavaHiddenProfiles {

    private static func url(serverDir: String) -> URL {
        URL(fileURLWithPath: serverDir).appendingPathComponent("java_hidden.json")
    }

    static func load(serverDir: String) -> Set<String> {
        let u = url(serverDir: serverDir)
        guard let data = try? Data(contentsOf: u),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(arr)
    }

    static func hide(uuid: String, serverDir: String) {
        var set = load(serverDir: serverDir)
        set.insert(uuid)
        save(set, serverDir: serverDir)
    }

    static func unhide(uuid: String, serverDir: String) {
        var set = load(serverDir: serverDir)
        set.remove(uuid)
        save(set, serverDir: serverDir)
    }

    private static func save(_ set: Set<String>, serverDir: String) {
        guard let data = try? JSONEncoder().encode(Array(set)) else { return }
        try? data.write(to: url(serverDir: serverDir), options: .atomic)
    }
}

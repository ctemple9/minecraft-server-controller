//
//  PaperVersionSidecar.swift
//  MinecraftServerController
//
//  Stores Paper MC version + build in a lightweight sidecar JSON file inside a server directory.
//

import Foundation

struct PaperVersionSidecar: Codable, Equatable {
    let mcVersion: String
    let build: Int
    let timestamp: String
}

enum PaperVersionSidecarManager {

    static let filename = ".msc_paper_version.json"

    static func sidecarURL(forServerDirectory serverDir: URL) -> URL {
        serverDir.appendingPathComponent(filename)
    }

    static func read(fromServerDirectory serverDir: URL) -> PaperVersionSidecar? {
        let url = sidecarURL(forServerDirectory: serverDir)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(PaperVersionSidecar.self, from: data)
        } catch {
            return nil
        }
    }

    static func write(mcVersion: String, build: Int, toServerDirectory serverDir: URL) {
        let url = sidecarURL(forServerDirectory: serverDir)

        let stamp = ISO8601DateFormatter().string(from: Date())
        let sidecar = PaperVersionSidecar(mcVersion: mcVersion, build: build, timestamp: stamp)

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(sidecar)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Intentionally silent: failure here should not break install/apply.
        }
    }
}

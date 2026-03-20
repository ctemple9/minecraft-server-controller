//
//  ServerPropertiesManager.swift
//

import Foundation

struct ServerPropertiesManager {

    static func propertiesURL(for serverDir: String) -> URL {
        URL(fileURLWithPath: serverDir, isDirectory: true)
            .appendingPathComponent("server.properties")
    }

    static func readProperties(serverDir: String) -> [String: String] {
        let url = propertiesURL(for: serverDir)
        guard let contents = try? String(contentsOf: url) else { return [:] }

        var dict: [String: String] = [:]

        for line in contents.split(whereSeparator: \.isNewline) {
            let raw = String(line)
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let idx = trimmed.firstIndex(of: "=") else { continue }

            let key = trimmed[..<idx].trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: idx)...]
                .trimmingCharacters(in: .whitespaces)

            dict[key] = value
        }

        return dict
    }

    static func writeProperties(_ props: [String: String], to serverDir: String) throws {
        let url = propertiesURL(for: serverDir)

        var out = "# Modified via MinecraftServerController\n"
        for (k, v) in props {
            out += "\(k)=\(v)\n"
        }

        try out.write(to: url, atomically: true, encoding: .utf8)
    }
}


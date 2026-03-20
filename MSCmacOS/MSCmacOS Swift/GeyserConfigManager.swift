//
//  GeyserConfigManager.swift
//

import Foundation

struct GeyserConfig {
    var address: String
    /// nil = not set / not found (do NOT default)
    var port: Int?
}

struct GeyserConfigManager {

    static func configURL(for serverDir: String) -> URL {
        URL(fileURLWithPath: serverDir, isDirectory: true)
            .appendingPathComponent("plugins/Geyser-Spigot/config.yml")
    }

    static func readConfig(serverDir: String) -> GeyserConfig? {
        let url = configURL(for: serverDir)
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        let dict = YAMLHelper.parseYAML(contents)
        guard let bedrock = dict["bedrock"] as? [String: Any] else { return nil }

        let address = bedrock["address"] as? String ?? "0.0.0.0"

        let port: Int?
        if let p = bedrock["port"] as? Int {
            port = p
        } else if let s = bedrock["port"] as? String,
                  let p = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
            port = p
        } else {
            port = nil
        }

        return GeyserConfig(address: address, port: port)
    }

    static func writeConfig(serverDir: String, config: GeyserConfig) throws {
        let url = configURL(for: serverDir)
        let fm = FileManager.default

        // Do not create files here; only patch if it exists.
        guard fm.fileExists(atPath: url.path) else { return }

        let original = try String(contentsOf: url, encoding: .utf8)
        let patched = patchBedrockSection(in: original, newAddress: config.address, newPort: config.port)

        // If nothing changed (or the keys weren't present), do nothing.
        guard patched != original else { return }

        try patched.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Patches existing `bedrock:` section keys without rewriting the whole file.
    /// - Updates `address:` only if the line exists AND newAddress is non-empty.
    /// - Updates `port:` only if the line exists AND newPort is non-nil.
    /// - If `port:` does not exist, the update is skipped.
    private static func patchBedrockSection(in text: String, newAddress: String, newPort: Int?) -> String {
        var lines = text.components(separatedBy: .newlines)

        // Find the `bedrock:` line
        guard let bedrockIndex = lines.firstIndex(where: {
            let t = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            // tolerate "bedrock:" with trailing comments, e.g. "bedrock: # comment"
            return t == "bedrock:" || t.hasPrefix("bedrock: ")
        }) else {
            return text
        }

        // Scan forward until we hit the next top-level (non-indented) key.
        var i = bedrockIndex + 1
        var didChange = false

        while i < lines.count {
            let line = lines[i]

            // Stop at next top-level section (non-empty, not comment, no leading whitespace)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty,
               !trimmed.hasPrefix("#"),
               (line.first != " " && line.first != "\t"),
               trimmed.hasSuffix(":") {
                break
            }

            let t = line.trimmingCharacters(in: .whitespaces)

            if !newAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               t.hasPrefix("address:") {
                let indent = line.prefix { $0 == " " || $0 == "\t" }
                let comment = line.range(of: "#").map { String(line[$0.lowerBound...]) } ?? ""
                let newLine = "\(indent)address: \"\(newAddress)\"\(comment.isEmpty ? "" : " \(comment)")"
                if lines[i] != newLine {
                    lines[i] = newLine
                    didChange = true
                }
            }

            if let port = newPort,
               t.hasPrefix("port:") {
                let indent = line.prefix { $0 == " " || $0 == "\t" }
                let comment = line.range(of: "#").map { String(line[$0.lowerBound...]) } ?? ""
                let newLine = "\(indent)port: \(port)\(comment.isEmpty ? "" : " \(comment)")"
                if lines[i] != newLine {
                    lines[i] = newLine
                    didChange = true
                }
            }

            i += 1
        }

        return didChange ? lines.joined(separator: "\n") : text
    }
    
    func isGeyserInstalled(serverPath: URL) -> Bool {
        let pluginsDir = serverPath.appendingPathComponent("plugins", isDirectory: true)

        guard let items = try? FileManager.default.contentsOfDirectory(
            at: pluginsDir,
            includingPropertiesForKeys: nil
        ) else {
            return false
        }

        return items.contains { url in
            let name = url.lastPathComponent.lowercased()
            return name.hasSuffix(".jar") && name.contains("geyser")
        }
    }
    

}


//
//  EULAManager.swift
//

import Foundation

struct EULAManager {

    static func eulaURL(for serverDir: String) -> URL {
        URL(fileURLWithPath: serverDir, isDirectory: true)
            .appendingPathComponent("eula.txt")
    }

    /// Checks if eula.txt exists and returns:
    /// - true  → accepted
    /// - false → explicitly false
    /// - nil   → no eula.txt yet
    static func readEULA(in serverDir: String) -> Bool? {
        let url = eulaURL(for: serverDir)
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        for line in contents.split(whereSeparator: \.isNewline) {
            let raw = String(line).trimmingCharacters(in: .whitespaces)
            if raw.lowercased().starts(with: "eula=") {
                return raw.lowercased().contains("true")
            }
        }
        return nil
    }

    static func writeAcceptedEULA(in serverDir: String) throws {
        let url = eulaURL(for: serverDir)
        let text = """
        # EULA accepted via MinecraftServerController
        eula=true

        """
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}


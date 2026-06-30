//
//  JavaRuntimeManager.swift
//  MinecraftServerController
//
//  M0 (partial): Java runtime compatibility. Maps a Minecraft version to the
//  Java major version it requires, detects the major version of the configured
//  `java` binary, and produces a clear warning when they don't match — so a
//  server that can't boot says *why* instead of failing silently.
//
//  Full auto-download/management of JDKs (Adoptium) is a later step; this is the
//  detection + guidance half, which is safe and non-invasive.
//

import Foundation

enum JavaRuntimeManager {

    /// The Java major version a given Minecraft version needs to run.
    /// Conservative mapping; unknown / new-scheme versions assume the current LTS (21).
    static func requiredJavaMajor(forMinecraftVersion version: String?) -> Int {
        guard let version, let first = version.split(separator: ".").compactMap({ Int($0) }).first else {
            return 21   // unknown → assume newest
        }
        if first == 1 {
            // Classic "1.x" scheme.
            let parts = version.split(separator: ".").compactMap { Int($0) }
            let minor = parts.count > 1 ? parts[1] : 0
            if minor >= 21 { return 21 }   // 1.21+  → Java 21
            if minor >= 17 { return 17 }   // 1.17–1.20 → Java 17
            return 8                        // ≤1.16 → Java 8
        }
        // New-scheme releases (e.g. 26.x) → current LTS.
        return 21
    }

    /// Detects the major version of a `java` binary by running `-version` and
    /// parsing its output. Returns nil if it can't be determined.
    /// Results are cached per resolved path for the app session.
    private static var detectionCache: [String: Int?] = [:]

    static func detectJavaMajor(javaPath: String) -> Int? {
        let key = javaPath.isEmpty ? "java" : javaPath
        if let cached = detectionCache[key] { return cached }
        let result = runJavaVersion(javaPath: key)
        detectionCache[key] = result
        return result
    }

    private static func runJavaVersion(javaPath: String) -> Int? {
        // Resolve "java" (bare command) via the login shell PATH; use absolute paths directly.
        let process = Process()
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe

        if javaPath.contains("/") {
            process.executableURL = URL(fileURLWithPath: (javaPath as NSString).expandingTildeInPath)
            process.arguments = ["-version"]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [javaPath, "-version"]
        }

        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        return parseMajor(fromVersionOutput: output)
    }

    /// Parses output like `openjdk version "21.0.3" 2024-...` or `java version "1.8.0_402"`.
    static func parseMajor(fromVersionOutput output: String) -> Int? {
        // Grab the first quoted version token.
        guard let firstQuote = output.firstIndex(of: "\"") else { return nil }
        let afterQuote = output[output.index(after: firstQuote)...]
        guard let secondQuote = afterQuote.firstIndex(of: "\"") else { return nil }
        let token = String(afterQuote[..<secondQuote])     // e.g. "21.0.3" or "1.8.0_402"

        let components = token.split(whereSeparator: { $0 == "." || $0 == "_" }).compactMap { Int($0) }
        guard let first = components.first else { return nil }
        if first == 1 {
            // Legacy "1.8" style → major 8.
            return components.count > 1 ? components[1] : 1
        }
        return first
    }

    /// Returns a user-facing warning if the configured Java is too old for the
    /// server's Minecraft version, or nil if it's fine / undeterminable.
    static func compatibilityWarning(minecraftVersion: String?, javaPath: String) -> String? {
        let required = requiredJavaMajor(forMinecraftVersion: minecraftVersion)
        guard let detected = detectJavaMajor(javaPath: javaPath) else { return nil }
        guard detected < required else { return nil }
        let versionText = minecraftVersion.map { "Minecraft \($0)" } ?? "this Minecraft version"
        return "\(versionText) needs Java \(required), but the configured Java is version \(detected). "
             + "Install Java \(required) (e.g. Temurin/Adoptium) and set it in Preferences, or choose an older Minecraft version."
    }
}

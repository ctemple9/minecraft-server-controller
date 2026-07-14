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

    // MARK: - Path normalization

    /// Normalizes a java path so MSC always receives an executable binary, not a JDK
    /// home directory. Bare command names that contain no "/" (e.g. "java") are left
    /// as-is — they are resolved against PATH at launch time. A directory that contains
    /// `bin/java` is automatically expanded to that binary (handles the common mistake
    /// of pasting a JAVA_HOME path from the Finder into Preferences, which produces
    /// "permission denied" when MSC tries to exec a directory).
    ///
    /// Returns `(path: normalized, error: nil)` on success, or `(path: nil, error: reason)`
    /// when the path cannot be resolved to something executable.
    static func normalizedJavaExecutablePath(_ rawPath: String) -> (path: String?, error: String?) {
        guard rawPath.contains("/") else { return (rawPath, nil) }
        let fm = FileManager.default
        let expanded = (rawPath as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: expanded, isDirectory: &isDir) else {
            return (nil, "Java path does not exist: \(rawPath)")
        }
        if isDir.boolValue {
            let candidate = (expanded as NSString).appendingPathComponent("bin/java")
            guard fm.isExecutableFile(atPath: candidate) else {
                return (nil, "'\(rawPath)' is a Java HOME directory but has no executable at bin/java")
            }
            return (candidate, nil)
        }
        guard fm.isExecutableFile(atPath: expanded) else {
            return (nil, "'\(rawPath)' exists but is not executable")
        }
        return (expanded, nil)
    }

    // MARK: - Compatibility warning

    /// Core warning logic extracted for testability (takes pre-detected major versions so
    /// no process needs to be spawned in tests). Returns nil when no warning is needed.
    static func compatibilityWarningText(minecraftVersion: String?, required: Int, detected: Int) -> String? {
        let versionText = minecraftVersion.map { "Minecraft \($0)" } ?? "this Minecraft version"
        if detected < required {
            return "\(versionText) needs Java \(required), but the configured Java is version \(detected). "
                 + "Install Java \(required) (e.g. Temurin/Adoptium) and set it in Preferences, or choose an older Minecraft version."
        }
        // Java-17-era Minecraft (1.17–1.20.x, required=17) is known to have classpath and
        // ASM issues with Java 21+. Warn when a newer runtime is configured so the user
        // understands why a modpack might fail, without blocking the start.
        if detected > required, required <= 17 {
            return "\(versionText) modpacks are usually built and tested for Java \(required), but the configured Java is version \(detected). "
                 + "If this server fails to start, install Java \(required) (e.g. Temurin/Adoptium) and set it in Preferences."
        }
        return nil
    }

    /// Returns a user-facing warning if the configured Java is too old or (for Java-17-era
    /// Minecraft) too new for the server's Minecraft version, or nil if it looks fine.
    static func compatibilityWarning(minecraftVersion: String?, javaPath: String) -> String? {
        let required = requiredJavaMajor(forMinecraftVersion: minecraftVersion)
        guard let detected = detectJavaMajor(javaPath: javaPath) else { return nil }
        return compatibilityWarningText(minecraftVersion: minecraftVersion, required: required, detected: detected)
    }
}

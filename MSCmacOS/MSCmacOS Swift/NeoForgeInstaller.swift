//
//  NeoForgeInstaller.swift
//  MinecraftServerController
//
//  M4: NeoForge provisioning. Unlike the other flavors, NeoForge ships an
//  *installer* that must run locally — it downloads the official Minecraft jar
//  plus libraries, patches/remaps them, and generates the startup args files we
//  later launch from. This handles version resolution, installer download, and
//  running `java -jar <installer> --installServer`, streaming its output.
//

import Foundation

enum NeoForgeError: LocalizedError {
    case network(String)
    case noStableVersion
    case installerFailed(Int32)
    case argsFileMissing

    var errorDescription: String? {
        switch self {
        case .network(let m):        return "NeoForge network error: \(m)"
        case .noStableVersion:       return "Couldn't find a stable NeoForge version."
        case .installerFailed(let c): return "The NeoForge installer exited with code \(c)."
        case .argsFileMissing:       return "NeoForge installed but its launch args file was not found."
        }
    }
}

enum NeoForgeInstaller {

    /// Result of a successful install.
    struct InstallResult {
        let minecraftVersion: String
        let neoForgeVersion: String
        /// Path to the generated unix args file, relative to the server directory.
        let argsFileRelativePath: String
    }

    // MARK: - Public

    /// Returns available NeoForge versions as MC-paired entries for the version picker.
    static func listVersionPairs() async throws -> [ServerVersionEntry] {
        let url = URL(string: "https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml")!
        let (data, resp) = try await MSCHTTP.get(url)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw NeoForgeError.network("metadata returned status \(http.statusCode)")
        }
        guard let xml = String(data: data, encoding: .utf8) else { throw NeoForgeError.network("metadata not text") }

        var versions: [String] = []
        var search = xml[...]
        while let open = search.range(of: "<version>"), let close = search.range(of: "</version>") {
            versions.append(String(search[open.upperBound..<close.lowerBound]))
            search = search[close.upperBound...]
        }
        let stable = versions.filter { !$0.contains("-") }

        // Keep the highest NeoForge build per MC version.
        var byMC: [String: String] = [:]
        for nfv in stable {
            let mc = minecraftVersion(forNeoForge: nfv)
            if let existing = byMC[mc] {
                if compare(nfv, existing) == .orderedDescending { byMC[mc] = nfv }
            } else {
                byMC[mc] = nfv
            }
        }

        return byMC
            .sorted { compareMC($0.key, $1.key) == .orderedDescending }
            .map { mc, nfv in
                ServerVersionEntry(
                    id: "\(mc)—\(nfv)",
                    displayLabel: mc,
                    mcVersion: mc,
                    loaderVersion: nfv,
                    buildLabel: "NeoForge \(nfv)",
                    isStable: true
                )
            }
    }

    private static func compareMC(_ a: String, _ b: String) -> ComparisonResult {
        let ap = a.split(separator: ".").compactMap { Int($0) }
        let bp = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(ap.count, bp.count) {
            let av = i < ap.count ? ap[i] : 0
            let bv = i < bp.count ? bp[i] : 0
            if av != bv { return av < bv ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    /// Resolves the latest stable NeoForge, downloads its installer into `serverDir`,
    /// runs `--installServer`, and returns the resolved versions + args file path.
    /// `onLog` receives installer output lines for display/logging.
    static func install(
        into serverDir: URL,
        javaPath: String,
        onLog: @escaping (String) -> Void
    ) async throws -> InstallResult {
        let version = try await latestStableVersion()
        let mc = minecraftVersion(forNeoForge: version)
        onLog("Resolving NeoForge \(version) (Minecraft \(mc))…")

        // Download the installer jar.
        let installerURLString = "https://maven.neoforged.net/releases/net/neoforged/neoforge/\(version)/neoforge-\(version)-installer.jar"
        guard let installerURL = URL(string: installerURLString) else { throw NeoForgeError.network("bad installer URL") }
        let installerJar = serverDir.appendingPathComponent("neoforge-installer.jar")
        onLog("Downloading NeoForge installer…")
        let (data, resp) = try await MSCHTTP.get(installerURL)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw NeoForgeError.network("installer download returned status \(http.statusCode)")
        }
        try data.write(to: installerJar, options: [.atomic])

        // Run the installer (downloads MC + libraries, patches, generates run files).
        onLog("Running NeoForge installer (this downloads Minecraft and libraries)…")
        let code = try await runJavaInstaller(javaPath: javaPath, installerJar: installerJar, cwd: serverDir, onLog: onLog)
        guard code == 0 else { throw NeoForgeError.installerFailed(code) }

        // Locate the generated unix args file.
        guard let argsRel = findArgsFile(in: serverDir) else { throw NeoForgeError.argsFileMissing }
        onLog("NeoForge install complete.")

        // Tidy up the installer jar (and its log) — they're not needed to run.
        try? FileManager.default.removeItem(at: installerJar)
        try? FileManager.default.removeItem(at: serverDir.appendingPathComponent("installer.log"))

        return InstallResult(minecraftVersion: mc, neoForgeVersion: version, argsFileRelativePath: argsRel)
    }

    /// Installs a specific NeoForge version (e.g. "21.1.234") chosen by the user.
    static func install(
        specificVersion version: String,
        into serverDir: URL,
        javaPath: String,
        onLog: @escaping (String) -> Void
    ) async throws -> InstallResult {
        let mc = minecraftVersion(forNeoForge: version)
        onLog("Resolving NeoForge \(version) (Minecraft \(mc))…")

        let installerURLString = "https://maven.neoforged.net/releases/net/neoforged/neoforge/\(version)/neoforge-\(version)-installer.jar"
        guard let installerURL = URL(string: installerURLString) else { throw NeoForgeError.network("bad installer URL") }
        let installerJar = serverDir.appendingPathComponent("neoforge-installer.jar")
        onLog("Downloading NeoForge \(version) installer…")
        let (data, resp) = try await MSCHTTP.get(installerURL)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw NeoForgeError.network("installer download returned status \(http.statusCode)")
        }
        try data.write(to: installerJar, options: [.atomic])

        onLog("Running NeoForge installer (this downloads Minecraft and libraries)…")
        let code = try await runJavaInstaller(javaPath: javaPath, installerJar: installerJar, cwd: serverDir, onLog: onLog)
        guard code == 0 else { throw NeoForgeError.installerFailed(code) }

        guard let argsRel = findArgsFile(in: serverDir) else { throw NeoForgeError.argsFileMissing }
        onLog("NeoForge \(version) install complete.")

        try? FileManager.default.removeItem(at: installerJar)
        try? FileManager.default.removeItem(at: serverDir.appendingPathComponent("installer.log"))

        return InstallResult(minecraftVersion: mc, neoForgeVersion: version, argsFileRelativePath: argsRel)
    }

    /// Finds the generated unix args file relative to the server directory, e.g.
    /// "libraries/net/neoforged/neoforge/21.1.234/unix_args.txt". Returns nil if absent.
    static func findArgsFile(in serverDir: URL) -> String? {
        let base = serverDir.appendingPathComponent("libraries/net/neoforged/neoforge", isDirectory: true)
        let fm = FileManager.default
        guard let versionDirs = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) else { return nil }
        for dir in versionDirs {
            let candidate = dir.appendingPathComponent("unix_args.txt")
            if fm.fileExists(atPath: candidate.path) {
                return "libraries/net/neoforged/neoforge/\(dir.lastPathComponent)/unix_args.txt"
            }
        }
        return nil
    }

    // MARK: - Version resolution

    /// Latest stable (non beta/alpha/rc) NeoForge version, highest numerically.
    static func latestStableVersion() async throws -> String {
        let url = URL(string: "https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml")!
        let (data, resp) = try await MSCHTTP.get(url)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw NeoForgeError.network("metadata returned status \(http.statusCode)")
        }
        guard let xml = String(data: data, encoding: .utf8) else { throw NeoForgeError.network("metadata not text") }

        // Cheap XML scrape of <version>…</version> entries.
        var versions: [String] = []
        var search = xml[...]
        while let open = search.range(of: "<version>"), let close = search.range(of: "</version>") {
            versions.append(String(search[open.upperBound..<close.lowerBound]))
            search = search[close.upperBound...]
        }
        let stable = versions.filter { !$0.contains("-") }   // drop -beta / -alpha / -rc
        guard let best = stable.max(by: { compare($0, $1) == .orderedAscending }) else {
            throw NeoForgeError.noStableVersion
        }
        return best
    }

    /// Maps a NeoForge version to its Minecraft version.
    /// Classic: "21.1.234" → "1.21.1", "21.0.x" → "1.21". New scheme (≥26): "26.2.x" → "26.2".
    static func minecraftVersion(forNeoForge version: String) -> String {
        let core = version.split(separator: "-").first.map(String.init) ?? version
        let comps = core.split(separator: ".").compactMap { Int($0) }
        guard comps.count >= 2 else { return core }
        let major = comps[0], minor = comps[1]
        if major >= 26 { return minor == 0 ? "\(major)" : "\(major).\(minor)" }
        return minor == 0 ? "1.\(major)" : "1.\(major).\(minor)"
    }

    private static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let ap = a.split(separator: ".").compactMap { Int($0) }
        let bp = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(ap.count, bp.count) {
            let av = i < ap.count ? ap[i] : 0
            let bv = i < bp.count ? bp[i] : 0
            if av != bv { return av < bv ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    // MARK: - Subprocess

    static func runInstaller(
        javaPath: String,
        installerJar: URL,
        cwd: URL,
        onLog: @escaping (String) -> Void
    ) async throws -> Int32 {
        try await runJavaInstaller(javaPath: javaPath, installerJar: installerJar, cwd: cwd, onLog: onLog)
    }
}

// MARK: - Shared subprocess helper (NeoForge + Forge)

/// Runs `java -jar <installer> --installServer` in `cwd`, streaming output lines
/// to `onLog`. Returns the process exit code. Used by both NeoForgeInstaller and
/// ForgeInstaller, which share the same installer invocation pattern.
private func runJavaInstaller(
    javaPath: String,
    installerJar: URL,
    cwd: URL,
    onLog: @escaping (String) -> Void
) async throws -> Int32 {
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int32, Error>) in
        let process = Process()
        if javaPath.contains("/") {
            process.executableURL = URL(fileURLWithPath: (javaPath as NSString).expandingTildeInPath)
            process.arguments = ["-jar", installerJar.path, "--installServer"]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [javaPath, "-jar", installerJar.path, "--installServer"]
        }
        process.currentDirectoryURL = cwd

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty, let text = String(data: chunk, encoding: .utf8) else { return }
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                onLog(String(line))
            }
        }
        process.terminationHandler = { proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            cont.resume(returning: proc.terminationStatus)
        }
        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            cont.resume(throwing: error)
        }
    }
}

// MARK: - Forge installer (maven.minecraftforge.net)

enum ForgeError: LocalizedError {
    case network(String)
    case noVersion
    case installerFailed(Int32)
    case argsFileMissing

    var errorDescription: String? {
        switch self {
        case .network(let m):         return "Forge network error: \(m)"
        case .noVersion:              return "Couldn't find a Forge recommended version."
        case .installerFailed(let c): return "The Forge installer exited with code \(c)."
        case .argsFileMissing:        return "Forge installed but its launch args file was not found."
        }
    }
}

enum ForgeInstaller {

    struct InstallResult {
        let minecraftVersion: String
        let forgeVersion: String
        let argsFileRelativePath: String
    }

    // MARK: - Public

    /// Resolves the latest recommended Forge, downloads its installer, runs
    /// `--installServer`, and returns the resolved versions + args file path.
    static func install(
        into serverDir: URL,
        javaPath: String,
        onLog: @escaping (String) -> Void
    ) async throws -> InstallResult {
        let (mcVersion, forgeVersion) = try await latestRecommendedVersion()
        onLog("Resolving Forge \(forgeVersion) (Minecraft \(mcVersion))…")

        let installerURLString = "https://maven.minecraftforge.net/net/minecraftforge/forge/\(mcVersion)-\(forgeVersion)/forge-\(mcVersion)-\(forgeVersion)-installer.jar"
        guard let installerURL = URL(string: installerURLString) else {
            throw ForgeError.network("bad installer URL")
        }
        let installerJar = serverDir.appendingPathComponent("forge-installer.jar")
        onLog("Downloading Forge installer…")
        let (data, resp) = try await MSCHTTP.get(installerURL)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw ForgeError.network("installer download returned status \(http.statusCode)")
        }
        try data.write(to: installerJar, options: [.atomic])

        onLog("Running Forge installer (this downloads Minecraft and libraries)…")
        let code = try await runJavaInstaller(javaPath: javaPath, installerJar: installerJar, cwd: serverDir, onLog: onLog)
        guard code == 0 else { throw ForgeError.installerFailed(code) }

        guard let argsRel = findArgsFile(in: serverDir) else { throw ForgeError.argsFileMissing }
        onLog("Forge install complete.")

        try? FileManager.default.removeItem(at: installerJar)

        return InstallResult(minecraftVersion: mcVersion, forgeVersion: forgeVersion, argsFileRelativePath: argsRel)
    }

    /// Installs a specific Forge build chosen by the user (e.g. MC "1.20.1", Forge "47.3.0").
    static func install(
        mcVersion: String,
        forgeVersion: String,
        into serverDir: URL,
        javaPath: String,
        onLog: @escaping (String) -> Void
    ) async throws -> InstallResult {
        onLog("Resolving Forge \(forgeVersion) (Minecraft \(mcVersion))…")

        let installerURLString = "https://maven.minecraftforge.net/net/minecraftforge/forge/\(mcVersion)-\(forgeVersion)/forge-\(mcVersion)-\(forgeVersion)-installer.jar"
        guard let installerURL = URL(string: installerURLString) else {
            throw ForgeError.network("bad installer URL")
        }
        let installerJar = serverDir.appendingPathComponent("forge-installer.jar")
        onLog("Downloading Forge \(forgeVersion) installer…")
        let (data, resp) = try await MSCHTTP.get(installerURL)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw ForgeError.network("installer download returned status \(http.statusCode)")
        }
        try data.write(to: installerJar, options: [.atomic])

        onLog("Running Forge installer (this downloads Minecraft and libraries)…")
        let code = try await runJavaInstaller(javaPath: javaPath, installerJar: installerJar, cwd: serverDir, onLog: onLog)
        guard code == 0 else { throw ForgeError.installerFailed(code) }

        guard let argsRel = findArgsFile(in: serverDir) else { throw ForgeError.argsFileMissing }
        onLog("Forge \(forgeVersion) install complete.")

        try? FileManager.default.removeItem(at: installerJar)

        return InstallResult(minecraftVersion: mcVersion, forgeVersion: forgeVersion, argsFileRelativePath: argsRel)
    }

    /// Returns available Forge versions as MC-paired entries for the version picker.
    static func listVersionPairs() async throws -> [ServerVersionEntry] {
        let url = URL(string: "https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json")!
        let (data, resp) = try await MSCHTTP.get(url)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw ForgeError.network("promotions returned status \(http.statusCode)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let promos = json["promos"] as? [String: String] else {
            throw ForgeError.network("promotions response malformed")
        }
        // Prefer "-recommended" entries, fall back to "-latest".
        var byMC: [String: (forge: String, isRecommended: Bool)] = [:]
        for (key, forgeVer) in promos {
            if key.hasSuffix("-recommended") {
                let mc = String(key.dropLast("-recommended".count))
                byMC[mc] = (forge: forgeVer, isRecommended: true)
            } else if key.hasSuffix("-latest") {
                let mc = String(key.dropLast("-latest".count))
                if byMC[mc] == nil {
                    byMC[mc] = (forge: forgeVer, isRecommended: false)
                }
            }
        }
        return byMC
            .sorted { compareMCStrings($0.key, $1.key) == .orderedDescending }
            .map { mc, pair in
                ServerVersionEntry(
                    id: "\(mc)—\(pair.forge)",
                    displayLabel: mc,
                    mcVersion: mc,
                    loaderVersion: pair.forge,
                    buildLabel: "Forge \(pair.forge)",
                    isStable: true
                )
            }
    }

    /// Finds the generated unix args file, e.g.
    /// "libraries/net/minecraftforge/forge/1.21.4-54.1.0/unix_args.txt".
    static func findArgsFile(in serverDir: URL) -> String? {
        let base = serverDir.appendingPathComponent("libraries/net/minecraftforge/forge", isDirectory: true)
        let fm = FileManager.default
        guard let versionDirs = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) else { return nil }
        for dir in versionDirs {
            let candidate = dir.appendingPathComponent("unix_args.txt")
            if fm.fileExists(atPath: candidate.path) {
                return "libraries/net/minecraftforge/forge/\(dir.lastPathComponent)/unix_args.txt"
            }
        }
        return nil
    }

    // MARK: - Version resolution

    private static func compareMCStrings(_ a: String, _ b: String) -> ComparisonResult {
        let ap = a.split(separator: ".").compactMap { Int($0) }
        let bp = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(ap.count, bp.count) {
            let av = i < ap.count ? ap[i] : 0
            let bv = i < bp.count ? bp[i] : 0
            if av != bv { return av < bv ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    /// Fetches the latest recommended Forge build for the highest supported MC version
    /// from the Forge promotions API.
    private static func latestRecommendedVersion() async throws -> (mcVersion: String, forgeVersion: String) {
        let url = URL(string: "https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json")!
        let (data, resp) = try await MSCHTTP.get(url)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw ForgeError.network("promotions returned status \(http.statusCode)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let promos = json["promos"] as? [String: String] else {
            throw ForgeError.network("promotions response malformed")
        }

        let suffix = "-recommended"
        let candidates = promos.compactMap { key, value -> (String, String)? in
            guard key.hasSuffix(suffix) else { return nil }
            return (String(key.dropLast(suffix.count)), value)
        }
        guard let best = candidates.max(by: { compareForgeVersions($0.0, $1.0) == .orderedAscending }) else {
            throw ForgeError.noVersion
        }
        return (best.0, best.1)
    }

    private static func compareForgeVersions(_ a: String, _ b: String) -> ComparisonResult {
        let ap = a.split(separator: ".").compactMap { Int($0) }
        let bp = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(ap.count, bp.count) {
            let av = i < ap.count ? ap[i] : 0
            let bv = i < bp.count ? bp[i] : 0
            if av != bv { return av < bv ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}

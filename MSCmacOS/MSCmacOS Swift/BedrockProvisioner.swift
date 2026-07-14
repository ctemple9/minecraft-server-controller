// BedrockProvisioner.swift
//  MinecraftServerController
//
// Installs / updates the Bedrock Dedicated Server files in a server's folder for
// the VM backend. In the Docker world this was the itzg image's job (it kept the
// bedrock_server binary inside the image and re-checked VERSION on each start).
// Without Docker, the app must place the BDS install in serverDir itself and
// honor the version pinned in the Components tab.
//
// Strategy:
//   - Resolve the target version (pinned, or newest) + download URL from the
//     kittizz manifest (the same source BedrockVersionFetcher uses).
//   - Track the installed version in `serverDir/.msc_bds_version`.
//   - Install/update when the binary is missing OR the installed version differs
//     from the target (or when `force` is set, e.g. the "Update" button).
//   - Extract with overwrite so the binary + libs + bundled packs are replaced,
//     but EXCLUDE the user's server.properties/allowlist/permissions/whitelist,
//     and never touch worlds/ (the zip contains none).

import Foundation

enum BedrockProvisioner {

    struct ProvisionError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static let versionMarker = ".msc_bds_version"

    /// Files in the BDS zip that hold user state — never overwrite these on update.
    private static let preservedFiles = ["server.properties", "allowlist.json",
                                         "permissions.json", "whitelist.json"]

    // MARK: - State

    static func isInstalled(serverDir: URL) -> Bool {
        FileManager.default.isExecutableFile(
            atPath: serverDir.appendingPathComponent("bedrock_server").path)
    }

    static func installedVersion(serverDir: URL) -> String? {
        let url = serverDir.appendingPathComponent(versionMarker)
        guard let s = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let v = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    private static func writeMarker(serverDir: URL, version: String) {
        try? version.write(to: serverDir.appendingPathComponent(versionMarker),
                           atomically: true, encoding: .utf8)
    }

    // MARK: - Ensure installed / updated

    /// Ensure the correct BDS version is present in serverDir. Synchronous; safe off
    /// the main thread. No-op when already at the target version (unless `force`).
    /// - Parameters:
    ///   - version: pinned version (e.g. "1.26.32.2") or nil/"LATEST" for newest.
    ///   - force: re-download even if the target is already installed (Update button).
    static func ensureInstalled(serverDir: URL,
                                version: String?,
                                force: Bool = false,
                                onProgress: (String) -> Void) throws {
        let already = isInstalled(serverDir: serverDir)
        let installed = installedVersion(serverDir: serverDir)

        // Resolve the target version + URL (needs the network).
        let target: (url: URL, version: String)
        do {
            target = try resolveDownload(version: version)
        } catch {
            // Offline (or manifest hiccup): if something is already installed and we
            // aren't forcing, just use what's there rather than failing the start.
            if already && !force {
                onProgress("[VM] Couldn't check Bedrock versions (offline?) — using installed files.")
                return
            }
            throw error
        }

        if already && !force {
            if installed == target.version { return }            // up to date
            if installed == nil, isLatestRequest(version) {
                // Legacy install with no marker, asking for latest → assume it's
                // current and just record the marker (avoid a needless re-download).
                writeMarker(serverDir: serverDir, version: target.version)
                return
            }
        }

        if already {
            onProgress("[VM] Updating Bedrock server \(installed ?? "?") → \(target.version)...")
        } else {
            onProgress("[VM] Installing Bedrock server \(target.version)...")
        }

        let zip = try download(target.url)
        defer { try? FileManager.default.removeItem(at: zip) }

        onProgress("[VM] Extracting Bedrock server (preserving your world & settings)...")
        try extract(zip: zip, into: serverDir, overwrite: already)

        let binary = serverDir.appendingPathComponent("bedrock_server")
        try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                               ofItemAtPath: binary.path)
        guard isInstalled(serverDir: serverDir) else {
            throw ProvisionError(message: "The download did not produce a bedrock_server binary.")
        }
        writeMarker(serverDir: serverDir, version: target.version)
        onProgress("[VM] Bedrock server \(target.version) ready.")
    }

    private static func isLatestRequest(_ version: String?) -> Bool {
        guard let v = version, !v.isEmpty else { return true }
        return v.uppercased() == "LATEST"
    }

    // MARK: - Version → (url, version)

    private static let manifestURL = URL(string:
        "https://raw.githubusercontent.com/kittizz/bedrock-server-downloads/refs/heads/main/bedrock-server-downloads.json")!

    private static func resolveDownload(version: String?) throws -> (url: URL, version: String) {
        let data = try Data(contentsOf: manifestURL)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let release = root["release"] as? [String: Any] else {
            throw ProvisionError(message: "Could not read the Bedrock version manifest.")
        }
        func linuxURL(_ entry: Any?) -> String? {
            guard let platforms = entry as? [String: Any],
                  let linux = platforms["linux"] as? [String: Any] else { return nil }
            return linux["url"] as? String
        }
        // Pinned version → match its download URL by the version token.
        if !isLatestRequest(version), let v = version {
            for (_, entry) in release {
                if let u = linuxURL(entry), u.contains("bedrock-server-\(v)"), let url = URL(string: u) {
                    return (url, versionFromURL(u) ?? v)
                }
            }
            throw ProvisionError(message: "Bedrock version \(v) was not found in the download manifest.")
        }
        // Newest release.
        let newestKey = release.keys.sorted(by: versionLess).last
        guard let key = newestKey, let u = linuxURL(release[key]), let url = URL(string: u) else {
            throw ProvisionError(message: "No Linux Bedrock server download found in the manifest.")
        }
        return (url, versionFromURL(u) ?? key)
    }

    private static func versionFromURL(_ urlString: String) -> String? {
        guard let r = urlString.range(of: #"bedrock-server-([0-9.]+)\.zip"#, options: .regularExpression)
        else { return nil }
        return String(urlString[r])
            .replacingOccurrences(of: "bedrock-server-", with: "")
            .replacingOccurrences(of: ".zip", with: "")
    }

    private static func versionLess(_ a: String, _ b: String) -> Bool {
        let pa = a.split(separator: ".").compactMap { Int($0) }
        let pb = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    // MARK: - Download + extract

    private static func download(_ url: URL) throws -> URL {
        var req = URLRequest(url: url)
        // Mojang's CDN rejects the default URLSession UA; mimic a browser.
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
                     forHTTPHeaderField: "User-Agent")
        req.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let sem = DispatchSemaphore(value: 0)
        var outURL: URL?
        var failure: Error?
        let task = URLSession.shared.downloadTask(with: req) { tmp, response, error in
            defer { sem.signal() }
            if let error { failure = error; return }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                failure = ProvisionError(message: "Download failed (HTTP \(http.statusCode)).")
                return
            }
            guard let tmp else { failure = ProvisionError(message: "Download produced no file."); return }
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("msc-bds-\(UUID().uuidString).zip")
            do { try FileManager.default.moveItem(at: tmp, to: dest); outURL = dest }
            catch { failure = error }
        }
        task.resume()
        sem.wait()
        if let failure { throw failure }
        guard let outURL else { throw ProvisionError(message: "Download failed.") }
        return outURL
    }

    /// Extract the zip into dir. When `overwrite` (an update), replace BDS-shipped
    /// files but exclude the user's config; when a fresh install, dir is empty so
    /// no-overwrite is implicit. Uses ditto to avoid /usr/bin/unzip's mode-000 quirk
    /// on downloads from some CDNs.
    private static func extract(zip: URL, into dir: URL, overwrite: Bool) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        // -x extract, -k treat source as zip; --exclude-pattern skips preserved user files on update
        var args = ["-x", "-k"]
        if overwrite {
            for name in Self.preservedFiles {
                args += ["--exclude-pattern", name]
            }
        }
        args += [zip.path, dir.path]
        p.arguments = args
        let errPipe = Pipe()
        p.standardOutput = FileHandle.nullDevice
        p.standardError = errPipe
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let out = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw ProvisionError(message: "Failed to extract Bedrock server (ditto \(p.terminationStatus)): \(out)")
        }
    }
}

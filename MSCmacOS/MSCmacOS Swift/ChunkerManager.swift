// ChunkerManager.swift
// MinecraftServerController
//
// Manages the Chunker CLI jar: GitHub release detection, download,
// format string discovery, and world conversion execution.
//
// Storage: ~/Library/Application Support/MinecraftServerController/chunker/
//   chunker-cli.jar      — the active CLI jar
//   chunker-version.txt  — installed version string (e.g. "1.18.1")

import Foundation

// MARK: - GitHub release models

struct ChunkerReleaseInfo: Decodable {
    let tagName: String
    let assets: [ChunkerAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

struct ChunkerAsset: Decodable {
    let name: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

// MARK: - Errors

enum ChunkerError: LocalizedError {
    case javaNotFound
    case jarNotInstalled
    case conversionFailed(String)
    case downloadFailed(String)
    case noCliAsset
    case worldFolderNotFound

    var errorDescription: String? {
        switch self {
        case .javaNotFound:
            return "Java was not found. Install Java (Adoptium Temurin) and ensure the path is set in MSC settings."
        case .jarNotInstalled:
            return "Chunker CLI is not installed. Use the conversion wizard to download it."
        case .conversionFailed(let msg):
            return "Conversion failed: \(msg)"
        case .downloadFailed(let msg):
            return "Download failed: \(msg)"
        case .noCliAsset:
            return "No CLI jar found in the latest Chunker release. Check github.com/HiveGamesOSS/Chunker."
        case .worldFolderNotFound:
            return "Could not locate the world folder inside the slot archive."
        }
    }
}

// MARK: - ChunkerManager

final class ChunkerManager {

    static let shared = ChunkerManager()
    private init() {}

    // MARK: - Storage paths

    private var chunkerDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("MinecraftServerController/chunker", isDirectory: true)
    }

    var jarURL: URL {
        chunkerDir.appendingPathComponent("chunker-cli.jar")
    }

    private var versionFileURL: URL {
        chunkerDir.appendingPathComponent("chunker-version.txt")
    }

    // MARK: - Installation state

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: jarURL.path)
    }

    var installedVersion: String? {
        try? String(contentsOf: versionFileURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
    }

    // MARK: - Java detection

    /// Returns a usable Java executable path. Checks the app's configured path first,
    /// then common system locations, then falls back to `which java`.
    func resolveJavaPath(appConfigJavaPath: String) -> String? {
        let fm = FileManager.default

        let configured = appConfigJavaPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !configured.isEmpty && fm.isExecutableFile(atPath: configured) {
            return configured
        }

        let candidates = ["/usr/bin/java", "/usr/local/bin/java", "/opt/homebrew/bin/java"]
        if let found = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) {
            return found
        }

        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["java"]
        let pipe = Pipe()
        which.standardOutput = pipe
        which.standardError = Pipe()
        try? which.run()
        which.waitUntilExit()
        let found = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !found.isEmpty && fm.isExecutableFile(atPath: found) { return found }

        return nil
    }

    // MARK: - GitHub release

    func fetchLatestRelease() async throws -> ChunkerReleaseInfo {
        let url = URL(string: "https://api.github.com/repos/HiveGamesOSS/Chunker/releases/latest")!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ChunkerError.downloadFailed("GitHub API returned HTTP \(http.statusCode)")
        }
        return try JSONDecoder().decode(ChunkerReleaseInfo.self, from: data)
    }

    // MARK: - Download

    func downloadLatestJar(progressHandler: @escaping (String) -> Void) async throws {
        progressHandler("Fetching latest Chunker release info…")
        let release = try await fetchLatestRelease()
        let version = release.tagName

        guard let asset = release.assets.first(where: {
            let n = $0.name.lowercased()
            return n.hasSuffix(".jar") && n.contains("cli")
        }) ?? release.assets.first(where: { $0.name.hasSuffix(".jar") }) else {
            throw ChunkerError.noCliAsset
        }

        progressHandler("Downloading Chunker \(version) (\(asset.name))…")

        guard let downloadURL = URL(string: asset.browserDownloadURL) else {
            throw ChunkerError.downloadFailed("Invalid download URL")
        }

        let (tempURL, _) = try await URLSession.shared.download(from: downloadURL)

        let fm = FileManager.default
        try fm.createDirectory(at: chunkerDir, withIntermediateDirectories: true)

        if fm.fileExists(atPath: jarURL.path) {
            try fm.removeItem(at: jarURL)
        }
        try fm.moveItem(at: tempURL, to: jarURL)
        try version.write(to: versionFileURL, atomically: true, encoding: .utf8)

        progressHandler("Chunker \(version) installed successfully.")
    }

    // MARK: - Format discovery

    /// Returns all format strings the installed jar supports.
    /// Runs `java -jar chunker-cli.jar -f ?` and parses the output for tokens
    /// matching `JAVA_X_Y_Z` or `BEDROCK_X_Y_Z`.
    func supportedFormats(javaPath: String) async -> [String] {
        guard isInstalled, let java = resolveJavaPath(appConfigJavaPath: javaPath) else { return [] }

        return await Task.detached(priority: .userInitiated) { [jar = self.jarURL] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: java)
            process.arguments = ["-jar", jar.path, "-f", "?"]
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            try? process.run()
            process.waitUntilExit()

            let combined = [outPipe, errPipe].compactMap {
                String(data: $0.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
            }.joined()

            var results: [String] = []
            // Bedrock formats use R-prefix: BEDROCK_R21_80, BEDROCK_R12, etc.
            // Java formats use numeric: JAVA_1_21_4, JAVA_26_1, etc.
            // Exclude PREVIEW and SETTINGS which are not conversion targets.
            let pattern = #"(?:JAVA|BEDROCK)_R?\d+(?:_\d+)*"#
            let excluded: Set<String> = ["PREVIEW", "SETTINGS"]
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let nsStr = combined as NSString
                let matches = regex.matches(in: combined, range: NSRange(location: 0, length: nsStr.length))
                for match in matches {
                    let s = nsStr.substring(with: match.range)
                    if !results.contains(s) && !excluded.contains(s) { results.append(s) }
                }
            }
            return results.sorted(by: self.chunkerFormatVersionOrder)
        }.value
    }

    // MARK: - Conversion

    /// Converts the world at `inputDir` to `targetFormat`, placing the result in `outputDir`.
    /// `outputDir` must not exist before this call. Streams each Chunker output line to `progressHandler`.
    func convert(
        inputDir: URL,
        outputDir: URL,
        targetFormat: String,
        javaPath: String,
        progressHandler: @escaping (String) -> Void
    ) async throws {
        guard isInstalled else { throw ChunkerError.jarNotInstalled }
        guard let java = resolveJavaPath(appConfigJavaPath: javaPath) else { throw ChunkerError.javaNotFound }

        try await Task.detached(priority: .userInitiated) { [jar = self.jarURL] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: java)
            process.arguments = ["-jar", jar.path, "-i", inputDir.path, "-f", targetFormat, "-o", outputDir.path]

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let text = String(data: handle.availableData, encoding: .utf8) ?? ""
                for line in text.components(separatedBy: .newlines) {
                    let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { progressHandler(t) }
                }
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let text = String(data: handle.availableData, encoding: .utf8) ?? ""
                for line in text.components(separatedBy: .newlines) {
                    let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { progressHandler(t) }
                }
            }

            try process.run()
            process.waitUntilExit()

            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil

            guard process.terminationStatus == 0 else {
                throw ChunkerError.conversionFailed("Chunker exited with code \(process.terminationStatus)")
            }
        }.value
    }

    // MARK: - World folder helpers

    /// Finds the input world folder inside a previously-unzipped slot directory.
    /// For Bedrock slots the zip contains `worlds/{levelName}/`; for Java it contains `{levelName}/`.
    func findInputWorldFolder(
        in unzipDir: URL,
        isBedrock: Bool,
        slotLevelName: String?
    ) -> URL? {
        let fm = FileManager.default

        func firstSubdir(_ parent: URL) -> URL? {
            guard let entries = try? fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil) else { return nil }
            return entries.first(where: { e in
                let n = e.lastPathComponent
                guard !n.hasPrefix("__"), !n.hasPrefix(".") else { return false }
                var isDir: ObjCBool = false
                fm.fileExists(atPath: e.path, isDirectory: &isDir)
                return isDir.boolValue
            })
        }

        if isBedrock {
            let worldsDir = unzipDir.appendingPathComponent("worlds", isDirectory: true)
            if let name = slotLevelName?.nonEmpty {
                let candidate = worldsDir.appendingPathComponent(name)
                if fm.fileExists(atPath: candidate.path) { return candidate }
            }
            return firstSubdir(worldsDir)
        } else {
            if let name = slotLevelName?.nonEmpty {
                let candidate = unzipDir.appendingPathComponent(name)
                if fm.fileExists(atPath: candidate.path) { return candidate }
            }
            // Find the primary overworld folder (not _nether / _the_end)
            if let entries = try? fm.contentsOfDirectory(at: unzipDir, includingPropertiesForKeys: nil) {
                let worlds = entries.filter { e in
                    let n = e.lastPathComponent
                    var isDir: ObjCBool = false
                    fm.fileExists(atPath: e.path, isDirectory: &isDir)
                    return isDir.boolValue && !n.hasSuffix("_nether") && !n.hasSuffix("_the_end")
                        && !n.hasPrefix("__") && !n.hasPrefix(".")
                }.sorted { $0.lastPathComponent < $1.lastPathComponent }
                return worlds.first
            }
        }
        return nil
    }

    /// Packages Chunker's output directory into a world.zip compatible with WorldSlotManager.
    /// Chunker writes world files DIRECTLY into the output directory (not into a subdirectory),
    /// so we move ALL output contents into the correct named folder before zipping.
    /// For a Java target: zip contains `{levelName}/`. For Bedrock: `worlds/{levelName}/`.
    /// Returns the URL of the created zip file (inside a `_package` subfolder of `outputDir`).
    func packageOutput(
        chunkerOutputDir: URL,
        isBedrockTarget: Bool,
        targetLevelName: String
    ) async throws -> URL {
        let fm = FileManager.default

        let packageDir = chunkerOutputDir.appendingPathComponent("_package", isDirectory: true)
        try fm.createDirectory(at: packageDir, withIntermediateDirectories: true)
        let zipURL = packageDir.appendingPathComponent("converted.zip")

        // All entries in outputDir except _package itself are world files
        guard let allEntries = try? fm.contentsOfDirectory(at: chunkerOutputDir, includingPropertiesForKeys: nil) else {
            throw ChunkerError.worldFolderNotFound
        }
        let worldEntries = allEntries.filter {
            $0.lastPathComponent != "_package" && !$0.lastPathComponent.hasPrefix(".")
        }
        guard !worldEntries.isEmpty else { throw ChunkerError.worldFolderNotFound }

        return try await Task.detached(priority: .userInitiated) {
            if isBedrockTarget {
                // Target zip structure: worlds/{targetLevelName}/...
                let worldDir = packageDir
                    .appendingPathComponent("worlds", isDirectory: true)
                    .appendingPathComponent(targetLevelName, isDirectory: true)
                try fm.createDirectory(at: worldDir, withIntermediateDirectories: true)
                for entry in worldEntries {
                    try fm.moveItem(at: entry, to: worldDir.appendingPathComponent(entry.lastPathComponent))
                }
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                p.currentDirectoryURL = packageDir
                p.arguments = ["-r", zipURL.path, "worlds"]
                p.standardOutput = FileHandle.nullDevice
                p.standardError = FileHandle.nullDevice
                try p.run(); p.waitUntilExit()
                guard p.terminationStatus == 0 else {
                    throw ChunkerError.conversionFailed("zip failed (status \(p.terminationStatus))")
                }
            } else {
                // Target zip structure: {targetLevelName}/...
                let worldDir = packageDir.appendingPathComponent(targetLevelName, isDirectory: true)
                try fm.createDirectory(at: worldDir, withIntermediateDirectories: true)
                for entry in worldEntries {
                    try fm.moveItem(at: entry, to: worldDir.appendingPathComponent(entry.lastPathComponent))
                }
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                p.currentDirectoryURL = packageDir
                p.arguments = ["-r", zipURL.path, targetLevelName]
                p.standardOutput = FileHandle.nullDevice
                p.standardError = FileHandle.nullDevice
                try p.run(); p.waitUntilExit()
                guard p.terminationStatus == 0 else {
                    throw ChunkerError.conversionFailed("zip failed (status \(p.terminationStatus))")
                }
            }
            return zipURL
        }.value
    }

    // MARK: - Version string helpers

    /// Attempts to infer the Chunker source format string from a ConfigServer's metadata.
    /// Returns e.g. "BEDROCK_1_21_80" or "JAVA_1_21_4" if resolvable, nil otherwise.
    func inferSourceFormatString(from server: ConfigServer) -> String? {
        if server.isBedrock {
            // Bedrock version stored as "1.21.80" → Chunker format "BEDROCK_R21_80"
            guard let ver = server.bedrockVersion?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
                  ver.uppercased() != "LATEST" else { return nil }
            let parts = ver.split(separator: ".").compactMap { Int($0) }
            guard parts.count >= 2 else { return nil }
            let minor = parts[1]
            let patch = parts.count >= 3 ? parts[2] : 0
            return patch == 0 ? "BEDROCK_R\(minor)" : "BEDROCK_R\(minor)_\(patch)"
        } else {
            // Extract from paper JAR filename: "paper-1.21.4-191.jar" → "JAVA_1_21_4"
            let filename = URL(fileURLWithPath: server.paperJarPath).lastPathComponent
            let pattern = #"paper-(\d+\.\d+(?:\.\d+)?)"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: filename, range: NSRange(filename.startIndex..., in: filename)),
               let range = Range(match.range(at: 1), in: filename) {
                return "JAVA_" + String(filename[range]).replacingOccurrences(of: ".", with: "_")
            }
            return nil
        }
    }

    /// Returns a human-readable label for a Chunker format string.
    /// Java: "JAVA_1_21_4" → "Java 1.21.4"
    /// Bedrock: "BEDROCK_R21_80" → "Bedrock 1.21.80", "BEDROCK_R12" → "Bedrock 1.12"
    func displayName(forFormat format: String) -> String {
        if format.hasPrefix("JAVA_") {
            let ver = String(format.dropFirst(5)).replacingOccurrences(of: "_", with: ".")
            return "Java \(ver)"
        } else if format.hasPrefix("BEDROCK_") {
            let raw = String(format.dropFirst(8))  // e.g. "R21_80" or "R12"
            if raw.hasPrefix("R") {
                let digits = String(raw.dropFirst())   // "21_80" or "12"
                let parts = digits.split(separator: "_")
                if let minor = parts.first.flatMap({ Int($0) }) {
                    if parts.count >= 2, let patch = Int(parts[1]) {
                        return "Bedrock 1.\(minor).\(patch)"
                    }
                    return "Bedrock 1.\(minor)"
                }
            }
            return "Bedrock \(raw.replacingOccurrences(of: "_", with: "."))"
        }
        return format
    }

    // MARK: - Sorting

    /// Numeric sort so that newer versions appear after older ones.
    private func chunkerFormatVersionOrder(_ a: String, _ b: String) -> Bool {
        func versionKey(_ s: String) -> [Int] {
            let withoutPrefix = s.hasPrefix("JAVA_") ? String(s.dropFirst(5))
                : s.hasPrefix("BEDROCK_") ? String(s.dropFirst(8))
                : s
            // Strip leading "R" for Bedrock R-notation
            let stripped = withoutPrefix.hasPrefix("R") ? String(withoutPrefix.dropFirst()) : withoutPrefix
            return stripped.split(separator: "_").compactMap { Int($0) }
        }
        let ka = versionKey(a)
        let kb = versionKey(b)
        for (x, y) in zip(ka, kb) {
            if x != y { return x < y }
        }
        return ka.count < kb.count
    }
}

// MARK: - String helper

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

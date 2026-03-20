// ResourcePackManager.swift
// MinecraftServerController
//
//
// Handles file placement and metadata reading for resource packs on both
// Java and Bedrock servers. The ViewModel calls these static methods;
// no UI code lives here.
//
// Java layout:
//   <serverDir>/resource-packs/<pack>.zip
//   server.properties  ->  resource-pack=<url or path>
//
// Bedrock layout:
//   <serverDir>/resource_packs/<pack.mcpack or extracted folder>
//   valid_known_packs.json  ->  array of { file_system, path, uuid, version, pack_type }
//
// NOTE: Bedrock's valid_known_packs.json is only authoritative when the server is
// stopped. We write it directly; BDS regenerates on next start.

import Foundation

// MARK: - Model

/// A resource pack installed on a server.
struct InstalledResourcePack: Identifiable, Hashable {
    let id: String           // UUID or derived filename key
    let name: String         // display name (filename without extension, or manifest name)
    let fileName: String     // actual filename on disk (e.g. "mythic.zip" or "mythic.mcpack")
    let fileURL: URL         // absolute path to the file
    let fileSizeBytes: Int64 // raw bytes, 0 if unknown
    let packType: PackType
    let isRequired: Bool     // Java only: whether the server forces it (resource-pack-sha1 set)

    enum PackType {
        case javaZip        // .zip in resource-packs/
        case bedrockMcpack  // .mcpack in resource_packs/
        case bedrockFolder  // extracted folder in resource_packs/
    }

    var fileSizeDisplay: String {
        ResourcePackManager.formatBytes(fileSizeBytes)
    }

    var typeLabel: String {
        switch packType {
        case .javaZip:        return "Java ZIP"
        case .bedrockMcpack:  return "Bedrock .mcpack"
        case .bedrockFolder:  return "Bedrock (folder)"
        }
    }

    var requirementLabel: String? {
        switch packType {
        case .javaZip:        return isRequired ? "Required" : "Optional"
        case .bedrockMcpack, .bedrockFolder: return nil  // Bedrock packs are always applied
        }
    }
}

// MARK: - Manager

enum ResourcePackManager {

    // MARK: - Directory helpers

    static func javaPacksDirectory(serverDir: String) -> URL {
        URL(fileURLWithPath: serverDir, isDirectory: true)
            .appendingPathComponent("resource-packs", isDirectory: true)
    }

    static func bedrockPacksDirectory(serverDir: String) -> URL {
        URL(fileURLWithPath: serverDir, isDirectory: true)
            .appendingPathComponent("resource_packs", isDirectory: true)
    }

    // MARK: - List installed packs

    /// Returns all packs installed for a Java server (files in resource-packs/).
    /// Reads server.properties to determine which pack (if any) is the active/required one.
    static func listJavaPacks(serverDir: String) -> [InstalledResourcePack] {
        let dir = javaPacksDirectory(serverDir: serverDir)
        let fm = FileManager.default

        guard fm.fileExists(atPath: dir.path) else { return [] }

        let props = ServerPropertiesManager.readProperties(serverDir: serverDir)
        let activePack = props["resource-pack"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasSHA1 = !(props["resource-pack-sha1"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty

        do {
            let contents = try fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            )

            return contents
                .filter { $0.pathExtension.lowercased() == "zip" }
                .map { url in
                    let attrs = try? url.resourceValues(forKeys: [.fileSizeKey])
                    let size = Int64(attrs?.fileSize ?? 0)
                    let name = url.deletingPathExtension().lastPathComponent
                    let isRequired = hasSHA1 && activePack.contains(url.lastPathComponent)

                    return InstalledResourcePack(
                        id: url.lastPathComponent,
                        name: name,
                        fileName: url.lastPathComponent,
                        fileURL: url,
                        fileSizeBytes: size,
                        packType: .javaZip,
                        isRequired: isRequired
                    )
                }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        } catch {
            return []
        }
    }

    /// Returns all packs installed for a Bedrock server (files/folders in resource_packs/).
    static func listBedrockPacks(serverDir: String) -> [InstalledResourcePack] {
        let dir = bedrockPacksDirectory(serverDir: serverDir)
        let fm = FileManager.default

        guard fm.fileExists(atPath: dir.path) else { return [] }

        do {
            let contents = try fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            var packs: [InstalledResourcePack] = []

            for url in contents {
                let attrs = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                let isDir = attrs?.isDirectory ?? false
                let ext = url.pathExtension.lowercased()

                if isDir {
                    let size = directorySizeInBytes(at: url)
                    let name = url.lastPathComponent
                    packs.append(InstalledResourcePack(
                        id: name,
                        name: name,
                        fileName: name,
                        fileURL: url,
                        fileSizeBytes: size,
                        packType: .bedrockFolder,
                        isRequired: false
                    ))
                } else if ext == "mcpack" || ext == "zip" {
                    let size = Int64(attrs?.fileSize ?? 0)
                    let name = url.deletingPathExtension().lastPathComponent
                    packs.append(InstalledResourcePack(
                        id: url.lastPathComponent,
                        name: name,
                        fileName: url.lastPathComponent,
                        fileURL: url,
                        fileSizeBytes: size,
                        packType: .bedrockMcpack,
                        isRequired: false
                    ))
                }
            }

            return packs.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

        } catch {
            return []
        }
    }

    // MARK: - Install packs

    /// Install a .zip resource pack for a Java server.
    /// Copies the file into resource-packs/, creating the directory if needed.
    /// Does NOT modify server.properties — the user can set it as active separately via setJavaActivePack.
    static func installJavaPack(from sourceURL: URL, serverDir: String) throws -> InstalledResourcePack {
        let dest = javaPacksDirectory(serverDir: serverDir)
        let fm = FileManager.default
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)

        var targetURL = dest.appendingPathComponent(sourceURL.lastPathComponent)

        var counter = 2
        while fm.fileExists(atPath: targetURL.path) {
            let base = sourceURL.deletingPathExtension().lastPathComponent
            let ext = sourceURL.pathExtension
            targetURL = dest.appendingPathComponent("\(base) (\(counter)).\(ext)")
            counter += 1
        }

        try fm.copyItem(at: sourceURL, to: targetURL)

        let attrs = try? targetURL.resourceValues(forKeys: [.fileSizeKey])
        let size = Int64(attrs?.fileSize ?? 0)

        return InstalledResourcePack(
            id: targetURL.lastPathComponent,
            name: targetURL.deletingPathExtension().lastPathComponent,
            fileName: targetURL.lastPathComponent,
            fileURL: targetURL,
            fileSizeBytes: size,
            packType: .javaZip,
            isRequired: false
        )
    }

    /// Install a .mcpack (or .zip) resource pack for a Bedrock server.
    /// Copies the file into resource_packs/, reads manifest.json, and updates valid_known_packs.json.
    static func installBedrockPack(from sourceURL: URL, serverDir: String) throws -> InstalledResourcePack {
        let dest = bedrockPacksDirectory(serverDir: serverDir)
        let fm = FileManager.default
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)

        var targetURL = dest.appendingPathComponent(sourceURL.lastPathComponent)

        var counter = 2
        while fm.fileExists(atPath: targetURL.path) {
            let base = sourceURL.deletingPathExtension().lastPathComponent
            let ext = sourceURL.pathExtension
            targetURL = dest.appendingPathComponent("\(base) (\(counter)).\(ext)")
            counter += 1
        }

        try fm.copyItem(at: sourceURL, to: targetURL)

        let attrs = try? targetURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
        let isDir = attrs?.isDirectory ?? false
        let size = isDir ? directorySizeInBytes(at: targetURL) : Int64(attrs?.fileSize ?? 0)

        let installedFileName = targetURL.lastPathComponent

        // Attempt to read manifest.json and update valid_known_packs.json.
        // Failure here is non-fatal: the file is already on disk.
        if let manifest = readBedrockManifest(from: targetURL, isDirectory: isDir) {
            ValidKnownPacksManager.upsertEntry(
                BedrockPackEntry(
                    file_system: "RawPath",
                    path: "resource_packs/\(installedFileName)",
                    uuid: manifest.uuid,
                    version: manifest.version,
                    pack_type: "resources"
                ),
                serverDir: serverDir
            )
        } else {
            #if DEBUG
            print("[ResourcePackManager] Warning: Could not read manifest.json from \(installedFileName). valid_known_packs.json was not updated.")
            #endif
        }

        return InstalledResourcePack(
            id: targetURL.lastPathComponent,
            name: targetURL.deletingPathExtension().lastPathComponent,
            fileName: installedFileName,
            fileURL: targetURL,
            fileSizeBytes: size,
            packType: isDir ? .bedrockFolder : .bedrockMcpack,
            isRequired: false
        )
    }

    // MARK: - Remove packs

    /// Remove a resource pack from disk (works for both Java and Bedrock).
    /// For Java, also clears server.properties resource-pack if it pointed to this file.
    /// For Bedrock, also removes the entry from valid_known_packs.json.
    static func removePack(_ pack: InstalledResourcePack, serverDir: String, isJava: Bool) throws {
        let fm = FileManager.default
        try fm.removeItem(at: pack.fileURL)

        if isJava {
            var props = ServerPropertiesManager.readProperties(serverDir: serverDir)
            let existing = props["resource-pack"]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if existing.contains(pack.fileName) {
                props["resource-pack"] = ""
                props["resource-pack-sha1"] = ""
                try ServerPropertiesManager.writeProperties(props, to: serverDir)
            }
        } else {
            ValidKnownPacksManager.removeEntry(matchingFileName: pack.fileName, serverDir: serverDir)
        }
    }

    // MARK: - Java: set active pack in server.properties

    /// Write the resource-pack field in server.properties for a Java server.
    /// Pass nil to clear the active pack.
    static func setJavaActivePack(_ pack: InstalledResourcePack?, serverDir: String) throws {
        var props = ServerPropertiesManager.readProperties(serverDir: serverDir)
        if let pack = pack {
            props["resource-pack"] = "resource-packs/\(pack.fileName)"
        } else {
            props["resource-pack"] = ""
            props["resource-pack-sha1"] = ""
        }
        try ServerPropertiesManager.writeProperties(props, to: serverDir)
    }

    // MARK: - Allowed file types

    static let javaAllowedTypes: [String] = ["zip"]
    static let bedrockAllowedTypes: [String] = ["mcpack", "zip"]

    // MARK: - Helpers

    static func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024.0
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024.0
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        return String(format: "%.1f GB", mb / 1024.0)
    }

    static func directorySizeInBytes(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let attrs = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(attrs?.fileSize ?? 0)
        }
        return total
    }

    // MARK: - Bedrock manifest reader

    /// Parsed subset of a Bedrock pack's manifest.json header block.
    private struct BedrockManifestResult {
        let uuid: String
        let version: [Int]
    }

    /// Reads manifest.json from an installed pack item (folder or .mcpack file).
    /// Returns nil if manifest cannot be found or parsed — caller handles gracefully.
    private static func readBedrockManifest(from packURL: URL, isDirectory: Bool) -> BedrockManifestResult? {
        let fm = FileManager.default

        if isDirectory {
            // Extracted folder: manifest.json is at the root of the folder.
            let manifestURL = packURL.appendingPathComponent("manifest.json")
            guard fm.fileExists(atPath: manifestURL.path),
                  let data = try? Data(contentsOf: manifestURL) else { return nil }
            return parseManifestData(data)
        } else {
            // .mcpack or .zip: it is a renamed zip archive.
            // Unzip to a temp directory, read manifest.json, then clean up.
            let tempDir = fm.temporaryDirectory
                .appendingPathComponent("msc_manifest_\(UUID().uuidString)", isDirectory: true)
            defer { try? fm.removeItem(at: tempDir) }

            do {
                try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
                // Use Process to unzip (Foundation has no built-in zip extraction on macOS)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                process.arguments = ["-q", packURL.path, "manifest.json", "-d", tempDir.path]
                try process.run()
                process.waitUntilExit()

                let manifestURL = tempDir.appendingPathComponent("manifest.json")
                guard fm.fileExists(atPath: manifestURL.path),
                      let data = try? Data(contentsOf: manifestURL) else { return nil }
                return parseManifestData(data)
            } catch {
                #if DEBUG
                print("[ResourcePackManager] Warning: Failed to extract manifest.json from \(packURL.lastPathComponent): \(error)")
                #endif
                return nil
            }
        }
    }

    /// Parse manifest.json data and extract header.uuid and header.version.
    private static func parseManifestData(_ data: Data) -> BedrockManifestResult? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let header = json["header"] as? [String: Any],
              let uuid = header["uuid"] as? String,
              let versionRaw = header["version"] as? [Any] else {
            return nil
        }

        // version may be [Int] or [NSNumber]; coerce safely
        let version = versionRaw.compactMap { v -> Int? in
            if let i = v as? Int { return i }
            if let n = v as? NSNumber { return n.intValue }
            return nil
        }

        guard version.count == 3 else { return nil }
        return BedrockManifestResult(uuid: uuid, version: version)
    }
}

// MARK: - ValidKnownPacksManager

/// Manages reading and writing of Bedrock's valid_known_packs.json.
/// All methods are non-throwing — errors are logged and swallowed to keep
/// the install/remove flow resilient.
private enum ValidKnownPacksManager {

    static func validKnownPacksURL(serverDir: String) -> URL {
        URL(fileURLWithPath: serverDir, isDirectory: true)
            .appendingPathComponent("valid_known_packs.json")
    }

    /// Read the current entries from valid_known_packs.json.
    /// Returns an empty array if the file is missing or malformed.
    static func readEntries(serverDir: String) -> [BedrockPackEntry] {
        let url = validKnownPacksURL(serverDir: serverDir)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return []
        }
        do {
            return try JSONDecoder().decode([BedrockPackEntry].self, from: data)
        } catch {
            #if DEBUG
            print("[ValidKnownPacksManager] Warning: Could not parse valid_known_packs.json: \(error). Starting fresh.")
            #endif
            return []
        }
    }

    /// Write entries back to valid_known_packs.json with pretty-print formatting.
    static func writeEntries(_ entries: [BedrockPackEntry], serverDir: String) {
        let url = validKnownPacksURL(serverDir: serverDir)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(entries)
            try data.write(to: url, options: .atomic)
        } catch {
            #if DEBUG
            print("[ValidKnownPacksManager] Warning: Failed to write valid_known_packs.json: \(error)")
            #endif
        }
    }

    /// Insert or replace an entry (matched by uuid). Creates the file if it does not exist.
    static func upsertEntry(_ entry: BedrockPackEntry, serverDir: String) {
        var entries = readEntries(serverDir: serverDir)
        entries.removeAll { $0.uuid == entry.uuid }
        entries.append(entry)
        writeEntries(entries, serverDir: serverDir)
    }

    /// Remove any entry whose path ends with the given filename.
    /// No-op if the file does not exist or cannot be parsed.
    static func removeEntry(matchingFileName fileName: String, serverDir: String) {
        guard FileManager.default.fileExists(atPath: validKnownPacksURL(serverDir: serverDir).path) else { return }
        var entries = readEntries(serverDir: serverDir)
        let before = entries.count
        entries.removeAll { entry in
            (entry.path as NSString).lastPathComponent == fileName
        }
        if entries.count != before {
            writeEntries(entries, serverDir: serverDir)
        }
    }
}

// MARK: - BedrockPackEntry

/// Codable representation of one entry in valid_known_packs.json.
struct BedrockPackEntry: Codable {
    var file_system: String
    var path: String
    var uuid: String
    var version: [Int]
    var pack_type: String
}

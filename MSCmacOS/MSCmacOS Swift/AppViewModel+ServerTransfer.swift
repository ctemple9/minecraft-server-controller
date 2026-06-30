//
//  AppViewModel+ServerTransfer.swift
//  MinecraftServerController
//
//  Transfer file feature (v2): export every server — settings, all world slots,
//  backups, plugins, resource packs, config files — into a single portable
//  .msctransfer package, then import that package on another Mac.
//
//  Design notes
//  ─────────────
//  Package layout:
//        manifest.json
//        servers/<folderName>/paper.jar           Java only
//        servers/<folderName>/world_slots/…       all world slots (wholesale)
//        servers/<folderName>/backups/…           all backups (wholesale)
//        servers/<folderName>/plugins/…           entire plugins dir
//        servers/<folderName>/resource-packs/…    entire resource-packs dir
//        servers/<folderName>/configs/…           top-level config files
//
//  App-level settings (Java path, Remote API token/port, Xbox broadcast account)
//  are intentionally excluded — those stay per-Mac.
//
//  Absolute paths are machine-specific: serverDir/paperJarPath are blanked on
//  export and re-rooted under the target Mac's serversRoot on import.
//
//  world_slots/ is copied wholesale so all slots and the active-slot marker
//  travel intact. No WorldSlotManager manipulation is needed on import.
//

import Foundation

// MARK: - Package layout constants

enum ServerTransfer {
    static let fileExtension = "msctransfer"
    /// v2: full world_slots + backups bundled, app-level settings excluded.
    static let formatVersion = 2
    static let manifestName = "manifest.json"

    /// Top-level server-dir names that are never bundled.
    static let excludedTopLevelDirs: Set<String> = [
        "logs", "cache", "crash-reports", "versions", "libraries",
        "world", "world_nether", "world_the_end",   // live folders superseded by world_slots
        ".git", "__MACOSX"
    ]

    static let configFileExtensions: Set<String> = [
        "properties", "yml", "yaml", "json", "txt", "toml", "conf"
    ]
}

// MARK: - Manifest models

struct TransferManifest: Codable {
    var formatVersion: Int
    var appConfigVersion: Int
    var createdAt: String           // ISO8601
    var sourceMachineName: String
    var servers: [TransferServerEntry]
}

/// One server's settings plus bundling metadata. Absolute paths are blanked.
struct TransferServerEntry: Codable {
    var server: ConfigServer
    var folderName: String          // sanitised, de-duped dir name inside the package
    var javaPort: Int?              // from server.properties; used for conflict detection
    var paperMCVersion: String?
    var paperBuild: Int?
    var bundledPaperJar: Bool
    var pluginLinks: [TransferPluginLink]
}

struct TransferPluginLink: Codable {
    var filename: String
    var url: String
    var type: String                // PluginSourceType raw value
}

// MARK: - Result / summary types

enum TransferResult<Success> {
    case success(Success)
    case failure(String)
}

struct TransferExportSummary {
    var serverCount: Int
    var destination: URL
}

struct TransferImportPlan {
    var stagingDir: URL             // caller must clean up on cancel/complete
    var manifest: TransferManifest
    var servers: [Row]

    struct Row: Identifiable {
        var id: String { entry.server.id }
        var entry: TransferServerEntry
        var displayName: String
        var serverTypeLabel: String
        var portConflict: Bool
        var conflictDetail: String?
    }
}

struct TransferImportSummary {
    var imported: Int
    var skipped: Int
    var replaced: Bool
}

enum TransferImportMode {
    case merge      // add alongside existing servers
    case replaceAll // remove existing servers, then import
}

// MARK: - Export

extension AppViewModel {

    /// Builds a `.msctransfer` package at `destination` for every configured server.
    func exportServerTransfer(to destination: URL) async -> TransferResult<TransferExportSummary> {
        let cfg = configManager.config
        let servers = cfg.servers
        guard !servers.isEmpty else { return .failure("There are no servers to export.") }

        let fm = FileManager.default
        let staging = fm.temporaryDirectory
            .appendingPathComponent("msc_export_\(UUID().uuidString)", isDirectory: true)
        let serversDir = staging.appendingPathComponent("servers", isDirectory: true)

        defer { try? fm.removeItem(at: staging) }

        let log: (String) -> Void = { [weak self] msg in
            Task { @MainActor in self?.logAppMessage(msg) }
        }

        return await Task.detached(priority: .userInitiated) { () -> TransferResult<TransferExportSummary> in
            do {
                try fm.createDirectory(at: serversDir, withIntermediateDirectories: true)

                var entries: [TransferServerEntry] = []
                var usedFolderNames = Set<String>()

                for server in servers {
                    let folderName = ServerTransfer.uniqueTransferFolderName(
                        for: server, taken: &usedFolderNames
                    )
                    let outDir = serversDir.appendingPathComponent(folderName, isDirectory: true)
                    try fm.createDirectory(at: outDir, withIntermediateDirectories: true)

                    let serverURL = URL(fileURLWithPath: server.serverDir, isDirectory: true)

                    // 1. Paper jar (Java only)
                    var bundledPaperJar = false
                    if server.isJava {
                        let jarURL = URL(fileURLWithPath: server.paperJarPath)
                        if fm.fileExists(atPath: jarURL.path) {
                            try? fm.copyItem(at: jarURL, to: outDir.appendingPathComponent("paper.jar"))
                            bundledPaperJar = true
                        }
                    }

                    // 2. World slots, backups, plugins, mods, resource packs — all wholesale
                    for sub in ["world_slots", "backups", "plugins", "mods", "resource-packs"] {
                        let src = serverURL.appendingPathComponent(sub, isDirectory: true)
                        if fm.fileExists(atPath: src.path) {
                            try? fm.copyItem(at: src, to: outDir.appendingPathComponent(sub, isDirectory: true))
                        }
                    }

                    // 2c. NeoForge/Forge: bundle libraries/ (required for server launch; not re-runnable on import)
                    if server.javaFlavor == .neoforge || server.javaFlavor == .forge {
                        let libSrc = serverURL.appendingPathComponent("libraries", isDirectory: true)
                        if fm.fileExists(atPath: libSrc.path) {
                            try? fm.copyItem(at: libSrc, to: outDir.appendingPathComponent("libraries", isDirectory: true))
                        }
                    }

                    // 2b. Live world directories — the server's current on-disk world, which
                    //     may be newer than the most recent slot zip. Copied directly so the
                    //     import always reflects the exact state the server was last left in.
                    for folderName in WorldSlotManager.worldFolderNames(for: server) {
                        let src = serverURL.appendingPathComponent(folderName, isDirectory: true)
                        if fm.fileExists(atPath: src.path) {
                            try? fm.copyItem(at: src, to: outDir.appendingPathComponent(folderName, isDirectory: true))
                        }
                    }

                    // 3. Top-level config files → configs/
                    let configsDir = outDir.appendingPathComponent("configs", isDirectory: true)
                    try? fm.createDirectory(at: configsDir, withIntermediateDirectories: true)
                    if let items = try? fm.contentsOfDirectory(
                        at: serverURL,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: [.skipsHiddenFiles]
                    ) {
                        for item in items {
                            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                            guard !isDir else { continue }
                            guard ServerTransfer.configFileExtensions.contains(item.pathExtension.lowercased()) else { continue }
                            try? fm.copyItem(at: item, to: configsDir.appendingPathComponent(item.lastPathComponent))
                        }
                    }

                    // 4. Read Java port for conflict detection on import
                    var javaPort: Int? = nil
                    if server.isJava {
                        let props = ServerPropertiesManager.readProperties(serverDir: serverURL.path)
                        javaPort = Int(props["server-port"] ?? "")
                    }

                    // 5. Paper version sidecar
                    let sidecar = PaperVersionSidecarManager.read(fromServerDirectory: serverURL)

                    // 6. Plugin source links (informational)
                    var pluginLinks: [TransferPluginLink] = []
                    if let sources = server.pluginSources {
                        for (stem, src) in sources {
                            pluginLinks.append(TransferPluginLink(filename: stem, url: src.url, type: src.type.rawValue))
                        }
                    }

                    // 7. Sanitise: strip machine-specific paths and per-mac Xbox account
                    var sanitized = server
                    sanitized.serverDir = ""
                    sanitized.paperJarPath = ""
                    sanitized.xboxBroadcastConfigPath = nil
                    sanitized.xboxBroadcastAltEmail = nil
                    sanitized.xboxBroadcastAltGamertag = nil
                    sanitized.xboxBroadcastAltPassword = nil
                    sanitized.xboxBroadcastAltAvatarPath = nil

                    entries.append(TransferServerEntry(
                        server: sanitized,
                        folderName: folderName,
                        javaPort: javaPort,
                        paperMCVersion: sidecar?.mcVersion,
                        paperBuild: sidecar?.build,
                        bundledPaperJar: bundledPaperJar,
                        pluginLinks: pluginLinks
                    ))
                    log("[Transfer] Bundled \(server.displayName).")
                }

                let manifest = TransferManifest(
                    formatVersion: ServerTransfer.formatVersion,
                    appConfigVersion: AppConfig.latestConfigVersion,
                    createdAt: ISO8601DateFormatter().string(from: Date()),
                    sourceMachineName: Host.current().localizedName ?? "Unknown Mac",
                    servers: entries
                )

                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(manifest).write(
                    to: staging.appendingPathComponent(ServerTransfer.manifestName),
                    options: .atomic
                )

                if fm.fileExists(atPath: destination.path) {
                    try? fm.removeItem(at: destination)
                }
                try ServerTransfer.zipDirectoryContents(staging, to: destination)

                log("[Transfer] Exported \(entries.count) server(s) → \(destination.lastPathComponent)")
                return .success(TransferExportSummary(serverCount: entries.count, destination: destination))
            } catch {
                return .failure("Export failed: \(error.localizedDescription)")
            }
        }.value
    }
}

// MARK: - Import

extension AppViewModel {

    /// Unzips and parses a package. The caller owns `plan.stagingDir` and must remove it when done.
    func inspectTransferPackage(at url: URL) async -> TransferResult<TransferImportPlan> {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory
            .appendingPathComponent("msc_import_\(UUID().uuidString)", isDirectory: true)

        let existing = configManager.config.servers
        let existingJavaPorts: Set<Int> = Set(existing.compactMap { s -> Int? in
            guard s.isJava else { return nil }
            return Int(ServerPropertiesManager.readProperties(serverDir: s.serverDir)["server-port"] ?? "")
        })
        let existingBedrockPorts: Set<Int> = Set(existing.compactMap { $0.isBedrock ? $0.bedrockPort : nil })

        return await Task.detached(priority: .userInitiated) { () -> TransferResult<TransferImportPlan> in
            do {
                try fm.createDirectory(at: staging, withIntermediateDirectories: true)
                try ServerTransfer.unzip(url, to: staging)

                let manifestURL = staging.appendingPathComponent(ServerTransfer.manifestName)
                guard fm.fileExists(atPath: manifestURL.path) else {
                    try? fm.removeItem(at: staging)
                    return .failure("This file is not a valid MSC transfer package (no manifest).")
                }

                let manifest = try JSONDecoder().decode(
                    TransferManifest.self,
                    from: Data(contentsOf: manifestURL)
                )

                guard manifest.formatVersion <= ServerTransfer.formatVersion else {
                    try? fm.removeItem(at: staging)
                    return .failure("This transfer file was created by a newer version of MSC. Update the app and try again.")
                }

                let rows: [TransferImportPlan.Row] = manifest.servers.map { entry in
                    var conflict = false
                    var detail: String? = nil
                    if entry.server.isJava, let p = entry.javaPort, existingJavaPorts.contains(p) {
                        conflict = true
                        detail = "Java port \(p) is already in use — edit below."
                    } else if entry.server.isBedrock, let p = entry.server.bedrockPort, existingBedrockPorts.contains(p) {
                        conflict = true
                        detail = "Bedrock port \(p) is already in use — edit below."
                    }
                    return TransferImportPlan.Row(
                        entry: entry,
                        displayName: entry.server.displayName,
                        serverTypeLabel: entry.server.serverType.displayName,
                        portConflict: conflict,
                        conflictDetail: detail
                    )
                }

                return .success(TransferImportPlan(stagingDir: staging, manifest: manifest, servers: rows))
            } catch {
                try? fm.removeItem(at: staging)
                return .failure("Could not read transfer file: \(error.localizedDescription)")
            }
        }.value
    }

    /// Applies a previously-inspected import plan.
    /// - Parameters:
    ///   - mode: merge into, or replace, the existing server set.
    ///   - javaPortOverrides: map of source server id → new Java port (only entries that changed).
    ///   - bedrockPortOverrides: map of source server id → new Bedrock port (only entries that changed).
    func applyTransferImport(
        plan: TransferImportPlan,
        mode: TransferImportMode,
        javaPortOverrides: [String: Int],
        bedrockPortOverrides: [String: Int]
    ) async -> TransferResult<TransferImportSummary> {

        let fm = FileManager.default
        let manifest = plan.manifest
        let staging = plan.stagingDir
        let root = configManager.serversRootURL

        let log: (String) -> Void = { [weak self] msg in
            Task { @MainActor in self?.logAppMessage(msg) }
        }

        let buildResult: TransferResult<([ConfigServer], Int, Int)> =
            await Task.detached(priority: .userInitiated) {
                () -> TransferResult<([ConfigServer], Int, Int)> in

            var newServers: [ConfigServer] = []
            var imported = 0
            var skipped = 0

            for entry in manifest.servers {
                let typeSubdir = entry.server.isJava ? "java" : "bedrock"
                let typeRoot = root.appendingPathComponent(typeSubdir, isDirectory: true)
                do { try fm.createDirectory(at: typeRoot, withIntermediateDirectories: true) }
                catch {
                    skipped += 1
                    log("[Transfer] Skipped \(entry.server.displayName): \(error.localizedDescription)")
                    continue
                }

                // Choose a non-colliding destination folder
                var folderName = entry.folderName
                var destURL = typeRoot.appendingPathComponent(folderName, isDirectory: true)
                var counter = 2
                while fm.fileExists(atPath: destURL.path) {
                    folderName = "\(entry.folderName)-\(counter)"
                    destURL = typeRoot.appendingPathComponent(folderName, isDirectory: true)
                    counter += 1
                }

                let pkgDir = staging
                    .appendingPathComponent("servers", isDirectory: true)
                    .appendingPathComponent(entry.folderName, isDirectory: true)

                do {
                    try fm.createDirectory(at: destURL, withIntermediateDirectories: true)

                    // configs/ → server-dir top level
                    let configsDir = pkgDir.appendingPathComponent("configs", isDirectory: true)
                    if let cfgs = try? fm.contentsOfDirectory(
                        at: configsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
                    ) {
                        for f in cfgs {
                            try? fm.copyItem(at: f, to: destURL.appendingPathComponent(f.lastPathComponent))
                        }
                    }

                    // world_slots/, backups/, plugins/, mods/, resource-packs/
                    for sub in ["world_slots", "backups", "plugins", "mods", "resource-packs"] {
                        let src = pkgDir.appendingPathComponent(sub, isDirectory: true)
                        if fm.fileExists(atPath: src.path) {
                            try fm.copyItem(at: src, to: destURL.appendingPathComponent(sub, isDirectory: true))
                        }
                    }

                    // NeoForge/Forge: restore libraries/ (bundled on export; required for launch)
                    if entry.server.javaFlavor == .neoforge || entry.server.javaFlavor == .forge {
                        let libSrc = pkgDir.appendingPathComponent("libraries", isDirectory: true)
                        if fm.fileExists(atPath: libSrc.path) {
                            try? fm.copyItem(at: libSrc, to: destURL.appendingPathComponent("libraries", isDirectory: true))
                        }
                    }

                    // paper.jar (only present when bundledPaperJar is true; NeoForge/Forge use @unix_args.txt instead)
                    var paperJarPath = ""
                    if entry.server.isJava && entry.bundledPaperJar {
                        let jar = pkgDir.appendingPathComponent("paper.jar")
                        let destJar = destURL.appendingPathComponent("paper.jar")
                        if fm.fileExists(atPath: jar.path) {
                            try? fm.copyItem(at: jar, to: destJar)
                            paperJarPath = destJar.path
                        }
                    }

                    // Apply Java port override → rewrite server.properties
                    if entry.server.isJava, let portOverride = javaPortOverrides[entry.server.id] {
                        ServerTransfer.updateServerPropertiesPort(in: destURL, port: portOverride)
                    }

                    var cfgServer = entry.server
                    cfgServer.id = UUID().uuidString
                    cfgServer.serverDir = destURL.path
                    cfgServer.paperJarPath = paperJarPath
                    cfgServer.xboxBroadcastConfigPath = nil

                    // Apply Bedrock port override → ConfigServer
                    if entry.server.isBedrock, let portOverride = bedrockPortOverrides[entry.server.id] {
                        cfgServer.bedrockPort = portOverride
                    }

                    // Restore world data. Prefer live world folders bundled in the package
                    // (exact state the server was left in). Fall back to slot restore only
                    // for older transfer files that don't have them.
                    var restoredLiveWorld = false
                    if entry.server.isJava {
                        // level-name is in the already-copied server.properties at destURL
                        let props = ServerPropertiesManager.readProperties(serverDir: destURL.path)
                        let raw = props["level-name"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let levelName = raw.isEmpty ? "world" : raw
                        for candidate in [levelName, "\(levelName)_nether", "\(levelName)_the_end"] {
                            let src = pkgDir.appendingPathComponent(candidate, isDirectory: true)
                            if fm.fileExists(atPath: src.path) {
                                try? fm.copyItem(at: src, to: destURL.appendingPathComponent(candidate, isDirectory: true))
                                restoredLiveWorld = true
                            }
                        }
                    } else {
                        let src = pkgDir.appendingPathComponent("worlds", isDirectory: true)
                        if fm.fileExists(atPath: src.path) {
                            try? fm.copyItem(at: src, to: destURL.appendingPathComponent("worlds", isDirectory: true))
                            restoredLiveWorld = true
                        }
                    }

                    if !restoredLiveWorld, let activeSlot = WorldSlotManager.activeSlot(forServerDir: destURL.path) {
                        await WorldSlotManager.activateSlot(
                            activeSlot,
                            for: cfgServer,
                            backupCurrent: false,
                            logLine: log,
                            backupWorld: { _ in true }
                        )
                    }

                    newServers.append(cfgServer)
                    imported += 1
                    log("[Transfer] Imported \(cfgServer.displayName) → \(destURL.path)")
                } catch {
                    skipped += 1
                    log("[Transfer] Skipped \(entry.server.displayName): \(error.localizedDescription)")
                    try? fm.removeItem(at: destURL)
                }
            }

            return .success((newServers, imported, skipped))
        }.value

        guard case let .success((newServers, imported, skipped)) = buildResult else {
            if case let .failure(msg) = buildResult { return .failure(msg) }
            return .failure("Import failed.")
        }

        return await MainActor.run { () -> TransferResult<TransferImportSummary> in
            var appConfig = configManager.config

            if mode == .replaceAll {
                let removedIDs = appConfig.servers.map(\.id)
                _ = KeychainManager.shared.deleteAllMSCSecrets(serverIDs: removedIDs)
                appConfig.servers = []
            }

            appConfig.servers.append(contentsOf: newServers)
            if appConfig.activeServerId == nil || mode == .replaceAll {
                appConfig.activeServerId = newServers.first?.id ?? appConfig.servers.first?.id
            }

            configManager.config = appConfig
            configManager.save()
            reloadServersFromConfig()
            try? fm.removeItem(at: staging)

            logAppMessage("[Transfer] Import complete: \(imported) added, \(skipped) skipped\(mode == .replaceAll ? " (replaced existing set)" : "").")
            return .success(TransferImportSummary(imported: imported, skipped: skipped, replaced: mode == .replaceAll))
        }
    }
}

// MARK: - Shared helpers
//
// Live on the non-isolated ServerTransfer enum so they can be called from
// background Task.detached closures without main-actor isolation errors.

extension ServerTransfer {

    static func uniqueTransferFolderName(for server: ConfigServer, taken: inout Set<String>) -> String {
        let raw = server.displayName.lowercased().replacingOccurrences(of: " ", with: "_")
        var base = String(raw.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }.prefix(40))
        if base.isEmpty { base = "server" }
        var name = base
        var n = 2
        while taken.contains(name) { name = "\(base)-\(n)"; n += 1 }
        taken.insert(name)
        return name
    }

    /// Rewrites the `server-port=` line in a just-copied server.properties.
    static func updateServerPropertiesPort(in dir: URL, port: Int) {
        let propsURL = dir.appendingPathComponent("server.properties")
        guard var content = try? String(contentsOf: propsURL, encoding: .utf8) else { return }
        content = content
            .components(separatedBy: "\n")
            .map { $0.hasPrefix("server-port=") ? "server-port=\(port)" : $0 }
            .joined(separator: "\n")
        try? content.write(to: propsURL, atomically: true, encoding: .utf8)
    }

    static func zipDirectoryContents(_ dir: URL, to destination: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        p.currentDirectoryURL = dir
        p.arguments = ["-r", "-q", "-X", destination.path, "."]
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw NSError(domain: "MSC.Transfer", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "zip failed (exit \(p.terminationStatus))."])
        }
    }

    static func unzip(_ archive: URL, to dir: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-q", "-o", archive.path, "-d", dir.path]
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw NSError(domain: "MSC.Transfer", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "unzip failed (exit \(p.terminationStatus))."])
        }
    }
}

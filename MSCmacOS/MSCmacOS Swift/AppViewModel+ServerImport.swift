//
//  AppViewModel+ServerImport.swift
//  MinecraftServerController
//
//  Handles importing an existing server folder or .zip archive into MSC.
//  Scans for server type, port, EULA, and available worlds.
//  Called by AddServerWizardView after the user confirms their selections.
//

import Foundation

// MARK: - Scan data models (shared with AddServerWizardView)

struct ScannedServerInfo {
    var serverType: ServerType
    var port: Int
    var maxPlayers: Int
    var eulaAccepted: Bool
    var worlds: [DetectedWorld]
    var defaultWorldName: String?
    // Java flavor detection (nil for Bedrock)
    var javaFlavor: JavaServerFlavor?
    var detectedMCVersion: String?
    var detectedLoaderVersion: String?
}

// MARK: - Flavor detection result

struct DetectedJavaFlavor {
    var flavor: JavaServerFlavor
    var mcVersion: String?
    var loaderVersion: String?
    var primaryJarPath: String?  // nil for NeoForge (uses unix_args.txt)
}

struct DetectedWorld: Identifiable {
    var id: String { name }
    var name: String
    var folderPath: URL
    var sizeBytes: Int64
    var hasNether: Bool
    var hasEnd: Bool

    var dimensionsLabel: String {
        var dims = ["Overworld"]
        if hasNether { dims.append("Nether") }
        if hasEnd    { dims.append("End") }
        return dims.joined(separator: " + ")
    }

    var formattedSize: String {
        let mb = Double(sizeBytes) / 1_048_576.0
        if mb < 1  { return "<1 MB" }
        if mb < 1000 { return String(format: "%.0f MB", mb) }
        return String(format: "%.1f GB", mb / 1000.0)
    }
}

// MARK: - AppViewModel extension

extension AppViewModel {

    enum ImportServerResult {
        case success
        case failure(String)
    }

    // MARK: - Import Existing Server

    /// Copies (or unzips) `sourceURL` into the MSC servers directory, registers
    /// the server in config, creates an initial world slot, and makes it active.
    func importExistingServer(
            sourceURL: URL,
            isZip: Bool,
            displayName: String,
            serverType: ServerType,
            activeWorldName: String?,
            portOverride: Int? = nil,
            maxPlayersOverride: Int? = nil,
            eulaOverride: Bool? = nil,
            enablePlayit: Bool = false
        ) async -> ImportServerResult {

        let safeName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !safeName.isEmpty else { return .failure("Display name cannot be empty.") }

        let fm = FileManager.default

        // Sanitize folder name
        let rawFolder = safeName.lowercased()
            .replacingOccurrences(of: " ", with: "_")
        let sanitizedFolder = String(rawFolder.filter {
            $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-"
        }.prefix(40))

        let root      = configManager.serversRootURL
        let typeSubdir = serverType == .java ? "java" : "bedrock"
        let typeRoot  = root.appendingPathComponent(typeSubdir, isDirectory: true)
        let destURL   = typeRoot.appendingPathComponent(sanitizedFolder, isDirectory: true)

        // Create type root directory if needed
        if !fm.fileExists(atPath: typeRoot.path) {
            do { try fm.createDirectory(at: typeRoot, withIntermediateDirectories: true) }
            catch { return .failure("Could not create servers directory: \(error.localizedDescription)") }
        }

        // Prevent overwrite
        if fm.fileExists(atPath: destURL.path) {
            return .failure("A folder named \"\(sanitizedFolder)\" already exists. Choose a different display name.")
        }

        // Copy or unzip to destination
        let copyResult: ImportServerResult = await Task.detached(priority: .userInitiated) {
            if isZip {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                p.arguments = ["-q", sourceURL.path, "-d", destURL.path]
                do { try p.run(); p.waitUntilExit() }
                catch { return .failure("Failed to start unzip: \(error.localizedDescription)") }
                guard p.terminationStatus == 0 else {
                    return .failure("Unzip failed (exit \(p.terminationStatus)). Ensure the file is a valid .zip archive.")
                }
            } else {
                do { try FileManager.default.copyItem(at: sourceURL, to: destURL) }
                catch { return .failure("Could not copy server folder: \(error.localizedDescription)") }
            }
            return .success
        }.value

        if case .failure = copyResult { return copyResult }

        // If the zip contained a single top-level folder, unwrap it
        let effectiveDir = resolvedImportDir(in: destURL, fm: fm)

        // Detect Java flavor and locate primary jar
        let detectedFlavor: DetectedJavaFlavor?
        let paperJarPath: String
        if serverType == .java {
            let d = AppViewModel.detectJavaFlavor(in: effectiveDir)
            detectedFlavor = d
            paperJarPath = d.primaryJarPath ?? ""
        } else {
            detectedFlavor = nil
            paperJarPath = ""
        }

        // Read port from properties
        let port: Int
        if serverType == .java {
            let props = ServerPropertiesManager.readProperties(serverDir: effectiveDir.path)
            port = Int(props["server-port"] ?? "") ?? 25565
        } else {
            let props = BedrockPropertiesManager.readRawProperties(serverDir: effectiveDir.path)
            port = Int(props["server-port"] ?? "") ?? 19132
        }

            // Apply user overrides (port, max players, world name, EULA) to properties
                    if serverType == .java {
                        var props = ServerPropertiesManager.readProperties(serverDir: effectiveDir.path)
                        if let worldName = activeWorldName { props["level-name"] = worldName }
                        if let port = portOverride         { props["server-port"] = "\(port)" }
                        if let maxP = maxPlayersOverride   { props["max-players"] = "\(maxP)" }
                        try? ServerPropertiesManager.writeProperties(props, to: effectiveDir.path)
                    } else {
                        var props = BedrockPropertiesManager.readRawProperties(serverDir: effectiveDir.path)
                        if let port = portOverride         { props["server-port"] = "\(port)" }
                        if let maxP = maxPlayersOverride   { props["max-players"] = "\(maxP)" }
                        try? BedrockPropertiesManager.writeRawProperties(props, serverDir: effectiveDir.path)
                    }

                    // Write EULA if user accepted it in the wizard
                    if let eula = eulaOverride, eula {
                        let eulaPath = effectiveDir.appendingPathComponent("eula.txt")
                        try? "eula=true\n".write(to: eulaPath, atomically: true, encoding: .utf8)
                    }

        // Build ConfigServer
        let newId = UUID().uuidString
        var cfgServer = ConfigServer(
            id: newId,
            displayName: safeName,
            serverDir: effectiveDir.path,
            paperJarPath: paperJarPath,
            minRamGB: 2,
            maxRamGB: 4,
            notes: ""
        )
        cfgServer.serverType     = serverType
        cfgServer.bedrockPort    = serverType == .bedrock ? port : nil
        cfgServer.bannerColorHex = configManager.config.defaultBannerColorHex
        cfgServer.playitEnabled  = enablePlayit
        if let d = detectedFlavor {
            cfgServer.javaFlavor       = d.flavor
            cfgServer.minecraftVersion = d.mcVersion
            cfgServer.loaderVersion    = d.loaderVersion
        }

        // Create initial world slot from whatever world data is in the server folder
        let logLine: (String) -> Void = { [weak self] msg in
            Task { @MainActor in self?.logAppMessage(msg) }
        }

        let slotName = activeWorldName ?? safeName
        let slot = await WorldSlotManager.createSlot(
            name: slotName,
            for: cfgServer,
            worldSeed: nil,
            logLine: logLine
        )

        if let slot = slot {
            do {
                try WorldSlotManager.setActiveSlotID(slot.id, forServerDir: cfgServer.serverDir)
            } catch {
                logLine("[Import] Warning — could not set active slot: \(error.localizedDescription)")
            }
        } else {
            logLine("[Import] No world data found in imported folder; world slot not created. A slot will be created after the first server start.")
        }

        upsertServer(cfgServer)
        setActiveServer(withId: newId)
        logAppMessage("[Import] Server \"\(safeName)\" imported from \(sourceURL.lastPathComponent).")
        return .success
    }

    // MARK: - Scan a server directory

    /// Reads server properties, detects server type, locates world folders,
    /// and returns a `ScannedServerInfo`. Called before the folder is copied
    /// into the MSC servers root so the user can review before committing.
    func scanServerDirectory(_ dirURL: URL) -> ScannedServerInfo {
        let fm = FileManager.default
        let javaProps    = ServerPropertiesManager.readProperties(serverDir: dirURL.path)
        let bedrockProps = BedrockPropertiesManager.readRawProperties(serverDir: dirURL.path)

        // Detect server type: presence of a .jar means Java; bedrock_server binary means Bedrock
        let contents = (try? fm.contentsOfDirectory(atPath: dirURL.path)) ?? []
        let hasJar = contents.contains { $0.lowercased().hasSuffix(".jar") }
        let hasBedrock = contents.contains {
            $0 == "bedrock_server" || $0 == "bedrock_server.exe"
        }
        let detectedType: ServerType = (hasBedrock && !hasJar) ? .bedrock : .java

        let rawProps   = detectedType == .java ? javaProps : bedrockProps
        let port       = Int(rawProps["server-port"] ?? "") ?? (detectedType == .java ? 25565 : 19132)
        let maxPlayers = Int(rawProps["max-players"] ?? "") ?? 20

        // EULA
        let eulaContent = (try? String(
            contentsOf: dirURL.appendingPathComponent("eula.txt"), encoding: .utf8
        )) ?? ""
        let eulaAccepted = eulaContent.contains("eula=true")

        // Level name configured in properties (used to rank worlds)
        let configuredLevelName = rawProps["level-name"] ?? "world"

        // Scan for world folders: any subdirectory that contains level.dat
                var rawWorlds: [(name: String, url: URL)] = []
                var seenNames = Set<String>()

                // Check both MSC-style worlds/ subdirectory and the server root
                let searchRoots: [URL] = [
                    dirURL.appendingPathComponent("worlds", isDirectory: true),
                    dirURL
                ]

                let skipDirs: Set<String> = [
                    "plugins", "logs", "cache", "crash-reports", "libraries",
                    "versions", "mods", "config", "backups", "worlds", "__MACOSX"
                ]

                for searchRoot in searchRoots {
                    guard let subdirs = try? fm.contentsOfDirectory(
                        at: searchRoot,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: .skipsHiddenFiles
                    ) else { continue }

                    for subdir in subdirs {
                        guard (try? subdir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                        else { continue }

                        let name = subdir.lastPathComponent
                        guard !seenNames.contains(name),
                              !skipDirs.contains(name),
                              !name.hasPrefix(".")
                        else { continue }

                        // A valid Minecraft world must have level.dat
                        guard fm.fileExists(atPath: subdir.appendingPathComponent("level.dat").path)
                        else { continue }

                        seenNames.insert(name)
                        rawWorlds.append((name: name, url: subdir))
                    }
                }

                // Group vanilla dimension companions (_nether, _the_end) into their root world.
                // e.g. project_jc, project_jc_nether, project_jc_the_end → one entry: project_jc
                let allNames = Set(rawWorlds.map(\.name))
                var worlds: [DetectedWorld] = []

                for entry in rawWorlds {
                    let name = entry.name

                    // Skip if this folder is a dimension companion of another detected world
                    let isNetherOf  = name.hasSuffix("_nether") && allNames.contains(String(name.dropLast("_nether".count)))
                    let isEndOf     = name.hasSuffix("_the_end") && allNames.contains(String(name.dropLast("_the_end".count)))
                    if isNetherOf || isEndOf { continue }

                    // Locate companion folders for this root world
                    let netherName  = "\(name)_nether"
                    let endName     = "\(name)_the_end"
                    let netherURL   = entry.url.deletingLastPathComponent().appendingPathComponent(netherName)
                    let endURL      = entry.url.deletingLastPathComponent().appendingPathComponent(endName)

                    // hasNether: inline DIM-1 folder OR a standalone companion folder
                    let hasNetherInline     = fm.fileExists(atPath: entry.url.appendingPathComponent("DIM-1").path)
                    let hasNetherCompanion  = allNames.contains(netherName)
                    let hasNether           = hasNetherInline || hasNetherCompanion

                    let hasEndInline        = fm.fileExists(atPath: entry.url.appendingPathComponent("DIM1").path)
                    let hasEndCompanion     = allNames.contains(endName)
                    let hasEnd              = hasEndInline || hasEndCompanion

                    // Sum size across root + any companion folders
                    var sizeBytes = directorySizeBytes(at: entry.url, fm: fm)
                    if hasNetherCompanion { sizeBytes += directorySizeBytes(at: netherURL, fm: fm) }
                    if hasEndCompanion    { sizeBytes += directorySizeBytes(at: endURL,    fm: fm) }

                    worlds.append(DetectedWorld(
                        name: name,
                        folderPath: entry.url,
                        sizeBytes: sizeBytes,
                        hasNether: hasNether,
                        hasEnd: hasEnd
                    ))
                }

                // Sort so the configured level-name world appears first
                worlds.sort { a, b in
                    if a.name == configuredLevelName { return true }
                    if b.name == configuredLevelName { return false }
                    return a.name < b.name
                }

        let flavorInfo = detectedType == .java ? AppViewModel.detectJavaFlavor(in: dirURL) : nil

        return ScannedServerInfo(
            serverType: detectedType,
            port: port,
            maxPlayers: maxPlayers,
            eulaAccepted: eulaAccepted,
            worlds: worlds,
            defaultWorldName: worlds.first?.name ?? configuredLevelName,
            javaFlavor: flavorInfo?.flavor,
            detectedMCVersion: flavorInfo?.mcVersion,
            detectedLoaderVersion: flavorInfo?.loaderVersion
        )
    }

    // MARK: - Java flavor detection

    /// Inspects a Java server directory and returns the detected flavor, MC version,
    /// loader version, and path to the primary jar (nil for NeoForge).
    static func detectJavaFlavor(in dir: URL) -> DetectedJavaFlavor {
        let fm = FileManager.default

        // 1. NeoForge — unique libraries/net/neoforged/neoforge/<version>/unix_args.txt
        let neoBase = dir.appendingPathComponent("libraries/net/neoforged/neoforge", isDirectory: true)
        if let vDirs = try? fm.contentsOfDirectory(at: neoBase, includingPropertiesForKeys: nil) {
            for vDir in vDirs {
                if fm.fileExists(atPath: vDir.appendingPathComponent("unix_args.txt").path) {
                    let loaderVer = vDir.lastPathComponent
                    let mcVer = NeoForgeInstaller.minecraftVersion(forNeoForge: loaderVer)
                    return DetectedJavaFlavor(flavor: .neoforge, mcVersion: mcVer,
                                              loaderVersion: loaderVer, primaryJarPath: nil)
                }
            }
        }

        // 2. Forge — libraries/net/minecraftforge/forge/<mc>-<forgeVersion>/unix_args.txt
        let forgeBase = dir.appendingPathComponent("libraries/net/minecraftforge/forge", isDirectory: true)
        if let vDirs = try? fm.contentsOfDirectory(at: forgeBase, includingPropertiesForKeys: nil) {
            for vDir in vDirs {
                if fm.fileExists(atPath: vDir.appendingPathComponent("unix_args.txt").path) {
                    // dir name is "{mcVersion}-{forgeVersion}", e.g. "1.21.4-54.1.0"
                    let parts = vDir.lastPathComponent.split(separator: "-", maxSplits: 1)
                    let mcVer = parts.count >= 1 ? String(parts[0]) : nil
                    let forgeVer = parts.count >= 2 ? String(parts[1]) : vDir.lastPathComponent
                    return DetectedJavaFlavor(flavor: .forge, mcVersion: mcVer,
                                              loaderVersion: forgeVer, primaryJarPath: nil)
                }
            }
        }

        // 4. Fabric — fabric-server-launch*.jar in root
        let rootFiles = (try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        )) ?? []
        if let jar = rootFiles.first(where: {
            $0.lastPathComponent.lowercased().hasPrefix("fabric-server-launch") &&
            $0.pathExtension.lowercased() == "jar"
        }) {
            let stem = jar.deletingPathExtension().lastPathComponent
            let mcVer = parseFabricMCVersion(from: stem)
            let loaderVer = detectFabricLoaderVersion(in: dir, fm: fm)
            return DetectedJavaFlavor(flavor: .fabric, mcVersion: mcVer,
                                      loaderVersion: loaderVer, primaryJarPath: jar.path)
        }

        // 5. Match remaining jars by well-known prefixes
        let jars = rootFiles.filter { $0.pathExtension.lowercased() == "jar" }

        if let jar = jars.first(where: { $0.lastPathComponent.lowercased().hasPrefix("purpur") }) {
            return DetectedJavaFlavor(flavor: .purpur,
                                      mcVersion: parseJarMCVersion(jar.deletingPathExtension().lastPathComponent, prefix: "purpur-"),
                                      loaderVersion: nil, primaryJarPath: jar.path)
        }

        if let jar = jars.first(where: { $0.lastPathComponent.lowercased().hasPrefix("minecraft_server") }) {
            return DetectedJavaFlavor(flavor: .vanilla,
                                      mcVersion: parseJarMCVersion(jar.deletingPathExtension().lastPathComponent, prefix: "minecraft_server-"),
                                      loaderVersion: nil, primaryJarPath: jar.path)
        }

        // 6. Paper (default) — prefer paper*.jar, fall back to any jar
        let paperJar = jars.first(where: { $0.lastPathComponent.lowercased().hasPrefix("paper") }) ?? jars.first
        return DetectedJavaFlavor(flavor: .paper,
                                  mcVersion: paperJar.map { parseJarMCVersion($0.deletingPathExtension().lastPathComponent, prefix: "paper-") } ?? nil,
                                  loaderVersion: nil,
                                  primaryJarPath: paperJar?.path)
    }

    /// Parses the MC version from a Fabric launcher filename stem.
    /// "fabric-server-launch-1.21.5" → "1.21.5"; "fabric-server-launch" → nil.
    private static func parseFabricMCVersion(from stem: String) -> String? {
        let prefix = "fabric-server-launch-"
        let lower = stem.lowercased()
        guard lower.hasPrefix(prefix) else { return nil }
        let ver = String(stem.dropFirst(prefix.count))
        return ver.isEmpty ? nil : ver
    }

    /// Finds the Fabric loader version from .fabric/server/libraries/net/fabricmc/fabric-loader/.
    private static func detectFabricLoaderVersion(in dir: URL, fm: FileManager) -> String? {
        let loaderBase = dir.appendingPathComponent(
            ".fabric/server/libraries/net/fabricmc/fabric-loader", isDirectory: true)
        guard let vDirs = try? fm.contentsOfDirectory(at: loaderBase, includingPropertiesForKeys: nil)
        else { return nil }
        return vDirs.map(\.lastPathComponent).sorted().last
    }

    /// Extracts the MC version from a jar filename stem given its known prefix.
    /// "paper-1.21.5-123" with prefix "paper-" → "1.21.5" (trailing -build stripped).
    /// "minecraft_server-1.21.5" with prefix "minecraft_server-" → "1.21.5".
    private static func parseJarMCVersion(_ stem: String, prefix: String) -> String? {
        let lower = stem.lowercased()
        guard lower.hasPrefix(prefix.lowercased()) else { return nil }
        var remainder = String(stem.dropFirst(prefix.count))
        // Strip trailing -<build> if the part after the last dash is purely numeric
        if let dashIdx = remainder.lastIndex(of: "-") {
            let afterDash = remainder[remainder.index(after: dashIdx)...]
            if afterDash.allSatisfy(\.isNumber) {
                remainder = String(remainder[..<dashIdx])
            }
        }
        return remainder.isEmpty ? nil : remainder
    }

    // MARK: - Private helpers

    /// If a zip produced exactly one subdirectory and no loose files, unwrap into it.
    private func resolvedImportDir(in destURL: URL, fm: FileManager) -> URL {
        guard let contents = try? fm.contentsOfDirectory(
            at: destURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return destURL }

        let subdirs = contents.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }
        let files = contents.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == false
        }

        if subdirs.count == 1 && files.isEmpty { return subdirs[0] }
        return destURL
    }

    /// Recursively sums file sizes under `url`.
    private func directorySizeBytes(at url: URL, fm: FileManager) -> Int64 {
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            total += Int64(
                (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            )
        }
        return total
    }
}

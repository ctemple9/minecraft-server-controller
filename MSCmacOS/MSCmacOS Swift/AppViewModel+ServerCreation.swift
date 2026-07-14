//
//  AppViewModel+ServerCreation.swift
//  MinecraftServerController
//

import Foundation

extension AppViewModel {

    // MARK: - World Source enum

    enum WorldSource {
        case fresh
        case backupZip(URL)
        case existingFolder(URL)
    }

    private func initialWorldSlotName(forServerName serverName: String, requestedWorldName: String?) -> String {
        let requestedTrimmed = requestedWorldName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !requestedTrimmed.isEmpty { return requestedTrimmed }

        let serverTrimmed = serverName.trimmingCharacters(in: .whitespacesAndNewlines)
        return serverTrimmed.isEmpty ? "World 1" : serverTrimmed
    }

    private func normalizedInitialWorldSeed(_ seed: String?, worldSource: WorldSource) -> String? {
        guard case .fresh = worldSource else { return nil }
        let trimmed = seed?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func updateWorldIdentityForNewServer(
        configServer: ConfigServer,
        levelName: String,
        seed: String?,
        applySeed: Bool
    ) throws {
        switch configServer.serverType {
        case .java:
            var props = ServerPropertiesManager.readProperties(serverDir: configServer.serverDir)
            props["level-name"] = levelName
            if applySeed {
                if let seed, !seed.isEmpty {
                    props["level-seed"] = seed
                } else {
                    props.removeValue(forKey: "level-seed")
                }
            }
            try ServerPropertiesManager.writeProperties(props, to: configServer.serverDir)

        case .bedrock:
            var props = BedrockPropertiesManager.readRawProperties(serverDir: configServer.serverDir)
            props["level-name"] = levelName
            if applySeed {
                if let seed, !seed.isEmpty {
                    props["level-seed"] = seed
                } else {
                    props.removeValue(forKey: "level-seed")
                }
            }
            try BedrockPropertiesManager.writeRawProperties(props, serverDir: configServer.serverDir)
        }
    }

    private func createInitialPersistentWorldSlot(
        for configServer: ConfigServer,
        serverName: String,
        requestedWorldName: String?,
        worldSource: WorldSource,
        requestedSeed: String?
    ) async -> WorldSlot? {
        let slotName = initialWorldSlotName(forServerName: serverName, requestedWorldName: requestedWorldName)
        let normalizedSeed = normalizedInitialWorldSeed(requestedSeed, worldSource: worldSource)
        let logLine: (String) -> Void = { [weak self] msg in
            Task { @MainActor in self?.logAppMessage(msg) }
        }

        let slot: WorldSlot?
        switch worldSource {
        case .fresh:
            slot = await WorldSlotManager.createFreshWorldSlot(
                name: slotName,
                seed: normalizedSeed,
                for: configServer,
                logLine: logLine
            )
        case .backupZip(let zipURL):
            slot = await WorldSlotManager.createSlotFromZIP(
                zipURL: zipURL,
                name: slotName,
                for: configServer,
                logLine: logLine
            )
        case .existingFolder(let folderURL):
            let importedMetadata = WorldSlotManager.importedWorldMetadata(fromFolder: folderURL, serverType: configServer.serverType)
            slot = await WorldSlotManager.createSlot(
                name: slotName,
                for: configServer,
                worldSeed: importedMetadata.seed,
                logLine: logLine
            )
        }

        guard let slot else { return nil }

        do {
            if let worldLevelName = slot.worldLevelName?.trimmingCharacters(in: .whitespacesAndNewlines), !worldLevelName.isEmpty {
                try updateWorldIdentityForNewServer(
                    configServer: configServer,
                    levelName: worldLevelName,
                    seed: normalizedSeed,
                    applySeed: normalizedSeed != nil
                )
            }
            try WorldSlotManager.setActiveSlotID(slot.id, forServerDir: configServer.serverDir)
        } catch {
            logLine("[CreateServer] Failed to finalize initial world slot for \(configServer.displayName): \(error.localizedDescription)")
            return nil
        }

        logLine("[CreateServer] Initial world slot \"\(slot.name)\" created for \(configServer.displayName).")
        return slot
    }


    // MARK: - Create Java server

    func createNewServer(
        name: String,
        initialWorldName: String? = nil,
        jarSource: CreateServerJarSource,
        flavor: JavaServerFlavor = .paper,
        specificVersion: ServerVersionEntry? = nil,
        stagedAddOns: [WizardStagedAddOn] = [],
        port: Int,
        enableCrossPlay: Bool,
        crossPlayBedrockPort: Int? = nil,
        enablePlayit: Bool = false,
        enableXboxBroadcast: Bool = false,
        difficulty: String,
        gamemode: String,
        worldSeed: String?,
        worldSource: WorldSource
    ) async -> Bool {
        let safeName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !safeName.isEmpty else { return false }

        let initialSlotName = initialWorldSlotName(forServerName: safeName, requestedWorldName: initialWorldName)
        let normalizedWorldSeed = normalizedInitialWorldSeed(worldSeed, worldSource: worldSource)
        let importedMetadata: WorldSlotManager.ImportedWorldMetadata
        switch worldSource {
        case .fresh:
            importedMetadata = WorldSlotManager.ImportedWorldMetadata()
        case .backupZip(let url):
            importedMetadata = WorldSlotManager.importedWorldMetadata(fromZIP: url, serverType: .java)
        case .existingFolder(let folderURL):
            importedMetadata = WorldSlotManager.importedWorldMetadata(fromFolder: folderURL, serverType: .java)
        }
        let effectiveDifficulty = importedMetadata.difficulty ?? difficulty
        let effectiveGamemode = importedMetadata.gamemode ?? gamemode
        let effectiveWorldSeed = normalizedWorldSeed ?? importedMetadata.seed
        let initialLevelName = WorldSlotManager.sanitizedWorldLevelName(initialSlotName, fallback: "world")

        lastServerCreateError = nil
        pendingCreationConsole.removeAll()
        await MainActor.run { creationLogLines.removeAll() }

        let folderName = safeName.replacingOccurrences(of: " ", with: "_").lowercased()
        let root = configManager.serversRootURL
        let javaRoot = root.appendingPathComponent("java", isDirectory: true)
        let newDir = javaRoot.appendingPathComponent(folderName, isDirectory: true)
        let fm = FileManager.default

        if !fm.fileExists(atPath: javaRoot.path) {
            try? fm.createDirectory(at: javaRoot, withIntermediateDirectories: true)
        }
        if fm.fileExists(atPath: newDir.path) {
            logAppMessage("[CreateServer] Folder already exists: \(newDir.path)")
            lastServerCreateError = "A server folder named \"\(folderName)\" already exists at \(newDir.path). Choose a different name, or remove that folder."
            return false
        }

        do {
            try fm.createDirectory(at: newDir, withIntermediateDirectories: true)

            var resolvedVersion: String? = nil
            var resolvedBuild: String? = nil
            var resolvedLoader: String? = nil
            // paperJarPath for the config. Empty for NeoForge, which launches from a
            // generated args file rather than a single jar.
            var primaryJarPath = ""

            if flavor.provisioningKind == .installStep {
                // NeoForge / Forge: run the installer (downloads Minecraft + libraries,
                // patches, and generates the run/args files we later launch from).
                noteCreation("[CreateServer] Installing \(flavor.displayName) — this can take a minute…")
                if flavor == .neoforge {
                    let info: NeoForgeInstaller.InstallResult
                    if let sv = specificVersion, !sv.isLatest, let nfv = sv.loaderVersion {
                        info = try await NeoForgeInstaller.install(
                            specificVersion: nfv,
                            into: newDir,
                            javaPath: configManager.config.javaPath,
                            onLog: { line in DispatchQueue.main.async { self.noteCreation("[NeoForge] \(line)") } }
                        )
                    } else {
                        info = try await NeoForgeInstaller.install(
                            into: newDir,
                            javaPath: configManager.config.javaPath,
                            onLog: { line in DispatchQueue.main.async { self.noteCreation("[NeoForge] \(line)") } }
                        )
                    }
                    resolvedVersion = info.minecraftVersion
                    resolvedLoader = info.neoForgeVersion
                    resolvedBuild = info.neoForgeVersion
                    noteCreation("[CreateServer] Installed NeoForge \(info.neoForgeVersion) (Minecraft \(info.minecraftVersion)).")
                } else if flavor == .forge {
                    let info: ForgeInstaller.InstallResult
                    if let sv = specificVersion, !sv.isLatest, let fv = sv.loaderVersion {
                        info = try await ForgeInstaller.install(
                            mcVersion: sv.mcVersion,
                            forgeVersion: fv,
                            into: newDir,
                            javaPath: configManager.config.javaPath,
                            onLog: { line in DispatchQueue.main.async { self.noteCreation("[Forge] \(line)") } }
                        )
                    } else {
                        info = try await ForgeInstaller.install(
                            into: newDir,
                            javaPath: configManager.config.javaPath,
                            onLog: { line in DispatchQueue.main.async { self.noteCreation("[Forge] \(line)") } }
                        )
                    }
                    resolvedVersion = info.minecraftVersion
                    resolvedLoader = info.forgeVersion
                    resolvedBuild = info.forgeVersion
                    noteCreation("[CreateServer] Installed Forge \(info.forgeVersion) (Minecraft \(info.minecraftVersion)).")
                }
            } else {

            let jarDest = newDir.appendingPathComponent("paper.jar")
            primaryJarPath = jarDest.path

            switch jarSource {
            case .template(let url):
                try fm.copyItem(at: url, to: jarDest)
                logAppMessage("[CreateServer] Copied \(flavor.displayName) template into new server.")
                if let parsed = ComponentVersionParsing.parsePaperJarFilename(url.lastPathComponent) {
                    resolvedVersion = parsed.mcVersion
                    resolvedBuild = String(parsed.build)
                    PaperVersionSidecarManager.write(mcVersion: parsed.mcVersion, build: parsed.build, toServerDirectory: newDir)
                }
            case .downloadLatest:
                // Archive-first for Paper: lightweight metadata check → skip download if the
                // exact version is already in the archive.
                var usedArchive = false
                if flavor == .paper && configManager.config.saveDownloadedJars {
                    if let meta = try? await PaperDownloader.fetchLatestMetadata() {
                        let archiveFilename = "paper-\(meta.version)-build\(meta.build).jar"
                        let archiveURL = URL(fileURLWithPath: configManager.config.paperTemplateDir)
                            .appendingPathComponent(archiveFilename)
                        if fm.fileExists(atPath: archiveURL.path) {
                            try fm.copyItem(at: archiveURL, to: jarDest)
                            resolvedVersion = meta.version
                            resolvedBuild = String(meta.build)
                            noteCreation("[CreateServer] Used archived Paper \(meta.version) (build \(meta.build)).")
                            PaperVersionSidecarManager.write(mcVersion: meta.version, build: meta.build, toServerDirectory: newDir)
                            usedArchive = true
                        }
                    }
                }

                if !usedArchive {
                    let result: ServerJarDownloadResult
                    if let sv = specificVersion, !sv.isLatest {
                        result = try await ServerJarProvider.downloadVersion(sv, flavor: flavor, to: jarDest)
                        noteCreation("[CreateServer] Downloaded \(flavor.displayName) \(result.version) (\(result.build)) [specific version].")
                    } else {
                        result = try await ServerJarProvider.downloadLatest(flavor: flavor, to: jarDest)
                        noteCreation("[CreateServer] Downloaded \(flavor.displayName) \(result.version) (\(result.build)).")
                    }
                    resolvedVersion = result.version
                    resolvedBuild = result.build
                    resolvedLoader = result.loaderVersion
                    if flavor == .paper, let buildInt = Int(result.build) {
                        PaperVersionSidecarManager.write(mcVersion: result.version, build: buildInt, toServerDirectory: newDir)
                    }
                    if configManager.config.saveDownloadedJars {
                        archiveServerJar(flavor: flavor, result: result, from: jarDest)
                    }
                }
            }
            }   // end non-install-step provisioning (else)

            try "eula=false\n".write(to: newDir.appendingPathComponent("eula.txt"), atomically: true, encoding: .utf8)

            var props = [
                "server-port": String(port),
                "motd": safeName,
                "max-players": "20",
                "online-mode": "true",
                "difficulty": effectiveDifficulty,
                "gamemode": effectiveGamemode,
                "level-name": initialLevelName
            ]
            if let effectiveWorldSeed {
                props["level-seed"] = effectiveWorldSeed
            }
            try ServerPropertiesManager.writeProperties(props, to: newDir.path)

            // Create the add-on folder for this flavor: plugins/ for plugin servers,
            // mods/ for modded loaders, nothing for Vanilla (no add-on API).
            if let addOn = flavor.addOnKind {
                let addOnDir = newDir.appendingPathComponent(addOn.folderName, isDirectory: true)
                try fm.createDirectory(at: addOnDir, withIntermediateDirectories: true)
                if enableCrossPlay, addOn == .plugin {
                    applyCrossPlayTemplatesIfAvailable(to: addOnDir)
                }
            }

            let writtenProps = ServerPropertiesManager.readProperties(serverDir: newDir.path)
            let levelName = (writtenProps["level-name"]?.trimmingCharacters(in: .whitespacesAndNewlines))
                .flatMap { $0.isEmpty ? nil : $0 } ?? "world"

            switch worldSource {
            case .fresh:
                break
            case .backupZip(let url):
                let ok = await unzipWorldBackup(url, into: newDir, logPrefix: "[CreateServer]")
                if !ok { return false }
            case .existingFolder(let srcFolderURL):
                let ok = await copyExistingWorldFolder(from: srcFolderURL, toServerDir: newDir, levelName: levelName, logPrefix: "[CreateServer]")
                if !ok { return false }
            }

            let newId = UUID().uuidString
            var cfgServer = ConfigServer(id: newId, displayName: safeName, serverDir: newDir.path,
                                         paperJarPath: primaryJarPath, minRamGB: 2, maxRamGB: 4, notes: "")
            cfgServer.javaFlavor = flavor
            cfgServer.minecraftVersion = resolvedVersion
            cfgServer.serverBuild = resolvedBuild
            cfgServer.loaderVersion = resolvedLoader
            // Modded servers need more memory than plugin servers.
            if flavor.category == .modded {
                cfgServer.minRamGB = 3
                cfgServer.maxRamGB = 6
            }
            cfgServer.bannerColorHex = configManager.config.defaultBannerColorHex
            cfgServer.playitEnabled = enablePlayit
            cfgServer.xboxBroadcastEnabled = enableXboxBroadcast
            if enableCrossPlay, let bedrockPort = crossPlayBedrockPort {
                cfgServer.bedrockPort = bedrockPort
            }

            guard await createInitialPersistentWorldSlot(
                for: cfgServer,
                serverName: safeName,
                requestedWorldName: initialWorldName,
                worldSource: worldSource,
                requestedSeed: effectiveWorldSeed
            ) != nil else {
                try? fm.removeItem(at: newDir)
                logAppMessage("[CreateServer] Failed to create the initial world slot for \(safeName); aborting server creation.")
                lastServerCreateError = "Couldn't create the initial world slot for \"\(safeName)\"."
                return false
            }

            // Apply staged add-ons chosen during the wizard.
            if !stagedAddOns.isEmpty, let addOnKind = flavor.addOnKind {
                let addOnDir = newDir.appendingPathComponent(addOnKind.folderName, isDirectory: true)
                do {
                    try fm.createDirectory(at: addOnDir, withIntermediateDirectories: true)
                } catch {
                    logAppMessage("[CreateServer] Failed to create \(addOnKind.folderName)/ for staged add-ons: \(error.localizedDescription)")
                }
                for addOn in stagedAddOns {
                    await applyStagedAddOn(addOn, to: addOnDir, serverConfig: cfgServer, label: "[CreateServer]")
                }
            }

            upsertServer(cfgServer)
            if cfgServer.javaFlavor.category == .modded,
               let mc = cfgServer.minecraftVersion,
               let loader = cfgServer.loaderVersion {
                recordLoaderVersion(flavor: cfgServer.javaFlavor, mc: mc, loader: loader)
            }
            setActiveServer(withId: newId)
            // Selecting the new server cleared the console — replay the creation/install
            // output so it's visible in the new server's console.
            replayCreationConsole()
            logAppMessage("[CreateServer] Created new server \(safeName).")
            return true

        } catch {
            logAppMessage("[CreateServer] Failed: \(error.localizedDescription)")
            lastServerCreateError = error.localizedDescription
            // Roll back the partially-created server folder so a retry isn't blocked
            // by a leftover directory (esp. NeoForge, which writes libraries/ during install).
            try? FileManager.default.removeItem(at: newDir)
            return false
        }
    }


    // MARK: - Create Bedrock server

    func createNewBedrockServer(
        name: String,
        initialWorldName: String? = nil,
        dockerImage: String,
        bedrockVersion: String,
        port: Int,
        maxPlayers: Int,
        enablePlayit: Bool = false,
        enableXboxBroadcast: Bool = false,
        difficulty: String,
        gamemode: String,
        worldSeed: String?,
        worldSource: WorldSource
    ) async -> Bool {
        let safeName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !safeName.isEmpty else { return false }

        let initialSlotName = initialWorldSlotName(forServerName: safeName, requestedWorldName: initialWorldName)
        let normalizedWorldSeed = normalizedInitialWorldSeed(worldSeed, worldSource: worldSource)
        let importedMetadata: WorldSlotManager.ImportedWorldMetadata
        let resolvedWorldFolder: URL?
        switch worldSource {
        case .fresh:
            importedMetadata = WorldSlotManager.ImportedWorldMetadata()
            resolvedWorldFolder = nil
        case .backupZip(let url):
            importedMetadata = WorldSlotManager.importedWorldMetadata(fromZIP: url, serverType: .bedrock)
            resolvedWorldFolder = nil
        case .existingFolder(let folderURL):
            // Find the actual world folder (the one containing level.dat) within the
            // user-selected URL. This handles both "user picked the world folder itself"
            // and "user picked a parent/wrapper directory".
            let resolved = Self.resolvedBedrockWorldFolder(from: folderURL)
            importedMetadata = WorldSlotManager.importedWorldMetadata(fromFolder: resolved, serverType: .bedrock)
            resolvedWorldFolder = resolved
        }
        let effectiveDifficulty = importedMetadata.difficulty ?? difficulty
        let effectiveGamemode = importedMetadata.gamemode ?? gamemode
        let effectiveWorldSeed = normalizedWorldSeed ?? importedMetadata.seed
        // For an imported folder, use the world folder's own name as level-name so BDS
        // finds it at worlds/{name}/. For fresh/zip sources, derive from the slot name.
        let initialLevelName: String
        if let worldFolder = resolvedWorldFolder {
            initialLevelName = WorldSlotManager.sanitizedWorldLevelName(worldFolder.lastPathComponent, fallback: initialSlotName)
        } else {
            initialLevelName = WorldSlotManager.sanitizedWorldLevelName(initialSlotName, fallback: "Bedrock level")
        }

        let folderName = safeName.replacingOccurrences(of: " ", with: "_").lowercased()
        let root = configManager.serversRootURL
        let bedrockRoot = root.appendingPathComponent("bedrock", isDirectory: true)
        let newDir = bedrockRoot.appendingPathComponent(folderName, isDirectory: true)
        let fm = FileManager.default

        if !fm.fileExists(atPath: bedrockRoot.path) {
            try? fm.createDirectory(at: bedrockRoot, withIntermediateDirectories: true)
        }
        if fm.fileExists(atPath: newDir.path) {
            logAppMessage("[CreateBedrockServer] Folder already exists: \(newDir.path)")
            return false
        }

        do {
            try fm.createDirectory(at: newDir, withIntermediateDirectories: true)

            var props: [String: String] = [
                "server-name": safeName,
                "level-name": initialLevelName,
                "gamemode": effectiveGamemode,
                "difficulty": effectiveDifficulty,
                "max-players": String(maxPlayers),
                "server-port": String(port),
                "server-portv6": "19133",
                "online-mode": "true",
                "allow-cheats": "false"
            ]
            if let effectiveWorldSeed {
                props["level-seed"] = effectiveWorldSeed
            }
            try BedrockPropertiesManager.writeRawProperties(props, serverDir: newDir.path)
            try BedrockPropertiesManager.writeAllowlist([], serverDir: newDir.path)
            try BedrockPropertiesManager.writePermissions([], serverDir: newDir.path)

            switch worldSource {
            case .fresh: break
            case .backupZip(let url):
                let ok = await unzipWorldBackup(url, into: newDir, logPrefix: "[CreateBedrockServer]")
                if !ok { return false }
            case .existingFolder:
                guard let worldFolder = resolvedWorldFolder else { return false }
                // BDS expects worlds at serverDir/worlds/{level-name}/
                // Create the worlds/ container first, then copy the folder into it.
                let worldsDir = newDir.appendingPathComponent("worlds", isDirectory: true)
                try? fm.createDirectory(at: worldsDir, withIntermediateDirectories: true)
                let ok = await copyExistingWorldFolder(from: worldFolder, toServerDir: worldsDir,
                                                        levelName: initialLevelName, logPrefix: "[CreateBedrockServer]")
                if !ok { return false }
            }

            let newId = UUID().uuidString
            var cfgServer = ConfigServer(id: newId, displayName: safeName, serverDir: newDir.path,
                                         paperJarPath: "", minRamGB: 0, maxRamGB: 0, notes: "")
            cfgServer.serverType = .bedrock
            cfgServer.playitEnabled = enablePlayit
            cfgServer.bedrockDockerImage = dockerImage.isEmpty ? "itzg/minecraft-bedrock-server" : dockerImage
            cfgServer.bedrockVersion = {
                let trimmed = bedrockVersion.trimmingCharacters(in: .whitespacesAndNewlines)
                return (trimmed.isEmpty || trimmed == "LATEST") ? nil : trimmed
            }()
            cfgServer.bedrockPort = port
            cfgServer.xboxBroadcastEnabled = enableXboxBroadcast
            cfgServer.bannerColorHex = configManager.config.defaultBannerColorHex

            guard await createInitialPersistentWorldSlot(
                for: cfgServer,
                serverName: safeName,
                requestedWorldName: initialWorldName,
                worldSource: worldSource,
                requestedSeed: effectiveWorldSeed
            ) != nil else {
                try? fm.removeItem(at: newDir)
                logAppMessage("[CreateBedrockServer] Failed to create the initial world slot for \(safeName); aborting server creation.")
                return false
            }

            upsertServer(cfgServer)
            setActiveServer(withId: newId)
            logAppMessage("[CreateBedrockServer] Created new Bedrock server \(safeName).")
            return true

        } catch {
            logAppMessage("[CreateBedrockServer] Failed: \(error.localizedDescription)")
            return false
        }
    }


    // MARK: - Cross-play helper

    private func applyCrossPlayTemplatesIfAvailable(to pluginsDir: URL) {
        let fm = FileManager.default
        let templateDir = configManager.pluginTemplateDirURL
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: templateDir.path, isDirectory: &isDir), isDir.boolValue else {
            logAppMessage("[CreateServer] Cross-play requested but plugin template directory not found. Use Plugin Templates to download Geyser/Floodgate.")
            return
        }
        let contents: [URL]
        do {
            contents = try fm.contentsOfDirectory(at: templateDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        } catch {
            logAppMessage("[CreateServer] Failed to list plugin template directory: \(error.localizedDescription)")
            return
        }
        let jars = contents.filter { $0.pathExtension.lowercased() == "jar" }
        let geyserJar = jars.first { $0.lastPathComponent.lowercased().contains("geyser") }
        let floodgateJar = jars.first { $0.lastPathComponent.lowercased().contains("floodgate") }
        guard let geyser = geyserJar, let floodgate = floodgateJar else {
            logAppMessage("[CreateServer] Cross-play requested but Geyser/Floodgate templates not found; use Plugin Templates to download them.")
            return
        }
        do {
            let destGeyser = pluginsDir.appendingPathComponent(geyser.lastPathComponent)
            let destFloodgate = pluginsDir.appendingPathComponent(floodgate.lastPathComponent)
            if fm.fileExists(atPath: destGeyser.path) { try fm.removeItem(at: destGeyser) }
            if fm.fileExists(atPath: destFloodgate.path) { try fm.removeItem(at: destFloodgate) }
            try fm.copyItem(at: geyser, to: destGeyser)
            try fm.copyItem(at: floodgate, to: destFloodgate)
            logAppMessage("[CreateServer] Applied Geyser/Floodgate templates to new server's plugins folder.")
        } catch {
            logAppMessage("[CreateServer] Failed to copy Geyser/Floodgate templates: \(error.localizedDescription)")
        }
    }

    // MARK: - Bedrock world folder detection

    /// Returns the URL of the actual Bedrock world folder (the directory containing level.dat)
    /// within the user-selected URL.
    ///
    /// Handles two common upload shapes:
    /// - User picks the world folder directly ("The Boys/" with level.dat at its root) → returns that folder.
    /// - User picks a parent/wrapper folder ("worlds/" containing "The Boys/") → returns "The Boys/".
    ///
    /// Falls back to the original URL if neither pattern matches.
    private static func resolvedBedrockWorldFolder(from folder: URL) -> URL {
        let fm = FileManager.default
        // Case 1: level.dat is directly inside the selected folder — it IS the world folder.
        if fm.fileExists(atPath: folder.appendingPathComponent("level.dat").path) {
            return folder
        }
        // Case 2: look one level deep for a single subdirectory containing level.dat.
        // Catches users who accidentally pick a parent directory or whose export
        // added an extra top-level wrapper.
        let contents = (try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let worldSubdirs = contents.filter { url in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            return isDir && fm.fileExists(atPath: url.appendingPathComponent("level.dat").path)
        }
        if worldSubdirs.count == 1 {
            return worldSubdirs[0]
        }
        // Fallback: return the original folder.
        return folder
    }

    // MARK: - Archive helpers

    /// Copies a freshly-downloaded server JAR into the archive directory with a versioned
    /// filename, so the same binary can be reused for future servers without a network fetch.
    /// Server/core JARs only — mods are tracked per-server and explicitly excluded.
    func archiveServerJar(
        flavor: JavaServerFlavor,
        result: ServerJarDownloadResult,
        from sourceURL: URL
    ) {
        let archiveDir = URL(fileURLWithPath: configManager.config.paperTemplateDir, isDirectory: true)

        let archiveFilename: String
        switch flavor {
        case .paper:
            guard let buildInt = Int(result.build) else { return }
            archiveFilename = "paper-\(result.version)-build\(buildInt).jar"
        case .purpur:
            archiveFilename = "purpur-\(result.version)-build\(result.build).jar"
        case .vanilla:
            archiveFilename = "minecraft_server-\(result.version).jar"
        case .fabric:
            archiveFilename = "fabric-server-launch-\(result.version).jar"
        default:
            return
        }

        let archiveURL = archiveDir.appendingPathComponent(archiveFilename)
        let fm = FileManager.default

        guard !fm.fileExists(atPath: archiveURL.path) else {
            logAppMessage("[Archive] Already in archive: \(archiveFilename)")
            return
        }

        do {
            try fm.createDirectory(at: archiveDir, withIntermediateDirectories: true)
            try fm.copyItem(at: sourceURL, to: archiveURL)
            logAppMessage("[Archive] Saved \(archiveFilename) to archive.")
            loadPaperTemplates()
        } catch {
            logAppMessage("[Archive] Failed to save \(archiveFilename): \(error.localizedDescription)")
        }
    }

    // MARK: - Staged add-on applicator

    func applyStagedAddOn(
        _ addOn: WizardStagedAddOn,
        to addOnDir: URL,
        serverConfig: ConfigServer,
        label: String
    ) async {
        let fm = FileManager.default
        switch addOn.source {
        case .modrinthDownload(_, let version):
            let dest = addOnDir.appendingPathComponent(addOn.filename)
            do {
                try await ModrinthAPI.downloadVersionFile(version, to: dest)
                noteCreation("\(label) Installed \(addOn.name).")
            } catch {
                noteCreation("\(label) Failed to download \(addOn.name): \(error.localizedDescription)")
            }

        case .localJar(let url):
            let dest = addOnDir.appendingPathComponent(addOn.filename)
            do {
                try fm.copyItem(at: url, to: dest)
                noteCreation("\(label) Copied \(addOn.name).")
            } catch {
                noteCreation("\(label) Failed to copy \(addOn.name): \(error.localizedDescription)")
            }

        case .remoteJar(let url, _):
            let dest = addOnDir.appendingPathComponent(addOn.filename)
            do {
                let (data, _) = try await MSCHTTP.get(url)
                try data.write(to: dest, options: [.atomic])
                noteCreation("\(label) Downloaded \(addOn.name).")
            } catch {
                noteCreation("\(label) Failed to fetch \(addOn.name): \(error.localizedDescription)")
            }

        case .mrpackFile(let url):
            noteCreation("\(label) Importing modpack \(addOn.filename)…")
            await importModpack(from: url, for: serverConfig)

        case .curseForgeFile(let url):
            noteCreation("\(label) Importing CurseForge modpack \(addOn.filename)…")
            // importModpack sniffs the archive and routes to the CurseForge importer.
            await importModpack(from: url, for: serverConfig)

        case .zipFolder(let url):
            let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("MSC-zip-\(UUID().uuidString)", isDirectory: true)
            defer { try? fm.removeItem(at: tmpDir) }
            do { try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true) } catch { return }
            // Use ditto to avoid /usr/bin/unzip's mode-000 quirk on user-supplied add-on zips.
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            unzip.arguments = ["-x", "-k", url.path, tmpDir.path]
            unzip.standardOutput = FileHandle.nullDevice
            unzip.standardError  = FileHandle.nullDevice
            try? unzip.run(); unzip.waitUntilExit()
            if let items = try? fm.contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: nil,
                                                        options: .skipsSubdirectoryDescendants) {
                for item in items where item.pathExtension.lowercased() == "jar" {
                    let dest = addOnDir.appendingPathComponent(item.lastPathComponent)
                    do {
                        try fm.copyItem(at: item, to: dest)
                        noteCreation("\(label) Copied \(item.lastPathComponent) from zip.")
                    } catch {
                        noteCreation("\(label) Failed to copy \(item.lastPathComponent) from zip: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}

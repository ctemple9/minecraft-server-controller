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
        port: Int,
        enableCrossPlay: Bool,
        crossPlayBedrockPort: Int? = nil,
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
            return false
        }

        do {
            try fm.createDirectory(at: newDir, withIntermediateDirectories: true)
            let jarDest = newDir.appendingPathComponent("paper.jar")

            switch jarSource {
            case .template(let url):
                try fm.copyItem(at: url, to: jarDest)
                logAppMessage("[CreateServer] Copied Paper template into new server.")
                if let parsed = ComponentVersionParsing.parsePaperJarFilename(url.lastPathComponent) {
                    PaperVersionSidecarManager.write(mcVersion: parsed.mcVersion, build: parsed.build, toServerDirectory: newDir)
                }
            case .downloadLatest:
                let result = try await PaperDownloader.downloadLatestPaper(to: jarDest)
                logAppMessage("[CreateServer] Downloaded Paper \(result.version) build \(result.build).")
                PaperVersionSidecarManager.write(mcVersion: result.version, build: result.build, toServerDirectory: newDir)
                let templateDirPath = configManager.config.paperTemplateDir
                if !templateDirPath.isEmpty {
                    let templatesDirURL = URL(fileURLWithPath: templateDirPath, isDirectory: true)
                    try fm.createDirectory(at: templatesDirURL, withIntermediateDirectories: true)
                    let templateJarURL = templatesDirURL.appendingPathComponent("paper-\(result.version)-build\(result.build).jar")
                    if !fm.fileExists(atPath: templateJarURL.path) {
                        try fm.copyItem(at: jarDest, to: templateJarURL)
                        logAppMessage("[CreateServer] Also saved Paper jar to templates: \(templateJarURL.lastPathComponent)")
                    } else {
                        logAppMessage("[CreateServer] Template jar already exists: \(templateJarURL.lastPathComponent)")
                    }
                }
            }

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

            let pluginsDir = newDir.appendingPathComponent("plugins", isDirectory: true)
            try fm.createDirectory(at: pluginsDir, withIntermediateDirectories: true)

            if enableCrossPlay { applyCrossPlayTemplatesIfAvailable(to: pluginsDir) }

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
                                         paperJarPath: jarDest.path, minRamGB: 2, maxRamGB: 4, notes: "")
            cfgServer.bannerColorHex = configManager.config.defaultBannerColorHex
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
                return false
            }

            upsertServer(cfgServer)
            setActiveServer(withId: newId)
            logAppMessage("[CreateServer] Created new server \(safeName).")
            return true

        } catch {
            logAppMessage("[CreateServer] Failed: \(error.localizedDescription)")
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
            importedMetadata = WorldSlotManager.importedWorldMetadata(fromZIP: url, serverType: .bedrock)
        case .existingFolder(let folderURL):
            importedMetadata = WorldSlotManager.importedWorldMetadata(fromFolder: folderURL, serverType: .bedrock)
        }
        let effectiveDifficulty = importedMetadata.difficulty ?? difficulty
        let effectiveGamemode = importedMetadata.gamemode ?? gamemode
        let effectiveWorldSeed = normalizedWorldSeed ?? importedMetadata.seed
        let initialLevelName = WorldSlotManager.sanitizedWorldLevelName(initialSlotName, fallback: "Bedrock level")

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
            case .existingFolder(let srcFolderURL):
                let ok = await copyExistingWorldFolder(from: srcFolderURL, toServerDir: newDir,
                                                        levelName: "worlds", logPrefix: "[CreateBedrockServer]")
                if !ok { return false }
            }

            let newId = UUID().uuidString
            var cfgServer = ConfigServer(id: newId, displayName: safeName, serverDir: newDir.path,
                                         paperJarPath: "", minRamGB: 0, maxRamGB: 0, notes: "")
            cfgServer.serverType = .bedrock
            cfgServer.bedrockDockerImage = dockerImage.isEmpty ? "itzg/minecraft-bedrock-server" : dockerImage
            cfgServer.bedrockVersion = {
                let trimmed = bedrockVersion.trimmingCharacters(in: .whitespacesAndNewlines)
                return (trimmed.isEmpty || trimmed == "LATEST") ? nil : trimmed
            }()
            cfgServer.bedrockPort = port
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
}

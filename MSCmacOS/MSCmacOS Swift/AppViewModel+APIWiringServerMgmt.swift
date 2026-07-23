//
//  AppViewModel+APIWiringServerMgmt.swift
//  MSCmacOS
//
//  M1 (flowstate) slice 7 (final): server-management Remote API providers — rename,
//  delete, templates, and import (scan + apply). Extracted verbatim from
//  AppViewModel.init (local-let + by-reference). The template/import helpers
//  (templateIdFor, templateFilenameFromId, templateFlavorForFilename,
//  scanExistingServerInfo, buildTemplatesResponse) stay local, captured by the providers.
//

import Foundation

extension AppViewModel {

    /// Server rename/delete, template listing/mutation, and existing-server import
    /// (scan + apply).
    func wireServerManagementProviders(into server: RemoteAPIServer) {
        let renameServerProvider: (String, String) async -> RemoteAPIServer.ServerRenameResultDTO = { [weak self] serverId, name in
            guard let self else {
                return RemoteAPIServer.ServerRenameResultDTO(success: false, message: "not_available")
            }
            let trimmedId = serverId.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedId.isEmpty else {
                return RemoteAPIServer.ServerRenameResultDTO(success: false, message: "missing_server_id")
            }
            guard !trimmedName.isEmpty else {
                return RemoteAPIServer.ServerRenameResultDTO(success: false, message: "name_required", serverId: trimmedId)
            }
            return await MainActor.run {
                guard let idx = self.configManager.config.servers.firstIndex(where: { $0.id == trimmedId }) else {
                    return RemoteAPIServer.ServerRenameResultDTO(success: false, message: "server_not_found", serverId: trimmedId)
                }
                self.configManager.config.servers[idx].displayName = trimmedName
                self.configManager.save()
                self.reloadServersFromConfig()
                self.logAppMessage("[Server] Remote: renamed server to \"\(trimmedName)\".")
                return RemoteAPIServer.ServerRenameResultDTO(success: true, message: "ok", serverId: trimmedId, name: trimmedName)
            }
        }

        let deleteServerProvider: (String) async -> RemoteAPIServer.ServerDeleteResultDTO = { [weak self] serverId in
            guard let self else {
                return RemoteAPIServer.ServerDeleteResultDTO(success: false, message: "not_available")
            }
            let trimmedId = serverId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedId.isEmpty else {
                return RemoteAPIServer.ServerDeleteResultDTO(success: false, message: "missing_server_id")
            }
            return await MainActor.run {
                let cfg = self.configManager.config
                guard cfg.servers.contains(where: { $0.id == trimmedId }) else {
                    return RemoteAPIServer.ServerDeleteResultDTO(success: false, message: "server_not_found", serverId: trimmedId)
                }
                if self.isServerRunning, cfg.activeServerId == trimmedId {
                    return RemoteAPIServer.ServerDeleteResultDTO(success: false, message: "server_running", serverId: trimmedId)
                }
                do {
                    try self.deleteServerFromDisk(withId: trimmedId)
                } catch {
                    self.logAppMessage("[Server] Remote: failed to delete server folder: \(error.localizedDescription)")
                    return RemoteAPIServer.ServerDeleteResultDTO(success: false, message: "delete_failed", serverId: trimmedId)
                }
                return RemoteAPIServer.ServerDeleteResultDTO(success: true, message: "ok", serverId: trimmedId)
            }
        }

        let createServerProvider: (RemoteAPIServer.ServerCreateRequestDTO) async -> RemoteAPIServer.ServerCreateResultDTO = { [weak self] req in
            guard let self else {
                return RemoteAPIServer.ServerCreateResultDTO(success: false, message: "not_available")
            }
            let name = req.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                return RemoteAPIServer.ServerCreateResultDTO(success: false, message: "name_required")
            }
            let typeRaw = req.serverType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let serverType: ServerType
            if let typeRaw, !typeRaw.isEmpty {
                guard let parsed = ServerType(rawValue: typeRaw) else {
                    return RemoteAPIServer.ServerCreateResultDTO(success: false, message: "invalid_server_type")
                }
                serverType = parsed
            } else {
                serverType = .java
            }

            func trimmedOrNil(_ value: String?) -> String? {
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }
            let difficulty = trimmedOrNil(req.difficulty) ?? "normal"
            let gamemode = trimmedOrNil(req.gamemode) ?? "survival"
            let worldName = trimmedOrNil(req.worldName)
            let worldSeed = trimmedOrNil(req.worldSeed)
            let requestedVersionId = trimmedOrNil(req.versionId)
            let requestedMinecraftVersion = trimmedOrNil(req.minecraftVersion)
            let requestedLoaderVersion = trimmedOrNil(req.loaderVersion)
            let supportedJavaFlavors: Set<JavaServerFlavor> = [.paper, .purpur, .vanilla, .fabric, .neoforge, .forge]
            let requestedJavaFlavor = trimmedOrNil(req.javaFlavor)?.lowercased()
            let javaFlavor: JavaServerFlavor
            if let requestedJavaFlavor {
                guard let parsed = JavaServerFlavor(rawValue: requestedJavaFlavor),
                      supportedJavaFlavors.contains(parsed) else {
                    return RemoteAPIServer.ServerCreateResultDTO(success: false, message: "invalid_java_flavor")
                }
                javaFlavor = parsed
            } else {
                javaFlavor = .paper
            }
            let specificJavaVersion: ServerVersionEntry?
            if let requestedVersionId, requestedVersionId != "__latest__" {
                let mcVersion = requestedMinecraftVersion ?? requestedVersionId
                specificJavaVersion = ServerVersionEntry(
                    id: requestedVersionId,
                    displayLabel: mcVersion,
                    mcVersion: mcVersion,
                    loaderVersion: requestedLoaderVersion,
                    buildLabel: nil,
                    isStable: true
                )
            } else {
                specificJavaVersion = nil
            }
            let before = await MainActor.run { Set(self.configManager.config.servers.map(\.id)) }

            let ok: Bool
            switch serverType {
            case .java:
                let supportsCrossPlay = javaFlavor.category == .standard && javaFlavor != .vanilla
                let enableJavaCrossPlay = supportsCrossPlay && (req.enableCrossPlay ?? false)
                ok = await self.createNewServer(
                    name: name,
                    initialWorldName: worldName,
                    jarSource: .downloadLatest,
                    flavor: javaFlavor,
                    specificVersion: specificJavaVersion,
                    port: req.port ?? 25565,
                    enableCrossPlay: enableJavaCrossPlay,
                    crossPlayBedrockPort: enableJavaCrossPlay ? (req.crossPlayBedrockPort ?? 19132) : nil,
                    enablePlayit: req.enablePlayit ?? false,
                    enableXboxBroadcast: enableJavaCrossPlay && (req.enableXboxBroadcast ?? false),
                    difficulty: difficulty,
                    gamemode: gamemode,
                    worldSeed: worldSeed,
                    worldSource: .fresh,
                    javaPath: trimmedOrNil(req.javaPath)
                )
            case .bedrock:
                ok = await self.createNewBedrockServer(
                    name: name,
                    initialWorldName: worldName,
                    dockerImage: trimmedOrNil(req.dockerImage) ?? "itzg/minecraft-bedrock-server",
                    bedrockVersion: trimmedOrNil(req.bedrockVersion) ?? requestedVersionId ?? "LATEST",
                    port: req.port ?? 19132,
                    maxPlayers: req.maxPlayers ?? 10,
                    enablePlayit: req.enablePlayit ?? false,
                    enableXboxBroadcast: req.enableXboxBroadcast ?? false,
                    difficulty: difficulty,
                    gamemode: gamemode,
                    worldSeed: worldSeed,
                    worldSource: .fresh
                )
            }

            guard ok else {
                let error = await MainActor.run { self.lastServerCreateError ?? "create_failed" }
                return RemoteAPIServer.ServerCreateResultDTO(success: false, message: error)
            }

            return await MainActor.run {
                let created = self.configManager.config.servers.first(where: { !before.contains($0.id) })
                    ?? self.configManager.config.activeServerId.flatMap { id in self.configManager.config.servers.first(where: { $0.id == id }) }
                if req.acceptEula == true, let created, created.serverType == .java {
                    do {
                        try EULAManager.writeAcceptedEULA(in: created.serverDir)
                        if self.selectedServer?.id == created.id {
                            self.eulaAccepted = true
                        }
                    } catch {
                        self.logAppMessage("[Server] Remote: failed to accept EULA for \"\(created.displayName)\": \(error.localizedDescription)")
                        return RemoteAPIServer.ServerCreateResultDTO(success: false, message: "eula_write_failed", serverId: created.id, serverName: created.displayName)
                    }
                }
                if let maxPlayers = req.maxPlayers, let created, created.serverType == .java {
                    var props = ServerPropertiesManager.readProperties(serverDir: created.serverDir)
                    props["max-players"] = String(maxPlayers)
                    try? ServerPropertiesManager.writeProperties(props, to: created.serverDir)
                }
                var createWarnings: [String] = []
                if let created, created.xboxBroadcastEnabled {
                    let jarPath = self.configManager.config.xboxBroadcastJarPath ?? ""
                    if jarPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        createWarnings.append("xbox_broadcast_jar_not_configured")
                    }
                }
                return RemoteAPIServer.ServerCreateResultDTO(
                    success: true,
                    message: "created",
                    serverId: created?.id,
                    serverName: created?.displayName,
                    warnings: createWarnings.isEmpty ? nil : createWarnings
                )
            }
        }

        let acceptEULAProvider: (RemoteAPIServer.ServerEULARequestDTO) async -> RemoteAPIServer.ServerEULAResultDTO = { [weak self] req in
            guard let self else {
                return RemoteAPIServer.ServerEULAResultDTO(success: false, message: "not_available")
            }
            let serverId = req.serverId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !serverId.isEmpty else {
                return RemoteAPIServer.ServerEULAResultDTO(success: false, message: "missing_server_id")
            }
            return await MainActor.run {
                guard let server = self.configManager.config.servers.first(where: { $0.id == serverId }) else {
                    return RemoteAPIServer.ServerEULAResultDTO(success: false, message: "server_not_found", serverId: serverId)
                }
                guard server.serverType == .java else {
                    return RemoteAPIServer.ServerEULAResultDTO(success: false, message: "unsupported_server_type", serverId: serverId)
                }
                do {
                    try EULAManager.writeAcceptedEULA(in: server.serverDir)
                    if self.selectedServer?.id == serverId {
                        self.eulaAccepted = true
                    }
                    self.logAppMessage("[Server] Remote: accepted EULA for \"\(server.displayName)\".")
                    return RemoteAPIServer.ServerEULAResultDTO(success: true, message: "ok", serverId: serverId, accepted: true)
                } catch {
                    self.logAppMessage("[Server] Remote: failed to accept EULA for \"\(server.displayName)\": \(error.localizedDescription)")
                    return RemoteAPIServer.ServerEULAResultDTO(success: false, message: "eula_write_failed", serverId: serverId, accepted: false)
                }
            }
        }

        let templateIdFor: (_ kind: String, _ filename: String) -> String = { kind, filename in
            "\(kind):\(filename)"
        }
        let templateFilenameFromId: (_ id: String, _ kind: String) -> String? = { id, kind in
            let prefix = "\(kind):"
            guard id.hasPrefix(prefix) else { return nil }
            return String(id.dropFirst(prefix.count))
        }
        let templateFlavorForFilename: (_ filename: String) -> JavaServerFlavor = { filename in
            let lower = filename.lowercased()
            if lower.hasPrefix("purpur-") { return .purpur }
            if lower.hasPrefix("pufferfish") { return .pufferfish }
            if lower.hasPrefix("minecraft_server-") { return .vanilla }
            if lower.hasPrefix("fabric-server-launch") { return .fabric }
            return .paper
        }
        let scanExistingServerInfo: (_ sourceURL: URL, _ isZip: Bool) async -> (info: ScannedServerInfo?, message: String?) = { [weak self] sourceURL, isZip in
            guard let self else { return (nil, "not_available") }
            let fm = FileManager.default
            var scanDir = sourceURL
            var tempDir: URL? = nil
            if isZip {
                let tmp = fm.temporaryDirectory.appendingPathComponent("msc_remote_scan_\(UUID().uuidString)", isDirectory: true)
                do { try fm.createDirectory(at: tmp, withIntermediateDirectories: true) }
                catch { return (nil, "Could not create temp directory: \(error.localizedDescription)") }
                // Use ditto to avoid /usr/bin/unzip's mode-000 quirk on user-uploaded archives.
                let exitCode: Int32 = await Task.detached(priority: .userInitiated) {
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                    p.arguments = ["-x", "-k", sourceURL.path, tmp.path]
                    p.standardOutput = FileHandle.nullDevice
                    p.standardError  = FileHandle.nullDevice
                    do { try p.run(); p.waitUntilExit() } catch { return -1 }
                    return p.terminationStatus
                }.value
                guard exitCode == 0 else {
                    try? fm.removeItem(at: tmp)
                    return (nil, "Could not read archive (exit \(exitCode)). Make sure it is a valid .zip file.")
                }
                scanDir = tmp
                tempDir = tmp
            }
            if let contents = try? fm.contentsOfDirectory(at: scanDir, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles) {
                let subdirs = contents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
                let files = contents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == false }
                if subdirs.count == 1 && files.isEmpty { scanDir = subdirs[0] }
            }
            let info = await MainActor.run { self.scanServerDirectory(scanDir) }
            if let tmp = tempDir { try? fm.removeItem(at: tmp) }
            return (info, nil)
        }
        let buildTemplatesResponse: () -> RemoteAPIServer.TemplatesResponseDTO = { [weak self] in
            guard let self else { return RemoteAPIServer.TemplatesResponseDTO(note: "not_available") }
            self.loadPaperTemplates()
            self.loadPluginTemplates()
            let iso = ISO8601DateFormatter()
            func attrs(_ url: URL) -> (Int64?, String?) {
                guard let a = try? FileManager.default.attributesOfItem(atPath: url.path) else { return (nil, nil) }
                let size = (a[.size] as? NSNumber)?.int64Value
                let modified = (a[.modificationDate] as? Date).map { iso.string(from: $0) }
                return (size, modified)
            }
            let paper = self.paperTemplateItems.map { item -> RemoteAPIServer.TemplateItemDTO in
                let parsed = ComponentVersionParsing.parsePaperJarFilename(item.filename)
                let (size, modified) = attrs(item.url)
                return RemoteAPIServer.TemplateItemDTO(
                    id: templateIdFor("paper", item.filename),
                    kind: "paper",
                    filename: item.filename,
                    displayName: item.displayTitle,
                    sizeBytes: size,
                    modifiedAt: modified,
                    version: parsed?.mcVersion,
                    build: parsed?.build
                )
            }
            let plugins = self.pluginTemplateItems.map { item -> RemoteAPIServer.TemplateItemDTO in
                let (size, modified) = attrs(item.url)
                return RemoteAPIServer.TemplateItemDTO(
                    id: templateIdFor("plugin", item.filename),
                    kind: "plugin",
                    filename: item.filename,
                    displayName: item.displayTitle,
                    sizeBytes: size,
                    modifiedAt: modified
                )
            }
            let cfg = self.configManager.config
            let active = cfg.servers.first(where: { $0.id == cfg.activeServerId })
            return RemoteAPIServer.TemplatesResponseDTO(
                serverName: active?.displayName,
                serverRunning: self.isServerRunning,
                paperTemplates: paper,
                pluginTemplates: plugins
            )
        }
        let templatesProvider: () async -> RemoteAPIServer.TemplatesResponseDTO = {
            await MainActor.run { buildTemplatesResponse() }
        }
        let templateMutationProvider: (RemoteAPIServer.TemplateMutationRequestDTO) async -> RemoteAPIServer.TemplateMutationResultDTO = { [weak self] req in
            guard let self else { return RemoteAPIServer.TemplateMutationResultDTO(success: false, message: "not_available") }
            let action = req.action.trimmingCharacters(in: .whitespacesAndNewlines)
            switch action {
            case "exportServer":
                return await MainActor.run {
                    let cfg = self.configManager.config
                    let serverId = (req.serverId?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? cfg.activeServerId
                    guard let serverId else {
                        return RemoteAPIServer.TemplateMutationResultDTO(success: false, message: "missing_server_id")
                    }
                    guard let server = cfg.servers.first(where: { $0.id == serverId }) else {
                        return RemoteAPIServer.TemplateMutationResultDTO(success: false, message: "server_not_found")
                    }
                    let fm = FileManager.default
                    var exported = 0
                    if server.isJava, let source = self.effectivePaperJarURL(for: server), fm.fileExists(atPath: source.path) {
                        do {
                            try fm.createDirectory(at: self.configManager.paperTemplateDirURL, withIntermediateDirectories: true)
                            let serverDir = URL(fileURLWithPath: server.serverDir, isDirectory: true)
                            let sidecar = PaperVersionSidecarManager.read(fromServerDirectory: serverDir)
                            let destName: String
                            if let sidecar {
                                destName = "paper-\(sidecar.mcVersion)-build\(sidecar.build).jar"
                            } else {
                                destName = source.lastPathComponent
                            }
                            let dest = self.configManager.paperTemplateDirURL.appendingPathComponent(destName)
                            if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
                            try fm.copyItem(at: source, to: dest)
                            exported += 1
                        } catch {
                            self.logAppMessage("[Templates] Remote export failed for server jar: \(error.localizedDescription)")
                        }
                    }
                    if req.includePlugins ?? true {
                        let pluginsDir = URL(fileURLWithPath: server.serverDir, isDirectory: true).appendingPathComponent("plugins", isDirectory: true)
                        if let jars = try? fm.contentsOfDirectory(at: pluginsDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles).filter({ $0.pathExtension.lowercased() == "jar" }) {
                            do { try fm.createDirectory(at: self.configManager.pluginTemplateDirURL, withIntermediateDirectories: true) }
                            catch { self.logAppMessage("[Templates] Remote export could not create plugin template directory: \(error.localizedDescription)") }
                            for jar in jars {
                                let dest = self.configManager.pluginTemplateDirURL.appendingPathComponent(jar.lastPathComponent)
                                if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
                                do {
                                    try fm.copyItem(at: jar, to: dest)
                                    exported += 1
                                } catch {
                                    self.logAppMessage("[Templates] Remote export failed for \(jar.lastPathComponent): \(error.localizedDescription)")
                                }
                            }
                        }
                    }
                    self.loadPaperTemplates()
                    self.loadPluginTemplates()
                    self.logAppMessage("[Templates] Remote exported \(exported) template item(s) from \(server.displayName).")
                    return RemoteAPIServer.TemplateMutationResultDTO(success: true, message: "exported", exportedCount: exported, templates: buildTemplatesResponse())
                }

            case "createServer":
                let name = req.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !name.isEmpty else { return RemoteAPIServer.TemplateMutationResultDTO(success: false, message: "name_required") }
                guard let templateId = req.templateId,
                      let filename = templateFilenameFromId(templateId, "paper") else {
                    return RemoteAPIServer.TemplateMutationResultDTO(success: false, message: "template_required")
                }
                let context = await MainActor.run { () -> (URL, JavaServerFlavor)? in
                    self.loadPaperTemplates()
                    guard let item = self.paperTemplateItems.first(where: { $0.filename == filename }) else { return nil }
                    return (item.url, templateFlavorForFilename(item.filename))
                }
                guard let (templateURL, flavor) = context else {
                    return RemoteAPIServer.TemplateMutationResultDTO(success: false, message: "template_not_found")
                }
                let success = await self.createNewServer(
                    name: name,
                    initialWorldName: req.worldName,
                    jarSource: .template(templateURL),
                    flavor: flavor,
                    port: req.port ?? 25565,
                    enableCrossPlay: req.enableCrossPlay ?? false,
                    crossPlayBedrockPort: req.enableCrossPlay == true ? (req.crossPlayBedrockPort ?? 19132) : nil,
                    enablePlayit: req.enablePlayit ?? false,
                    difficulty: req.difficulty ?? "normal",
                    gamemode: req.gamemode ?? "survival",
                    worldSeed: req.worldSeed,
                    worldSource: .fresh
                )
                guard success else {
                    let error = await MainActor.run { self.lastServerCreateError ?? "create_failed" }
                    return RemoteAPIServer.TemplateMutationResultDTO(success: false, message: error)
                }
                return await MainActor.run {
                    let activeId = self.configManager.config.activeServerId
                    let created = activeId.flatMap { id in self.configManager.config.servers.first(where: { $0.id == id }) }
                    if req.acceptEula == true, let created {
                        try? "eula=true\n".write(
                            to: URL(fileURLWithPath: created.serverDir, isDirectory: true).appendingPathComponent("eula.txt"),
                            atomically: true,
                            encoding: .utf8
                        )
                    }
                    return RemoteAPIServer.TemplateMutationResultDTO(
                        success: true,
                        message: "created",
                        createdServerId: created?.id,
                        createdServerName: created?.displayName,
                        templates: buildTemplatesResponse()
                    )
                }

            default:
                return RemoteAPIServer.TemplateMutationResultDTO(success: false, message: "invalid_action")
            }
        }
        let serverImportScanProvider: (RemoteAPIServer.ServerImportRequestDTO) async -> RemoteAPIServer.ServerImportScanResponseDTO = { [weak self] req in
            guard self != nil else { return RemoteAPIServer.ServerImportScanResponseDTO(success: false, message: "not_available") }
            let rawPath = req.sourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawPath.isEmpty else { return RemoteAPIServer.ServerImportScanResponseDTO(success: false, message: "missing_source_path") }
            let expanded = (rawPath as NSString).expandingTildeInPath
            let sourceURL = URL(fileURLWithPath: expanded)
            let fm = FileManager.default
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: sourceURL.path, isDirectory: &isDir) else {
                return RemoteAPIServer.ServerImportScanResponseDTO(success: false, message: "source_not_found")
            }
            let kind = req.importKind?.lowercased() ?? "auto"
            let isZip = kind == "zip" || (kind == "auto" && sourceURL.pathExtension.lowercased() == "zip")
            let scan = await scanExistingServerInfo(sourceURL, isZip)
            if let message = scan.message {
                return RemoteAPIServer.ServerImportScanResponseDTO(success: false, message: message)
            }
            if let info = scan.info {
                let worlds = info.worlds.map {
                    RemoteAPIServer.ServerImportWorldDTO(id: $0.id, name: $0.name, sizeBytes: $0.sizeBytes, dimensionsLabel: $0.dimensionsLabel)
                }
                return RemoteAPIServer.ServerImportScanResponseDTO(
                    success: true,
                    message: "ok",
                    sourcePath: sourceURL.path,
                    isZip: isZip,
                    serverType: info.serverType.rawValue,
                    port: info.port,
                    maxPlayers: info.maxPlayers,
                    eulaAccepted: info.eulaAccepted,
                    worlds: worlds,
                    defaultWorldName: info.defaultWorldName,
                    javaFlavor: info.javaFlavor?.rawValue,
                    detectedMCVersion: info.detectedMCVersion,
                    detectedLoaderVersion: info.detectedLoaderVersion
                )
            }
            return RemoteAPIServer.ServerImportScanResponseDTO(success: false, message: "scan_failed")
        }
        let serverImportProvider: (RemoteAPIServer.ServerImportRequestDTO) async -> RemoteAPIServer.ServerImportResultDTO = { [weak self] req in
            guard let self else { return RemoteAPIServer.ServerImportResultDTO(success: false, message: "not_available") }
            let rawPath = req.sourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawPath.isEmpty else { return RemoteAPIServer.ServerImportResultDTO(success: false, message: "missing_source_path") }
            let expanded = (rawPath as NSString).expandingTildeInPath
            let sourceURL = URL(fileURLWithPath: expanded)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                return RemoteAPIServer.ServerImportResultDTO(success: false, message: "source_not_found")
            }
            let kind = req.importKind?.lowercased() ?? "auto"
            let action = req.action.trimmingCharacters(in: .whitespacesAndNewlines)
            let isTransfer = action == "importTransfer" || kind == "transfer" || sourceURL.pathExtension.lowercased() == ServerTransfer.fileExtension
            if isTransfer {
                let transferMode: TransferImportMode = req.transferMode == "replaceAll" ? .replaceAll : .merge
                if transferMode == .replaceAll {
                    guard let backupRaw = req.backupPath?.trimmingCharacters(in: .whitespacesAndNewlines), !backupRaw.isEmpty else {
                        return RemoteAPIServer.ServerImportResultDTO(success: false, message: "backup_path_required")
                    }
                    let backupURL = URL(fileURLWithPath: (backupRaw as NSString).expandingTildeInPath)
                    let backup = await self.exportServerTransfer(to: backupURL)
                    if case let .failure(message) = backup {
                        return RemoteAPIServer.ServerImportResultDTO(success: false, message: "backup_failed: \(message)")
                    }
                }
                let inspected = await self.inspectTransferPackage(at: sourceURL)
                guard case let .success(plan) = inspected else {
                    if case let .failure(message) = inspected {
                        return RemoteAPIServer.ServerImportResultDTO(success: false, message: message)
                    }
                    return RemoteAPIServer.ServerImportResultDTO(success: false, message: "inspect_failed")
                }
                let applied = await self.applyTransferImport(
                    plan: plan,
                    mode: transferMode,
                    javaPortOverrides: req.javaPortOverrides ?? [:],
                    bedrockPortOverrides: req.bedrockPortOverrides ?? [:]
                )
                switch applied {
                case .success(let summary):
                    return RemoteAPIServer.ServerImportResultDTO(success: true, message: "imported",
                                                                 imported: summary.imported, skipped: summary.skipped,
                                                                 replaced: summary.replaced)
                case .failure(let message):
                    try? FileManager.default.removeItem(at: plan.stagingDir)
                    return RemoteAPIServer.ServerImportResultDTO(success: false, message: message)
                }
            }

            let isZip = kind == "zip" || (kind == "auto" && sourceURL.pathExtension.lowercased() == "zip")
            let scan = await scanExistingServerInfo(sourceURL, isZip)
            let scannedInfo: ScannedServerInfo
            if let message = scan.message {
                return RemoteAPIServer.ServerImportResultDTO(success: false, message: message)
            }
            if let info = scan.info {
                scannedInfo = info
            } else {
                return RemoteAPIServer.ServerImportResultDTO(success: false, message: "scan_failed")
            }
            let displayName = req.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let safeName = (displayName?.isEmpty == false ? displayName : nil) ?? sourceURL.deletingPathExtension().lastPathComponent
            guard !safeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return RemoteAPIServer.ServerImportResultDTO(success: false, message: "display_name_required")
            }
            let serverType = req.serverType.flatMap(ServerType.init(rawValue:)) ?? scannedInfo.serverType
            let before = await MainActor.run { Set(self.configManager.config.servers.map(\.id)) }
            let result = await self.importExistingServer(
                sourceURL: sourceURL,
                isZip: isZip,
                displayName: safeName,
                serverType: serverType,
                activeWorldName: req.activeWorldName ?? scannedInfo.defaultWorldName,
                portOverride: req.port ?? scannedInfo.port,
                maxPlayersOverride: req.maxPlayers ?? scannedInfo.maxPlayers,
                eulaOverride: req.acceptEula ?? scannedInfo.eulaAccepted,
                enablePlayit: req.enablePlayit ?? false
            )
            switch result {
            case .success:
                return await MainActor.run {
                    let created = self.configManager.config.servers.first(where: { !before.contains($0.id) })
                        ?? self.configManager.config.activeServerId.flatMap { id in self.configManager.config.servers.first(where: { $0.id == id }) }
                    return RemoteAPIServer.ServerImportResultDTO(success: true, message: "imported",
                                                                 serverId: created?.id, serverName: created?.displayName,
                                                                 imported: 1, skipped: 0, replaced: false)
                }
            case .failure(let message):
                return RemoteAPIServer.ServerImportResultDTO(success: false, message: message)
            }
        }
        server.renameServerProvider = renameServerProvider
        server.deleteServerProvider = deleteServerProvider
        server.createServerProvider = createServerProvider
        server.acceptEULAProvider = acceptEULAProvider
        server.templatesProvider = templatesProvider
        server.templateMutationProvider = templateMutationProvider
        server.serverImportScanProvider = serverImportScanProvider
        server.serverImportProvider = serverImportProvider
    }
}

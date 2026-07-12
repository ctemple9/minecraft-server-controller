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
                self.deleteServer(withId: trimmedId)
                return RemoteAPIServer.ServerDeleteResultDTO(success: true, message: "ok", serverId: trimmedId)
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
                let exitCode: Int32 = await Task.detached(priority: .userInitiated) {
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                    p.arguments = ["-q", sourceURL.path, "-d", tmp.path]
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
        server.templatesProvider = templatesProvider
        server.templateMutationProvider = templateMutationProvider
        server.serverImportScanProvider = serverImportScanProvider
        server.serverImportProvider = serverImportProvider
    }
}

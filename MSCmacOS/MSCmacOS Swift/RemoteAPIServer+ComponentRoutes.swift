import Foundation

// MARK: - Component & Broadcast route handlers
//
// Called from RemoteAPIServer+HTTP.swift for:
//   GET  /components
//   POST /components/update
//   GET  /broadcast/status
//   POST /broadcast/restart
//   POST /broadcast/credentials

extension RemoteAPIServer {

    // MARK: - Server management (P14): rename / delete

    private func serverMutationStatus(success: Bool, message: String) -> Int {
        if success { return 200 }
        switch message {
        case "name_required", "missing_server_id", "invalid_server_type", "invalid_java_flavor", "unsupported_server_type": return 400
        case "server_not_found": return 404
        case "server_running", "create_failed": return 409
        case "delete_failed", "eula_write_failed": return 500
        default: return 500
        }
    }

    func handleRenameServer(body: Data, clientFD: Int32) {
        guard !body.isEmpty else {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "missing_body"], clientFD: clientFD)
            return
        }
        do {
            let req = try JSONDecoder().decode(ServerRenameRequestDTO.self, from: body)
            let serverId = req.serverId.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = req.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !serverId.isEmpty else {
                sendJSON(statusCode: 400, reason: "Bad Request",
                         jsonObject: ["error": "missing_server_id"], clientFD: clientFD)
                return
            }
            guard !name.isEmpty else {
                sendJSON(statusCode: 400, reason: "Bad Request",
                         jsonObject: ["error": "name_required"], clientFD: clientFD)
                return
            }
            Task { [weak self] in
                guard let self else { return }
                let result = await renameServerProvider(serverId, name)
                sendJSON(statusCode: serverMutationStatus(success: result.success, message: result.message),
                         reason: result.success ? "OK" : "Error",
                         encodable: result, clientFD: clientFD)
            }
        } catch {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "invalid_json"], clientFD: clientFD)
        }
    }

    func handleDeleteServer(body: Data, clientFD: Int32) {
        guard !body.isEmpty else {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "missing_body"], clientFD: clientFD)
            return
        }
        do {
            let req = try JSONDecoder().decode(ServerDeleteRequestDTO.self, from: body)
            let serverId = req.serverId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !serverId.isEmpty else {
                sendJSON(statusCode: 400, reason: "Bad Request",
                         jsonObject: ["error": "missing_server_id"], clientFD: clientFD)
                return
            }
            Task { [weak self] in
                guard let self else { return }
                let result = await deleteServerProvider(serverId)
                sendJSON(statusCode: serverMutationStatus(success: result.success, message: result.message),
                         reason: result.success ? "OK" : "Error",
                         encodable: result, clientFD: clientFD)
            }
        } catch {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "invalid_json"], clientFD: clientFD)
        }
    }

    func handleCreateServer(body: Data, clientFD: Int32) {
        guard !body.isEmpty else {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "missing_body"], clientFD: clientFD)
            return
        }
        do {
            let req = try JSONDecoder().decode(ServerCreateRequestDTO.self, from: body)
            let name = req.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                sendJSON(statusCode: 400, reason: "Bad Request",
                         jsonObject: ["error": "name_required"], clientFD: clientFD)
                return
            }
            Task { [weak self] in
                guard let self else { return }
                let result = await createServerProvider(req)
                sendJSON(statusCode: serverMutationStatus(success: result.success, message: result.message),
                         reason: result.success ? "OK" : "Error",
                         encodable: result, clientFD: clientFD)
            }
        } catch {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "invalid_json"], clientFD: clientFD)
        }
    }

    func handleAcceptServerEULA(body: Data, clientFD: Int32) {
        guard !body.isEmpty else {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "missing_body"], clientFD: clientFD)
            return
        }
        do {
            let req = try JSONDecoder().decode(ServerEULARequestDTO.self, from: body)
            let serverId = req.serverId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !serverId.isEmpty else {
                sendJSON(statusCode: 400, reason: "Bad Request",
                         jsonObject: ["error": "missing_server_id"], clientFD: clientFD)
                return
            }
            Task { [weak self] in
                guard let self else { return }
                let result = await acceptEULAProvider(req)
                sendJSON(statusCode: serverMutationStatus(success: result.success, message: result.message),
                         reason: result.success ? "OK" : "Error",
                         encodable: result, clientFD: clientFD)
            }
        } catch {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "invalid_json"], clientFD: clientFD)
        }
    }

    // MARK: - Templates / server import (P15): templates + transfer/import

    private func templateMutationStatus(_ result: TemplateMutationResultDTO) -> Int {
        if result.success { return 200 }
        switch result.message {
        case "invalid_action", "name_required", "template_required", "missing_server_id",
             "missing_source_path", "invalid_path": return 400
        case "server_not_found", "template_not_found": return 404
        case "server_running", "unsupported_template": return 409
        default: return 500
        }
    }

    private func importStatus(success: Bool, message: String) -> Int {
        if success { return 200 }
        switch message {
        case "invalid_action", "missing_source_path", "invalid_path", "display_name_required",
             "backup_path_required": return 400
        case "source_not_found": return 404
        case "server_running": return 409
        default: return 500
        }
    }

    func handleGetTemplates(clientFD: Int32) {
        Task { [weak self] in
            guard let self else { return }
            let dto = await templatesProvider()
            sendJSON(statusCode: 200, reason: "OK", encodable: dto, clientFD: clientFD)
        }
    }

    func handleMutateTemplates(body: Data, clientFD: Int32) {
        guard !body.isEmpty else {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "missing_body"], clientFD: clientFD)
            return
        }
        do {
            let req = try JSONDecoder().decode(TemplateMutationRequestDTO.self, from: body)
            Task { [weak self] in
                guard let self else { return }
                let result = await templateMutationProvider(req)
                sendJSON(statusCode: templateMutationStatus(result),
                         reason: result.success ? "OK" : "Error",
                         encodable: result, clientFD: clientFD)
            }
        } catch {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "invalid_json"], clientFD: clientFD)
        }
    }

    func handleImportServer(body: Data, clientFD: Int32) {
        guard !body.isEmpty else {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "missing_body"], clientFD: clientFD)
            return
        }
        do {
            let req = try JSONDecoder().decode(ServerImportRequestDTO.self, from: body)
            let action = req.action.trimmingCharacters(in: .whitespacesAndNewlines)
            Task { [weak self] in
                guard let self else { return }
                if action == "scan" {
                    let result = await serverImportScanProvider(req)
                    sendJSON(statusCode: importStatus(success: result.success, message: result.message),
                             reason: result.success ? "OK" : "Error",
                             encodable: result, clientFD: clientFD)
                } else {
                    let result = await serverImportProvider(req)
                    sendJSON(statusCode: importStatus(success: result.success, message: result.message),
                             reason: result.success ? "OK" : "Error",
                             encodable: result, clientFD: clientFD)
                }
            }
        } catch {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "invalid_json"], clientFD: clientFD)
        }
    }

    // MARK: - Player polish (P16): skins + hidden profiles

    private func playerMutationStatus(success: Bool, message: String) -> Int {
        if success { return 200 }
        switch message {
        case "missing_profile_id", "invalid_profile_id": return 400
        case "profile_not_found": return 404
        case "no_active_server": return 409
        default: return 500
        }
    }

    func handleGetPlayerSkin(profileId: String, clientFD: Int32) {
        let trimmed = profileId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "missing_profile_id"], clientFD: clientFD)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let result = await playerSkinProvider(trimmed)
            let status = result.success ? 200 : (result.message == "profile_not_found" ? 404 : 500)
            sendJSON(statusCode: status, reason: result.success ? "OK" : "Error",
                     encodable: result, clientFD: clientFD)
        }
    }

    func handleSetPlayerSkinOverride(body: Data, clientFD: Int32) {
        guard !body.isEmpty else {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "missing_body"], clientFD: clientFD)
            return
        }
        do {
            let req = try JSONDecoder().decode(PlayerSkinOverrideRequestDTO.self, from: body)
            let profileId = req.profileId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !profileId.isEmpty else {
                sendJSON(statusCode: 400, reason: "Bad Request",
                         jsonObject: ["error": "missing_profile_id"], clientFD: clientFD)
                return
            }
            Task { [weak self] in
                guard let self else { return }
                let result = await playerSkinOverrideProvider(profileId, req.lookupIdentifier)
                sendJSON(statusCode: playerMutationStatus(success: result.success, message: result.message),
                         reason: result.success ? "OK" : "Error",
                         encodable: result, clientFD: clientFD)
            }
        } catch {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "invalid_json"], clientFD: clientFD)
        }
    }

    func handleSetHiddenProfile(body: Data, clientFD: Int32) {
        guard !body.isEmpty else {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "missing_body"], clientFD: clientFD)
            return
        }
        do {
            let req = try JSONDecoder().decode(HiddenProfileMutationRequestDTO.self, from: body)
            let profileId = req.profileId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !profileId.isEmpty else {
                sendJSON(statusCode: 400, reason: "Bad Request",
                         jsonObject: ["error": "missing_profile_id"], clientFD: clientFD)
                return
            }
            Task { [weak self] in
                guard let self else { return }
                let result = await hiddenProfileProvider(profileId, req.hidden)
                sendJSON(statusCode: playerMutationStatus(success: result.success, message: result.message),
                         reason: result.success ? "OK" : "Error",
                         encodable: result, clientFD: clientFD)
            }
        } catch {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "invalid_json"], clientFD: clientFD)
        }
    }

    // MARK: - Server files + client export (P16)

    func handleGetFiles(path: String?, clientFD: Int32) {
        Task { [weak self] in
            guard let self else { return }
            let dto = await filesProvider(path)
            sendJSON(statusCode: dto.note == "no_active_server" ? 409 : 200,
                     reason: dto.note == "no_active_server" ? "Conflict" : "OK",
                     encodable: dto, clientFD: clientFD)
        }
    }

    func handleReadFile(path: String, clientFD: Int32) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "missing_path"], clientFD: clientFD)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let result = await fileReadProvider(trimmed)
            let status: Int
            switch result.message {
            case "file_not_found": status = 404
            case "directory_not_file", "not_previewable", "no_active_server": status = 409
            case "read_failed": status = 500  // E2: file exists but couldn't be read (IO/permission)
            default: status = result.success ? 200 : 500
            }
            sendJSON(statusCode: status, reason: result.success ? "OK" : "Error",
                     encodable: result, clientFD: clientFD)
        }
    }

    func handleGetClientExport(selectedIds: [String]?, clientFD: Int32) {
        Task { [weak self] in
            guard let self else { return }
            let dto = await clientExportProvider(selectedIds)
            sendJSON(statusCode: dto.note == "no_active_server" ? 409 : 200,
                     reason: dto.note == "no_active_server" ? "Conflict" : "OK",
                     encodable: dto, clientFD: clientFD)
        }
    }

    // MARK: - GET /components

    func handleGetComponents(clientFD: Int32) {
        Task { [weak self] in
            guard let self else { return }
            let dto = await componentsProvider()
            sendJSON(statusCode: 200, reason: "OK", encodable: dto, clientFD: clientFD)
        }
    }

    // MARK: - POST /components/update

    func handleUpdateComponent(body: Data, clientFD: Int32) {
        guard !body.isEmpty else {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "missing_body"], clientFD: clientFD)
            return
        }

        do {
            let decoded = try JSONDecoder().decode(ComponentUpdateRequestDTO.self, from: body)

            // New path A: update all Modrinth add-ons that have available updates.
            if decoded.updateAll == true {
                Task { [weak self] in
                    guard let self else { return }
                    let result = updateAddonProvider(nil, true)
                    let status = (result.result == "update_started" || result.result == "no_updates_available") ? 200 : 500
                    self.sendJSON(statusCode: status, reason: "OK", encodable: result, clientFD: clientFD)
                }
                return
            }

            // New path B: update a specific Modrinth add-on by jarStem.
            if let jarStem = decoded.jarStem,
               !jarStem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let trimmed = jarStem.trimmingCharacters(in: .whitespacesAndNewlines)
                Task { [weak self] in
                    guard let self else { return }
                    let result = updateAddonProvider(trimmed, false)
                    let status: Int
                    switch result.result {
                    case "update_started", "no_updates_available": status = 200
                    case "not_found": status = 404
                    case "not_supported": status = 409
                    default: status = 500
                    }
                    self.sendJSON(statusCode: status, reason: "OK", encodable: result, clientFD: clientFD)
                }
                return
            }

            // Legacy path: system component (paper | geyser | floodgate).
            let component = (decoded.component ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !component.isEmpty else {
                sendJSON(statusCode: 400, reason: "Bad Request",
                         jsonObject: ["error": "missing_component_or_jar_stem"], clientFD: clientFD)
                return
            }
            guard ["paper", "geyser", "floodgate"].contains(component) else {
                sendJSON(statusCode: 400, reason: "Bad Request",
                         jsonObject: ["error": "unknown_component"], clientFD: clientFD)
                return
            }

            let capturedFD = clientFD
            updateComponentProvider(component) { [weak self] result in
                guard let self else { return }
                let status = result.success ? 200 : 500
                let reason = result.success ? "OK" : "Internal Server Error"
                self.sendJSON(statusCode: status, reason: reason, encodable: result, clientFD: capturedFD)
            }
        } catch {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "invalid_json"], clientFD: clientFD)
        }
    }

    // MARK: - GET /addons

    func handleGetAddons(clientFD: Int32) {
        Task { [weak self] in
            guard let self else { return }
            let dto = await addonsProvider()
            sendJSON(statusCode: 200, reason: "OK", encodable: dto, clientFD: clientFD)
        }
    }

    // MARK: - POST /components/remove

    func handleRemoveAddon(body: Data, clientFD: Int32) {
        guard !body.isEmpty else {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "missing_body"], clientFD: clientFD)
            return
        }
        do {
            struct RemoveRequest: Decodable { let jarStem: String }
            let decoded = try JSONDecoder().decode(RemoveRequest.self, from: body)
            let jarStem = decoded.jarStem.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !jarStem.isEmpty else {
                sendJSON(statusCode: 400, reason: "Bad Request",
                         jsonObject: ["error": "missing_jar_stem"], clientFD: clientFD)
                return
            }
            let result = removeAddonProvider(jarStem)
            if result.success {
                sendJSON(statusCode: 200, reason: "OK", encodable: result, clientFD: clientFD)
            } else {
                let status: Int
                switch result.message {
                case "not_found": status = 404
                case "not_supported": status = 409
                default: status = 500
                }
                sendJSON(statusCode: status, reason: "Error", encodable: result, clientFD: clientFD)
            }
        } catch {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "invalid_json"], clientFD: clientFD)
        }
    }

    // MARK: - GET /catalog/search

    func handleCatalogSearch(query: String, offset: Int, clientFD: Int32) {
        Task { [weak self] in
            guard let self else { return }
            // Search is a read: always 200. `supportsAddons=false` + `note` conveys
            // unsupported/no-active-server states in the body for the client to render.
            let dto = await catalogSearchProvider(query, offset)
            self.sendJSON(statusCode: 200, reason: "OK", encodable: dto, clientFD: clientFD)
        }
    }

    // MARK: - POST /components/install

    func handleInstallAddon(body: Data, clientFD: Int32) {
        guard !body.isEmpty else {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "missing_body"], clientFD: clientFD)
            return
        }
        do {
            let decoded = try JSONDecoder().decode(CatalogInstallRequestDTO.self, from: body)
            let projectId = decoded.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
            let slug = decoded.slug.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = decoded.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !slug.isEmpty || !projectId.isEmpty else {
                sendJSON(statusCode: 400, reason: "Bad Request",
                         jsonObject: ["error": "missing_project"], clientFD: clientFD)
                return
            }
            Task { [weak self] in
                guard let self else { return }
                let result = await installAddonProvider(projectId, slug.isEmpty ? projectId : slug, title.isEmpty ? slug : title)
                let status: Int
                if result.success {
                    status = 200
                } else {
                    switch result.message {
                    case "not_supported": status = 409
                    case "no_active_server": status = 409
                    default: status = 200   // a "no compatible version" is a valid, non-error outcome the client shows
                    }
                }
                self.sendJSON(statusCode: status, reason: result.success ? "OK" : "Error", encodable: result, clientFD: clientFD)
            }
        } catch {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "invalid_json"], clientFD: clientFD)
        }
    }

    // MARK: - GET /versions

    func handleGetVersions(clientFD: Int32) {
        Task { [weak self] in
            guard let self else { return }
            let dto = await versionsProvider()
            sendJSON(statusCode: 200, reason: "OK", encodable: dto, clientFD: clientFD)
        }
    }

    // MARK: - GET /broadcast/jar-status

    func handleGetBroadcastJarStatus(clientFD: Int32) {
        Task { [weak self] in
            guard let self else { return }
            let dto = await broadcastJarStatusProvider()
            sendJSON(statusCode: 200, reason: "OK", encodable: dto, clientFD: clientFD)
        }
    }

    // MARK: - POST /broadcast/download-jar

    func handleDownloadBroadcastJar(clientFD: Int32) {
        Task { [weak self] in
            guard let self else { return }
            let dto = await downloadBroadcastJarProvider()
            sendJSON(statusCode: dto.success ? 200 : 409, reason: dto.success ? "OK" : "Conflict",
                     encodable: dto, clientFD: clientFD)
        }
    }

    // MARK: - GET /java-runtimes

    func handleGetJavaRuntimes(clientFD: Int32) {
        Task { [weak self] in
            guard let self else { return }
            let dto = await javaRuntimesProvider()
            sendJSON(statusCode: 200, reason: "OK", encodable: dto, clientFD: clientFD)
        }
    }

    // MARK: - GET /config/java-runtime

    func handleGetJavaConfig(clientFD: Int32) {
        Task { [weak self] in
            guard let self else { return }
            let dto = await getJavaConfigProvider()
            sendJSON(statusCode: 200, reason: "OK", encodable: dto, clientFD: clientFD)
        }
    }

    // MARK: - POST /config/java-runtime

    func handleSetJavaConfig(body: Data, clientFD: Int32) {
        guard !body.isEmpty else {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "missing_body"], clientFD: clientFD)
            return
        }
        do {
            let req = try JSONDecoder().decode(JavaConfigSetRequestDTO.self, from: body)
            Task { [weak self] in
                guard let self else { return }
                let ok = await setJavaConfigProvider(req.executablePath)
                if ok {
                    let dto = await getJavaConfigProvider()
                    sendJSON(statusCode: 200, reason: "OK", encodable: dto, clientFD: clientFD)
                } else {
                    sendJSON(statusCode: 500, reason: "Internal Server Error",
                             jsonObject: ["error": "set_failed"], clientFD: clientFD)
                }
            }
        } catch {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "invalid_json"], clientFD: clientFD)
        }
    }

    // MARK: - GET /versions/create

    func handleGetCreateVersions(serverType: String?, javaFlavor: String?, clientFD: Int32) {
        Task { [weak self] in
            guard let self else { return }
            let dto = await createVersionsProvider(serverType, javaFlavor)
            sendJSON(statusCode: 200, reason: "OK", encodable: dto, clientFD: clientFD)
        }
    }

    // MARK: - POST /components/version

    func handleChangeVersion(body: Data, clientFD: Int32) {
        guard !body.isEmpty else {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "missing_body"], clientFD: clientFD)
            return
        }
        do {
            let decoded = try JSONDecoder().decode(VersionChangeRequestDTO.self, from: body)
            let versionId = decoded.versionId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !versionId.isEmpty else {
                sendJSON(statusCode: 400, reason: "Bad Request",
                         jsonObject: ["error": "missing_version_id"], clientFD: clientFD)
                return
            }
            Task { [weak self] in
                guard let self else { return }
                let result = await changeVersionProvider(versionId, decoded.loaderVersion)
                let status: Int
                switch result.message {
                case "server_running":          status = 409
                case "no_active_server":        status = 409
                case "not_supported":           status = 409
                case "download_in_progress":    status = 429
                default:                        status = result.success ? 200 : 500
                }
                self.sendJSON(statusCode: status, reason: result.success ? "OK" : "Error",
                             encodable: result, clientFD: clientFD)
            }
        } catch {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "invalid_json"], clientFD: clientFD)
        }
    }

    // MARK: - GET /resourcepacks

    func handleGetResourcePacks(clientFD: Int32) {
        Task { [weak self] in
            guard let self else { return }
            let dto = await resourcePacksProvider()
            sendJSON(statusCode: 200, reason: "OK", encodable: dto, clientFD: clientFD)
        }
    }

    // MARK: - POST /resourcepacks/activate

    func handleActivateResourcePack(body: Data, clientFD: Int32) {
        guard !body.isEmpty else {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "missing_body"], clientFD: clientFD)
            return
        }
        do {
            let req = try JSONDecoder().decode(ResourcePackActivateRequestDTO.self, from: body)
            Task { [weak self] in
                guard let self else { return }
                let result = await activateResourcePackProvider(req.packId, req.require ?? false)
                let status = result.success ? 200 : (result.message == "no_active_server" || result.message == "java_only" ? 409 : 500)
                sendJSON(statusCode: status, reason: result.success ? "OK" : "Error",
                         encodable: result, clientFD: clientFD)
            }
        } catch {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "invalid_json"], clientFD: clientFD)
        }
    }

    // MARK: - POST /resourcepacks/seturl

    func handleSetResourcePackURL(body: Data, clientFD: Int32) {
        guard !body.isEmpty else {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "missing_body"], clientFD: clientFD)
            return
        }
        do {
            let req = try JSONDecoder().decode(ResourcePackSetURLRequestDTO.self, from: body)
            guard !req.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                sendJSON(statusCode: 400, reason: "Bad Request",
                         jsonObject: ["error": "url_required"], clientFD: clientFD)
                return
            }
            Task { [weak self] in
                guard let self else { return }
                let result = await setResourcePackURLProvider(req.url, req.sha1, req.require ?? false)
                let status = result.success ? 200 : (result.message == "no_active_server" || result.message == "java_only" ? 409 : 500)
                sendJSON(statusCode: status, reason: result.success ? "OK" : "Error",
                         encodable: result, clientFD: clientFD)
            }
        } catch {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "invalid_json"], clientFD: clientFD)
        }
    }

    // MARK: - POST /resourcepacks/toggle

    func handleToggleGeyserPack(body: Data, clientFD: Int32) {
        guard !body.isEmpty else {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "missing_body"], clientFD: clientFD)
            return
        }
        do {
            let req = try JSONDecoder().decode(ResourcePackToggleRequestDTO.self, from: body)
            Task { [weak self] in
                guard let self else { return }
                let result = await toggleGeyserPackProvider(req.packId, req.enabled)
                let status = result.success ? 200 : (result.message == "pack_not_found" ? 404 : 500)
                sendJSON(statusCode: status, reason: result.success ? "OK" : "Error",
                         encodable: result, clientFD: clientFD)
            }
        } catch {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "invalid_json"], clientFD: clientFD)
        }
    }

    // MARK: - POST /resourcepacks/remove

    func handleRemoveResourcePack(body: Data, clientFD: Int32) {
        guard !body.isEmpty else {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "missing_body"], clientFD: clientFD)
            return
        }
        do {
            let req = try JSONDecoder().decode(ResourcePackRemoveRequestDTO.self, from: body)
            Task { [weak self] in
                guard let self else { return }
                let result = await removeResourcePackProvider(req.packId, req.packKind)
                let status = result.success ? 200 : (result.message == "pack_not_found" ? 404 : 500)
                sendJSON(statusCode: status, reason: result.success ? "OK" : "Error",
                         encodable: result, clientFD: clientFD)
            }
        } catch {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "invalid_json"], clientFD: clientFD)
        }
    }

    // MARK: - World management (P9): create / rename / replace / repair

    /// Maps a WorldMutationResultDTO.message to an HTTP status code.
    private func worldMutationStatus(_ result: WorldMutationResultDTO) -> Int {
        if result.success { return 200 }
        switch result.message {
        case "name_required":                              return 400
        case "slot_not_found", "source_not_found":         return 404
        case "no_active_server", "server_running",
             "bedrock_only", "not_active_slot", "same_slot",
             "repair_in_progress":                         return 409
        default:                                           return 500
        }
    }

    // MARK: - POST /worlds/create

    func handleCreateWorld(body: Data, clientFD: Int32) {
        guard !body.isEmpty else {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "missing_body"], clientFD: clientFD)
            return
        }
        do {
            let req = try JSONDecoder().decode(WorldCreateRequestDTO.self, from: body)
            guard !req.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                sendJSON(statusCode: 400, reason: "Bad Request",
                         jsonObject: ["error": "name_required"], clientFD: clientFD)
                return
            }
            Task { [weak self] in
                guard let self else { return }
                let result = await createWorldSlotProvider(req.name, req.seed)
                sendJSON(statusCode: worldMutationStatus(result), reason: result.success ? "OK" : "Error",
                         encodable: result, clientFD: clientFD)
            }
        } catch {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "invalid_json"], clientFD: clientFD)
        }
    }

    // MARK: - POST /worlds/rename

    func handleRenameWorld(body: Data, clientFD: Int32) {
        guard !body.isEmpty else {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "missing_body"], clientFD: clientFD)
            return
        }
        do {
            let req = try JSONDecoder().decode(WorldRenameRequestDTO.self, from: body)
            guard !req.slotId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                sendJSON(statusCode: 400, reason: "Bad Request",
                         jsonObject: ["error": "missing_slot_id"], clientFD: clientFD)
                return
            }
            Task { [weak self] in
                guard let self else { return }
                let result = await renameWorldSlotProvider(req.slotId, req.name)
                sendJSON(statusCode: worldMutationStatus(result), reason: result.success ? "OK" : "Error",
                         encodable: result, clientFD: clientFD)
            }
        } catch {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "invalid_json"], clientFD: clientFD)
        }
    }

    // MARK: - POST /worlds/replace

    func handleReplaceWorld(body: Data, clientFD: Int32) {
        guard !body.isEmpty else {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "missing_body"], clientFD: clientFD)
            return
        }
        do {
            let req = try JSONDecoder().decode(WorldReplaceRequestDTO.self, from: body)
            guard !req.slotId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !req.sourceSlotId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                sendJSON(statusCode: 400, reason: "Bad Request",
                         jsonObject: ["error": "missing_slot_id"], clientFD: clientFD)
                return
            }
            Task { [weak self] in
                guard let self else { return }
                let result = await replaceWorldSlotProvider(req.slotId, req.sourceSlotId)
                sendJSON(statusCode: worldMutationStatus(result), reason: result.success ? "OK" : "Error",
                         encodable: result, clientFD: clientFD)
            }
        } catch {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "invalid_json"], clientFD: clientFD)
        }
    }

    // MARK: - POST /worlds/repair

    func handleRepairWorld(body: Data, clientFD: Int32) {
        guard !body.isEmpty else {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "missing_body"], clientFD: clientFD)
            return
        }
        do {
            let req = try JSONDecoder().decode(WorldRepairRequestDTO.self, from: body)
            guard !req.slotId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                sendJSON(statusCode: 400, reason: "Bad Request",
                         jsonObject: ["error": "missing_slot_id"], clientFD: clientFD)
                return
            }
            Task { [weak self] in
                guard let self else { return }
                let result = await repairWorldSlotProvider(req.slotId)
                sendJSON(statusCode: worldMutationStatus(result), reason: result.success ? "OK" : "Error",
                         encodable: result, clientFD: clientFD)
            }
        } catch {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "invalid_json"], clientFD: clientFD)
        }
    }

    // MARK: - Diagnostics (P10): GET /health, GET /health/problems, POST /health/repair

    func handleGetHealth(clientFD: Int32) {
        Task { [weak self] in
            guard let self else { return }
            let dto = await healthProvider()
            sendJSON(statusCode: 200, reason: "OK", encodable: dto, clientFD: clientFD)
        }
    }

    func handleGetHealthProblems(clientFD: Int32) {
        Task { [weak self] in
            guard let self else { return }
            let dto = await healthProblemsProvider()
            sendJSON(statusCode: 200, reason: "OK", encodable: dto, clientFD: clientFD)
        }
    }

    func handleRepairHealthProblem(body: Data, clientFD: Int32) {
        guard !body.isEmpty else {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "missing_body"], clientFD: clientFD)
            return
        }
        do {
            let req = try JSONDecoder().decode(HealthRepairRequestDTO.self, from: body)
            guard !req.problemId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                sendJSON(statusCode: 400, reason: "Bad Request",
                         jsonObject: ["error": "missing_problem_id"], clientFD: clientFD)
                return
            }
            Task { [weak self] in
                guard let self else { return }
                let result = await repairHealthProblemProvider(req.problemId, req.action)
                let status: Int
                switch result.message {
                case "server_running":              status = 409
                case "no_active_server":            status = 409
                case "problem_not_found":           status = 404
                case "invalid_action", "action_unavailable": status = 400
                default:                            status = result.success ? 200 : 500
                }
                self.sendJSON(statusCode: status, reason: result.success ? "OK" : "Error",
                             encodable: result, clientFD: clientFD)
            }
        } catch {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "invalid_json"], clientFD: clientFD)
        }
    }

    // MARK: - GET /playit + POST /playit/start + POST /playit/stop (P12)

    func handleGetPlayitStatus(clientFD: Int32) {
        Task { [weak self] in
            guard let self else { return }
            let dto = await playitStatusProvider()
            sendJSON(statusCode: 200, reason: "OK", encodable: dto, clientFD: clientFD)
        }
    }

    func handleStartPlayit(clientFD: Int32) {
        Task { [weak self] in
            guard let self else { return }
            let result = await startPlayitProvider()
            let status: Int
            switch result.result {
            case "not_enabled", "no_secret_key", "no_server": status = 409
            default: status = 200
            }
            sendJSON(statusCode: status, reason: status == 200 ? "OK" : "Conflict",
                     encodable: result, clientFD: clientFD)
        }
    }

    func handleStopPlayit(clientFD: Int32) {
        Task { [weak self] in
            guard let self else { return }
            let result = await stopPlayitProvider()
            sendJSON(statusCode: 200, reason: "OK", encodable: result, clientFD: clientFD)
        }
    }

    // MARK: - GET/POST /duckdns (P13)

    func handleGetDuckDNS(clientFD: Int32) {
        Task { [weak self] in
            guard let self else { return }
            let dto = await duckdnsStatusProvider()
            sendJSON(statusCode: 200, reason: "OK", encodable: dto, clientFD: clientFD)
        }
    }

    func handleUpdateDuckDNS(body: Data, clientFD: Int32) {
        struct Body: Decodable { let hostname: String? }
        guard let req = try? JSONDecoder().decode(Body.self, from: body) else {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "invalid_json"], clientFD: clientFD)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let result = await updateDuckDNSProvider(req.hostname)
            sendJSON(statusCode: result.success ? 200 : 500,
                     reason: result.success ? "OK" : "Error",
                     encodable: result, clientFD: clientFD)
        }
    }

    // MARK: - GET/POST /config/ram

    func handleGetRAMConfig(clientFD: Int32) {
        Task { [weak self] in
            guard let self else { return }
            let dto = await ramConfigProvider()
            sendJSON(statusCode: 200, reason: "OK", encodable: dto, clientFD: clientFD)
        }
    }

    func handleUpdateRAMConfig(body: Data, clientFD: Int32) {
        struct Body: Decodable { let minRamGB: Double?; let maxRamGB: Double? }
        guard let req = try? JSONDecoder().decode(Body.self, from: body) else {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "invalid_json"], clientFD: clientFD)
            return
        }
        guard req.minRamGB != nil || req.maxRamGB != nil else {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "no_changes"], clientFD: clientFD)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let result = await updateRAMConfigProvider(req.minRamGB, req.maxRamGB)
            let status: Int
            if result.success { status = 200 }
            else if result.message == "no_active_server" { status = 409 }
            else { status = 500 }
            sendJSON(statusCode: status, reason: result.success ? "OK" : "Error",
                     encodable: result, clientFD: clientFD)
        }
    }

    // MARK: - GET/POST /config/geyser (P13)

    func handleGetGeyserConfig(clientFD: Int32) {
        Task { [weak self] in
            guard let self else { return }
            let dto = await geyserConfigProvider()
            sendJSON(statusCode: 200, reason: "OK", encodable: dto, clientFD: clientFD)
        }
    }

    func handleUpdateGeyserConfig(body: Data, clientFD: Int32) {
        struct Body: Decodable { let address: String?; let port: Int? }
        guard let req = try? JSONDecoder().decode(Body.self, from: body) else {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "invalid_json"], clientFD: clientFD)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let result = await updateGeyserConfigProvider(req.address, req.port)
            let status: Int
            switch result.message {
            case "no_server", "not_installed": status = 409
            default: status = result.success ? 200 : 500
            }
            sendJSON(statusCode: status, reason: result.success ? "OK" : "Error",
                     encodable: result, clientFD: clientFD)
        }
    }

    // MARK: - GET /connectivity (P11)

    func handleGetConnectivity(clientFD: Int32) {
        Task { [weak self] in
            guard let self else { return }
            let dto = await connectivityProvider()
            sendJSON(statusCode: 200, reason: "OK", encodable: dto, clientFD: clientFD)
        }
    }

    // MARK: - GET /broadcast/autostart

    func handleGetBroadcastAutoStart(clientFD: Int32) {
        let dto = broadcastAutoStartProvider()
        sendJSON(statusCode: 200, reason: "OK", encodable: dto, clientFD: clientFD)
    }

    // MARK: - POST /broadcast/autostart

    func handleSetBroadcastAutoStart(body: Data, clientFD: Int32) {
        struct Body: Decodable { let enabled: Bool }
        guard let decoded = try? JSONDecoder().decode(Body.self, from: body) else {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "invalid_json"], clientFD: clientFD)
            return
        }
        setBroadcastAutoStartProvider(decoded.enabled)
        sendJSON(statusCode: 200, reason: "OK",
                 encodable: BroadcastAutoStartDTO(enabled: decoded.enabled), clientFD: clientFD)
    }

    // MARK: - GET /broadcast/auth-prompt

    func handleGetAuthPrompt(clientFD: Int32) {
        let dto = authPromptProvider()
        sendJSON(statusCode: 200, reason: "OK", encodable: dto, clientFD: clientFD)
    }

    // MARK: - POST /broadcast/auth-prompt/dismiss

    func handleDismissAuthPrompt(clientFD: Int32) {
        dismissAuthPromptProvider()
        sendJSON(statusCode: 200, reason: "OK",
                 jsonObject: ["result": "dismissed"], clientFD: clientFD)
    }

    // MARK: - POST /broadcast/start

    func handleStartBroadcast(clientFD: Int32) {
        startBroadcastProvider()
        sendJSON(statusCode: 200, reason: "OK",
                 jsonObject: ["result": "broadcast_start_requested"], clientFD: clientFD)
    }

    // MARK: - POST /broadcast/stop

    func handleStopBroadcast(clientFD: Int32) {
        stopBroadcastProvider()
        sendJSON(statusCode: 200, reason: "OK",
                 jsonObject: ["result": "broadcast_stop_requested"], clientFD: clientFD)
    }

    // MARK: - GET /broadcast/status

    func handleGetBroadcastStatus(clientFD: Int32) {
        let dto = broadcastStatusProvider()
        sendJSON(statusCode: 200, reason: "OK", encodable: dto, clientFD: clientFD)
    }

    // MARK: - POST /broadcast/restart

    func handleRestartBroadcast(clientFD: Int32) {
        restartBroadcastProvider()
        sendJSON(statusCode: 200, reason: "OK",
                 jsonObject: ["result": "broadcast_restart_requested"], clientFD: clientFD)
    }

    // MARK: - POST /broadcast/credentials

    func handleUpdateBroadcastCredentials(body: Data, clientFD: Int32) {
        guard !body.isEmpty else {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "missing_body"], clientFD: clientFD)
            return
        }

        do {
            let decoded = try JSONDecoder().decode(BroadcastCredentialsDTO.self, from: body)

            guard !decoded.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !decoded.password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !decoded.gamertag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                sendJSON(statusCode: 400, reason: "Bad Request",
                         jsonObject: ["error": "missing_fields"], clientFD: clientFD)
                return
            }

            let ok = updateBroadcastCredentialsProvider(decoded)
            if ok {
                sendJSON(statusCode: 200, reason: "OK",
                         jsonObject: ["result": "credentials_updated"], clientFD: clientFD)
            } else {
                sendJSON(statusCode: 500, reason: "Internal Server Error",
                         jsonObject: ["error": "update_failed"], clientFD: clientFD)
            }
        } catch {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "invalid_json"], clientFD: clientFD)
        }
    }
}

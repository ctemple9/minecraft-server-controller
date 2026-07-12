//
//  AppViewModel+APIWiringContent.swift
//  MSCmacOS
//
//  M1 (flowstate) slice 4: player-skin and server-file Remote API providers.
//  Extracted verbatim from AppViewModel.init (kept as local-let + by-reference
//  assignment, exactly as init did).
//

import Foundation
import AppKit

extension AppViewModel {

    /// Player skin lookup/override, hidden-profile toggling, server-file browse/read,
    /// and the "export for clients" bundle builder.
    func wireSkinAndFileProviders(into server: RemoteAPIServer) {
        let previewableFileExtensions: Set<String> = ["txt", "log", "yml", "yaml", "json", "properties", "sh", "cfg", "conf", "toml", "ini", "md"]

        let pngDataForImage: (NSImage) -> Data? = { image in
            guard let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
            return bitmap.representation(using: .png, properties: [:])
        }

        let activeConfigServer: () -> ConfigServer? = { [weak self] in
            guard let self else { return nil }
            let cfg = self.configManager.config
            return cfg.activeServerId.flatMap { id in cfg.servers.first(where: { $0.id == id }) }
        }

        let relativePathForURL: (_ url: URL, _ root: URL) -> String = { url, root in
            let rootPath = root.standardizedFileURL.path
            let path = url.standardizedFileURL.path
            guard path != rootPath else { return "" }
            let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
            guard path.hasPrefix(prefix) else { return "" }
            return String(path.dropFirst(prefix.count))
        }

        let resolvedServerFileURL: (_ relativePath: String?, _ cfg: ConfigServer) -> URL? = { relativePath, cfg in
            let root = URL(fileURLWithPath: cfg.serverDir, isDirectory: true)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            let trimmed = (relativePath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let candidate = trimmed.isEmpty
                ? root
                : root.appendingPathComponent(trimmed, isDirectory: false)
                    .standardizedFileURL
                    .resolvingSymlinksInPath()
            let rootPath = root.path
            let candidatePath = candidate.path
            guard candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/") else {
                return nil
            }
            return candidate
        }

        let clientStatusRawValue: (_ status: ClientSideStatus) -> String = { status in
            switch status {
            case .required: return "required"
            case .optional: return "optional"
            case .serverOnly: return "server_only"
            case .unknown: return "unknown"
            }
        }

        let playerSkinProvider: (String) async -> RemoteAPIServer.PlayerSkinResponseDTO = { [weak self] profileId in
            guard let self else { return RemoteAPIServer.PlayerSkinResponseDTO(success: false, message: "not_available") }
            let context = await MainActor.run { () -> (PlayerProfile, PlayerSkinOverride?, String, URL?)? in
                guard let cfg = activeConfigServer(),
                      let profile = self.playerProfiles.first(where: { $0.id == profileId }) else { return nil }
                let override = PlayerSkinStore.currentOverride(profileID: profile.id, serverDir: cfg.serverDir)
                let appearance = PlayerSkinStore.resolveAppearance(for: profile, serverDir: cfg.serverDir)
                return (profile, override, appearance.identifier, appearance.skinURL)
            }
            guard let (profile, override, identifier, skinURL) = context else {
                return RemoteAPIServer.PlayerSkinResponseDTO(success: false, message: "profile_not_found", profileId: profileId)
            }

            let image: NSImage?
            let source: String
            if let skinURL, let skinImg = NSImage(contentsOf: skinURL) {
                let face = PlayerSkinRenderer.extractFace(from: skinImg) ?? skinImg
                image = PlayerImageTrim.croppedToOpaqueBounds(face) ?? face
                source = "skin_file"
            } else if identifier.hasPrefix(".") {
                image = await BedrockSkinFetcher.fetchAvatar(gamertag: identifier, size: 128).flatMap {
                    PlayerImageTrim.croppedToOpaqueBounds($0) ?? $0
                }
                source = override?.lookupIdentifier?.isEmpty == false ? "lookup_override" : "bedrock_lookup"
            } else if let url = URL(string: "https://mc-heads.net/avatar/\(identifier)/128") {
                var req = URLRequest(url: url)
                req.setValue("MinecraftServerController/1.0", forHTTPHeaderField: "User-Agent")
                req.timeoutInterval = 10
                if let (data, resp) = try? await URLSession.shared.data(for: req),
                   (resp as? HTTPURLResponse)?.statusCode == 200,
                   let img = NSImage(data: data) {
                    image = PlayerImageTrim.croppedToOpaqueBounds(img) ?? img
                } else {
                    image = nil
                }
                source = override?.lookupIdentifier?.isEmpty == false ? "lookup_override" : "profile_lookup"
            } else {
                image = nil
                source = "invalid_lookup"
            }

            guard let image, let png = pngDataForImage(image) else {
                self.logAppMessage("[PlayerSkins] Remote skin render failed for \(profile.displayName).")
                return RemoteAPIServer.PlayerSkinResponseDTO(success: false, message: "skin_not_found", profileId: profile.id)
            }
            return RemoteAPIServer.PlayerSkinResponseDTO(
                success: true,
                message: "ok",
                profileId: profile.id,
                imageBase64: png.base64EncodedString(),
                imageMimeType: "image/png",
                lookupIdentifier: identifier,
                isOverride: override?.lookupIdentifier != nil || override?.skinFileName != nil,
                source: source
            )
        }

        let playerSkinOverrideProvider: (String, String?) async -> RemoteAPIServer.PlayerSkinOverrideResultDTO = { [weak self] profileId, lookupIdentifier in
            guard let self else {
                return RemoteAPIServer.PlayerSkinOverrideResultDTO(success: false, message: "not_available", profileId: profileId, lookupIdentifier: nil)
            }
            return await MainActor.run {
                guard activeConfigServer() != nil else {
                    return RemoteAPIServer.PlayerSkinOverrideResultDTO(success: false, message: "no_active_server", profileId: profileId, lookupIdentifier: nil)
                }
                guard let profile = self.playerProfiles.first(where: { $0.id == profileId }) else {
                    return RemoteAPIServer.PlayerSkinOverrideResultDTO(success: false, message: "profile_not_found", profileId: profileId, lookupIdentifier: nil)
                }
                let trimmed = lookupIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if trimmed.isEmpty {
                    self.clearPlayerSkinOverride(for: profile)
                    self.logAppMessage("[PlayerSkins] Remote cleared skin override for \(profile.displayName).")
                    return RemoteAPIServer.PlayerSkinOverrideResultDTO(success: true, message: "cleared", profileId: profile.id, lookupIdentifier: nil)
                } else {
                    self.setPlayerLookupOverride(trimmed, for: profile)
                    self.logAppMessage("[PlayerSkins] Remote set lookup override for \(profile.displayName) -> \(trimmed).")
                    return RemoteAPIServer.PlayerSkinOverrideResultDTO(success: true, message: "saved", profileId: profile.id, lookupIdentifier: trimmed)
                }
            }
        }

        let hiddenProfileProvider: (String, Bool) async -> RemoteAPIServer.HiddenProfileMutationResultDTO = { [weak self] profileId, hidden in
            guard let self else {
                return RemoteAPIServer.HiddenProfileMutationResultDTO(success: false, message: "not_available", profileId: profileId, isHidden: hidden)
            }
            return await MainActor.run {
                guard activeConfigServer() != nil else {
                    return RemoteAPIServer.HiddenProfileMutationResultDTO(success: false, message: "no_active_server", profileId: profileId, isHidden: nil)
                }
                guard let profile = self.playerProfiles.first(where: { $0.id == profileId }) else {
                    return RemoteAPIServer.HiddenProfileMutationResultDTO(success: false, message: "profile_not_found", profileId: profileId, isHidden: nil)
                }
                if hidden {
                    self.hideProfile(profile)
                } else {
                    self.unhideProfile(profile)
                }
                self.logAppMessage("[Players] Remote \(hidden ? "hid" : "unhid") profile \(profile.displayName).")
                return RemoteAPIServer.HiddenProfileMutationResultDTO(success: true, message: hidden ? "hidden" : "visible", profileId: profile.id, isHidden: hidden)
            }
        }

        let filesProvider: (String?) async -> RemoteAPIServer.ServerFilesResponseDTO = { path in
            let cfg = await MainActor.run { activeConfigServer() }
            guard let cfg else { return RemoteAPIServer.ServerFilesResponseDTO(note: "no_active_server") }
            return await Task.detached(priority: .userInitiated) {
                let fm = FileManager.default
                let root = URL(fileURLWithPath: cfg.serverDir, isDirectory: true)
                    .standardizedFileURL
                    .resolvingSymlinksInPath()
                guard let dir = resolvedServerFileURL(path, cfg) else {
                    return RemoteAPIServer.ServerFilesResponseDTO(serverName: cfg.displayName, note: "invalid_path")
                }
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
                    return RemoteAPIServer.ServerFilesResponseDTO(serverName: cfg.displayName, note: "directory_not_found")
                }
                let urls = (try? fm.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                )) ?? []
                let iso = ISO8601DateFormatter()
                let items: [RemoteAPIServer.ServerFileItemDTO] = urls.compactMap { url in
                    let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
                    let isDirectory = values?.isDirectory ?? false
                    let rel = relativePathForURL(url, root)
                    let ext = isDirectory ? nil : url.pathExtension.lowercased()
                    return RemoteAPIServer.ServerFileItemDTO(
                        id: rel.isEmpty ? url.lastPathComponent : rel,
                        name: url.lastPathComponent,
                        path: rel,
                        isDirectory: isDirectory,
                        sizeBytes: values?.fileSize.map { Int64($0) },
                        modifiedAt: values?.contentModificationDate.map { iso.string(from: $0) },
                        fileExtension: ext,
                        isPreviewable: ext.map { previewableFileExtensions.contains($0) } ?? false
                    )
                }
                .sorted {
                    if $0.isDirectory != $1.isDirectory { return $0.isDirectory && !$1.isDirectory }
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                let relPath = relativePathForURL(dir, root)
                let parent: String?
                if relPath.isEmpty {
                    parent = nil
                } else {
                    let parentURL = dir.deletingLastPathComponent()
                    parent = relativePathForURL(parentURL, root)
                }
                return RemoteAPIServer.ServerFilesResponseDTO(
                    serverName: cfg.displayName,
                    path: relPath,
                    parentPath: parent,
                    items: items
                )
            }.value
        }

        let fileReadProvider: (String) async -> RemoteAPIServer.ServerFileReadResponseDTO = { path in
            let cfg = await MainActor.run { activeConfigServer() }
            guard let cfg else { return RemoteAPIServer.ServerFileReadResponseDTO(success: false, message: "no_active_server") }
            return await Task.detached(priority: .userInitiated) {
                let fm = FileManager.default
                guard let url = resolvedServerFileURL(path, cfg) else {
                    return RemoteAPIServer.ServerFileReadResponseDTO(success: false, message: "invalid_path", path: path)
                }
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
                    return RemoteAPIServer.ServerFileReadResponseDTO(success: false, message: "file_not_found", path: path)
                }
                guard !isDir.boolValue else {
                    return RemoteAPIServer.ServerFileReadResponseDTO(success: false, message: "directory_not_file", path: path)
                }
                let ext = url.pathExtension.lowercased()
                guard previewableFileExtensions.contains(ext) else {
                    return RemoteAPIServer.ServerFileReadResponseDTO(success: false, message: "not_previewable", path: path, name: url.lastPathComponent)
                }
                let attrs = try? fm.attributesOfItem(atPath: url.path)
                let size = (attrs?[.size] as? NSNumber)?.int64Value
                let maxBytes = 512 * 1024
                // E2: surface a genuine read failure instead of masking it as an empty
                // preview. A previously-existing, previewable file that we can't read
                // (permissions, mid-write lock, IO error) is a real error, not "".
                let data: Data
                do {
                    data = try Data(contentsOf: url)
                } catch {
                    return RemoteAPIServer.ServerFileReadResponseDTO(success: false, message: "read_failed", path: path, name: url.lastPathComponent)
                }
                let truncated = data.count > maxBytes
                let slice = truncated ? data.prefix(maxBytes) : data[...]
                let content = String(data: Data(slice), encoding: .utf8)
                    ?? String(data: Data(slice), encoding: .isoLatin1)
                    ?? ""
                return RemoteAPIServer.ServerFileReadResponseDTO(
                    success: true,
                    message: "ok",
                    path: path,
                    name: url.lastPathComponent,
                    sizeBytes: size,
                    content: content,
                    encoding: "text",
                    truncated: truncated
                )
            }.value
        }

        let clientExportProvider: ([String]?) async -> RemoteAPIServer.ClientExportResponseDTO = { [weak self] selectedIds in
            guard let self else { return RemoteAPIServer.ClientExportResponseDTO(note: "not_available") }
            let cfg = await MainActor.run { activeConfigServer() }
            guard let cfg else { return RemoteAPIServer.ClientExportResponseDTO(note: "no_active_server") }
            guard cfg.isJava, cfg.javaFlavor.addOnKind != nil else {
                return RemoteAPIServer.ClientExportResponseDTO(serverName: cfg.displayName, serverType: cfg.serverType.rawValue, note: "java_addons_only")
            }
            var items = await MainActor.run { self.buildClientExportItems(for: cfg) }
            guard !items.isEmpty else {
                return RemoteAPIServer.ClientExportResponseDTO(serverName: cfg.displayName, serverType: cfg.serverType.rawValue, note: "empty")
            }
                if let selectedIds, !selectedIds.isEmpty {
                    let selected = Set(selectedIds)
                    for index in items.indices {
                        items[index].isSelected = selected.contains(items[index].id)
                    }
                }
                let isPaperLike = cfg.javaFlavor.addOnKind == .plugin
                let selected = items.filter(\.isSelected)
                let itemDTOs = items.map {
                    RemoteAPIServer.ClientExportItemDTO(
                        id: $0.id,
                        fileName: $0.fileName,
                        displayName: $0.displayName,
                        iconURL: $0.iconURL,
                        projectURL: $0.modrinthURL?.absoluteString,
                        clientStatus: clientStatusRawValue($0.clientStatus),
                        statusSource: $0.statusSource,
                        selectedByDefault: $0.clientStatus.isSelectedByDefault
                    )
                }
                guard !selected.isEmpty else {
                    return RemoteAPIServer.ClientExportResponseDTO(
                        serverName: cfg.displayName,
                        serverType: cfg.serverType.rawValue,
                        exportKind: isPaperLike ? "links" : "zip",
                        isPaperLike: isPaperLike,
                        items: itemDTOs,
                        selectedCount: 0,
                        note: "nothing_selected"
                    )
                }
                if isPaperLike {
                    let text = selected.map { item -> String in
                        let url = item.modrinthURL.map { $0.absoluteString } ?? "(no link)"
                        return "\(item.displayName): \(url)"
                    }.joined(separator: "\n")
                    return RemoteAPIServer.ClientExportResponseDTO(
                        serverName: cfg.displayName,
                        serverType: cfg.serverType.rawValue,
                        exportKind: "links",
                        isPaperLike: true,
                        items: itemDTOs,
                        selectedCount: selected.count,
                        shareText: text
                    )
                }

                let fm = FileManager.default
                let tmp = fm.temporaryDirectory.appendingPathComponent("msc-remote-client-export-\(UUID().uuidString)", isDirectory: true)
                let zipName = "\(cfg.displayName)-client-\(cfg.minecraftVersion ?? "mods").zip"
                    .replacingOccurrences(of: "/", with: "-")
                    .replacingOccurrences(of: ":", with: "")
                let zipURL = fm.temporaryDirectory.appendingPathComponent(zipName)
                do {
                    try? fm.removeItem(at: zipURL)
                    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
                    for item in selected {
                        let target = tmp.appendingPathComponent(item.fileName)
                        try? fm.copyItem(at: item.jarURL, to: target)
                    }
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                    process.arguments = ["-j", zipURL.path] + selected.map { tmp.appendingPathComponent($0.fileName).path }
                    try process.run()
                    process.waitUntilExit()
                    try? fm.removeItem(at: tmp)
                    guard process.terminationStatus == 0,
                          let data = try? Data(contentsOf: zipURL) else {
                        return RemoteAPIServer.ClientExportResponseDTO(serverName: cfg.displayName, serverType: cfg.serverType.rawValue, items: itemDTOs, selectedCount: selected.count, note: "zip_failed")
                    }
                    try? fm.removeItem(at: zipURL)
                    return RemoteAPIServer.ClientExportResponseDTO(
                        serverName: cfg.displayName,
                        serverType: cfg.serverType.rawValue,
                        exportKind: "zip",
                        isPaperLike: false,
                        items: itemDTOs,
                        selectedCount: selected.count,
                        zipFileName: zipName,
                        zipBase64: data.base64EncodedString()
                    )
            } catch {
                try? fm.removeItem(at: tmp)
                try? fm.removeItem(at: zipURL)
                return RemoteAPIServer.ClientExportResponseDTO(serverName: cfg.displayName, serverType: cfg.serverType.rawValue, items: itemDTOs, selectedCount: selected.count, note: "zip_failed: \(error.localizedDescription)")
            }
        }
        server.playerSkinProvider = playerSkinProvider
        server.playerSkinOverrideProvider = playerSkinOverrideProvider
        server.hiddenProfileProvider = hiddenProfileProvider
        server.filesProvider = filesProvider
        server.fileReadProvider = fileReadProvider
        server.clientExportProvider = clientExportProvider
    }
}

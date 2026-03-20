//  AppViewModel+ComponentVersions.swift
//  MinecraftServerController
//
//  Details -> Components tab support.
//  All pre-existing Java logic is unchanged.

import Foundation
import AppKit

extension AppViewModel {

    // MARK: - Public API used by DetailsView

    /// Refresh local + template versions for the selected server.
    /// - Parameter clearOnline: if true, clears any previously fetched online versions.
    func refreshComponentsSnapshotLocalAndTemplate(clearOnline: Bool) {
        guard let cfg = selectedServerConfig else {
            if clearOnline {
                componentsSnapshot = ComponentsVersionSnapshot()
                componentsOnlineErrorMessage = nil
            }
            return
        }

        var snapshot = componentsSnapshot

        // Local
        snapshot.paper.local = localPaperVersionString(for: cfg)
        snapshot.geyser.local = localPluginBuildString(for: cfg, matching: "geyser")
        snapshot.floodgate.local = localPluginBuildString(for: cfg, matching: "floodgate")
        snapshot.broadcast.local = localBroadcastVersionString()
        snapshot.bedrockConnect.local = localBedrockConnectVersionString()

        // Template versions (no longer derived from stacks)
        snapshot.paper.template = nil
        snapshot.geyser.template = nil
        snapshot.floodgate.template = nil

        if clearOnline {
            snapshot.paper.online = nil
            snapshot.geyser.online = nil
            snapshot.floodgate.online = nil
            snapshot.broadcast.online = nil
            snapshot.bedrockConnect.online = nil
            componentsOnlineErrorMessage = nil
        }

        componentsSnapshot = snapshot
    }

    /// Explicit online version check for Java components (no background polling).
    func checkComponentsOnline() {
        guard !isCheckingComponentsOnline else { return }

        isCheckingComponentsOnline = true
        componentsOnlineErrorMessage = nil

        Task.detached { [weak self] in
            guard let self else { return }

            do {
                async let paperMeta = PaperDownloader.fetchLatestMetadata()
                async let geyserMeta = PluginDownloader.fetchLatestGeyserBuildInfo()
                async let floodgateMeta = PluginDownloader.fetchLatestFloodgateBuildInfo()
                async let broadcastTag = GitHubReleaseChecker.fetchLatestReleaseTag(owner: "MCXboxBroadcast", repo: "Broadcaster")
                async let bedrockConnectTag = GitHubReleaseChecker.fetchLatestReleaseTag(owner: "Pugmatt", repo: "BedrockConnect")

                let (p, g, f, b, bc) = try await (paperMeta, geyserMeta, floodgateMeta, broadcastTag, bedrockConnectTag)

                await MainActor.run {
                    var snapshot = self.componentsSnapshot

                    snapshot.paper.online = "\(p.version) (build \(p.build))"
                    snapshot.geyser.online = "\(g.version) (build \(g.build))"
                    snapshot.floodgate.online = "\(f.version) (build \(f.build))"
                    snapshot.broadcast.online = b
                    snapshot.bedrockConnect.online = bc

                    self.componentsSnapshot = snapshot
                    self.isCheckingComponentsOnline = false
                }
            } catch {
                await MainActor.run {
                    self.componentsOnlineErrorMessage = error.localizedDescription
                    self.isCheckingComponentsOnline = false
                }
            }
        }
    }

    /// Reveals a file/folder in Finder.
    func revealInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Local version detection

    private var selectedServerConfig: ConfigServer? {
        guard let server = selectedServer else { return nil }
        return configManager.config.servers.first(where: { $0.id == server.id })
    }

    private func localPaperVersionString(for cfg: ConfigServer) -> String? {
        guard let jarURL = effectivePaperJarURL(for: cfg) else { return nil }

        // 1) Sidecar metadata (preferred)
        let serverDirURL = URL(fileURLWithPath: cfg.serverDir, isDirectory: true)
        if let sidecar = PaperVersionSidecarManager.read(fromServerDirectory: serverDirURL) {
            return "\(sidecar.mcVersion) (build \(sidecar.build))"
        }

        // 2) Filename parsing (rare: jar filename includes version/build)
        if let parsed = ComponentVersionParsing.parsePaperJarFilename(jarURL.lastPathComponent) {
            return parsed.displayString
        }

        // 3) Fallback: show the jar name (commonly "paper.jar")
        return jarURL.lastPathComponent
    }

    private func localPluginBuildString(for cfg: ConfigServer, matching keyword: String) -> String? {
        guard let jarURL = localPluginJarURL(for: cfg, matching: keyword) else { return nil }
        let build = ComponentVersionParsing.parseTrailingBuildNumber(fromJarFilename: jarURL.lastPathComponent)
        return ComponentVersionParsing.buildDisplayString(build) ?? jarURL.lastPathComponent
    }

    private func localPluginJarURL(for cfg: ConfigServer, matching keyword: String) -> URL? {
        let fm = FileManager.default
        let serverDirURL = URL(fileURLWithPath: cfg.serverDir, isDirectory: true)
        let pluginsDir = serverDirURL.appendingPathComponent("plugins", isDirectory: true)

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: pluginsDir.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }

        do {
            let contents = try fm.contentsOfDirectory(at: pluginsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            return contents.first(where: { url in
                url.pathExtension.lowercased() == "jar" && url.lastPathComponent.lowercased().contains(keyword.lowercased())
            })
        } catch {
            logAppMessage("[Components] Failed to inspect plugins for \(keyword): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Broadcast local version tracking

    private var xboxBroadcastVersionFileURL: URL {
        configManager.appDirectoryURL
            .appendingPathComponent("MCXboxBroadcastStandalone.version.txt", isDirectory: false)
    }

    private func localBroadcastVersionString() -> String? {
        guard let path = configManager.config.xboxBroadcastJarPath,
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        let filename = URL(fileURLWithPath: path).lastPathComponent

        // Primary: parse version from filename.
        // Current download format: "MCXboxBroadcastStandalone-v3.0.2.jar"
        let base = filename.replacingOccurrences(of: ".jar", with: "", options: .caseInsensitive)
        let prefix = "MCXboxBroadcastStandalone-"
        if base.hasPrefix(prefix) {
            let version = String(base.dropFirst(prefix.count))
            if !version.isEmpty { return version }
        }

        // Secondary: legacy sidecar file written by older download code.
        let fm = FileManager.default
        if fm.fileExists(atPath: xboxBroadcastVersionFileURL.path),
           let data = try? Data(contentsOf: xboxBroadcastVersionFileURL),
           let s = String(data: data, encoding: .utf8) {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        return "Installed (version unknown)"
    }

    // MARK: - Bedrock Connect local version tracking

    private func localBedrockConnectVersionString() -> String? {
        guard let path = configManager.config.bedrockConnectJarPath,
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        let filename = URL(fileURLWithPath: path).lastPathComponent

        // Expected format: "BedrockConnect-1.62.jar"
        let base = filename.replacingOccurrences(of: ".jar", with: "", options: .caseInsensitive)
        let prefix = "BedrockConnect-"
        if base.hasPrefix(prefix) {
            let version = String(base.dropFirst(prefix.count))
            if !version.isEmpty { return version }
        }

        return "Installed (version unknown)"
    }

    // MARK: - Bedrock version management

    /// Populate bedrockAvailableVersions from the network (or static fallback).
    /// Safe to call multiple times — no-ops if already loaded or currently loading.
    func fetchBedrockVersionsIfNeeded() {
        guard bedrockAvailableVersions.isEmpty, !isFetchingBedrockVersions else { return }
        isFetchingBedrockVersions = true
        bedrockVersionFetchError = nil

        Task.detached { [weak self] in
            guard let self else { return }
            // fetchVersions() never throws — returns static fallback on any error.
            let versions = await BedrockVersionFetcher.fetchVersions()
            await MainActor.run {
                self.bedrockAvailableVersions = versions
                self.isFetchingBedrockVersions = false
            }
        }
    }

    /// Persist the chosen BDS version into the selected server's config.
    /// Passing "LATEST" (or empty string) clears the pin, meaning the image
    /// always pulls the newest version on next start.
    func setBedrockVersion(_ version: String) {
        guard let server = selectedServer,
              let idx = configManager.config.servers.firstIndex(where: { $0.id == server.id })
        else { return }

        let normalized = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let pinned: String? = (normalized.isEmpty || normalized == "LATEST") ? nil : normalized
        configManager.config.servers[idx].bedrockVersion = pinned
                configManager.save()
        logAppMessage("[Bedrock] Version pinned to: \(pinned ?? "LATEST (auto)")")
    }

    /// Pulls the selected Bedrock Docker image from the app.
    /// Safe to call from either the Overview health card or the Components tab.
    /// The server must be stopped before calling this.
    func updateBedrockImageAndRestart() {
        if isServerRunning {
            logAppMessage("[Bedrock] Stop the server before pulling the Bedrock image.")
            return
        }
        if isUpdatingBedrockImage {
            logAppMessage("[Bedrock] Image pull already in progress.")
            return
        }
        guard let cfg = selectedServerConfig, cfg.isBedrock else {
            logAppMessage("[Bedrock] Select a Bedrock server first.")
            return
        }

        isUpdatingBedrockImage = true
        let imageName = cfg.bedrockDockerImage ?? "itzg/minecraft-bedrock-server"

        Task.detached { [weak self] in
            guard let self else { return }

            await MainActor.run {
                self.logAppMessage("[Bedrock] Pulling latest image: \(imageName)...")
            }

            let dockerPath = await MainActor.run { DockerUtility.dockerPath() }
            guard let dockerPath else {
                await MainActor.run {
                    self.isUpdatingBedrockImage = false
                    self.logAppMessage("[Bedrock] Image pull failed: Docker is not installed.")
                }
                return
            }

            let dockerAvailable = await MainActor.run { DockerUtility.ensureDockerAvailable(autoLaunch: true) }
            if !dockerAvailable {
                await MainActor.run {
                    self.isUpdatingBedrockImage = false
                    self.logAppMessage("[Bedrock] Image pull failed: Docker Desktop is not running.")
                }
                return
            }

            let result = await MainActor.run {
                DockerUtility.pullImage(imageName, dockerPath: dockerPath) { line in
                Task { @MainActor in
                    self.logAppMessage("[Docker] \(line)")
                }
                }
            }

            await MainActor.run {
                self.isUpdatingBedrockImage = false

                guard let result else {
                    self.logAppMessage("[Bedrock] Image pull failed: could not launch docker pull.")
                    self.refreshHealthCardsForSelectedServer()
                    return
                }

                if result.exitCode == 0 || DockerUtility.isImagePresent(imageName, dockerPath: dockerPath) {
                    self.logAppMessage("[Bedrock] Image pull complete.")
                } else {
                    let msg = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.logAppMessage("[Bedrock] Image pull failed: \(msg.isEmpty ? "docker pull failed (exit \(result.exitCode))" : msg)")
                }

                self.refreshHealthCardsForSelectedServer()
            }
        }
    }

}


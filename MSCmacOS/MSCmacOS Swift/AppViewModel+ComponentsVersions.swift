//  AppViewModel+ComponentVersions.swift
//  MinecraftServerController
//
//  Details -> Components tab support.

import Foundation
import AppKit

extension AppViewModel {

    // MARK: - Public API used by DetailsView

    /// Refresh local + template versions for the selected server.
    /// - Parameter clearOnline: if true, also clears online versions, the available
    ///   Paper version list, and the user's current selection.
    func refreshComponentsSnapshotLocalAndTemplate(clearOnline: Bool) {
        guard let cfg = selectedServerConfig else {
            if clearOnline {
                componentsSnapshot = ComponentsVersionSnapshot()
                componentsOnlineErrorMessage = nil
                availablePaperVersions = []
                selectedPaperVersionOption = nil
            }
            return
        }

        var snapshot = componentsSnapshot

        snapshot.paper.local      = localPaperVersionString(for: cfg)
        snapshot.geyser.local     = localPluginBuildString(for: cfg, matching: "geyser")
        snapshot.floodgate.local  = localPluginBuildString(for: cfg, matching: "floodgate")
        snapshot.broadcast.local  = localBroadcastVersionString()
        snapshot.bedrockConnect.local = localBedrockConnectVersionString()

        snapshot.paper.template    = nil
        snapshot.geyser.template   = nil
        snapshot.floodgate.template = nil

        if clearOnline {
            snapshot.paper.online        = nil
            snapshot.geyser.online       = nil
            snapshot.floodgate.online    = nil
            snapshot.broadcast.online    = nil
            snapshot.bedrockConnect.online = nil
            componentsOnlineErrorMessage = nil
            availablePaperVersions       = []
            selectedPaperVersionOption   = nil
        }

        componentsSnapshot = snapshot
    }

    /// Full online check: Paper version list + Geyser, Floodgate, Broadcast,
    /// and BedrockConnect. All fetches run concurrently.
    func checkComponentsOnline() {
        guard !isCheckingComponentsOnline else { return }

        isCheckingComponentsOnline = true
        componentsOnlineErrorMessage = nil

        Task.detached { [weak self] in
            guard let self else { return }

            let includeExp = await MainActor.run { self.includeExperimentalPaperBuilds }

            do {
                async let paperVersions = PaperDownloader.fetchAvailableVersions(
                    includeExperimental: includeExp, limit: 5
                )
                async let geyserMeta      = PluginDownloader.fetchLatestGeyserBuildInfo()
                async let floodgateMeta   = PluginDownloader.fetchLatestFloodgateBuildInfo()
                async let broadcastTag    = GitHubReleaseChecker.fetchLatestReleaseTag(
                    owner: "MCXboxBroadcast", repo: "Broadcaster"
                )
                async let bedrockConnectTag = GitHubReleaseChecker.fetchLatestReleaseTag(
                    owner: "Pugmatt", repo: "BedrockConnect"
                )

                let (versions, g, f, b, bc) = try await (
                    paperVersions, geyserMeta, floodgateMeta, broadcastTag, bedrockConnectTag
                )

                await MainActor.run {
                    var snapshot = self.componentsSnapshot
                    snapshot.paper.online       = versions.first?.displayString
                    snapshot.geyser.online      = "\(g.version) (build \(g.build))"
                    snapshot.floodgate.online   = "\(f.version) (build \(f.build))"
                    snapshot.broadcast.online   = b
                    snapshot.bedrockConnect.online = bc
                    self.componentsSnapshot     = snapshot
                    self.availablePaperVersions = versions
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

    /// Paper-only online check. Called automatically when the user switches tracks
    /// (Stable vs Experimental) so the version list refreshes without re-checking
    /// Geyser, Floodgate, Broadcast, or BedrockConnect.
    func checkPaperVersionsOnline() {
        guard !isCheckingComponentsOnline else { return }

        isCheckingComponentsOnline = true
        componentsOnlineErrorMessage = nil

        Task.detached { [weak self] in
            guard let self else { return }

            let includeExp = await MainActor.run { self.includeExperimentalPaperBuilds }

            do {
                let versions = try await PaperDownloader.fetchAvailableVersions(
                    includeExperimental: includeExp, limit: 5
                )
                await MainActor.run {
                    var snapshot = self.componentsSnapshot
                    snapshot.paper.online = versions.first?.displayString
                    self.componentsSnapshot = snapshot
                    self.availablePaperVersions = versions
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

    /// Switches between the Stable and Experimental Paper tracks.
    /// Clears the current version list and selection, then re-fetches automatically.
    /// No-ops if the track is not actually changing.
    func switchPaperTrack(includeExperimental: Bool) {
        guard includeExperimentalPaperBuilds != includeExperimental else { return }
        includeExperimentalPaperBuilds = includeExperimental
        selectedPaperVersionOption = nil
        availablePaperVersions = []
        checkPaperVersionsOnline()
    }

    /// Downloads the user's selected Paper version directly to the active server's
    /// Paper JAR location and writes the version sidecar so the local version display
    /// updates immediately.
    ///
    /// Requires the server to be stopped. Reuses `isDownloadingAndApplyingPaper` so
    /// the UI disabled state works without an additional flag.
    func downloadAndApplySelectedPaperVersion() {
        guard !isDownloadingAndApplyingPaper else { return }
        guard let option = selectedPaperVersionOption,
              let cfg = selectedServerConfig else { return }

        isDownloadingAndApplyingPaper = true

        Task.detached { [weak self] in
            guard let self else { return }

            let serverDir = URL(fileURLWithPath: cfg.serverDir, isDirectory: true)
            let trimmed   = cfg.paperJarPath.trimmingCharacters(in: .whitespacesAndNewlines)
            let destURL   = trimmed.isEmpty
                ? serverDir.appendingPathComponent("paper.jar")
                : URL(fileURLWithPath: trimmed)

            do {
                try FileManager.default.createDirectory(
                    at: destURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
            } catch {
                await MainActor.run {
                    self.logAppMessage("[Paper] Failed to create destination directory: \(error.localizedDescription)")
                    self.isDownloadingAndApplyingPaper = false
                }
                return
            }

            await MainActor.run {
                self.logAppMessage("[Paper] Downloading Paper \(option.version) build \(option.build)...")
            }

            do {
                let result = try await PaperDownloader.downloadPaper(option: option, to: destURL)

                await MainActor.run {
                    PaperVersionSidecarManager.write(
                        mcVersion: result.version,
                        build: result.build,
                        toServerDirectory: serverDir
                    )
                    self.logAppMessage("[Paper] Applied Paper \(result.version) build \(result.build).")
                    self.selectedPaperVersionOption = nil
                    self.isDownloadingAndApplyingPaper = false
                    self.refreshComponentsSnapshotLocalAndTemplate(clearOnline: false)
                }
            } catch {
                await MainActor.run {
                    self.logAppMessage("[Paper] Download failed: \(error.localizedDescription)")
                    self.isDownloadingAndApplyingPaper = false
                }
            }
        }
    }

    /// Reveals a file or folder in Finder.
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

        let serverDirURL = URL(fileURLWithPath: cfg.serverDir, isDirectory: true)
        if let sidecar = PaperVersionSidecarManager.read(fromServerDirectory: serverDirURL) {
            return "\(sidecar.mcVersion) (build \(sidecar.build))"
        }

        if let parsed = ComponentVersionParsing.parsePaperJarFilename(jarURL.lastPathComponent) {
            return parsed.displayString
        }

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
        let pluginsDir   = serverDirURL.appendingPathComponent("plugins", isDirectory: true)

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: pluginsDir.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }

        do {
            let contents = try fm.contentsOfDirectory(
                at: pluginsDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            return contents.first(where: { url in
                url.pathExtension.lowercased() == "jar" &&
                url.lastPathComponent.lowercased().contains(keyword.lowercased())
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
              FileManager.default.fileExists(atPath: path) else { return nil }

        let filename = URL(fileURLWithPath: path).lastPathComponent
        let base     = filename.replacingOccurrences(of: ".jar", with: "", options: .caseInsensitive)
        let prefix   = "MCXboxBroadcastStandalone-"
        if base.hasPrefix(prefix) {
            let version = String(base.dropFirst(prefix.count))
            if !version.isEmpty { return version }
        }

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
              FileManager.default.fileExists(atPath: path) else { return nil }

        let filename = URL(fileURLWithPath: path).lastPathComponent
        let base     = filename.replacingOccurrences(of: ".jar", with: "", options: .caseInsensitive)
        let prefix   = "BedrockConnect-"
        if base.hasPrefix(prefix) {
            let version = String(base.dropFirst(prefix.count))
            if !version.isEmpty { return version }
        }

        return "Installed (version unknown)"
    }

    // MARK: - Bedrock version management

    func fetchBedrockVersionsIfNeeded() {
        guard bedrockAvailableVersions.isEmpty, !isFetchingBedrockVersions else { return }
        isFetchingBedrockVersions = true
        bedrockVersionFetchError  = nil

        Task.detached { [weak self] in
            guard let self else { return }
            let versions = await BedrockVersionFetcher.fetchVersions()
            await MainActor.run {
                self.bedrockAvailableVersions  = versions
                self.isFetchingBedrockVersions = false
            }
        }
    }

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

            let dockerAvailable = await MainActor.run {
                DockerUtility.ensureDockerAvailable(autoLaunch: true)
            }
            if !dockerAvailable {
                await MainActor.run {
                    self.isUpdatingBedrockImage = false
                    self.logAppMessage("[Bedrock] Image pull failed: Docker Desktop is not running.")
                }
                return
            }

            let result = await MainActor.run {
                DockerUtility.pullImage(imageName, dockerPath: dockerPath) { line in
                    Task { @MainActor in self.logAppMessage("[Docker] \(line)") }
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
                    self.logAppMessage(
                        "[Bedrock] Image pull failed: \(msg.isEmpty ? "docker pull failed (exit \(result.exitCode))" : msg)"
                    )
                }

                self.refreshHealthCardsForSelectedServer()
            }
        }
    }
}

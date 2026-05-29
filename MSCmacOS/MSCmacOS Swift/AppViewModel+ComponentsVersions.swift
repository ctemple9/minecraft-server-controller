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

        snapshot.paper.template    = nil
        snapshot.geyser.template   = nil
        snapshot.floodgate.template = nil

        if clearOnline {
            snapshot.paper.online        = nil
            snapshot.geyser.online       = nil
            snapshot.floodgate.online    = nil
            snapshot.broadcast.online    = nil
            componentsOnlineErrorMessage = nil
            availablePaperVersions       = []
            selectedPaperVersionOption   = nil
        }

        componentsSnapshot = snapshot
        refreshDiscoveredPlugins()
    }

    /// Full online check: Paper version list + Geyser, Floodgate, Broadcast,
    /// and all user-sourced plugins. All fetches run concurrently.
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

                let (versions, g, f, b) = try await (
                    paperVersions, geyserMeta, floodgateMeta, broadcastTag
                )

                await MainActor.run {
                    var snapshot = self.componentsSnapshot
                    snapshot.paper.online       = versions.first?.displayString
                    snapshot.geyser.online      = "\(g.version) (build \(g.build))"
                    snapshot.floodgate.online   = "\(f.version) (build \(f.build))"
                    snapshot.broadcast.online   = b
                    self.componentsSnapshot     = snapshot
                    self.availablePaperVersions = versions

                    // Mirror geyser/floodgate online data into discoveredPlugins entries
                    self.updateManagedPluginOnlineVersions(
                        geyserOnline: "\(g.version) (build \(g.build))",
                        floodgateOnline: "\(f.version) (build \(f.build))"
                    )
                }
            } catch {
                await MainActor.run {
                    self.componentsOnlineErrorMessage = error.localizedDescription
                }
            }

            // Check user-sourced plugins — don't let failures here block the overall check
            await self.checkUserSourcedPluginsOnline()

            await MainActor.run {
                self.isCheckingComponentsOnline = false
            }
        }
    }

    // MARK: - Plugin discovery

    /// Scans the selected server's plugins folder and rebuilds `discoveredPlugins`.
    /// Merges source configs from config and preserves any already-fetched online data.
    func refreshDiscoveredPlugins() {
        guard let cfg = selectedServerConfig else {
            discoveredPlugins = []
            return
        }

        let serverDirURL = URL(fileURLWithPath: cfg.serverDir, isDirectory: true)
        let pluginsDir   = serverDirURL.appendingPathComponent("plugins", isDirectory: true)
        let fm           = FileManager.default

        // Collect all .jar and .jar.disabled files
        var jarURLs: [URL] = []
        if let contents = try? fm.contentsOfDirectory(
            at: pluginsDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            jarURLs = contents.filter { url in
                let name = url.lastPathComponent.lowercased()
                return name.hasSuffix(".jar") || name.hasSuffix(".jar.disabled")
            }
        }

        let sources = cfg.pluginSources ?? [:]
        let existing = discoveredPlugins  // preserve online data already fetched

        var entries: [PluginEntry] = jarURLs.map { url in
            let filename  = url.lastPathComponent
            let isEnabled = !filename.lowercased().hasSuffix(".jar.disabled")
            let jarStem   = isEnabled
                ? (url.deletingPathExtension().lastPathComponent)
                : String(filename.dropLast(".jar.disabled".count))

            let displayName   = PluginNameParser.extractDisplayName(from: jarStem)
            let parsedVersion = PluginNameParser.extractVersion(from: jarStem)

            // Determine tier
            let isGeyser     = jarStem.lowercased().contains("geyser")
            let isFloodgate  = jarStem.lowercased().contains("floodgate")

            let tier: PluginTier
            if isGeyser || isFloodgate {
                tier = .managed
            } else if findSource(for: jarStem, in: sources) != nil {
                tier = .userSourced
            } else {
                tier = .unmanaged
            }

            let sourceConfig = findSource(for: jarStem, in: sources)

            // Preserve previously fetched online data for this stem
            let prior = existing.first(where: { $0.jarStem == jarStem })

            var entry = PluginEntry(
                filename:      filename,
                jarStem:       jarStem,
                displayName:   displayName,
                isEnabled:     isEnabled,
                parsedVersion: parsedVersion,
                tier:          tier,
                sourceConfig:  sourceConfig,
                onlineVersion:     prior?.onlineVersion,
                onlineDownloadURL: prior?.onlineDownloadURL
            )

            // Populate local/template from snapshot for managed plugins
            if isGeyser {
                entry.localVersion    = componentsSnapshot.geyser.local
                entry.templateVersion = componentsSnapshot.geyser.template
            } else if isFloodgate {
                entry.localVersion    = componentsSnapshot.floodgate.local
                entry.templateVersion = componentsSnapshot.floodgate.template
            }

            return entry
        }

        // Sort: managed → userSourced → unmanaged; within tier alpha by displayName
        // Managed: Geyser before Floodgate by convention
        entries.sort { a, b in
            if a.tier != b.tier { return a.tier < b.tier }
            if a.tier == .managed {
                let aG = a.jarStem.lowercased().contains("geyser")
                let bG = b.jarStem.lowercased().contains("geyser")
                if aG != bG { return aG }
            }
            return a.displayName.lowercased() < b.displayName.lowercased()
        }

        discoveredPlugins = entries
    }

    /// Finds the source config for a jarStem: exact match first, then prefix match.
    private func findSource(for jarStem: String, in sources: [String: PluginSourceConfig]) -> PluginSourceConfig? {
        if let exact = sources[jarStem] { return exact }
        // Prefix match: source key is a prefix of the current stem (or vice-versa)
        let lower = jarStem.lowercased()
        for (key, config) in sources {
            let kl = key.lowercased()
            if lower.hasPrefix(kl) || kl.hasPrefix(lower) { return config }
        }
        return nil
    }

    /// Mirrors updated Geyser/Floodgate online versions into the discoveredPlugins array.
    private func updateManagedPluginOnlineVersions(geyserOnline: String, floodgateOnline: String) {
        discoveredPlugins = discoveredPlugins.map { entry in
            var e = entry
            if entry.tier == .managed {
                if entry.jarStem.lowercased().contains("geyser") {
                    e.onlineVersion = geyserOnline
                } else if entry.jarStem.lowercased().contains("floodgate") {
                    e.onlineVersion = floodgateOnline
                }
            }
            return e
        }
    }

    // MARK: - User-sourced plugin online checks

    /// Checks all user-sourced plugins for updates concurrently.
    func checkUserSourcedPluginsOnline() async {
        let plugins = await MainActor.run { discoveredPlugins.filter { $0.tier == .userSourced } }
        let mcVersion = await MainActor.run { currentMCVersion() } ?? "1.21"

        await withTaskGroup(of: (String, String?, URL?)?.self) { group in
            for plugin in plugins {
                guard let source = plugin.sourceConfig else { continue }
                group.addTask {
                    do {
                        let (version, url) = try await self.fetchOnlineVersion(
                            for: source, mcVersion: mcVersion
                        )
                        return (plugin.jarStem, version, url)
                    } catch {
                        return nil
                    }
                }
            }

            for await result in group {
                guard let (stem, version, url) = result else { continue }
                await MainActor.run {
                    self.discoveredPlugins = self.discoveredPlugins.map { entry in
                        guard entry.jarStem == stem else { return entry }
                        var e = entry
                        e.onlineVersion = version
                        e.onlineDownloadURL = url
                        return e
                    }
                }
            }
        }
    }

    /// Fetches the online version and download URL for a single source config.
    func fetchOnlineVersion(
        for source: PluginSourceConfig,
        mcVersion: String
    ) async throws -> (String, URL) {
        switch source.type {
        case .github:
            guard let (owner, repo) = PluginSourceDetector.parseGitHub(url: source.url) else {
                throw NSError(domain: "PluginSource", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Could not parse GitHub URL."])
            }
            let (tag, jarURL) = try await GitHubReleaseChecker.fetchLatestRelease(owner: owner, repo: repo)
            guard let url = jarURL else {
                throw NSError(domain: "PluginSource", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "No JAR asset found in GitHub release."])
            }
            return (tag, url)

        case .modrinth:
            guard let slug = PluginSourceDetector.parseModrinth(url: source.url) else {
                throw NSError(domain: "PluginSource", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Could not parse Modrinth URL."])
            }
            return try await ModrinthAPI.fetchLatest(slug: slug, mcVersion: mcVersion)

        case .hangar:
            guard let (author, slug) = PluginSourceDetector.parseHangar(url: source.url) else {
                throw NSError(domain: "PluginSource", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Could not parse Hangar URL."])
            }
            return try await HangarAPI.fetchLatest(author: author, slug: slug, mcVersion: mcVersion)

        case .direct:
            guard let url = URL(string: source.url) else {
                throw NSError(domain: "PluginSource", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Invalid direct download URL."])
            }
            // Direct URL: no version to display, but we can still download
            return ("(direct)", url)
        }
    }

    // MARK: - Helpers

    private func currentMCVersion() -> String? {
        componentsSnapshot.paper.local?.split(separator: " ").first.map(String.init)
    }

    /// Paper-only online check. Called automatically when the user switches tracks
    /// (Stable vs Experimental) so the version list refreshes without re-checking
    /// Geyser, Floodgate, or Broadcast.
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

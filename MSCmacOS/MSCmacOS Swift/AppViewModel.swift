//
//  AppViewModel.swift
//  MinecraftServerController
//

import Foundation
import Combine
import SwiftUI
import AppKit   // Finder tools (NSWorkspace)

// MARK: - Shared models moved to AppViewModelModels.swift

// MARK: - View model

/// Central observable object that coordinates server selection, process lifecycle, console output,
/// and persistent configuration for the app.
@MainActor
final class AppViewModel: ObservableObject {

    // MARK: - Extracted sub-managers

    /// Owns all console state, filtering logic, and structured line parsing.
    let console = ConsoleManager()

    /// Owns the metrics timer, server-readiness flags, and per-run Initiate state.
    let lifecycle = ServerLifecycleManager()

    /// Holds Combine subscriptions.
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Broadcast auth UI

    @Published var pendingBroadcastAuthPrompt: BroadcastAuthPrompt?
    @Published var firstStartNotice: FirstStartNotice?
    @Published var errorAlert: AppError?

    // MARK: - Components tab state

    @Published var discoveredPlugins: [PluginEntry] = []
    @Published var downloadingPlugins: Set<String> = []   // jarStem keys

    @Published var componentsSnapshot: ComponentsVersionSnapshot = ComponentsVersionSnapshot()
    @Published var isCheckingComponentsOnline: Bool = false
        @Published var componentsOnlineErrorMessage: String? = nil
        @Published var isDownloadingAndApplyingPaper: Bool = false
        @Published var isDownloadingAndApplyingGeyser: Bool = false
        @Published var isDownloadingAndApplyingFloodgate: Bool = false
    @Published var includeExperimentalPaperBuilds: Bool = false
    @Published var availablePaperVersions: [PaperVersionOption] = []
    @Published var selectedPaperVersionOption: PaperVersionOption? = nil
    @Published var bedrockAvailableVersions: [BedrockVersionEntry] = []
    @Published var isFetchingBedrockVersions: Bool = false
    @Published var bedrockVersionFetchError: String? = nil
    @Published var isUpdatingBedrockImage: Bool = false

    // MARK: - Published UI state

    @Published var servers: [Server] = []
    @Published var manageServersShouldAutoEditSelectedOnSettingsTab: Bool = false
    @Published var resolvedAccentColor: Color = Color(red: 30/255, green: 30/255, blue: 30/255)

    @Published var selectedServer: Server? {
        didSet {
            guard let server = selectedServer else { return }
            if OnboardingManager.shared.isActive,
               OnboardingManager.shared.currentStep == .createButton {
                let isBedrock = configServer(for: server)?.isBedrock ?? false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    OnboardingManager.shared.jumpTo(.dismissManage)
                }
                if isBedrock {
                    OnboardingManager.shared.tourServerType = .bedrock
                }
            }

            configManager.config.activeServerId = server.id
            configManager.save()
            logAppMessage("[App] Selected server: \(server.name)")

            loadBackupsForSelectedServer()
            loadWorldSlotsForSelectedServer()

            onlinePlayers = []
            playerSessionHistory.removeAll()
            latestTps1m = nil
            latestTps5m = nil
            latestTps15m = nil
            tpsHistory1m.removeAll()
            playerCountHistory.removeAll()
            clearBedrockPerformanceMetrics()

            serverStartTime = Date()
            updateUptimeDisplay()

            refreshWorldSize()
            loadBedrockAllowlistIfNeeded()
            syncTourAccentColor()
            loadResourcePacksForSelectedServer()
            loadSessionLogForSelectedServer()
            loadPlayerProfilesForSelectedServer()

            refreshEULAState()
            loadGeyserConfig()
            loadServerSettings()

            refreshComponentsSnapshotLocalAndTemplate(clearOnline: true)
                        refreshHealthCardsForSelectedServer()
                        clearConsole()
                    }
                }

    // MARK: - Running state

    @Published var commandText: String = ""
    @Published var isServerRunning: Bool = false
    @Published var orphanedJavaProcessCount: Int = 0
    @Published var watchdogEnabled: Bool = false
    @Published var isShowingInitialSetup: Bool = false
    @Published var isOnboardingActive: Bool = false
    @Published var isXboxBroadcastRunning: Bool = false
    @Published var isBedrockBroadcastRunning: Bool = false

    // MARK: - Bedrock / Docker state

    @Published var dockerDaemonRunning: Bool = false
    @Published var bedrockRunningVersion: String? = nil

    // MARK: - Health Cards

    @Published var healthCards: [HealthCardResult] = []

    // MARK: - First-start alert

    @Published var showFirstStartAlert: Bool = false
    @Published var firstStartAlertTitle: String = ""
    @Published var firstStartAlertMessage: String = ""

    // MARK: - Welcome / onboarding

    @Published var isShowingWelcomeGuide: Bool = false

    // MARK: - Backups / World Slots

    @Published var backupItems: [BackupItem] = []
    @Published var backupsFolderSizeDisplay: String? = nil
    @Published var worldSlots: [WorldSlot] = []
    @Published var isWorldSlotsLoading: Bool = false

    // MARK: - Resource Packs

    @Published var installedResourcePacks: [InstalledResourcePack] = []
    @Published var isLoadingResourcePacks: Bool = false

    // MARK: - Session log

    @Published var sessionEvents: [SessionEvent] = []

    // MARK: - Player Profiles (Java Edition)

    @Published var playerProfiles: [PlayerProfile] = []
    @Published var isLoadingProfiles: Bool = false

    // MARK: - Templates

    @Published var pluginTemplateItems: [PluginTemplateItem] = []
    @Published var paperTemplateItems: [PaperTemplateItem] = []

    // MARK: - JAR libraries

    @Published var xboxBroadcastJarItems: [JarLibraryItem] = []

    // MARK: - Players / TPS

    @Published var onlinePlayers: [OnlinePlayer] = []
    @Published var playerSessionHistory: [String] = []
    @Published var bedrockAllowlist: [BedrockAllowlistEntry] = []
    @Published var latestTps1m: Double?
    @Published var latestTps5m: Double?
    @Published var latestTps15m: Double?
    @Published var tpsHistory1m: [Double] = []
    @Published var playerCountHistory: [Int] = []

    // MARK: - CPU / RAM

    @Published var serverCpuPercent: Double? = nil
    @Published var serverRamMB: Double? = nil
    @Published var bedrockCpuPercent: Double? = nil
    @Published var bedrockMemoryUsedMB: Double? = nil
    @Published var bedrockMemoryLimitMB: Double? = nil
    @Published var bedrockCpuHistory: [Double] = []
    @Published var serverStartTime: Date? = nil
    @Published var serverUptimeDisplay: String? = nil
    @Published var serverRamFractionOfMax: Double? = nil
    @Published var isMetricsPaused: Bool = false
    @Published var worldSizeDisplay: String? = nil
    @Published var worldSizeMB: Double? = nil

    // MARK: - Server settings

    @Published var eulaAccepted: Bool? = nil
    @Published var serverSettings: ServerSettingsData? = nil
    @Published var isShowingSettingsEditor: Bool = false
    @Published var isShowingCreateServer: Bool = false
    @Published var geyserAddress: String = ""
    @Published var geyserPort: String = ""
    @Published var hasGeyser: Bool = false
    @Published var duckdnsInput: String = ""
    @Published var cachedPublicIPAddress: String? = nil
    @Published var isShowingPreferences: Bool = false
    @Published var isShowingAbout: Bool = false
    @Published var isShowingPrerequisites: Bool = false
    @Published var isShowingRouterPortForwardGuide: Bool = false
    @Published var isShowingCrossPlatformGuide: Bool = false
    @Published var triggerExplainWorkspace: Bool = false

    // MARK: - Computed helpers

    /// Human-readable TPS summary for the UI.
    var tpsSummaryText: String {
        func fmt(_ value: Double?) -> String {
            guard let v = value else { return "--" }
            return String(format: "%.2f", v)
        }
        return "TPS – 1m: \(fmt(latestTps1m))  •  5m: \(fmt(latestTps5m))  •  15m: \(fmt(latestTps15m))"
    }

    /// Max RAM (in GB) for the currently selected server, if known.
    var currentServerMaxRamGB: Int? {
        guard let server = selectedServer,
              let cfg = configServer(for: server) else { return nil }
        return cfg.maxRam
    }

    // MARK: - Child process PIDs (read by AppDelegate for shutdown cleanup)

    var serverProcessID: pid_t? { javaBackend.processID }
    var broadcastProcessID: pid_t? { broadcastManager.processID }

    // MARK: - Internal stored properties

    let configManager = ConfigManager.shared

    let javaBackend = JavaServerBackend()
    let bedrockBackend = BedrockServerBackend()
    var activeBackend: ServerBackend?

    let broadcastManager = XboxBroadcastProcessManager()
    let bedrockBroadcastManager = BedrockBroadcastManager()

    static var sharedRemoteAPIServer: RemoteAPIServer?
    var remoteAPIServer: RemoteAPIServer?

    var autoBackupTimer: Timer?
    let logicalCoreCount: Int = ProcessInfo.processInfo.activeProcessorCount

    var shouldStartOnboardingAfterWelcomeGuide: Bool = false
    var shouldLaunchFirstRunEducationAfterInitialSetupDismiss: Bool = false

    // MARK: - Init

    init() {
        // Chain ConsoleManager's objectWillChange into AppViewModel's so SwiftUI
        // views that observe AppViewModel re-render whenever console state changes.
        console.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        reloadServersFromConfig()
        logAppMessage("[App] MinecraftServerController started.")
        #if DEBUG
        #endif

        requestNotificationPermissionIfNeeded()
        checkForOrphansOnStartup()
        WatchdogRunner.markSessionActive()
        checkWatchdogStatus()

        let cfg = configManager.config

        // Remote API is a process-wide singleton to prevent multiple AppViewModel instances from
        // double-binding the port.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let cfg = self.configManager.config

            let port = UInt16(max(1024, min(65535, cfg.remoteAPIPort)))
            let tokenProvider: () -> [String: RemoteAPIServer.TokenRole] = { [weak self] in
                guard let self else { return [:] }
                let cfg2 = self.configManager.config
                var map: [String: RemoteAPIServer.TokenRole] = [:]
                if let ownerToken = KeychainManager.shared.readRemoteAPIToken() {
                    let t = ownerToken.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { map[t] = .admin }
                }
                for entry in cfg2.remoteAPISharedAccess {
                    let t = entry.token.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { map[t] = (entry.role == "guest") ? .guest : .admin }
                }
                return map
            }

            let serversProvider: () -> [Server] = { [weak self] in
                guard let self else { return [] }
                if Thread.isMainThread { return self.servers }
                return DispatchQueue.main.sync { self.servers }
            }

            let statusProvider: () -> RemoteAPIStatus = { [weak self] in
                guard let self else {
                    return RemoteAPIStatus(running: false, activeServerId: nil, pid: nil)
                }
                if Thread.isMainThread {
                    let cfg = self.configManager.config
                    let activeType = cfg.servers.first(where: { $0.id == cfg.activeServerId })?.serverType
                    let isBedrock = activeType == .bedrock
                    return RemoteAPIStatus(
                        running: self.isServerRunning,
                        activeServerId: cfg.activeServerId,
                        pid: isBedrock ? nil : self.javaBackend.processID.map { Int($0) },
                        serverType: activeType?.rawValue,
                        dockerContainerRunning: isBedrock ? self.isServerRunning : nil,
                        dockerContainerStatus: isBedrock ? (self.isServerRunning ? "running" : "stopped") : nil
                    )
                }
                return DispatchQueue.main.sync {
                    let cfg = self.configManager.config
                    let activeType = cfg.servers.first(where: { $0.id == cfg.activeServerId })?.serverType
                    let isBedrock = activeType == .bedrock
                    return RemoteAPIStatus(
                        running: self.isServerRunning,
                        activeServerId: cfg.activeServerId,
                        pid: isBedrock ? nil : self.javaBackend.processID.map { Int($0) },
                        serverType: activeType?.rawValue,
                        dockerContainerRunning: isBedrock ? self.isServerRunning : nil,
                        dockerContainerStatus: isBedrock ? (self.isServerRunning ? "running" : "stopped") : nil
                    )
                }
            }

            let performanceProvider: () -> RemoteAPIServer.PerformanceSnapshotDTO = { [weak self] in
                let ts = ISO8601DateFormatter().string(from: Date())
                guard let self else {
                    return RemoteAPIServer.PerformanceSnapshotDTO(
                        ts: ts, tps1m: nil, playersOnline: nil, cpuPercent: nil,
                        ramUsedMB: nil, ramMaxMB: nil, worldSizeMB: nil, serverType: nil)
                }
                let resolveOnMain: () -> RemoteAPIServer.PerformanceSnapshotDTO = {
                    let cfg = self.configManager.config
                    let activeType = cfg.servers.first(where: { $0.id == cfg.activeServerId })?.serverType
                    let isBedrock = activeType == .bedrock
                    let maxMB = self.performanceRamLimitGBForSelectedServer.map { Double($0) * 1024.0 }
                    return RemoteAPIServer.PerformanceSnapshotDTO(
                        ts: ts,
                        tps1m: isBedrock ? nil : self.latestTps1m,
                        playersOnline: self.onlinePlayers.count,
                        cpuPercent: self.performanceCpuPercentForSelectedServer,
                        ramUsedMB: self.performanceRamMBForSelectedServer,
                        ramMaxMB: maxMB,
                        worldSizeMB: self.worldSizeMB,
                        serverType: activeType?.rawValue
                    )
                }
                if Thread.isMainThread { return resolveOnMain() }
                return DispatchQueue.main.sync { resolveOnMain() }
            }

            let startProvider: () -> Void = { [weak self] in
                DispatchQueue.main.async { self?.startServer() }
            }
            let stopProvider: () -> Void = { [weak self] in
                DispatchQueue.main.async { self?.stopServer() }
            }
            let commandProvider: (String) -> Void = { [weak self] cmd in
                DispatchQueue.main.async { self?.sendQuickCommand(cmd) }
            }

            let setActiveServerProvider: (String) -> Bool = { [weak self] serverId in
                guard let self else { return false }
                if Thread.isMainThread {
                    guard let server = self.servers.first(where: { $0.id == serverId }) else { return false }
                    self.selectedServer = server
                    return true
                }
                return DispatchQueue.main.sync {
                    guard let server = self.servers.first(where: { $0.id == serverId }) else { return false }
                    self.selectedServer = server
                    return true
                }
            }

            let serverConnectionInfoProvider: (String) -> RemoteAPIServer.ServerConnectionInfoDTO? = { [weak self] serverId in
                guard let self else { return nil }
                let resolveOnMain: () -> RemoteAPIServer.ServerConnectionInfoDTO? = {
                    guard let cfgServer = self.configManager.config.servers.first(where: { $0.id == serverId }) else {
                        return nil
                    }
                    let gamePort: Int?
                    if cfgServer.serverType == .bedrock {
                        gamePort = self.bedrockPropertiesModel(for: cfgServer).serverPort
                    } else {
                        gamePort = self.loadServerPropertiesModel(for: cfgServer).serverPort
                    }
                    let resolvedHost = self.previewBroadcastHost(for: cfgServer, mode: cfgServer.xboxBroadcastIPMode)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let hostAddress = (resolvedHost.isEmpty || resolvedHost == "0.0.0.0") ? nil : resolvedHost
                    return RemoteAPIServer.ServerConnectionInfoDTO(gamePort: gamePort, hostAddress: hostAddress)
                }
                if Thread.isMainThread { return resolveOnMain() }
                return DispatchQueue.main.sync { resolveOnMain() }
            }

            let playersProvider: () -> RemoteAPIServer.PlayersResponseDTO = { [weak self] in
                guard let self else { return RemoteAPIServer.PlayersResponseDTO(players: [], count: 0) }
                let resolveOnMain: () -> RemoteAPIServer.PlayersResponseDTO = {
                    let cfg = self.configManager.config
                    let activeType = cfg.servers.first(where: { $0.id == cfg.activeServerId })?.serverType
                    let isBedrock = activeType == .bedrock
                    let players = self.onlinePlayers.map { RemoteAPIServer.PlayerDTO(name: $0.name, uuid: nil) }
                    let note: String? = isBedrock ? "Player list sourced from console log parsing for Bedrock servers." : nil
                    return RemoteAPIServer.PlayersResponseDTO(players: players, count: players.count, note: note)
                }
                if Thread.isMainThread { return resolveOnMain() }
                return DispatchQueue.main.sync { resolveOnMain() }
            }

            let allowlistProvider: () -> RemoteAPIServer.AllowlistResponseDTO = { [weak self] in
                guard let self else { return RemoteAPIServer.AllowlistResponseDTO(serverType: "java", entries: []) }
                let resolve: () -> RemoteAPIServer.AllowlistResponseDTO = {
                    let cfg = self.configManager.config
                    let activeType = cfg.servers.first(where: { $0.id == cfg.activeServerId })?.serverType ?? .java
                    let entries = self.bedrockAllowlist.map {
                        RemoteAPIServer.AllowlistEntryDTO(name: $0.name, xuid: $0.xuid, ignoresPlayerLimit: $0.ignoresPlayerLimit)
                    }
                    return RemoteAPIServer.AllowlistResponseDTO(serverType: activeType.rawValue, entries: entries)
                }
                if Thread.isMainThread { return resolve() }
                return DispatchQueue.main.sync { resolve() }
            }

            let isoFormatter = ISO8601DateFormatter()
            let sessionLogProvider: () -> RemoteAPIServer.SessionLogResponseDTO = { [weak self] in
                guard let self else { return RemoteAPIServer.SessionLogResponseDTO(activeServerId: nil, events: []) }
                let resolve: () -> RemoteAPIServer.SessionLogResponseDTO = {
                    let activeId = self.configManager.config.activeServerId
                    let events = self.sessionEvents.map { e in
                        RemoteAPIServer.SessionEventDTO(
                            id: e.id.uuidString,
                            playerName: e.playerName,
                            eventType: e.eventType.rawValue,
                            timestamp: isoFormatter.string(from: e.timestamp)
                        )
                    }
                    return RemoteAPIServer.SessionLogResponseDTO(activeServerId: activeId, events: events)
                }
                if Thread.isMainThread { return resolve() }
                return DispatchQueue.main.sync { resolve() }
            }

            let configServersProvider: () -> [ConfigServer] = { [weak self] in
                guard let self else { return [] }
                if Thread.isMainThread { return self.configManager.config.servers }
                return DispatchQueue.main.sync { self.configManager.config.servers }
            }

            let logger: (String) -> Void = { [weak self] msg in
                guard let self else { return }
                Task { @MainActor in self.logAppMessage(msg) }
            }

            // MARK: Component providers

            let componentsProvider: () async -> RemoteAPIServer.ComponentsStatusDTO = { [weak self] in
                guard let self else {
                    return RemoteAPIServer.ComponentsStatusDTO(components: [], restartRequiredToApply: false)
                }
                let (activeDir, isRunning, effectivePaperURL): (String?, Bool, URL?) = await MainActor.run {
                    let cfg = self.configManager.config
                    let activeServer = cfg.servers.first(where: { $0.id == cfg.activeServerId })
                    return (activeServer?.serverDir, self.isServerRunning, activeServer.flatMap { self.effectivePaperJarURL(for: $0) })
                }
                guard let dir = activeDir else {
                    return RemoteAPIServer.ComponentsStatusDTO(components: [], restartRequiredToApply: false)
                }
                let dirURL = URL(fileURLWithPath: dir, isDirectory: true)
                let pluginsURL = dirURL.appendingPathComponent("plugins", isDirectory: true)
                let hasPlugins = FileManager.default.fileExists(atPath: pluginsURL.path)

                // Resolve installed Paper version: sidecar → filename parse → jar present
                var paperInstalled: PaperJarVersion? = nil
                let paperJarURL: URL? = effectivePaperURL
                if effectivePaperURL != nil {
                    if let sidecar = PaperVersionSidecarManager.read(fromServerDirectory: dirURL) {
                        paperInstalled = PaperJarVersion(mcVersion: sidecar.mcVersion, build: sidecar.build)
                    } else if let url = effectivePaperURL {
                        paperInstalled = ComponentVersionParsing.parsePaperJarFilename(url.lastPathComponent)
                    }
                }

                // Scan plugins/ for Geyser and Floodgate
                var geyserBuild: Int? = nil
                var geyserJarURL: URL? = nil
                var floodgateBuild: Int? = nil
                var floodgateJarURL: URL? = nil
                if hasPlugins, let pluginFiles = try? FileManager.default.contentsOfDirectory(atPath: pluginsURL.path) {
                    for file in pluginFiles where file.hasSuffix(".jar") {
                        let lower = file.lowercased()
                        if lower.contains("geyser") && geyserBuild == nil {
                            geyserBuild = ComponentVersionParsing.parseTrailingBuildNumber(fromJarFilename: file)
                            geyserJarURL = pluginsURL.appendingPathComponent(file)
                        } else if lower.contains("floodgate") && floodgateBuild == nil {
                            floodgateBuild = ComponentVersionParsing.parseTrailingBuildNumber(fromJarFilename: file)
                            floodgateJarURL = pluginsURL.appendingPathComponent(file)
                        }
                    }
                }

                // Fetch latest versions concurrently
                async let latestPaper = try? PaperDownloader.fetchLatestMetadata()
                async let latestGeyser = hasPlugins ? (try? PluginDownloader.fetchLatestGeyserBuildInfo()) : nil
                async let latestFloodgate = hasPlugins ? (try? PluginDownloader.fetchLatestFloodgateBuildInfo()) : nil

                let (pMeta, gMeta, fMeta) = await (latestPaper, latestGeyser, latestFloodgate)

                var components: [RemoteAPIServer.ComponentStatusDTO] = []

                // Paper
                let paperLatestBuild = pMeta.map { $0.build }
                let paperLatestVer = pMeta.map { $0.version }
                let paperUpToDate: Bool
                if let inst = paperInstalled?.build, let latest = paperLatestBuild {
                    paperUpToDate = inst >= latest
                } else {
                    paperUpToDate = paperInstalled == nil && paperLatestBuild == nil
                }
                if paperJarURL != nil || paperLatestBuild != nil {
                    components.append(RemoteAPIServer.ComponentStatusDTO(
                        name: "Paper",
                        installedBuild: paperInstalled?.build,
                        latestBuild: paperLatestBuild,
                        installedVersion: paperInstalled?.mcVersion,
                        latestVersion: paperLatestVer,
                        isUpToDate: paperUpToDate
                    ))
                }

                // Geyser
                if hasPlugins {
                    let gLatest = gMeta?.build
                    let gLatestVer = gMeta?.version
                    let gUpToDate: Bool
                    if let inst = geyserBuild, let latest = gLatest { gUpToDate = inst >= latest }
                    else { gUpToDate = geyserBuild == nil && gLatest == nil }
                    components.append(RemoteAPIServer.ComponentStatusDTO(
                        name: "Geyser",
                        installedBuild: geyserBuild,
                        latestBuild: gLatest,
                        installedVersion: nil,
                        latestVersion: gLatestVer,
                        isUpToDate: gUpToDate
                    ))
                }

                // Floodgate
                if hasPlugins {
                    let fLatest = fMeta?.build
                    let fLatestVer = fMeta?.version
                    let fUpToDate: Bool
                    if let inst = floodgateBuild, let latest = fLatest { fUpToDate = inst >= latest }
                    else { fUpToDate = floodgateBuild == nil && fLatest == nil }
                    components.append(RemoteAPIServer.ComponentStatusDTO(
                        name: "Floodgate",
                        installedBuild: floodgateBuild,
                        latestBuild: fLatest,
                        installedVersion: nil,
                        latestVersion: fLatestVer,
                        isUpToDate: fUpToDate
                    ))
                }

                return RemoteAPIServer.ComponentsStatusDTO(
                    components: components,
                    restartRequiredToApply: isRunning
                )
            }

            let updateComponentProvider: (String, @escaping (RemoteAPIServer.ComponentUpdateResultDTO) -> Void) -> Void = { [weak self] component, completion in
                guard let self else {
                    completion(RemoteAPIServer.ComponentUpdateResultDTO(success: false, message: "Internal error.", newBuild: nil, newVersion: nil))
                    return
                }
                let configManager = self.configManager
                let appViewModel = self
                Task {
                    let (activeDir, comp, paperJarURL): (String?, String, URL?) = await MainActor.run {
                        let cfg = configManager.config
                        let activeServer = cfg.servers.first(where: { $0.id == cfg.activeServerId })
                        return (activeServer?.serverDir, component, activeServer.flatMap { appViewModel.effectivePaperJarURL(for: $0) })
                    }
                    guard let dir = activeDir else {
                        completion(RemoteAPIServer.ComponentUpdateResultDTO(success: false, message: "No active server.", newBuild: nil, newVersion: nil))
                        return
                    }
                    let dirURL = URL(fileURLWithPath: dir, isDirectory: true)
                    let pluginsURL = dirURL.appendingPathComponent("plugins", isDirectory: true)
                    do {
                        let result: RemoteAPIServer.ComponentUpdateResultDTO
                        switch comp {
                        case "paper":
                            guard let jarURL = paperJarURL else {
                                completion(RemoteAPIServer.ComponentUpdateResultDTO(success: false, message: "No Paper JAR found in server directory.", newBuild: nil, newVersion: nil))
                                return
                            }
                            let r = try await PaperDownloader.downloadLatestPaper(to: jarURL)
                            PaperVersionSidecarManager.write(mcVersion: r.version, build: r.build, toServerDirectory: dirURL)
                            result = RemoteAPIServer.ComponentUpdateResultDTO(success: true, message: "Paper updated to \(r.version) build \(r.build).", newBuild: r.build, newVersion: r.version)

                        case "geyser":
                            let pluginFiles = (try? FileManager.default.contentsOfDirectory(atPath: pluginsURL.path)) ?? []
                            guard let existing = pluginFiles.first(where: { $0.lowercased().contains("geyser") && $0.hasSuffix(".jar") }) else {
                                completion(RemoteAPIServer.ComponentUpdateResultDTO(success: false, message: "No Geyser JAR found in plugins/.", newBuild: nil, newVersion: nil))
                                return
                            }
                            let tempDest = pluginsURL.appendingPathComponent(existing)
                            let r = try await PluginDownloader.downloadLatestGeyser(to: tempDest)
                            let newGeyserName = renamedJar(existing, newBuild: r.build)
                            if newGeyserName != existing {
                                try? FileManager.default.moveItem(at: tempDest, to: pluginsURL.appendingPathComponent(newGeyserName))
                            }
                            result = RemoteAPIServer.ComponentUpdateResultDTO(success: true, message: "Geyser updated to build \(r.build).", newBuild: r.build, newVersion: r.version)

                        case "floodgate":
                            let pluginFiles = (try? FileManager.default.contentsOfDirectory(atPath: pluginsURL.path)) ?? []
                            guard let existing = pluginFiles.first(where: { $0.lowercased().contains("floodgate") && $0.hasSuffix(".jar") }) else {
                                completion(RemoteAPIServer.ComponentUpdateResultDTO(success: false, message: "No Floodgate JAR found in plugins/.", newBuild: nil, newVersion: nil))
                                return
                            }
                            let tempDest2 = pluginsURL.appendingPathComponent(existing)
                            let r = try await PluginDownloader.downloadLatestFloodgate(to: tempDest2)
                            let newFloodgateName = renamedJar(existing, newBuild: r.build)
                            if newFloodgateName != existing {
                                try? FileManager.default.moveItem(at: tempDest2, to: pluginsURL.appendingPathComponent(newFloodgateName))
                            }
                            result = RemoteAPIServer.ComponentUpdateResultDTO(success: true, message: "Floodgate updated to build \(r.build).", newBuild: r.build, newVersion: r.version)

                        default:
                            result = RemoteAPIServer.ComponentUpdateResultDTO(success: false, message: "Unknown component.", newBuild: nil, newVersion: nil)
                        }
                        completion(result)
                    } catch {
                        completion(RemoteAPIServer.ComponentUpdateResultDTO(success: false, message: error.localizedDescription, newBuild: nil, newVersion: nil))
                    }
                }
            }

            // MARK: Broadcast providers

            let broadcastStatusProvider: () -> RemoteAPIServer.BroadcastStatusDTO = { [weak self] in
                guard let self else { return RemoteAPIServer.BroadcastStatusDTO(xboxBroadcastRunning: false, bedrockBroadcastRunning: false) }
                let resolve = { RemoteAPIServer.BroadcastStatusDTO(xboxBroadcastRunning: self.isXboxBroadcastRunning, bedrockBroadcastRunning: self.isBedrockBroadcastRunning) }
                if Thread.isMainThread { return resolve() }
                return DispatchQueue.main.sync { resolve() }
            }

            let restartBroadcastProvider: () -> Void = { [weak self] in
                DispatchQueue.main.async {
                    self?.stopXboxBroadcast()
                    self?.startXboxBroadcast()
                }
            }

            let startBroadcastProvider: () -> Void = { [weak self] in
                DispatchQueue.main.async { self?.startXboxBroadcast() }
            }

            let stopBroadcastProvider: () -> Void = { [weak self] in
                DispatchQueue.main.async { self?.stopXboxBroadcast() }
            }

            let updateBroadcastCredentialsProvider: (RemoteAPIServer.BroadcastCredentialsDTO) -> Bool = { [weak self] creds in
                guard let self else { return false }
                let serverId: String? = DispatchQueue.main.sync { self.configManager.config.activeServerId }
                guard let serverId else { return false }
                DispatchQueue.main.async {
                    self.updateBroadcastProfile(
                        for: serverId,
                        enabled: true,
                        ipMode: .auto,
                        altEmail: creds.email,
                        altGamertag: creds.gamertag,
                        altPassword: creds.password,
                        altAvatarPath: ""
                    )
                }
                return true
            }

            let authPromptProvider: () -> RemoteAPIServer.BroadcastAuthPromptDTO = { [weak self] in
                guard let self else { return RemoteAPIServer.BroadcastAuthPromptDTO(isPresent: false, code: nil, linkURL: nil) }
                let prompt: BroadcastAuthPrompt? = Thread.isMainThread
                    ? self.pendingBroadcastAuthPrompt
                    : DispatchQueue.main.sync { self.pendingBroadcastAuthPrompt }
                guard let prompt else {
                    return RemoteAPIServer.BroadcastAuthPromptDTO(isPresent: false, code: nil, linkURL: nil)
                }
                return RemoteAPIServer.BroadcastAuthPromptDTO(isPresent: true, code: prompt.code, linkURL: prompt.linkURL.absoluteString)
            }

            let dismissAuthPromptProvider: () -> Void = { [weak self] in
                DispatchQueue.main.async { self?.pendingBroadcastAuthPrompt = nil }
            }

            let broadcastAutoStartProvider: () -> RemoteAPIServer.BroadcastAutoStartDTO = { [weak self] in
                guard let self else { return RemoteAPIServer.BroadcastAutoStartDTO(enabled: false) }
                let enabled: Bool = Thread.isMainThread
                    ? self.selectedServerXboxBroadcastEnabled
                    : DispatchQueue.main.sync { self.selectedServerXboxBroadcastEnabled }
                return RemoteAPIServer.BroadcastAutoStartDTO(enabled: enabled)
            }

            let setBroadcastAutoStartProvider: (Bool) -> Void = { [weak self] enabled in
                DispatchQueue.main.async { self?.selectedServerXboxBroadcastEnabled = enabled }
            }

            let isoFmt: ISO8601DateFormatter = {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return f
            }()

            if let shared = AppViewModel.sharedRemoteAPIServer {
                shared.updateProviders(
                    tokenProvider: tokenProvider,
                    serversProvider: serversProvider,
                    statusProvider: statusProvider,
                    performanceProvider: performanceProvider,
                    startProvider: startProvider,
                    stopProvider: stopProvider,
                    commandProvider: commandProvider,
                    setActiveServerProvider: setActiveServerProvider,
                    playersProvider: playersProvider,
                    allowlistProvider: allowlistProvider,
                    sessionLogProvider: sessionLogProvider,
                    configServersProvider: configServersProvider,
                    serverConnectionInfoProvider: serverConnectionInfoProvider,
                    componentsProvider: componentsProvider,
                    updateComponentProvider: updateComponentProvider,
                    broadcastStatusProvider: broadcastStatusProvider,
                    restartBroadcastProvider: restartBroadcastProvider,
                    startBroadcastProvider: startBroadcastProvider,
                    stopBroadcastProvider: stopBroadcastProvider,
                    updateBroadcastCredentialsProvider: updateBroadcastCredentialsProvider,
                    authPromptProvider: authPromptProvider,
                    dismissAuthPromptProvider: dismissAuthPromptProvider,
                    broadcastAutoStartProvider: broadcastAutoStartProvider,
                    setBroadcastAutoStartProvider: setBroadcastAutoStartProvider,
                    logger: logger
                )
                shared.setListenOnAllInterfaces(cfg.remoteAPIExposeOnLAN)
                self.remoteAPIServer = shared
                shared.watchdogStatusProvider  = { [weak self] in self?.watchdogEnabled ?? false }
                shared.enableWatchdogProvider  = { [weak self] in self?.enableWatchdogSync() }
                shared.disableWatchdogProvider = { [weak self] in self?.disableWatchdogSync() }
                shared.playerProfilesProvider = { [weak self, isoFmt] in
                    guard let self else { return RemoteAPIServer.PlayerProfilesResponseDTO(profiles: [], isLoadingStats: false) }
                    let profiles = Thread.isMainThread ? self.playerProfiles : DispatchQueue.main.sync { self.playerProfiles }
                    let dtos = profiles.map { p -> RemoteAPIServer.PlayerProfileDTO in
                        let statsDTO = p.stats.map { s in
                            RemoteAPIServer.PlayerStatsDTO(
                                health: s.health, maxHealth: s.maxHealth, foodLevel: s.foodLevel,
                                xpLevel: s.xpLevel, xpTotal: s.xpTotal, gameMode: s.gameMode,
                                gameModeDisplay: s.gameModeDisplay, posX: s.posX, posY: s.posY,
                                posZ: s.posZ, dimensionDisplay: s.dimensionDisplay, score: s.score
                            )
                        }
                    let inventoryDTOs = p.inventory.map { item in
                            RemoteAPIServer.InventoryItemDTO(
                                slot: item.slot, itemID: item.itemID, iconName: item.iconName,
                                count: item.count, displayName: item.displayName,
                                enchantments: item.enchantments.map {
                                    RemoteAPIServer.ItemEnchantmentDTO(id: $0.id, level: $0.level, displayName: $0.displayName)
                                },
                                damage: item.damage
                            )
                        }
                        return RemoteAPIServer.PlayerProfileDTO(
                            id: p.id, username: p.username, imageIdentifier: p.imageIdentifier,
                            isOnline: p.isOnline, isOp: p.isOp,
                            lastSeen: isoFmt.string(from: p.lastModified),
                            isBedrockPlayer: p.isBedrockPlayer, stats: statsDTO,
                            inventory: inventoryDTOs
                        )
                    }
                    // Trigger NBT loading for Java profiles that don't have stats yet.
                    let needsNBT = profiles.filter { $0.stats == nil && !$0.isBedrockPlayer }
                    if !needsNBT.isEmpty {
                        DispatchQueue.main.async { needsNBT.forEach { self.loadProfileNBT(uuid: $0.uuid) } }
                    }
                    return RemoteAPIServer.PlayerProfilesResponseDTO(profiles: dtos, isLoadingStats: !needsNBT.isEmpty)
                }
                shared.worldSlotsProvider = { [weak self, isoFmt] in
                    guard let self else { return RemoteAPIServer.WorldSlotsResponseDTO(slots: [], activeSlotId: nil, serverRunning: false) }
                    let (slots, running, selectedServer) = Thread.isMainThread
                        ? (self.worldSlots, self.isServerRunning, self.selectedServer)
                        : DispatchQueue.main.sync { (self.worldSlots, self.isServerRunning, self.selectedServer) }
                    let activeId = selectedServer.flatMap { self.activeWorldSlotId(forServerDir: $0.directory) }
                    let dtos = slots.map { RemoteAPIServer.WorldSlotDTO(id: $0.id, name: $0.name, isActive: $0.id == activeId,
                                                                        createdAt: isoFmt.string(from: $0.createdAt),
                                                                        zipSizeBytes: $0.zipSizeBytes, worldSeed: $0.worldSeed) }
                    return RemoteAPIServer.WorldSlotsResponseDTO(slots: dtos, activeSlotId: activeId, serverRunning: running)
                }
                shared.activateWorldSlotProvider = { [weak self] slotId in
                    guard let self else { return false }
                    let (slots, running) = Thread.isMainThread
                        ? (self.worldSlots, self.isServerRunning)
                        : DispatchQueue.main.sync { (self.worldSlots, self.isServerRunning) }
                    guard !running, let slot = slots.first(where: { $0.id == slotId }) else { return false }
                    Task { @MainActor [weak self] in await self?.activateWorldSlot(slot) }
                    return true
                }
                shared.backupItemsProvider = { [weak self, isoFmt] in
                    guard let self else { return RemoteAPIServer.BackupsResponseDTO(backups: []) }
                    let items = Thread.isMainThread ? self.backupItems : DispatchQueue.main.sync { self.backupItems }
                    let dtos = items.map { RemoteAPIServer.BackupItemDTO(id: $0.filename, displayName: $0.displayName,
                                                                         fileSize: $0.fileSize,
                                                                         modificationDate: $0.modificationDate.map { isoFmt.string(from: $0) },
                                                                         isAutomatic: $0.isAutomatic, slotId: $0.slotId,
                                                                         slotName: $0.slotName, triggerReason: $0.triggerReason) }
                    return RemoteAPIServer.BackupsResponseDTO(backups: dtos)
                }
                shared.createBackupNowProvider = { [weak self] in
                    DispatchQueue.main.async { self?.createBackupForSelectedServer(isAutomatic: false) }
                }
                shared.restoreBackupProvider = { [weak self] filename in
                    guard let self else { return false }
                    let items = Thread.isMainThread ? self.backupItems : DispatchQueue.main.sync { self.backupItems }
                    guard let backup = items.first(where: { $0.filename == filename }) else { return false }
                    DispatchQueue.main.async { self.restoreBackup(backup) }
                    return true
                }
                shared.start()
                return
            }

            let api = RemoteAPIServer(
                port: port,
                listenOnAllInterfaces: cfg.remoteAPIExposeOnLAN,
                tokenProvider: tokenProvider,
                serversProvider: serversProvider,
                statusProvider: statusProvider,
                performanceProvider: performanceProvider,
                startProvider: startProvider,
                stopProvider: stopProvider,
                commandProvider: commandProvider,
                setActiveServerProvider: setActiveServerProvider,
                playersProvider: playersProvider,
                allowlistProvider: allowlistProvider,
                sessionLogProvider: sessionLogProvider,
                configServersProvider: configServersProvider,
                serverConnectionInfoProvider: serverConnectionInfoProvider,
                componentsProvider: componentsProvider,
                updateComponentProvider: updateComponentProvider,
                broadcastStatusProvider: broadcastStatusProvider,
                restartBroadcastProvider: restartBroadcastProvider,
                startBroadcastProvider: startBroadcastProvider,
                stopBroadcastProvider: stopBroadcastProvider,
                updateBroadcastCredentialsProvider: updateBroadcastCredentialsProvider,
                authPromptProvider: authPromptProvider,
                dismissAuthPromptProvider: dismissAuthPromptProvider,
                broadcastAutoStartProvider: broadcastAutoStartProvider,
                setBroadcastAutoStartProvider: setBroadcastAutoStartProvider,
                logger: logger
            )
            AppViewModel.sharedRemoteAPIServer = api
            self.remoteAPIServer = api
            api.watchdogStatusProvider  = { [weak self] in self?.watchdogEnabled ?? false }
            api.enableWatchdogProvider  = { [weak self] in self?.enableWatchdogSync() }
            api.disableWatchdogProvider = { [weak self] in self?.disableWatchdogSync() }
            api.playerProfilesProvider = { [weak self, isoFmt] in
                guard let self else { return RemoteAPIServer.PlayerProfilesResponseDTO(profiles: [], isLoadingStats: false) }
                let profiles = Thread.isMainThread ? self.playerProfiles : DispatchQueue.main.sync { self.playerProfiles }
                let dtos = profiles.map { p -> RemoteAPIServer.PlayerProfileDTO in
                    let statsDTO = p.stats.map { s in
                        RemoteAPIServer.PlayerStatsDTO(
                            health: s.health, maxHealth: s.maxHealth, foodLevel: s.foodLevel,
                            xpLevel: s.xpLevel, xpTotal: s.xpTotal, gameMode: s.gameMode,
                            gameModeDisplay: s.gameModeDisplay, posX: s.posX, posY: s.posY,
                            posZ: s.posZ, dimensionDisplay: s.dimensionDisplay, score: s.score
                        )
                    }
                    let inventoryDTOs = p.inventory.map { item in
                        RemoteAPIServer.InventoryItemDTO(
                            slot: item.slot, itemID: item.itemID, iconName: item.iconName,
                            count: item.count, displayName: item.displayName,
                            enchantments: item.enchantments.map {
                                RemoteAPIServer.ItemEnchantmentDTO(id: $0.id, level: $0.level, displayName: $0.displayName)
                            },
                            damage: item.damage
                        )
                    }
                    return RemoteAPIServer.PlayerProfileDTO(
                        id: p.id, username: p.username, imageIdentifier: p.imageIdentifier,
                        isOnline: p.isOnline, isOp: p.isOp,
                        lastSeen: isoFmt.string(from: p.lastModified),
                        isBedrockPlayer: p.isBedrockPlayer, stats: statsDTO,
                        inventory: inventoryDTOs
                    )
                }
                let needsNBT = profiles.filter { $0.stats == nil && !$0.isBedrockPlayer }
                if !needsNBT.isEmpty {
                    DispatchQueue.main.async { needsNBT.forEach { self.loadProfileNBT(uuid: $0.uuid) } }
                }
                return RemoteAPIServer.PlayerProfilesResponseDTO(profiles: dtos, isLoadingStats: !needsNBT.isEmpty)
            }
            api.worldSlotsProvider = { [weak self, isoFmt] in
                guard let self else { return RemoteAPIServer.WorldSlotsResponseDTO(slots: [], activeSlotId: nil, serverRunning: false) }
                let (slots, running, selectedServer) = Thread.isMainThread
                    ? (self.worldSlots, self.isServerRunning, self.selectedServer)
                    : DispatchQueue.main.sync { (self.worldSlots, self.isServerRunning, self.selectedServer) }
                let activeId = selectedServer.flatMap { self.activeWorldSlotId(forServerDir: $0.directory) }
                let dtos = slots.map { RemoteAPIServer.WorldSlotDTO(id: $0.id, name: $0.name, isActive: $0.id == activeId,
                                                                    createdAt: isoFmt.string(from: $0.createdAt),
                                                                    zipSizeBytes: $0.zipSizeBytes, worldSeed: $0.worldSeed) }
                return RemoteAPIServer.WorldSlotsResponseDTO(slots: dtos, activeSlotId: activeId, serverRunning: running)
            }
            api.activateWorldSlotProvider = { [weak self] slotId in
                guard let self else { return false }
                let (slots, running) = Thread.isMainThread
                    ? (self.worldSlots, self.isServerRunning)
                    : DispatchQueue.main.sync { (self.worldSlots, self.isServerRunning) }
                guard !running, let slot = slots.first(where: { $0.id == slotId }) else { return false }
                Task { @MainActor [weak self] in await self?.activateWorldSlot(slot) }
                return true
            }
            api.backupItemsProvider = { [weak self, isoFmt] in
                guard let self else { return RemoteAPIServer.BackupsResponseDTO(backups: []) }
                let items = Thread.isMainThread ? self.backupItems : DispatchQueue.main.sync { self.backupItems }
                let dtos = items.map { RemoteAPIServer.BackupItemDTO(id: $0.filename, displayName: $0.displayName,
                                                                     fileSize: $0.fileSize,
                                                                     modificationDate: $0.modificationDate.map { isoFmt.string(from: $0) },
                                                                     isAutomatic: $0.isAutomatic, slotId: $0.slotId,
                                                                     slotName: $0.slotName, triggerReason: $0.triggerReason) }
                return RemoteAPIServer.BackupsResponseDTO(backups: dtos)
            }
            api.createBackupNowProvider = { [weak self] in
                DispatchQueue.main.async { self?.createBackupForSelectedServer(isAutomatic: false) }
            }
            api.restoreBackupProvider = { [weak self] filename in
                guard let self else { return false }
                let items = Thread.isMainThread ? self.backupItems : DispatchQueue.main.sync { self.backupItems }
                guard let backup = items.first(where: { $0.filename == filename }) else { return false }
                DispatchQueue.main.async { self.restoreBackup(backup) }
                return true
            }
            api.start()
        }

        // Setup wizard
        isShowingInitialSetup = !cfg.initialSetupDone

        // DuckDNS
        duckdnsInput = cfg.duckdnsHostname ?? ""

        AppUtilities.fetchPublicIPAddress { [weak self] ip in
            self?.cachedPublicIPAddress = ip
        }

        if cfg.initialSetupDone {
            stageWelcomeGuideThenTourIfNeeded()
        }

        if cfg.initialSetupDone {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                let configuredTypes = Set(cfg.servers.map { $0.serverType })
                let hasMissing = PrerequisitesView.hasCriticalMissingDependency(for: configuredTypes)
                if hasMissing {
                    DispatchQueue.main.async { self.isShowingPrerequisites = true }
                }
            }
        }

        // Java backend output handlers
        javaBackend.onOutputLine = { [weak self] line in
            guard let self else { return }
            Task { @MainActor in self.handleServerOutputLine(line) }
        }

        javaBackend.onDidTerminate = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                let reachedReadyState = self.lifecycle.serverReadyForAutoMetrics
                let wasUserRequestedStop = self.lifecycle.isStopRequested
                self.isServerRunning = false
                self.serverStartTime = nil
                self.serverUptimeDisplay = nil
                self.serverCpuPercent = nil
                self.serverRamMB = nil
                self.serverRamFractionOfMax = nil
                self.clearBedrockPerformanceMetrics()
                self.isMetricsPaused = false
                self.lifecycle.resetAfterTermination()
                self.stopBroadcastIfRunning()
                self.stopAutoBackupTimer()
                self.refreshWorldSize()
                if let server = self.selectedServer, let cfg = self.configServer(for: server) {
                    self.fireNotificationIfEnabled(event: .serverStopped, serverName: cfg.displayName, serverId: cfg.id)
                }
                if !reachedReadyState {
                    if let server = self.selectedServer, let cfg = self.configServer(for: server) {
                        self.writeLastStartupResult(for: cfg, wasClean: false, fatalErrors: ["Server stopped before reaching ready state."], warnings: [])
                    }
                }
                self.refreshHealthCardsForSelectedServer()
                if !wasUserRequestedStop {
                    let recentErrors = self.console.entries
                        .filter { $0.source == .server && $0.level == .error }
                        .suffix(5)
                        .map { $0.raw }
                    let detail = recentErrors.isEmpty
                        ? "The server process stopped unexpectedly with no error output in the log."
                        : recentErrors.joined(separator: "\n")
                    self.showError(title: "Server Stopped Unexpectedly", message: detail)
                }
                self.logAppMessage("[App] Server process ended.")
                if let server = self.selectedServer, let cfg = self.configServer(for: server) {
                    self.createInitialWorldSlotIfNeeded(for: cfg)
                }
            }
        }

                        // Bedrock backend output handlers
        bedrockBackend.onOutputLine = { [weak self] line in
            guard let self else { return }
            Task { @MainActor in self.handleServerOutputLine(line) }
        }

        bedrockBackend.onDidTerminate = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                let reachedReadyState = self.lifecycle.serverReadyForAutoMetrics
                let wasStopRequested = self.lifecycle.isStopRequested
                self.isServerRunning = false
                self.serverStartTime = nil
                self.serverUptimeDisplay = nil
                self.serverCpuPercent = nil
                self.serverRamMB = nil
                self.serverRamFractionOfMax = nil
                self.clearBedrockPerformanceMetrics()
                self.isMetricsPaused = false
                self.bedrockRunningVersion = nil
                self.lifecycle.resetAfterTermination()
                self.stopBroadcastIfRunning()
                self.stopAutoBackupTimer()
                self.refreshWorldSize()
                if let server = self.selectedServer, let cfg = self.configServer(for: server) {
                    self.fireNotificationIfEnabled(event: .serverStopped, serverName: cfg.displayName, serverId: cfg.id)
                }
                if !reachedReadyState {
                    if let server = self.selectedServer, let cfg = self.configServer(for: server) {
                        self.writeLastStartupResult(for: cfg, wasClean: false, fatalErrors: ["Container stopped before server reached ready state."], warnings: [])
                    }
                }
                self.refreshHealthCardsForSelectedServer()
                                if !wasStopRequested {
                                    let recentErrors = self.console.entries
                                        .filter { $0.source == .server && $0.level == .error }
                                        .suffix(5)
                                        .map { $0.raw }
                                    let detail = recentErrors.isEmpty
                                        ? "The Bedrock container stopped unexpectedly with no error output in the log."
                                        : recentErrors.joined(separator: "\n")
                                    self.showError(title: "Server Stopped Unexpectedly", message: detail)
                                }
                                self.logAppMessage("[App] Bedrock container stopped.")
                                if let server = self.selectedServer, let cfg = self.configServer(for: server) {
                                    self.createInitialWorldSlotIfNeeded(for: cfg)
                                }
                            }
                        }

                        // Broadcast output handlers
        broadcastManager.onOutputLine = { [weak self] line in
            guard let self else { return }
            Task { @MainActor in self.handleBroadcastOutputLine(line) }
        }

        broadcastManager.onDidTerminate = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.isXboxBroadcastRunning = false
                self.logAppMessage("[Broadcast] Broadcast process ended.")
            }
        }

        bedrockBroadcastManager.onOutputLine = { [weak self] line in
            guard let self else { return }
            Task { @MainActor in self.handleBroadcastOutputLine(line) }
        }

        bedrockBroadcastManager.onDidTerminate = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.isBedrockBroadcastRunning = false
                self.logAppMessage("[BroadcastBDS] Broadcast container ended.")
            }
        }

    }

    // MARK: - Controller refresh

       func refreshController() {
           reloadServersFromConfig()
           if let current = selectedServer {
               selectedServer = current
           }
           logAppMessage("[App] Controller refreshed.")
       }

       // MARK: - Tour accent color

    func syncTourAccentColor() {
        let accentHex: String?
        if let server = selectedServer,
           let cfgServer = configServer(for: server),
           let hex = cfgServer.bannerColorHex {
            accentHex = hex
        } else {
            accentHex = configManager.config.defaultBannerColorHex
        }
        let resolved: Color
        if let hex = accentHex, let color = Color(hexRGB: hex) {
            resolved = color.clampedAwayFromWhite().clampedAwayFromBlack()
        } else {
            resolved = Color(red: 0.133, green: 0.784, blue: 0.349)
        }
        DispatchQueue.main.async {
            self.resolvedAccentColor = resolved
            OnboardingManager.shared.accentColor = resolved
            ContextualHelpManager.shared.accentColor = resolved
        }
    }

    // MARK: - Console state forwarding (delegates to ConsoleManager)

    var consoleEntries: [ConsoleEntry] {
        get { console.entries }
        set { console.entries = newValue }
    }

    var consoleTab: ConsoleTab {
        get { console.tab }
        set { console.tab = newValue }
    }

    var consoleSearchText: String {
        get { console.searchText }
        set { console.searchText = newValue }
    }

    var consoleSelectedSources: Set<ConsoleSource> {
        get { console.selectedSources }
        set { console.selectedSources = newValue }
    }

    var consoleSelectedLevels: Set<ConsoleLevel> {
        get { console.selectedLevels }
        set { console.selectedLevels = newValue }
    }

    var consoleSelectedTags: Set<String> {
        get { console.selectedTags }
        set { console.selectedTags = newValue }
    }

    var consoleHideAuto: Bool {
        get { console.hideAuto }
        set { console.hideAuto = newValue }
    }

    var consoleKnownTags: [String] { console.knownTags }
    var filteredConsoleEntries: [ConsoleEntry] { console.filteredEntries }
    var errorPopupsEnabled: Bool { configManager.config.errorPopupsEnabled }

    // MARK: - Console filter helpers

    func resetConsoleFilters() { console.resetFilters() }

    func setErrorPopupsEnabled(_ enabled: Bool) {
        guard configManager.config.errorPopupsEnabled != enabled else { return }
        configManager.config.errorPopupsEnabled = enabled
        configManager.save()
        if !enabled {
            errorAlert = nil
        }
        logAppMessage(enabled
                      ? "[Console] Error popups enabled."
                      : "[Console] Error popups disabled.")
    }
    func setSource(_ source: ConsoleSource, enabled: Bool) { console.setSource(source, enabled: enabled) }
    func setLevel(_ level: ConsoleLevel, enabled: Bool) { console.setLevel(level, enabled: enabled) }
    func setTag(_ tag: String, enabled: Bool) { console.setTag(tag, enabled: enabled) }
    func autoSelectConsoleTabForCurrentFilters() { console.autoSelectTab() }

    // MARK: - Core helpers

    func configServer(for server: Server) -> ConfigServer? {
        configManager.config.servers.first(where: { $0.id == server.id })
    }

    func showError(title: String, message: String) {
        guard configManager.config.errorPopupsEnabled else { return }
        errorAlert = AppError(title: title, message: message)
    }

    func logAppMessage(_ msg: String) {
        let ts = AppUtilities.timestampString()
        let line = "[\(ts)] \(msg)"
        console.appendRaw(line, source: .controller)
        remoteAPIServer?.publishConsoleLine(source: "app", text: line)
    }

    func clearConsole() {
        console.clearEntries()
        remoteAPIServer?.clearConsoleBuffer()
    }
}

/// Returns a JAR filename with the trailing build number replaced by `newBuild`.
/// e.g. "Geyser-spigot-1126.jar" + 1155 → "Geyser-spigot-1155.jar"
/// If the filename doesn't end with a numeric build suffix, returns it unchanged.
private func renamedJar(_ filename: String, newBuild: Int) -> String {
    let base = (filename as NSString).deletingPathExtension   // "Geyser-spigot-1126"
    let ext  = (filename as NSString).pathExtension           // "jar"
    var parts = base.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
    if let last = parts.last, Int(last) != nil {
        parts[parts.count - 1] = "\(newBuild)"
    } else {
        parts.append("\(newBuild)")
    }
    return parts.joined(separator: "-") + "." + ext
}

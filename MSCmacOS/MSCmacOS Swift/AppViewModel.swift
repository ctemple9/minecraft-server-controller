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

    @Published var componentsSnapshot: ComponentsVersionSnapshot = ComponentsVersionSnapshot()
    @Published var isCheckingComponentsOnline: Bool = false
        @Published var componentsOnlineErrorMessage: String? = nil
        @Published var isDownloadingAndApplyingPaper: Bool = false
        @Published var isDownloadingAndApplyingGeyser: Bool = false
        @Published var isDownloadingAndApplyingFloodgate: Bool = false
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
    @Published var isShowingInitialSetup: Bool = false
    @Published var isOnboardingActive: Bool = false
    @Published var isBedrockConnectRunning: Bool = false
    @Published var isXboxBroadcastRunning: Bool = false

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

    // MARK: - Templates

    @Published var pluginTemplateItems: [PluginTemplateItem] = []
    @Published var paperTemplateItems: [PaperTemplateItem] = []

    // MARK: - JAR libraries

    @Published var xboxBroadcastJarItems: [JarLibraryItem] = []
    @Published var bedrockConnectJarItems: [JarLibraryItem] = []

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
    var bedrockConnectProcessID: pid_t? { bedrockConnectManager.processID }

    // MARK: - Internal stored properties

    let configManager = ConfigManager.shared

    let javaBackend = JavaServerBackend()
    let bedrockBackend = BedrockServerBackend()
    var activeBackend: ServerBackend?

    let broadcastManager = XboxBroadcastProcessManager()
    let bedrockConnectManager = BedrockConnectProcessManager()

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

        let cfg = configManager.config

        // Remote API is a process-wide singleton to prevent multiple AppViewModel instances from
        // double-binding the port.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let cfg = self.configManager.config

            let port = UInt16(max(1024, min(65535, cfg.remoteAPIPort)))
            let tokenProvider: () -> Set<String> = { [weak self] in
                guard let self else { return [] }
                let cfg2 = self.configManager.config
                var tokens: [String] = []
                if let ownerToken = KeychainManager.shared.readRemoteAPIToken() {
                    tokens.append(ownerToken)
                }
                tokens.append(contentsOf: cfg2.remoteAPISharedAccess.map { $0.token })
                let normalized = tokens
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                return Set(normalized)
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
                    logger: logger
                )
                shared.setListenOnAllInterfaces(cfg.remoteAPIExposeOnLAN)
                self.remoteAPIServer = shared
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
                logger: logger
            )
            AppViewModel.sharedRemoteAPIServer = api
            self.remoteAPIServer = api
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
                self.stopBedrockConnectIfRunning()
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
                self.stopBedrockConnectIfRunning()
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
                                if !self.lifecycle.isStopRequested {
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

        // Bedrock Connect output handlers
        bedrockConnectManager.onOutputLine = { [weak self] line in
            guard let self else { return }
            Task { @MainActor in self.handleBedrockConnectOutputLine(line) }
        }

        bedrockConnectManager.onDidTerminate = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.isBedrockConnectRunning = false
                self.logAppMessage("[BedrockConnect] Bedrock Connect process ended.")
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

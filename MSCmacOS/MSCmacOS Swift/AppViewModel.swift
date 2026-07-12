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
    /// One-time alert shown when `ConfigManager.init` found an unreadable config and
    /// replaced it with defaults (R3). Presented on a separate `Color.clear` anchor in
    /// ContentView to honour the one-presentation-per-view rule.
    @Published var configCorruptAlert: AppError?
    @Published var pendingSVCTunnelMismatch: SVCTunnelMismatchAlert?
    @Published var pendingSVCPortForwardingPrompt: SVCPortForwardingAlert?
    @Published var pendingBedrockTunnelMissing: BedrockTunnelMissingAlert?

    // MARK: - Components tab state

    @Published var discoveredPlugins: [PluginEntry] = []
    @Published var downloadingPlugins: Set<String> = []   // jarStem keys
    @Published var discoveredMods: [ModEntry] = []

    // Add-on (plugin/mod) update planning — drives the Update All sheet + per-row badges.
    @Published var addonUpdatePlan: [AddonUpdateItem] = []
    @Published var isResolvingAddonUpdates: Bool = false
    @Published var addonUpdateError: String? = nil
    /// jarStems currently being downloaded/applied, for per-row progress.
    @Published var updatingAddonStems: Set<String> = []
    /// Which server `addonUpdatePlan` was computed for. Acts as the cache key so the plan
    /// is resolved once per server and reused until invalidated (server change / mutation).
    @Published var addonPlanServerId: String? = nil

    // Startup crash diagnostics — parsed mod/plugin problems from a failed start.
    @Published var startupProblems: [StartupProblem] = []
    @Published var isShowingStartupProblems: Bool = false
    /// The server the current `startupProblems` belong to (for the sheet's actions).
    @Published var startupProblemsServerId: String? = nil
    /// StartupProblem ids currently being repaired (update/install), for per-row spinners.
    @Published var repairingProblemIds: Set<String> = []
    /// True when the current problems are a "soft fail" (server started but some add-ons
    /// failed to load) vs a hard fail (server couldn't start). Tunes the sheet's copy.
    @Published var startupProblemsAreSoftFail: Bool = false

    @Published var componentsSnapshot: ComponentsVersionSnapshot = ComponentsVersionSnapshot()
    @Published var isCheckingComponentsOnline: Bool = false
        @Published var componentsOnlineErrorMessage: String? = nil
        @Published var isDownloadingAndApplyingPaper: Bool = false
        @Published var isDownloadingAndApplyingGeyser: Bool = false
        @Published var isDownloadingAndApplyingFloodgate: Bool = false
    @Published var isDownloadingJar: Bool = false
    @Published var includeExperimentalPaperBuilds: Bool = false
    @Published var availablePaperVersions: [PaperVersionOption] = []
    @Published var selectedPaperVersionOption: PaperVersionOption? = nil
    @Published var bedrockAvailableVersions: [BedrockVersionEntry] = []
    @Published var isFetchingBedrockVersions: Bool = false
    @Published var bedrockVersionFetchError: String? = nil
    /// Human-readable reason the most recent server creation failed, surfaced in the
    /// Add Server wizard. Nil when no failure is pending.
    @Published var lastServerCreateError: String? = nil
    /// Set when the configured Java is too old for the Minecraft version of the
    /// server being started (the common cause of a silent boot failure). Nil when fine.
    @Published var javaCompatibilityWarning: String? = nil
    @Published var isUpdatingBedrockImage: Bool = false
    @Published var isRepairingWorld: Bool = false
    /// Fires true when a long-running operation (e.g. NeoForge installer) wants the
    /// console to be visible so the user can see streaming output. ContentView reacts
    /// by unhiding / expanding the console panel, then resets this to false.
    @Published var requestConsoleExpand: Bool = false

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
            clearLiveWorldTime()

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
            checkSVCTunnelMismatch()
                    }
                }

    // MARK: - Running state

    @Published var commandText: String = ""
    @Published var isServerRunning: Bool = false
    @Published var orphanedJavaProcessCount: Int = 0
    @Published var watchdogEnabled: Bool = false
    @Published var isShowingInitialSetup: Bool = false
    /// Set by ContentView to reflect its own local @State sheet booleans,
    /// so the ViewModel can gate broadcast auth presentation behind all sheets.
    @Published var contentViewSheetIsPresented: Bool = false
    @Published var isOnboardingActive: Bool = false
    @Published var isXboxBroadcastRunning: Bool = false
    @Published var isBedrockBroadcastRunning: Bool = false

    // MARK: - playit.gg tunnel
    @Published var isPlayitRunning: Bool = false
    /// The public tunnel address (e.g. "abc.joinmc.link:25565") once the agent is connected.
    @Published var playitTunnelAddress: String? = nil
    /// True when the user needs to enter their playit.gg secret key for the first time.
    @Published var isShowingPlayitSecretSetup: Bool = false
    /// Transient flag: true for one log line after "tunnel setup" is printed.
    var playitExpectingAddressLine: Bool = false

    // MARK: - Bedrock / Docker state

    @Published var dockerDaemonRunning: Bool = false
    @Published var bedrockRunningVersion: String? = nil

    // MARK: - Health Cards

    @Published var healthCards: [HealthCardResult] = []

    // MARK: - First-start alert

    @Published var showFirstStartAlert: Bool = false
    @Published var firstStartAlertTitle: String = ""
    @Published var firstStartAlertMessage: String = ""

    /// Single global reveal toggle for connection addresses/ports — shared by the
    /// Overview "Connection Info" card and the sidebar "How to Connect" section so
    /// hiding in one place hides everywhere. Defaults to hidden.
    @Published var showConnectionAddresses: Bool = false

    // MARK: - First-time initiation (pass 2 — transport bring-up)

    /// Drives the non-modal progress overlay shown while playit / Xbox broadcast
    /// come up during first-time initiation. Non-modal so the in-app Xbox sign-in
    /// sheet can still present over it.
    @Published var isShowingInitiationProgress: Bool = false
    @Published var initiationPlayitStatus: InitiationTransportStatus = .notApplicable
    @Published var initiationBroadcastStatus: InitiationTransportStatus = .notApplicable
    /// Gamertag captured live from the broadcast auth line during initiation.
    /// Transient (not persisted to the server config — auto-fill is deferred).
    @Published var initiationBroadcastGamertag: String? = nil

    /// After a successful Xbox broadcast sign-in, offers to save the gamertag to
    /// the server's broadcast profile (for alt/dummy accounts the user may forget).
    @Published var pendingBroadcastGamertagSave: BroadcastGamertagSavePrompt?
    /// Servers for which the user declined the save prompt this session (don't re-nag).
    var broadcastGamertagSaveDeclinedServerIds: Set<String> = []
    /// Stashed during initiation (where the save sheet is suppressed) so we can offer
    /// it right after the completion sheet is dismissed.
    var pendingInitiationGamertagSave: BroadcastGamertagSavePrompt?

    // MARK: - Welcome / onboarding

    @Published var isShowingConceptGuide: Bool = false
    @Published var isShowingServerHandbook: Bool = false

    // MARK: - Backups / World Slots

    @Published var backupItems: [BackupItem] = []
    @Published var backupsFolderSizeDisplay: String? = nil
    @Published var worldSlots: [WorldSlot] = []
    @Published var isWorldSlotsLoading: Bool = false

    // MARK: - Resource Packs

    @Published var installedResourcePacks: [InstalledResourcePack] = []
    @Published var isLoadingResourcePacks: Bool = false

    /// Bedrock packs managed through Geyser (for Bedrock/Xbox players on a Java server).
    @Published var geyserResourcePacks: [InstalledResourcePack] = []
    @Published var isGeyserAvailable: Bool = false

    /// HTTP server that hosts Java resource packs so connecting clients can download them.
    let resourcePackHostServer = ResourcePackHostServer()

    // MARK: - Session log

    @Published var sessionEvents: [SessionEvent] = []

    // MARK: - Player Profiles (Java Edition)

    @Published var playerProfiles: [PlayerProfile] = []
    @Published var isLoadingProfiles: Bool = false

    /// Friendly name of the world the currently shown player data belongs to.
    /// Player .dat / LevelDB data is read only from the active world, so this makes that explicit.
    @Published var activePlayerDataWorldName: String? = nil
    @Published var hiddenBedrockXUIDs: Set<String> = []
    @Published var hiddenJavaUUIDs: Set<String> = []

    /// Live in-game world time, polled from the running Java server via `/time query`.
    /// `worldTimeOfDayTicks` is 0–23999 (time of day); `worldDayNumber` is the day count.
    /// Both are nil when no live reading is available (use the level.dat fallback instead).
    @Published var worldTimeOfDayTicks: Int? = nil
    @Published var worldDayNumber: Int? = nil
    /// True while the values above are being refreshed from a running server.
    @Published var worldTimeIsLive: Bool = false
    /// Transient parse state: which `/time query` responses we're expecting next,
    /// in submission order (responses share the same "The time is X" text).
    var pendingTimeQueryKinds: [TimeQueryKind] = []

    enum TimeQueryKind { case gametime, daytime }

    /// Transient console-line waiters. Flush-consistent backups register a waiter
    /// here to await a save-confirmation line (e.g. Java "Saved the game", Bedrock
    /// "ready to be copied"); `handleServerOutputLine` — the single console
    /// observation point — feeds every line to them. Empty when no backup is pausing
    /// saves. See `waitForConsoleLine(timeout:matching:)` in AppViewModel+Backups.
    var consoleLineWaiters: [ConsoleLineWaiter] = []

    /// The player whose full-body render is featured in the Overview Players card.
    /// Drives the live health query so we only poll the one shown character.
    @Published var featuredPlayerName: String? = nil {
        didSet {
            // Drop the old player's health immediately so hearts don't linger.
            if oldValue != featuredPlayerName { featuredPlayerHealth = nil }
        }
    }
    /// Live current health (HP) of the featured player, from `/data get entity … Health`.
    /// nil when unavailable (offline / Bedrock / not yet polled).
    @Published var featuredPlayerHealth: Double? = nil

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
    /// Native VM Bedrock backend (Docker replacement). Selected over bedrockBackend
    /// when AppConfig.useVMBedrockBackend is true.
    let vmBedrockBackend = VMBedrockServerBackend()
    var activeBackend: ServerBackend?

    /// Open handle for the rolling `logs/latest.log` mirror of the Bedrock console.
    /// Bedrock (in the VM) streams only to the console and writes no log of its own,
    /// so the app mirrors it to disk — matching Java's `logs/` convention and making
    /// the Maintenance → Logs button meaningful for Bedrock servers.
    var bedrockLogHandle: FileHandle?

    let broadcastManager = XboxBroadcastProcessManager()
    let bedrockBroadcastManager = BedrockBroadcastManager()
    let playitAgentManager = PlayitAgentManager()

    static var sharedRemoteAPIServer: RemoteAPIServer?
    var remoteAPIServer: RemoteAPIServer?

    var autoBackupTimer: Timer?
    let logicalCoreCount: Int = ProcessInfo.processInfo.activeProcessorCount

    /// Per-server timestamps of auto-restart attempts. Used by the crash-loop guard to
    /// count how many times a server has been restarted in the rolling 10-minute window.
    /// Cleared on app launch; not persisted (the guard only matters within a session).
    var crashRestartTimestamps: [String: [Date]] = [:]

    private var auditLogger: AuditLogger?

    var shouldStartOnboardingAfterConceptGuide: Bool = false
    var shouldStartOnboardingAfterHandbook: Bool = false
    var shouldLaunchFirstRunEducationAfterInitialSetupDismiss: Bool = false

    // MARK: - Init

    init() {
        // Chain ConsoleManager's objectWillChange into AppViewModel's so SwiftUI
        // views that observe AppViewModel re-render whenever console state changes.
        console.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // (M4a) Wire save-failure callback before any code that may call save().
        // Fires at most once per session (guard is in ConfigManager). Routing via
        // callback keeps ConfigManager free of AppKit/SwiftUI imports.
        configManager.onSaveError = { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.logAppMessage("[Config] Save failed: \(error.localizedDescription)")
                // Surface via errorAlert directly — critical data-safety event, must
                // show regardless of the errorPopupsEnabled preference.
                self.errorAlert = AppError(
                    title: "Settings Save Failed",
                    message: "Your settings couldn't be saved to disk: \(error.localizedDescription)\n\nCheck available disk space and app permissions."
                )
            }
        }

        // (R3) If init detected a corrupt config file, surface a one-time alert.
        // corruptConfigCopyPath is "" when the copy attempt itself failed (sentinel).
        if let corruptPath = configManager.corruptConfigCopyPath {
            let message: String
            if corruptPath.isEmpty {
                message = "Your settings file was unreadable and has been replaced with defaults. The original file could not be preserved (check disk permissions)."
            } else {
                message = "Your settings file was unreadable and has been replaced with defaults.\n\nA copy of the original was saved to:\n\(corruptPath)"
            }
            configCorruptAlert = AppError(
                title: "Settings File Couldn't Be Read",
                message: message
            )
        }

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
                    if !t.isEmpty { map[t] = .admin(label: "owner-admin") }
                }
                for entry in cfg2.remoteAPISharedAccess {
                    guard !entry.isExpired else { continue }
                    let t = entry.token.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !t.isEmpty else { continue }
                    if let perms = entry.permissions {
                        map[t] = .named(label: entry.label, permissions: perms)
                    } else {
                        map[t] = (entry.role == "guest") ? .guest(label: entry.label) : .admin(label: entry.label)
                    }
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

            // GET /resourcepacks — list installed packs + Geyser packs for the active server.
            // Helper: build the response DTO from disk (pure, no self needed).
            let buildResourcePacksResponse: (_ serverDir: String, _ isJava: Bool) -> RemoteAPIServer.ResourcePacksResponseDTO = { serverDir, isJava in
                let packs = isJava
                    ? ResourcePackManager.listJavaPacks(serverDir: serverDir)
                    : ResourcePackManager.listBedrockPacks(serverDir: serverDir)
                let isGeyserAvail = isJava && ResourcePackManager.isGeyserInstalled(serverDir: serverDir)
                let geyserPacks = isGeyserAvail ? ResourcePackManager.listGeyserPacks(serverDir: serverDir) : []
                let props = isJava ? ServerPropertiesManager.readProperties(serverDir: serverDir) : [:]
                let activeUrl = props["resource-pack"]?.trimmingCharacters(in: .whitespacesAndNewlines)
                let requirePack = (props["require-resource-pack"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "") == "true"
                func dto(_ p: InstalledResourcePack, kind: String) -> RemoteAPIServer.ResourcePackItemDTO {
                    RemoteAPIServer.ResourcePackItemDTO(
                        id: p.id, name: p.name, fileName: p.fileName,
                        fileSizeDisplay: p.fileSizeDisplay,
                        packKind: kind, isActive: p.isActive, typeLabel: p.typeLabel
                    )
                }
                return RemoteAPIServer.ResourcePacksResponseDTO(
                    serverType: isJava ? "java" : "bedrock",
                    isJava: isJava,
                    packs: packs.map { dto($0, kind: isJava ? "java" : "bedrock") },
                    geyserPacks: geyserPacks.map { dto($0, kind: "geyser") },
                    isGeyserAvailable: isGeyserAvail,
                    activePackUrl: activeUrl.flatMap { $0.isEmpty ? nil : $0 },
                    requirePack: requirePack
                )
            }

            let resourcePacksProvider: () async -> RemoteAPIServer.ResourcePacksResponseDTO = { [weak self] in
                guard let self else { return RemoteAPIServer.ResourcePacksResponseDTO(serverType: "java", note: "not_available") }
                let result = await MainActor.run { () -> (String, Bool)? in
                    guard let server = self.selectedServer, let cfg = self.configServer(for: server) else { return nil }
                    return (cfg.serverDir, cfg.isJava)
                }
                guard let (serverDir, isJava) = result else {
                    return RemoteAPIServer.ResourcePacksResponseDTO(serverType: "java", note: "no_active_server")
                }
                return buildResourcePacksResponse(serverDir, isJava)
            }

            // POST /resourcepacks/activate — set or clear the active Java pack (local file hosted by Mac).
            let activateResourcePackProvider: (String?, Bool) async -> RemoteAPIServer.ResourcePackMutationResultDTO = { [weak self] packId, require in
                guard let self else { return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: "not_available") }
                let state = await MainActor.run { () -> (String, String?, Int, Bool)? in
                    guard let server = self.selectedServer, let cfg = self.configServer(for: server), cfg.isJava else { return nil }
                    return (cfg.serverDir, self.resourcePackHostAddress(), cfg.resourcePackHostPort, true)
                }
                guard let (serverDir, hostAddr, port, _) = state else {
                    return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: "java_only")
                }
                if let packId {
                    let packs = ResourcePackManager.listJavaPacks(serverDir: serverDir)
                    guard let pack = packs.first(where: { $0.id == packId }) else {
                        return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: "pack_not_found")
                    }
                    guard let host = hostAddr, !host.isEmpty else {
                        return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: "no_host_address")
                    }
                    let sha1 = ResourcePackManager.sha1Hex(of: pack.fileURL)
                    let encoded = pack.fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pack.fileName
                    let url = "http://\(host):\(port)/\(encoded)"
                    await MainActor.run {
                        let dir = ResourcePackManager.javaPacksDirectory(serverDir: serverDir)
                        self.resourcePackHostServer.start(directory: dir, port: UInt16(port))
                    }
                    do {
                        try ResourcePackManager.setJavaActivePack(url: url, sha1: sha1, require: require, serverDir: serverDir)
                        await MainActor.run { self.logAppMessage("[ResourcePacks] Remote: activated \(pack.fileName).") }
                    } catch {
                        return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: error.localizedDescription)
                    }
                } else {
                    do {
                        try ResourcePackManager.setJavaActivePack(url: nil, sha1: nil, require: false, serverDir: serverDir)
                        await MainActor.run { self.resourcePackHostServer.stop() }
                    } catch {
                        return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: error.localizedDescription)
                    }
                }
                await MainActor.run { self.loadResourcePacksForSelectedServer() }
                return RemoteAPIServer.ResourcePackMutationResultDTO(success: true, message: "ok",
                    updated: buildResourcePacksResponse(serverDir, true))
            }

            // POST /resourcepacks/seturl — write a custom URL directly to server.properties (iOS "add by URL").
            let setResourcePackURLProvider: (String, String?, Bool) async -> RemoteAPIServer.ResourcePackMutationResultDTO = { [weak self] url, sha1, require in
                guard let self else { return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: "not_available") }
                let state = await MainActor.run { () -> String? in
                    guard let server = self.selectedServer, let cfg = self.configServer(for: server), cfg.isJava else { return nil }
                    return cfg.serverDir
                }
                guard let serverDir = state else {
                    return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: "java_only")
                }
                do {
                    try ResourcePackManager.setJavaActivePack(url: url, sha1: sha1, require: require, serverDir: serverDir)
                    await MainActor.run { self.logAppMessage("[ResourcePacks] Remote: set custom URL \(url).") }
                } catch {
                    return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: error.localizedDescription)
                }
                await MainActor.run { self.loadResourcePacksForSelectedServer() }
                return RemoteAPIServer.ResourcePackMutationResultDTO(success: true, message: "ok",
                    updated: buildResourcePacksResponse(serverDir, true))
            }

            // POST /resourcepacks/toggle — enable or disable a Geyser pack.
            let toggleGeyserPackProvider: (String, Bool) async -> RemoteAPIServer.ResourcePackMutationResultDTO = { [weak self] packId, enabled in
                guard let self else { return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: "not_available") }
                let state = await MainActor.run { () -> (String, Bool)? in
                    guard let server = self.selectedServer, let cfg = self.configServer(for: server) else { return nil }
                    return (cfg.serverDir, cfg.isJava)
                }
                guard let (serverDir, isJava) = state else {
                    return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: "no_active_server")
                }
                let geyserPacks = ResourcePackManager.listGeyserPacks(serverDir: serverDir)
                guard let pack = geyserPacks.first(where: { $0.id == packId }) else {
                    return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: "pack_not_found")
                }
                do {
                    try ResourcePackManager.setGeyserPackEnabled(pack, enabled: enabled, serverDir: serverDir)
                    await MainActor.run { self.logAppMessage("[ResourcePacks] Remote: \(enabled ? "enabled" : "disabled") Geyser pack \(pack.fileName).") }
                } catch {
                    return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: error.localizedDescription)
                }
                await MainActor.run { self.loadResourcePacksForSelectedServer() }
                return RemoteAPIServer.ResourcePackMutationResultDTO(success: true, message: "ok",
                    updated: buildResourcePacksResponse(serverDir, isJava))
            }

            // POST /resourcepacks/remove — delete a pack from disk.
            let removeResourcePackProvider: (String, String) async -> RemoteAPIServer.ResourcePackMutationResultDTO = { [weak self] packId, packKind in
                guard let self else { return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: "not_available") }
                let state = await MainActor.run { () -> (String, Bool)? in
                    guard let server = self.selectedServer, let cfg = self.configServer(for: server) else { return nil }
                    return (cfg.serverDir, cfg.isJava)
                }
                guard let (serverDir, isJava) = state else {
                    return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: "no_active_server")
                }
                switch packKind {
                case "geyser":
                    let packs = ResourcePackManager.listGeyserPacks(serverDir: serverDir)
                    guard let pack = packs.first(where: { $0.id == packId }) else {
                        return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: "pack_not_found")
                    }
                    do { try ResourcePackManager.removeGeyserPack(pack, serverDir: serverDir) }
                    catch { return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: error.localizedDescription) }
                case "java":
                    let packs = ResourcePackManager.listJavaPacks(serverDir: serverDir)
                    guard let pack = packs.first(where: { $0.id == packId }) else {
                        return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: "pack_not_found")
                    }
                    do {
                        let wasActive = pack.isActive
                        try ResourcePackManager.removePack(pack, serverDir: serverDir, isJava: true)
                        if wasActive { await MainActor.run { self.resourcePackHostServer.stop() } }
                    } catch { return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: error.localizedDescription) }
                case "bedrock":
                    let packs = ResourcePackManager.listBedrockPacks(serverDir: serverDir)
                    guard let pack = packs.first(where: { $0.id == packId }) else {
                        return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: "pack_not_found")
                    }
                    do { try ResourcePackManager.removePack(pack, serverDir: serverDir, isJava: false) }
                    catch { return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: error.localizedDescription) }
                default:
                    return RemoteAPIServer.ResourcePackMutationResultDTO(success: false, message: "invalid_kind")
                }
                await MainActor.run { self.loadResourcePacksForSelectedServer() }
                return RemoteAPIServer.ResourcePackMutationResultDTO(success: true, message: "ok",
                    updated: buildResourcePacksResponse(serverDir, isJava))
            }

            // GET /settings — typed server.properties schema for the active server.
            let settingsProvider: () -> RemoteAPIServer.SettingsResponseDTO = { [weak self] in
                guard let self else {
                    return RemoteAPIServer.SettingsResponseDTO(serverType: "java", serverName: "", serverRunning: false, editable: false, sections: [], note: "not_available")
                }
                let work: () -> RemoteAPIServer.SettingsResponseDTO = {
                    let cfg = self.configManager.config
                    guard let server = cfg.servers.first(where: { $0.id == cfg.activeServerId }) else {
                        return RemoteAPIServer.SettingsResponseDTO(serverType: "java", serverName: "", serverRunning: false, editable: false, sections: [], note: "no_active_server")
                    }
                    if server.isBedrock {
                        let model = self.bedrockPropertiesModel(for: server)
                        return RemoteAPIServer.SettingsResponseDTO(
                            serverType: server.serverType.rawValue,
                            serverName: server.displayName,
                            serverRunning: self.isServerRunning,
                            editable: true,
                            sections: ServerSettingsSchema.bedrockSections(from: model)
                        )
                    }
                    let model = self.loadServerPropertiesModel(for: server)
                    return RemoteAPIServer.SettingsResponseDTO(
                        serverType: server.serverType.rawValue,
                        serverName: server.displayName,
                        serverRunning: self.isServerRunning,
                        editable: true,
                        sections: ServerSettingsSchema.javaSections(from: model)
                    )
                }
                if Thread.isMainThread { return work() }
                return DispatchQueue.main.sync { work() }
            }

            // POST /settings — apply a sparse change set to the active Java server.
            let updateSettingsProvider: ([String: String]) -> RemoteAPIServer.SettingsUpdateResultDTO = { [weak self] changes in
                guard let self else {
                    return RemoteAPIServer.SettingsUpdateResultDTO(success: false, message: "not_available", restartRequired: false, appliedKeys: [])
                }
                let work: () -> RemoteAPIServer.SettingsUpdateResultDTO = {
                    let cfg = self.configManager.config
                    guard let server = cfg.servers.first(where: { $0.id == cfg.activeServerId }) else {
                        return RemoteAPIServer.SettingsUpdateResultDTO(success: false, message: "no_active_server", restartRequired: false, appliedKeys: [])
                    }
                    if server.isBedrock {
                        var model = self.bedrockPropertiesModel(for: server)
                        let (applied, rejected) = ServerSettingsSchema.applyBedrock(changes: changes, onto: &model)
                        let rejectedOut = rejected.isEmpty ? nil : rejected
                        guard !applied.isEmpty else {
                            let sections = ServerSettingsSchema.bedrockSections(from: self.bedrockPropertiesModel(for: server))
                            return RemoteAPIServer.SettingsUpdateResultDTO(success: false, message: "no_valid_changes", restartRequired: self.isServerRunning, appliedKeys: [], rejected: rejectedOut, sections: sections)
                        }
                        do {
                            try self.saveBedrockPropertiesModel(model, for: server)
                            let sections = ServerSettingsSchema.bedrockSections(from: self.bedrockPropertiesModel(for: server))
                            let msg = rejected.isEmpty ? "saved" : "saved_with_rejections"
                            self.logAppMessage("[Settings] (remote) Applied \(applied.count) change(s) to \(server.displayName)\(rejected.isEmpty ? "" : "; \(rejected.count) rejected").")
                            return RemoteAPIServer.SettingsUpdateResultDTO(success: true, message: msg, restartRequired: self.isServerRunning, appliedKeys: applied, rejected: rejectedOut, sections: sections)
                        } catch {
                            return RemoteAPIServer.SettingsUpdateResultDTO(success: false, message: error.localizedDescription, restartRequired: self.isServerRunning, appliedKeys: [], rejected: rejectedOut)
                        }
                    }
                    var model = self.loadServerPropertiesModel(for: server)
                    let (applied, rejected) = ServerSettingsSchema.applyJava(changes: changes, onto: &model)
                    let rejectedOut = rejected.isEmpty ? nil : rejected
                    guard !applied.isEmpty else {
                        // Nothing valid changed — report but don't touch the file.
                        let sections = ServerSettingsSchema.javaSections(from: self.loadServerPropertiesModel(for: server))
                        return RemoteAPIServer.SettingsUpdateResultDTO(success: false, message: "no_valid_changes", restartRequired: self.isServerRunning, appliedKeys: [], rejected: rejectedOut, sections: sections)
                    }
                    do {
                        try self.saveServerPropertiesModel(model, for: server)
                        // Re-read from disk so the echoed schema reflects clamped/merged ground truth.
                        let sections = ServerSettingsSchema.javaSections(from: self.loadServerPropertiesModel(for: server))
                        let msg = rejected.isEmpty ? "saved" : "saved_with_rejections"
                        self.logAppMessage("[Settings] (remote) Applied \(applied.count) change(s) to \(server.displayName)\(rejected.isEmpty ? "" : "; \(rejected.count) rejected").")
                        return RemoteAPIServer.SettingsUpdateResultDTO(success: true, message: msg, restartRequired: self.isServerRunning, appliedKeys: applied, rejected: rejectedOut, sections: sections)
                    } catch {
                        return RemoteAPIServer.SettingsUpdateResultDTO(success: false, message: error.localizedDescription, restartRequired: self.isServerRunning, appliedKeys: [], rejected: rejectedOut)
                    }
                }
                if Thread.isMainThread { return work() }
                return DispatchQueue.main.sync { work() }
            }

            // GET /backups/config — current schedule + retention for the active server.
            let backupConfigProvider: () -> RemoteAPIServer.BackupConfigResponseDTO = { [weak self] in
                guard let self else {
                    return RemoteAPIServer.BackupConfigResponseDTO(serverName: "", autoBackupEnabled: false, autoBackupIntervalMinutes: 30, autoBackupMaxCount: 12, note: "not_available")
                }
                let work: () -> RemoteAPIServer.BackupConfigResponseDTO = {
                    let cfg = self.configManager.config
                    guard let server = cfg.servers.first(where: { $0.id == cfg.activeServerId }) else {
                        return RemoteAPIServer.BackupConfigResponseDTO(serverName: "", autoBackupEnabled: false, autoBackupIntervalMinutes: 30, autoBackupMaxCount: 12, note: "no_active_server")
                    }
                    return RemoteAPIServer.BackupConfigResponseDTO(
                        serverName: server.displayName,
                        autoBackupEnabled: server.autoBackupEnabled,
                        autoBackupIntervalMinutes: server.autoBackupIntervalMinutes,
                        autoBackupMaxCount: server.autoBackupMaxCount
                    )
                }
                if Thread.isMainThread { return work() }
                return DispatchQueue.main.sync { work() }
            }

            // POST /backups/config — apply sparse backup schedule changes to the active server.
            let updateBackupConfigProvider: (_ enabled: Bool?, _ intervalMinutes: Int?, _ maxCount: Int?) -> RemoteAPIServer.BackupConfigUpdateResultDTO = { [weak self] enabled, intervalMinutes, maxCount in
                guard let self else {
                    return RemoteAPIServer.BackupConfigUpdateResultDTO(success: false, message: "not_available")
                }
                let work: () -> RemoteAPIServer.BackupConfigUpdateResultDTO = {
                    let cfg = self.configManager.config
                    guard let server = cfg.servers.first(where: { $0.id == cfg.activeServerId }) else {
                        return RemoteAPIServer.BackupConfigUpdateResultDTO(success: false, message: "no_active_server")
                    }
                    if let enabled { self.setAutoBackupEnabled(enabled, for: server.id) }
                    if let intervalMinutes {
                        let clamped = [15, 30, 45, 60, 120, 240, 360].contains(intervalMinutes) ? intervalMinutes : 30
                        self.setAutoBackupInterval(clamped, for: server.id)
                    }
                    if let maxCount { self.setAutoBackupMaxCount(Swift.max(3, Swift.min(50, maxCount)), for: server.id) }
                    let fresh = self.configManager.config.servers.first(where: { $0.id == server.id })
                    let echoDTO = RemoteAPIServer.BackupConfigResponseDTO(
                        serverName: server.displayName,
                        autoBackupEnabled: fresh?.autoBackupEnabled ?? server.autoBackupEnabled,
                        autoBackupIntervalMinutes: fresh?.autoBackupIntervalMinutes ?? server.autoBackupIntervalMinutes,
                        autoBackupMaxCount: fresh?.autoBackupMaxCount ?? server.autoBackupMaxCount
                    )
                    self.logAppMessage("[Backup] (remote) Config updated for \(server.displayName).")
                    return RemoteAPIServer.BackupConfigUpdateResultDTO(success: true, message: "saved", config: echoDTO)
                }
                if Thread.isMainThread { return work() }
                return DispatchQueue.main.sync { work() }
            }

            let listUsersProvider: () async -> RemoteAPIServer.UserListResponseDTO = { [weak self] in
                guard let self else { return RemoteAPIServer.UserListResponseDTO(users: []) }
                let entries = self.configManager.config.remoteAPISharedAccess
                let dtos = entries.map { e in
                    RemoteAPIServer.UserSummaryDTO(
                        id: e.id, label: e.label, role: e.role,
                        permissions: e.permissions,
                        createdAtISO8601: e.createdAtISO8601,
                        expiresAtISO8601: e.expiresAtISO8601,
                        isExpired: e.isExpired
                    )
                }
                return RemoteAPIServer.UserListResponseDTO(users: dtos)
            }

            let createUserProvider: (_ label: String, _ role: String, _ permissions: [String]?, _ expiresInDays: Int?) async -> RemoteAPIServer.UserCreateResultDTO = { [weak self] label, role, permissions, expiresInDays in
                guard let self else { return RemoteAPIServer.UserCreateResultDTO(success: false, message: "not_available") }
                let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return RemoteAPIServer.UserCreateResultDTO(success: false, message: "label_empty") }
                let rawToken = UUID().uuidString + UUID().uuidString.replacingOccurrences(of: "-", with: "")
                let entry = RemoteAPISharedAccessEntry.make(
                    label: trimmed, token: rawToken, role: role,
                    permissions: permissions, expiresInDays: expiresInDays
                )
                await MainActor.run {
                    self.configManager.config.remoteAPISharedAccess.append(entry)
                    self.configManager.save()
                }
                let dto = RemoteAPIServer.UserSummaryDTO(
                    id: entry.id, label: entry.label, role: entry.role,
                    permissions: entry.permissions,
                    createdAtISO8601: entry.createdAtISO8601,
                    expiresAtISO8601: entry.expiresAtISO8601,
                    isExpired: false
                )
                return RemoteAPIServer.UserCreateResultDTO(success: true, message: "created", user: dto, token: rawToken)
            }

            let revokeUserProvider: (_ userId: String) async -> RemoteAPIServer.UserRevokeResultDTO = { [weak self] userId in
                guard let self else { return RemoteAPIServer.UserRevokeResultDTO(success: false, message: "not_available") }
                let found = await MainActor.run { () -> Bool in
                    let before = self.configManager.config.remoteAPISharedAccess.count
                    self.configManager.config.remoteAPISharedAccess.removeAll { $0.id == userId }
                    if self.configManager.config.remoteAPISharedAccess.count < before {
                        self.configManager.save()
                        return true
                    }
                    return false
                }
                return found
                    ? RemoteAPIServer.UserRevokeResultDTO(success: true, message: "revoked")
                    : RemoteAPIServer.UserRevokeResultDTO(success: false, message: "not_found")
            }

            let updateUserProvider: (_ userId: String, _ label: String?, _ role: String?, _ permissions: [String]?, _ expiresInDays: Int?) async -> RemoteAPIServer.UserUpdateResultDTO = { [weak self] userId, label, role, permissions, expiresInDays in
                guard let self else { return RemoteAPIServer.UserUpdateResultDTO(success: false, message: "not_available") }
                if let l = label, l.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return RemoteAPIServer.UserUpdateResultDTO(success: false, message: "label_empty")
                }
                let result: RemoteAPIServer.UserUpdateResultDTO = await MainActor.run {
                    guard let idx = self.configManager.config.remoteAPISharedAccess.firstIndex(where: { $0.id == userId }) else {
                        return RemoteAPIServer.UserUpdateResultDTO(success: false, message: "not_found")
                    }
                    var e = self.configManager.config.remoteAPISharedAccess[idx]
                    if let l = label { e.label = l.trimmingCharacters(in: .whitespacesAndNewlines) }
                    if let r = role { e.role = r }
                    if let p = permissions { e.permissions = p }
                    if let days = expiresInDays {
                        if days < 0 {
                            e.expiresAtISO8601 = nil
                        } else {
                            let fmt = ISO8601DateFormatter()
                            e.expiresAtISO8601 = Calendar.current.date(byAdding: .day, value: days, to: Date()).map { fmt.string(from: $0) }
                        }
                    }
                    self.configManager.config.remoteAPISharedAccess[idx] = e
                    self.configManager.save()
                    let dto = RemoteAPIServer.UserSummaryDTO(
                        id: e.id, label: e.label, role: e.role,
                        permissions: e.permissions,
                        createdAtISO8601: e.createdAtISO8601,
                        expiresAtISO8601: e.expiresAtISO8601,
                        isExpired: e.isExpired
                    )
                    return RemoteAPIServer.UserUpdateResultDTO(success: true, message: "updated", user: dto)
                }
                return result
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

            // POST /worlds/create — create a fresh (empty) named slot that generates on first activation.
            // Non-destructive: does not touch the live world, so it is allowed while running.
            // Create the audit logger once; both API branches share it.
            if self.auditLogger == nil {
                let al = AuditLogger(logger: { [weak self] msg in
                    Task { @MainActor [weak self] in self?.logAppMessage(msg) }
                })
                self.auditLogger = al
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
                shared.renameServerProvider = renameServerProvider
                shared.deleteServerProvider = deleteServerProvider
                shared.templatesProvider = templatesProvider
                shared.templateMutationProvider = templateMutationProvider
                shared.serverImportScanProvider = serverImportScanProvider
                shared.serverImportProvider = serverImportProvider
                shared.resourcePacksProvider = resourcePacksProvider
                shared.activateResourcePackProvider = activateResourcePackProvider
                shared.setResourcePackURLProvider = setResourcePackURLProvider
                shared.toggleGeyserPackProvider = toggleGeyserPackProvider
                shared.removeResourcePackProvider = removeResourcePackProvider
                shared.settingsProvider = settingsProvider
                shared.updateSettingsProvider = updateSettingsProvider
                shared.backupConfigProvider = backupConfigProvider
                shared.updateBackupConfigProvider = updateBackupConfigProvider
                shared.listUsersProvider = listUsersProvider
                shared.createUserProvider = createUserProvider
                shared.revokeUserProvider = revokeUserProvider
                shared.updateUserProvider = updateUserProvider
                shared.auditLogger = self.auditLogger
                self.wireProviders(into: shared, isoFmt: isoFmt)
#if DEBUG
                // M2: Verify additive providers were wired in this branch before starting.
                // Called on the main thread so providers use the Thread.isMainThread fast-path.
                shared.assertProviderWiringComplete()
#endif
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
            api.renameServerProvider = renameServerProvider
            api.deleteServerProvider = deleteServerProvider
            api.templatesProvider = templatesProvider
            api.templateMutationProvider = templateMutationProvider
            api.serverImportScanProvider = serverImportScanProvider
            api.serverImportProvider = serverImportProvider
            api.resourcePacksProvider = resourcePacksProvider
            api.activateResourcePackProvider = activateResourcePackProvider
            api.setResourcePackURLProvider = setResourcePackURLProvider
            api.toggleGeyserPackProvider = toggleGeyserPackProvider
            api.removeResourcePackProvider = removeResourcePackProvider
            api.settingsProvider = settingsProvider
            api.updateSettingsProvider = updateSettingsProvider
            api.backupConfigProvider = backupConfigProvider
            api.updateBackupConfigProvider = updateBackupConfigProvider
            api.listUsersProvider = listUsersProvider
            api.createUserProvider = createUserProvider
            api.revokeUserProvider = revokeUserProvider
            api.updateUserProvider = updateUserProvider
            api.auditLogger = self.auditLogger
            self.wireProviders(into: api, isoFmt: isoFmt)
#if DEBUG
            // M2: Verify additive providers were wired in this branch before starting.
            // Called on the main thread so providers use the Thread.isMainThread fast-path.
            api.assertProviderWiringComplete()
#endif
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
            stageConceptGuideThenTourIfNeeded()
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
                // Capture initiation state BEFORE resetAfterTermination() clears it.
                let initiation = self.captureInitiationTerminationContext()
                self.isServerRunning = false
                self.closeBedrockLogFile()
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
                if !wasUserRequestedStop {
                    // Diagnose: present the mod-problems sheet (modded hard fail) or a
                    // generic alert; also writes last_startup_result + refreshes cards.
                    self.diagnoseUnexpectedStop(reachedReadyState: reachedReadyState)
                    // Auto-restart (opt-in, crash-loop guarded). Skip during initiation passes —
                    // pass1ServerId != nil means any initiation (even one that crashed early).
                    let isInitiationPass = initiation.pass1ServerId != nil || initiation.pass2JustEnded
                    if !isInitiationPass, let server = self.selectedServer, let cfg = self.configServer(for: server) {
                        self.scheduleAutoRestartIfNeeded(for: cfg)
                    }
                } else {
                    if !reachedReadyState, let server = self.selectedServer, let cfg = self.configServer(for: server) {
                        self.writeLastStartupResult(for: cfg, wasClean: false, fatalErrors: ["Server stopped before reaching ready state."], warnings: [])
                    }
                    self.refreshHealthCardsForSelectedServer()
                }
                self.logAppMessage("[App] Server process ended.")
                if let server = self.selectedServer, let cfg = self.configServer(for: server) {
                    self.createInitialWorldSlotIfNeeded(for: cfg)
                }
                self.routeInitiationAfterTermination(initiation)
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
                // Capture initiation state BEFORE resetAfterTermination() clears it.
                let initiation = self.captureInitiationTerminationContext()
                self.isServerRunning = false
                self.closeBedrockLogFile()
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
                                    // Auto-restart (opt-in, crash-loop guarded).
                                    let isInitiationPass = initiation.pass1ServerId != nil || initiation.pass2JustEnded
                                    if !isInitiationPass, let server = self.selectedServer, let cfg = self.configServer(for: server) {
                                        self.scheduleAutoRestartIfNeeded(for: cfg)
                                    }
                                }
                                self.logAppMessage("[App] Bedrock container stopped.")
                                if let server = self.selectedServer, let cfg = self.configServer(for: server) {
                                    self.createInitialWorldSlotIfNeeded(for: cfg)
                                }
                                self.routeInitiationAfterTermination(initiation)
                            }
                        }

        // The VM Bedrock backend reuses the exact same output/termination handlers
        // as the Docker Bedrock backend — identical lifecycle handling either way.
        vmBedrockBackend.onOutputLine = bedrockBackend.onOutputLine
        vmBedrockBackend.onDidTerminate = bedrockBackend.onDidTerminate

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
                self.logAppMessage("[BroadcastBDS] Broadcast stopped.")
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

    // MARK: - Broadcast auth deferred presentation

    /// True when any sheet/modal is currently presented in the app.
    /// Used to gate broadcast auth so it never interrupts another flow.
    var isAnyModalPresented: Bool {
        isShowingPlayitSecretSetup  ||
        isShowingStartupProblems    ||
        isShowingInitialSetup       ||
        isShowingConceptGuide       ||
        isShowingServerHandbook     ||
        isShowingPreferences        ||
        isShowingRouterPortForwardGuide ||
        isShowingCrossPlatformGuide ||
        contentViewSheetIsPresented ||
        pendingBroadcastAuthPrompt != nil
    }

    private var queuedBroadcastAuthPrompt: BroadcastAuthPrompt?
    private var broadcastAuthPresentTimer: Timer?

    /// Present the broadcast auth sheet now if no other modal is up, otherwise queue it
    /// and retry every 0.5 s until the coast is clear.
    func enqueueBroadcastAuthPrompt(_ prompt: BroadcastAuthPrompt) {
        if !isAnyModalPresented {
            pendingBroadcastAuthPrompt = prompt
        } else {
            queuedBroadcastAuthPrompt = prompt
            guard broadcastAuthPresentTimer == nil else { return }
            broadcastAuthPresentTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }
                guard !self.isAnyModalPresented else { return }
                self.pendingBroadcastAuthPrompt = self.queuedBroadcastAuthPrompt
                self.queuedBroadcastAuthPrompt = nil
                timer.invalidate()
                self.broadcastAuthPresentTimer = nil
            }
        }
    }

    // MARK: - Simple Voice Chat prompt checks

    /// Evaluates the Flow 1 mismatch: SVC installed + playit on + voice tunnel off + not dismissed.
    /// Call after server selection changes or after voice chat / playit settings change.
    func checkSVCTunnelMismatch() {
        guard let cfg = selectedServerConfig else {
            pendingSVCTunnelMismatch = nil
            return
        }
        guard cfg.playitEnabled,
              !cfg.playitVoiceChatEnabled,
              !cfg.svcTunnelPromptDismissed,
              VoiceChatConfigManager.isInstalled(serverDir: cfg.serverDir) else {
            pendingSVCTunnelMismatch = nil
            return
        }
        pendingSVCTunnelMismatch = SVCTunnelMismatchAlert(serverId: cfg.id)
    }

    /// Clears both SVC prompt preferences for a server (call when SVC is disabled/removed).
    func clearSVCPromptPrefs(for serverId: String) {
        guard let idx = configManager.config.servers.firstIndex(where: { $0.id == serverId }) else { return }
        configManager.config.servers[idx].svcTunnelPromptDismissed   = false
        configManager.config.servers[idx].svcPortForwardingConfirmed = false
        configManager.save()
    }

    func logAppMessage(_ msg: String) {
        let ts = AppUtilities.timestampString()
        let line = "[\(ts)] \(msg)"
        console.appendRaw(line, source: .controller)
        remoteAPIServer?.publishConsoleLine(source: "app", text: line)
    }

    /// Buffer of formatted console lines emitted while creating a server. Selecting
    /// the new server clears the console, so these are replayed afterwards so the
    /// creation/install output (e.g. NeoForge) survives into the new server's console.
    var pendingCreationConsole: [String] = []

    /// Live-observable log of installer output during the current server creation.
    /// Populated by noteCreation; cleared when a new creation starts; shown in the wizard
    /// as a scrolling log for installStep flavors (NeoForge, Forge).
    @Published var creationLogLines: [String] = []

    /// Like `logAppMessage`, but also buffers the line for replay into the newly
    /// created server's console (see `replayCreationConsole`).
    func noteCreation(_ msg: String) {
        let ts = AppUtilities.timestampString()
        let line = "[\(ts)] \(msg)"
        console.appendRaw(line, source: .controller)
        remoteAPIServer?.publishConsoleLine(source: "app", text: line)
        pendingCreationConsole.append(line)
        creationLogLines.append(msg)
    }

    /// Replays buffered creation lines into the (now-selected) server's console.
    func replayCreationConsole() {
        guard !pendingCreationConsole.isEmpty else { return }
        for line in pendingCreationConsole {
            console.appendRaw(line, source: .controller)
        }
        pendingCreationConsole.removeAll()
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

extension AddonUpdateBucket {
    var remoteAPIString: String {
        switch self {
        case .updateAvailable:     return "updateAvailable"
        case .upToDate:            return "upToDate"
        case .noCompatibleVersion: return "noCompatibleVersion"
        case .unlinked:            return "unlinked"
        }
    }
}

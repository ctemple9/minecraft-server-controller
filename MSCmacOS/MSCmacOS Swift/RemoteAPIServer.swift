//
//  RemoteAPIServer.swift
//  MinecraftServerController
//
//  Local HTTP/WebSocket API used by the companion iOS app.
//
//  Provides authenticated endpoints for process control, server selection, status, performance snapshots,
//  and a console tail (HTTP + WebSocket streaming).
//

import Foundation
import Darwin

/// A small, self-hosted HTTP/WebSocket server used for local remote control.
///
/// The server is designed to be lightweight and dependency-free, and supports optional binding to
/// all interfaces when explicitly enabled in preferences.
final class RemoteAPIServer {

    // MARK: - DTOs / wire formats moved to RemoteAPIServerDTOs.swift

    // MARK: - Internals

    enum ClientMode {
        case http
        case webSocket
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private let queue = DispatchQueue(label: "RemoteAPIServer.queue")

    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?

    private var clientSources: [Int32: DispatchSourceRead] = [:]
    var clientBuffers: [Int32: Data] = [:]
    var clientModes: [Int32: ClientMode] = [:]

    var clientIPs: [Int32: String] = [:]

    // Hardening limits
    static let maxRequestHeaderBytes: Int = 16 * 1024
    static let maxRequestBodyBytes: Int = 64 * 1024
    static let maxWebSocketClientFrameBytes: Int = 64 * 1024

    // POST rate limiting (kept on `queue`)
    private struct FixedWindowCounter {
        var windowStart: TimeInterval
        var count: Int
    }
    private var postRateLimitByIP: [String: FixedWindowCounter] = [:]
    private var postRateLimitLastPrune: TimeInterval = 0
    private let postRateLimitMax: Int = 10
    private let postRateLimitWindowSeconds: TimeInterval = 5.0

    static let rateLimitedPOSTPaths: Set<String> = ["/command", "/start", "/stop", "/active-server", "/servers/rename", "/servers/delete", "/servers/import", "/templates", "/players/skin-override", "/players/hidden", "/components/update", "/components/remove", "/components/install", "/components/version", "/allowlist", "/settings", "/backups/config", "/resourcepacks/activate", "/resourcepacks/seturl", "/resourcepacks/toggle", "/resourcepacks/remove", "/worlds/create", "/worlds/rename", "/worlds/replace", "/worlds/repair", "/health/repair", "/playit/start", "/playit/stop", "/duckdns", "/config/geyser", "/users", "/users/revoke", "/users/update"]

    // Console ring buffer (kept on `queue`)
    var consoleBuffer: [ConsoleLineDTO] = []
    private let consoleBufferLimit: Int = 5000

    private let port: UInt16
    private var listenOnAllInterfaces: Bool

    // MARK: - Token roles

    enum TokenRole {
        case admin
        case guest
        /// Permission-scoped named token. Only the listed permission categories are granted.
        case named(label: String, permissions: [String])
    }

    // Providers can change (Preferences updates), so these must be mutable.
    var tokenProvider: () -> [String: TokenRole]
    var serversProvider: () -> [Server]
    var statusProvider: () -> RemoteAPIStatus
    var performanceProvider: () -> PerformanceSnapshotDTO
    var startProvider: () -> Void
    var stopProvider: () -> Void
    var commandProvider: (String) -> Void
    var setActiveServerProvider: (String) -> Bool

    var playersProvider: () -> PlayersResponseDTO
    var allowlistProvider: () -> AllowlistResponseDTO
    var sessionLogProvider: () -> SessionLogResponseDTO
    var configServersProvider: () -> [ConfigServer]
    var serverConnectionInfoProvider: (String) -> ServerConnectionInfoDTO?
    var renameServerProvider: (_ serverId: String, _ name: String) async -> ServerRenameResultDTO = { _, _ in
        ServerRenameResultDTO(success: false, message: "not_available")
    }
    var deleteServerProvider: (_ serverId: String) async -> ServerDeleteResultDTO = { _ in
        ServerDeleteResultDTO(success: false, message: "not_available")
    }
    var templatesProvider: () async -> TemplatesResponseDTO = {
        TemplatesResponseDTO(note: "not_available")
    }
    var templateMutationProvider: (_ request: TemplateMutationRequestDTO) async -> TemplateMutationResultDTO = { _ in
        TemplateMutationResultDTO(success: false, message: "not_available")
    }
    var serverImportScanProvider: (_ request: ServerImportRequestDTO) async -> ServerImportScanResponseDTO = { _ in
        ServerImportScanResponseDTO(success: false, message: "not_available")
    }
    var serverImportProvider: (_ request: ServerImportRequestDTO) async -> ServerImportResultDTO = { _ in
        ServerImportResultDTO(success: false, message: "not_available")
    }
    var componentsProvider: () async -> ComponentsStatusDTO
    var updateComponentProvider: (String, @escaping (ComponentUpdateResultDTO) -> Void) -> Void
    var broadcastStatusProvider: () -> BroadcastStatusDTO
    var restartBroadcastProvider: () -> Void
    var startBroadcastProvider: () -> Void
    var stopBroadcastProvider: () -> Void
    var updateBroadcastCredentialsProvider: (BroadcastCredentialsDTO) -> Bool
    var watchdogStatusProvider:  () -> Bool     = { false }
    var enableWatchdogProvider:  () -> String?  = { nil }   // nil = success, non-nil = error message
    var disableWatchdogProvider: () -> String?  = { nil }

    var playerProfilesProvider:    () -> PlayerProfilesResponseDTO = { PlayerProfilesResponseDTO(profiles: [], isLoadingStats: false) }
    var playerSkinProvider: (_ profileId: String) async -> PlayerSkinResponseDTO = { _ in
        PlayerSkinResponseDTO(success: false, message: "not_available")
    }
    var playerSkinOverrideProvider: (_ profileId: String, _ lookupIdentifier: String?) async -> PlayerSkinOverrideResultDTO = { profileId, _ in
        PlayerSkinOverrideResultDTO(success: false, message: "not_available", profileId: profileId, lookupIdentifier: nil)
    }
    var hiddenProfileProvider: (_ profileId: String, _ hidden: Bool) async -> HiddenProfileMutationResultDTO = { profileId, hidden in
        HiddenProfileMutationResultDTO(success: false, message: "not_available", profileId: profileId, isHidden: hidden)
    }
    var filesProvider: (_ path: String?) async -> ServerFilesResponseDTO = { _ in
        ServerFilesResponseDTO(note: "not_available")
    }
    var fileReadProvider: (_ path: String) async -> ServerFileReadResponseDTO = { _ in
        ServerFileReadResponseDTO(success: false, message: "not_available")
    }
    var clientExportProvider: (_ selectedIds: [String]?) async -> ClientExportResponseDTO = { _ in
        ClientExportResponseDTO(note: "not_available")
    }

    /// Mutates the active Bedrock server's allowlist. `action` is "add" or "remove".
    /// Returns the freshly-read list so callers stay in sync in one round-trip.
    /// Defaulted (additive) so older wiring compiles unchanged.
    var mutateAllowlistProvider: (_ action: String, _ name: String) -> AllowlistMutationResultDTO = { _, _ in
        AllowlistMutationResultDTO(success: false, message: "not_available", serverType: "java", entries: [])
    }

    /// Returns the current add-on update plan (Modrinth-tracked mods/plugins).
    var addonsProvider:       () async -> AddonsResponseDTO          = { AddonsResponseDTO(addons: [], isResolving: false, serverSupportsAddons: false) }
    /// Updates a specific add-on (jarStem) or all updatable add-ons (updateAll=true). Fire-and-forget.
    var updateAddonProvider:  (_ jarStem: String?, _ updateAll: Bool) -> AddonUpdateResultDTO = { _, _ in AddonUpdateResultDTO(result: "not_available", jarStem: nil, count: 0) }
    /// Removes an installed add-on by jarStem. Returns result after file deletion.
    var removeAddonProvider:  (_ jarStem: String) -> AddonRemoveResultDTO = { s in AddonRemoveResultDTO(success: false, message: "not_available", jarStem: s) }

    /// Searches the add-on catalog (Modrinth) for the active server's loader + version (GET /catalog/search).
    var catalogSearchProvider: (_ query: String, _ offset: Int) async -> CatalogSearchResponseDTO = { _, _ in
        CatalogSearchResponseDTO(supportsAddons: false, note: "not_available")
    }
    /// Installs the latest compatible version of a catalog add-on into the active server (POST /components/install).
    var installAddonProvider: (_ projectId: String, _ slug: String, _ title: String) async -> CatalogInstallResultDTO = { pid, _, _ in
        CatalogInstallResultDTO(success: false, message: "not_available", projectId: pid)
    }

    /// Available server JAR versions for the active server's flavor (GET /versions).
    var versionsProvider: () async -> VersionsResponseDTO = {
        VersionsResponseDTO(supportsVersions: false, note: "not_available")
    }
    /// Downloads / installs a chosen version for the active server (POST /components/version).
    var changeVersionProvider: (_ versionId: String, _ loaderVersion: String?) async -> VersionChangeResultDTO = { _, _ in
        VersionChangeResultDTO(success: false, message: "not_available", requiresRestart: false)
    }

    /// Lists installed resource packs for the active server (GET /resourcepacks).
    var resourcePacksProvider: () async -> ResourcePacksResponseDTO = {
        ResourcePacksResponseDTO(serverType: "java", note: "not_available")
    }
    /// Activates or clears the active Java resource pack (POST /resourcepacks/activate).
    var activateResourcePackProvider: (_ packId: String?, _ require: Bool) async -> ResourcePackMutationResultDTO = { _, _ in
        ResourcePackMutationResultDTO(success: false, message: "not_available")
    }
    /// Sets a custom URL as the active Java resource pack (POST /resourcepacks/seturl).
    var setResourcePackURLProvider: (_ url: String, _ sha1: String?, _ require: Bool) async -> ResourcePackMutationResultDTO = { _, _, _ in
        ResourcePackMutationResultDTO(success: false, message: "not_available")
    }
    /// Enables or disables a Geyser pack (POST /resourcepacks/toggle).
    var toggleGeyserPackProvider: (_ packId: String, _ enabled: Bool) async -> ResourcePackMutationResultDTO = { _, _ in
        ResourcePackMutationResultDTO(success: false, message: "not_available")
    }
    /// Removes a resource pack from disk (POST /resourcepacks/remove).
    var removeResourcePackProvider: (_ packId: String, _ packKind: String) async -> ResourcePackMutationResultDTO = { _, _ in
        ResourcePackMutationResultDTO(success: false, message: "not_available")
    }

    /// Typed server.properties schema for the active server (GET /settings).
    var settingsProvider:       () -> SettingsResponseDTO = {
        SettingsResponseDTO(serverType: "java", serverName: "", serverRunning: false, editable: false, sections: [], note: "not_available")
    }
    /// Applies a sparse set of setting changes to the active server (POST /settings).
    var updateSettingsProvider: (_ changes: [String: String]) -> SettingsUpdateResultDTO = { _ in
        SettingsUpdateResultDTO(success: false, message: "not_available", restartRequired: false, appliedKeys: [])
    }

    var worldSlotsProvider:        () -> WorldSlotsResponseDTO = { WorldSlotsResponseDTO(slots: [], activeSlotId: nil, serverRunning: false) }
    var activateWorldSlotProvider: (String) -> Bool            = { _ in false }
    // World management verbs (P9). All async (world I/O is slow) and echo fresh slot state.
    var createWorldSlotProvider:  (_ name: String, _ seed: String?) async -> WorldMutationResultDTO = { _, _ in
        WorldMutationResultDTO(success: false, message: "not_available")
    }
    var renameWorldSlotProvider:  (_ slotId: String, _ newName: String) async -> WorldMutationResultDTO = { _, _ in
        WorldMutationResultDTO(success: false, message: "not_available")
    }
    var replaceWorldSlotProvider: (_ slotId: String, _ sourceSlotId: String) async -> WorldMutationResultDTO = { _, _ in
        WorldMutationResultDTO(success: false, message: "not_available")
    }
    var repairWorldSlotProvider:  (_ slotId: String) async -> WorldMutationResultDTO = { _ in
        WorldMutationResultDTO(success: false, message: "not_available")
    }
    // Diagnostics (P10): health cards + startup-problem repair.
    var healthProvider: () async -> HealthResponseDTO = { HealthResponseDTO(serverType: "java", note: "not_available") }
    var healthProblemsProvider: () async -> HealthProblemsResponseDTO = { HealthProblemsResponseDTO(serverType: "java", note: "not_available") }
    var repairHealthProblemProvider: (_ problemId: String, _ action: String) async -> HealthRepairResultDTO = { _, _ in
        HealthRepairResultDTO(success: false, message: "not_available")
    }
    // Connectivity (P11): is the active server joinable right now?
    var connectivityProvider: () async -> ConnectivityResponseDTO = {
        ConnectivityResponseDTO(serverType: "java", status: "unknown", severity: "gray",
                                headline: "Connectivity unavailable", note: "not_available")
    }
    // Playit tunnel (P12)
    var playitStatusProvider: () async -> PlayitStatusResponseDTO = {
        PlayitStatusResponseDTO(serverName: "", serverType: "java", playitEnabled: false, isRunning: false, hasSecretKey: false, note: "not_available")
    }
    var startPlayitProvider: () async -> PlayitActionResultDTO = { PlayitActionResultDTO(result: "not_available") }
    var stopPlayitProvider:  () async -> PlayitActionResultDTO = { PlayitActionResultDTO(result: "not_available") }
    // DuckDNS (P13)
    var duckdnsStatusProvider: () async -> DuckDNSStatusResponseDTO = { DuckDNSStatusResponseDTO() }
    var updateDuckDNSProvider: (_ hostname: String?) async -> DuckDNSUpdateResultDTO = { _ in DuckDNSUpdateResultDTO(success: false, message: "not_available") }
    // Geyser config (P13)
    var geyserConfigProvider: () async -> GeyserConfigResponseDTO = { GeyserConfigResponseDTO(note: "not_available") }
    var updateGeyserConfigProvider: (_ address: String?, _ port: Int?) async -> GeyserConfigUpdateResultDTO = { _, _ in GeyserConfigUpdateResultDTO(success: false, message: "not_available") }
    var backupItemsProvider:       () -> BackupsResponseDTO    = { BackupsResponseDTO(backups: []) }
    var createBackupNowProvider:   () -> Void                  = { }
    var restoreBackupProvider:     (String) -> Bool            = { _ in false }
    var backupConfigProvider:      () -> BackupConfigResponseDTO = {
        BackupConfigResponseDTO(serverName: "", autoBackupEnabled: false, autoBackupIntervalMinutes: 30, autoBackupMaxCount: 12, note: "not_available")
    }
    var updateBackupConfigProvider: (_ enabled: Bool?, _ intervalMinutes: Int?, _ maxCount: Int?) -> BackupConfigUpdateResultDTO = { _, _, _ in
        BackupConfigUpdateResultDTO(success: false, message: "not_available")
    }

    // Named users / shared access (P17)
    var listUsersProvider:   () async -> UserListResponseDTO = {
        UserListResponseDTO(users: [])
    }
    var createUserProvider:  (_ label: String, _ role: String, _ permissions: [String]?, _ expiresInDays: Int?) async -> UserCreateResultDTO = { _, _, _, _ in
        UserCreateResultDTO(success: false, message: "not_available")
    }
    var revokeUserProvider:  (_ userId: String) async -> UserRevokeResultDTO = { _ in
        UserRevokeResultDTO(success: false, message: "not_available")
    }
    var updateUserProvider:  (_ userId: String, _ label: String?, _ role: String?, _ permissions: [String]?, _ expiresInDays: Int?) async -> UserUpdateResultDTO = { _, _, _, _, _ in
        UserUpdateResultDTO(success: false, message: "not_available")
    }

    var authPromptProvider: () -> BroadcastAuthPromptDTO
    var dismissAuthPromptProvider: () -> Void
    var broadcastAutoStartProvider: () -> BroadcastAutoStartDTO
    var setBroadcastAutoStartProvider: (Bool) -> Void
    private var logger: (String) -> Void

    init(
        port: UInt16,
        listenOnAllInterfaces: Bool,
        tokenProvider: @escaping () -> [String: TokenRole],
        serversProvider: @escaping () -> [Server],
        statusProvider: @escaping () -> RemoteAPIStatus,
        performanceProvider: @escaping () -> PerformanceSnapshotDTO,
        startProvider: @escaping () -> Void,
        stopProvider: @escaping () -> Void,
        commandProvider: @escaping (String) -> Void,
        setActiveServerProvider: @escaping (String) -> Bool,
        playersProvider: @escaping () -> PlayersResponseDTO,
        allowlistProvider: @escaping () -> AllowlistResponseDTO,
        sessionLogProvider: @escaping () -> SessionLogResponseDTO,
        configServersProvider: @escaping () -> [ConfigServer],
        serverConnectionInfoProvider: @escaping (String) -> ServerConnectionInfoDTO?,
        componentsProvider: @escaping () async -> ComponentsStatusDTO,
        updateComponentProvider: @escaping (String, @escaping (ComponentUpdateResultDTO) -> Void) -> Void,
        broadcastStatusProvider: @escaping () -> BroadcastStatusDTO,
        restartBroadcastProvider: @escaping () -> Void,
        startBroadcastProvider: @escaping () -> Void,
        stopBroadcastProvider: @escaping () -> Void,
        updateBroadcastCredentialsProvider: @escaping (BroadcastCredentialsDTO) -> Bool,
        authPromptProvider: @escaping () -> BroadcastAuthPromptDTO,
        dismissAuthPromptProvider: @escaping () -> Void,
        broadcastAutoStartProvider: @escaping () -> BroadcastAutoStartDTO,
        setBroadcastAutoStartProvider: @escaping (Bool) -> Void,
        logger: @escaping (String) -> Void
    ) {
        self.port = port
        self.listenOnAllInterfaces = listenOnAllInterfaces
        self.tokenProvider = tokenProvider
        self.serversProvider = serversProvider
        self.statusProvider = statusProvider
        self.performanceProvider = performanceProvider
        self.startProvider = startProvider
        self.stopProvider = stopProvider
        self.commandProvider = commandProvider
        self.setActiveServerProvider = setActiveServerProvider
        self.playersProvider = playersProvider
        self.allowlistProvider = allowlistProvider
        self.sessionLogProvider = sessionLogProvider
        self.configServersProvider = configServersProvider
        self.serverConnectionInfoProvider = serverConnectionInfoProvider
        self.componentsProvider = componentsProvider
        self.updateComponentProvider = updateComponentProvider
        self.broadcastStatusProvider = broadcastStatusProvider
        self.restartBroadcastProvider = restartBroadcastProvider
        self.startBroadcastProvider = startBroadcastProvider
        self.stopBroadcastProvider = stopBroadcastProvider
        self.updateBroadcastCredentialsProvider = updateBroadcastCredentialsProvider
        self.authPromptProvider = authPromptProvider
        self.dismissAuthPromptProvider = dismissAuthPromptProvider
        self.broadcastAutoStartProvider = broadcastAutoStartProvider
        self.setBroadcastAutoStartProvider = setBroadcastAutoStartProvider
        self.logger = logger
    }

    func updateProviders(
        tokenProvider: @escaping () -> [String: TokenRole],
        serversProvider: @escaping () -> [Server],
        statusProvider: @escaping () -> RemoteAPIStatus,
        performanceProvider: @escaping () -> PerformanceSnapshotDTO,
        startProvider: @escaping () -> Void,
        stopProvider: @escaping () -> Void,
        commandProvider: @escaping (String) -> Void,
        setActiveServerProvider: @escaping (String) -> Bool,
        playersProvider: @escaping () -> PlayersResponseDTO,
        allowlistProvider: @escaping () -> AllowlistResponseDTO,
        sessionLogProvider: @escaping () -> SessionLogResponseDTO,
        configServersProvider: @escaping () -> [ConfigServer],
        serverConnectionInfoProvider: @escaping (String) -> ServerConnectionInfoDTO?,
        componentsProvider: @escaping () async -> ComponentsStatusDTO,
        updateComponentProvider: @escaping (String, @escaping (ComponentUpdateResultDTO) -> Void) -> Void,
        broadcastStatusProvider: @escaping () -> BroadcastStatusDTO,
        restartBroadcastProvider: @escaping () -> Void,
        startBroadcastProvider: @escaping () -> Void,
        stopBroadcastProvider: @escaping () -> Void,
        updateBroadcastCredentialsProvider: @escaping (BroadcastCredentialsDTO) -> Bool,
        authPromptProvider: @escaping () -> BroadcastAuthPromptDTO,
        dismissAuthPromptProvider: @escaping () -> Void,
        broadcastAutoStartProvider: @escaping () -> BroadcastAutoStartDTO,
        setBroadcastAutoStartProvider: @escaping (Bool) -> Void,
        logger: @escaping (String) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            self.tokenProvider = tokenProvider
            self.serversProvider = serversProvider
            self.statusProvider = statusProvider
            self.performanceProvider = performanceProvider
            self.startProvider = startProvider
            self.stopProvider = stopProvider
            self.commandProvider = commandProvider
            self.setActiveServerProvider = setActiveServerProvider
            self.playersProvider = playersProvider
            self.allowlistProvider = allowlistProvider
            self.sessionLogProvider = sessionLogProvider
            self.configServersProvider = configServersProvider
            self.serverConnectionInfoProvider = serverConnectionInfoProvider
            self.componentsProvider = componentsProvider
            self.updateComponentProvider = updateComponentProvider
            self.broadcastStatusProvider = broadcastStatusProvider
            self.restartBroadcastProvider = restartBroadcastProvider
            self.startBroadcastProvider = startBroadcastProvider
            self.stopBroadcastProvider = stopBroadcastProvider
            self.updateBroadcastCredentialsProvider = updateBroadcastCredentialsProvider
            self.authPromptProvider = authPromptProvider
            self.dismissAuthPromptProvider = dismissAuthPromptProvider
            self.broadcastAutoStartProvider = broadcastAutoStartProvider
            self.setBroadcastAutoStartProvider = setBroadcastAutoStartProvider
            self.logger = logger
        }
    }

    /// Updates whether the server binds to localhost only or all interfaces (LAN/VPN).
    /// If the listener is currently running, this will restart it to apply the new bind address.
    func setListenOnAllInterfaces(_ enabled: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.listenOnAllInterfaces != enabled else { return }
            self.listenOnAllInterfaces = enabled

            if self.listenFD != -1 {
                self.stopInternal()
                self.startInternal()
            }
        }
    }

    // MARK: - Console buffer publishing

    func publishConsoleLine(source: String, text: String, level: String? = nil) {
        queue.async { [weak self] in
            guard let self else { return }

            let dto = ConsoleLineDTO(
                ts: Self.isoFormatter.string(from: Date()),
                source: source,
                level: level,
                text: text
            )

            self.consoleBuffer.append(dto)
            if self.consoleBuffer.count > self.consoleBufferLimit {
                let overflow = self.consoleBuffer.count - self.consoleBufferLimit
                self.consoleBuffer.removeFirst(overflow)
            }

            // Fan-out to websocket clients (best-effort)
            for (fd, mode) in self.clientModes {
                if case .webSocket = mode {
                    self.sendWebSocketJSON(dto, clientFD: fd)
                }
            }
        }
    }

    func clearConsoleBuffer() {
        queue.async { [weak self] in
            self?.consoleBuffer.removeAll()
        }
    }

    // MARK: - Public lifecycle

    func start() {
        queue.async { [weak self] in
            self?.startInternal()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopInternal()
        }
    }

    // MARK: - Internals

    private func log(_ message: String) {
        logger(message)
    }

    private func startInternal() {
#if DEBUG
        // Validate all four route-registry invariants on first start (pure Set checks,
        // no provider calls).  A failed assertion here means a POST path was added to one
        // registry but not the others — the fix is in RemoteAPIServer.swift /
        // RemoteAPIServer+HTTP.swift, not in the assertion.
        assertRegistryConsistency()
#endif
        if listenFD != -1 {
            let bindHost = listenOnAllInterfaces ? "0.0.0.0" : "127.0.0.1"
            let scope = listenOnAllInterfaces ? "LAN/VPN" : "localhost only"
            log("[Remote API] Listening on http://\(bindHost):\(port) (\(scope)).")
            return
        }

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            log("[Remote API] Failed to create socket.")
            return
        }

        setNonBlocking(fd)

        var yes: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = htons(port)

        let bindHost = listenOnAllInterfaces ? "0.0.0.0" : "127.0.0.1"
        addr.sin_addr = in_addr(s_addr: inet_addr(bindHost))

        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sptr in
                Darwin.bind(fd, sptr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            let e = errno
            close(fd)
            log("[Remote API] bind() failed errno=\(e).")
            return
        }

        guard listen(fd, SOMAXCONN) == 0 else {
            let e = errno
            close(fd)
            log("[Remote API] listen() failed errno=\(e).")
            return
        }

        listenFD = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptLoop()
        }

        // IMPORTANT:
        // Do not close(fd) in a DispatchSource cancelHandler here.
        // During a rapid stop/start restart, the OS can reuse the same FD number for the new listener,
        // and the old cancelHandler would accidentally close the new socket.
        source.setCancelHandler { }

        acceptSource = source
        source.resume()

        log("[Remote API] Listening on http://\(bindHost):\(port) (\(listenOnAllInterfaces ? "LAN/VPN" : "localhost only")).")
    }

    private func stopInternal() {
        acceptSource?.cancel()
        acceptSource = nil

        // Tear down all active clients. We close the client FD immediately to avoid any delayed
        // DispatchSource cancel handlers accidentally closing a reused FD number.
        let fds = Array(clientSources.keys)
        for fd in fds {
            teardownClient(fd)
        }

        if listenFD != -1 {
            close(listenFD)
            listenFD = -1
        }

        log("[Remote API] Stopped.")
    }

    private func acceptLoop() {
        while true {
            var addr = sockaddr_in()
            var len: socklen_t = socklen_t(MemoryLayout<sockaddr_in>.size)

            let clientFD: Int32 = withUnsafeMutablePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sptr in
                    accept(listenFD, sptr, &len)
                }
            }

            if clientFD < 0 {
                let e = errno
                if e == EAGAIN || e == EWOULDBLOCK { return }
                log("[Remote API] accept() failed errno=\(e).")
                return
            }

            setNonBlocking(clientFD)

            // Avoid SIGPIPE crashes if the peer disconnects while we're writing.
            var yes: Int32 = 1
            _ = setsockopt(clientFD, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))

            clientModes[clientFD] = .http
            clientIPs[clientFD] = String(cString: inet_ntoa(addr.sin_addr))

            let src = DispatchSource.makeReadSource(fileDescriptor: clientFD, queue: queue)
            src.setEventHandler { [weak self] in
                self?.readFromClient(clientFD)
            }

            // IMPORTANT:
            // Do not close(fd) in a DispatchSource cancelHandler here.
            // The OS can reuse the same FD number for a new connection, and a delayed cancelHandler
            // would accidentally close or mutate the new client's state.
            src.setCancelHandler { }

            clientSources[clientFD] = src
            src.resume()
        }
    }

    

    func teardownClient(_ clientFD: Int32) {
        // Cancel the dispatch source first to prevent further events, then close immediately.
        // Avoid doing any cleanup in the cancelHandler to prevent delayed work from acting on a reused FD number.
        if let src = clientSources[clientFD] {
            src.cancel()
        }

        clientSources.removeValue(forKey: clientFD)
        clientBuffers.removeValue(forKey: clientFD)
        clientModes.removeValue(forKey: clientFD)
        clientIPs.removeValue(forKey: clientFD)

        _ = close(clientFD)
    }

    private func enforceHTTPRequestLimits(clientFD: Int32, buffer: Data) -> Bool {
        // Hard cap on total buffered request data (headers + body).
        if buffer.count > (Self.maxRequestHeaderBytes + Self.maxRequestBodyBytes) {
            sendJSON(
                statusCode: 413,
                reason: "Payload Too Large",
                jsonObject: ["error": "payload_too_large"],
                clientFD: clientFD
            )
            teardownClient(clientFD)
            return true
        }

        guard let headerEnd = buffer.range(of: Data([13, 10, 13, 10])) else {
            // No complete header yet; cap header growth.
            if buffer.count > Self.maxRequestHeaderBytes {
                sendJSON(
                    statusCode: 413,
                    reason: "Payload Too Large",
                    jsonObject: ["error": "payload_too_large"],
                    clientFD: clientFD
                )
                teardownClient(clientFD)
                return true
            }
            return false
        }

        if headerEnd.lowerBound > Self.maxRequestHeaderBytes {
            sendJSON(
                statusCode: 413,
                reason: "Payload Too Large",
                jsonObject: ["error": "payload_too_large"],
                clientFD: clientFD
            )
            teardownClient(clientFD)
            return true
        }

        let headerData = buffer.subdata(in: 0..<headerEnd.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            sendJSON(
                statusCode: 400,
                reason: "Bad Request",
                jsonObject: ["error": "bad_request"],
                clientFD: clientFD
            )
            teardownClient(clientFD)
            return true
        }

        let lines = headerText.components(separatedBy: "\r\n")
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard !line.isEmpty else { continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[name] = value
        }

        if let clRaw = headers["content-length"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           let contentLength = Int(clRaw),
           contentLength > Self.maxRequestBodyBytes {
            sendJSON(
                statusCode: 413,
                reason: "Payload Too Large",
                jsonObject: ["error": "payload_too_large"],
                clientFD: clientFD
            )
            teardownClient(clientFD)
            return true
        }

        // Also cap any bytes we already buffered after the header (covers cases with missing/invalid Content-Length).
        let bytesAfterHeader = buffer.count - headerEnd.upperBound
        if bytesAfterHeader > Self.maxRequestBodyBytes {
            sendJSON(
                statusCode: 413,
                reason: "Payload Too Large",
                jsonObject: ["error": "payload_too_large"],
                clientFD: clientFD
            )
            teardownClient(clientFD)
            return true
        }

        return false
    }

    func allowPOSTRequest(from clientIP: String) -> Bool {
        let now = Date().timeIntervalSince1970

        // Periodic pruning to prevent unbounded growth.
        if postRateLimitLastPrune == 0 || (now - postRateLimitLastPrune) > 60 {
            postRateLimitLastPrune = now
            postRateLimitByIP = postRateLimitByIP.filter { (_, v) in
                (now - v.windowStart) < (postRateLimitWindowSeconds * 6)
            }
        }

        if var existing = postRateLimitByIP[clientIP] {
            if (now - existing.windowStart) >= postRateLimitWindowSeconds {
                existing.windowStart = now
                existing.count = 1
                postRateLimitByIP[clientIP] = existing
                return true
            }

            if existing.count >= postRateLimitMax {
                return false
            }

            existing.count += 1
            postRateLimitByIP[clientIP] = existing
            return true
        } else {
            postRateLimitByIP[clientIP] = FixedWindowCounter(windowStart: now, count: 1)
            return true
        }
    }

    private func readFromClient(_ clientFD: Int32) {
        let mode = clientModes[clientFD] ?? .http

        var buf = [UInt8](repeating: 0, count: 8192)

        while true {
            let n = read(clientFD, &buf, buf.count)
            if n > 0 {
                var existing = clientBuffers[clientFD] ?? Data()
                existing.append(contentsOf: buf[0..<n])
                clientBuffers[clientFD] = existing

                switch mode {
                case .http:
                    if enforceHTTPRequestLimits(clientFD: clientFD, buffer: existing) {
                        return
                    }

                    if let request = parseRequest(from: existing) {
                        let shouldClose = respond(to: request, clientFD: clientFD)
                        if shouldClose {
                            teardownClient(clientFD)
                        } else {
                            clientBuffers[clientFD] = request.remainingData
                        }
                        return
                    }

                case .webSocket:
                    parseWebSocketFrames(clientFD: clientFD)
                    if clientModes[clientFD] == nil { return }
                }

                continue
            } else if n == 0 {
                teardownClient(clientFD)
                return
            } else {
                let e = errno
                if e == EAGAIN || e == EWOULDBLOCK { return }
                teardownClient(clientFD)
                return
            }
        }
    }

    // MARK: - Helpers

    func writeAll(_ data: Data, to fd: Int32) -> Bool {
        return data.withUnsafeBytes { rawBuf in
            guard let base = rawBuf.baseAddress else { return false }
            var remaining = rawBuf.count
            var ptr = base.assumingMemoryBound(to: UInt8.self)

            while remaining > 0 {
                let written = write(fd, ptr, remaining)
                if written > 0 {
                    remaining -= written
                    ptr = ptr.advanced(by: written)
                    continue
                }

                if written == -1 {
                    let e = errno
                    if e == EAGAIN || e == EWOULDBLOCK {
                        return false
                    }
                }

                return false
            }

            return true
        }
    }

    private func setNonBlocking(_ fd: Int32) {
        let flags = fcntl(fd, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        }
    }

    private func htons(_ value: UInt16) -> UInt16 {
        return (value << 8) | (value >> 8)
    }
}

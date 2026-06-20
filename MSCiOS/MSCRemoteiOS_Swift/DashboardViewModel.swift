import Foundation
import Combine

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var status: RemoteAPIStatus? = nil
    @Published var servers: [ServerDTO] = []
    @Published var consoleTail: [ConsoleLineDTO] = []
    @Published var consoleStream: [ConsoleLineDTO] = []
    @Published var players: PlayersResponse? = nil

    struct PerformancePoint: Identifiable, Equatable {
        let id = UUID()
        let timestamp: Date
        let tps1m: Double?
        let playersOnline: Int?
        let cpuPercent: Double?
        let ramUsedMB: Double?
        let ramMaxMB: Double?
        let worldSizeMB: Double?
    }

    @Published var performanceLatest: PerformancePoint? = nil
    @Published var performanceHistory: [PerformancePoint] = []
    @Published var performanceErrorMessage: String? = nil

    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var lastUpdated: Date? = nil
    @Published var isStreamingConsole: Bool = false

    @Published var componentsStatus: ComponentsStatusDTO? = nil
    @Published var broadcastStatus: BroadcastStatusDTO? = nil
    @Published var pendingAuthPrompt: BroadcastAuthPromptDTO? = nil
    @Published var broadcastAutoStart: Bool? = nil

    /// "admin" or "guest", nil = not yet determined or not connected.
    @Published var connectedRole: String? = nil

    @Published var worldsResponse: WorldSlotsResponseDTO? = nil
    @Published var backupsResponse: BackupsResponseDTO? = nil
    @Published var sessionLogResponse: SessionLogResponseDTO? = nil
    @Published var playerProfilesResponse: PlayerProfilesResponseDTO? = nil

    var notifications: NotificationManager = .shared

    // MARK: - Internal state (do not access from views)
    // These properties are managed exclusively by the DashboardViewModel extension
    // files (ConsoleStream, Performance, Notifications). Do not read or write them
    // from SwiftUI views or other callsites outside this class and its extensions.
    var previousRunning: Bool? = nil
    var previousPlayerNames: Set<String> = []

    let maxPerformanceSamples: Int = 60
    var client: RemoteAPIClient? = nil
    var clientBaseURL: URL? = nil
    var clientToken: String? = nil
    var webSocketTask: URLSessionWebSocketTask? = nil
    var webSocketReceiveTask: Task<Void, Never>? = nil

    func updateCredentials(baseURL: URL, token: String) {
        guard baseURL != clientBaseURL || token != clientToken else { return }
        clientBaseURL = baseURL
        clientToken = token
        client = nil
        connectedRole = nil
    }

    func requireClient() throws -> RemoteAPIClient {
        if let existing = client { return existing }
        guard let baseURL = clientBaseURL, let token = clientToken else {
            throw RemoteAPIError.missingToken
        }
        let newClient = try RemoteAPIClient(baseURL: baseURL, token: token)
        client = newClient
        return newClient
    }

    func refreshAll(baseURL: URL, token: String, tailN: Int) async {
        updateCredentials(baseURL: baseURL, token: token)

        isLoading = true
        errorMessage = nil

        let runningBeforeRefresh = previousRunning
        let playerNamesBeforeRefresh = previousPlayerNames

        do {
            let client = try requireClient()

            async let s1 = client.getStatus()
            async let s2 = client.getServers()
            async let s3 = client.getConsoleTail(n: tailN)

            let (fetchedStatus, fetchedServers, fetchedTail) = try await (s1, s2, s3)

            status = fetchedStatus
            servers = fetchedServers
            consoleTail = fetchedTail
            lastUpdated = Date()
        } catch {
            errorMessage = error.localizedDescription
        }

        await fetchPerformanceSnapshot(baseURL: baseURL, token: token)
        await fetchComponentsAndBroadcast(baseURL: baseURL, token: token)

        if connectedRole == nil {
            if let c = try? requireClient() {
                connectedRole = try? await c.getMe()
            }
        }

        isLoading = false

        await fetchPlayers(baseURL: baseURL, token: token)

        evaluateNotifications(
            previousRunning: runningBeforeRefresh,
            previousPlayerNames: playerNamesBeforeRefresh
        )
    }

    func pollStatusAndPlayers(baseURL: URL, token: String) async {
        updateCredentials(baseURL: baseURL, token: token)

        let runningBeforeRefresh = previousRunning
        let playerNamesBeforeRefresh = previousPlayerNames

        do {
            let client = try requireClient()

            async let s1 = client.getStatus()
            async let s2 = client.getPlayers()
            async let s3auth = try? client.getAuthPrompt()
            async let s3broad = try? client.getBroadcastStatus()

            if servers.isEmpty {
                async let s3 = client.getServers()
                let (fetchedStatus, fetchedPlayers, fetchedServers, auth, broad) = try await (s1, s2, s3, s3auth, s3broad)
                status = fetchedStatus
                players = fetchedPlayers
                servers = fetchedServers
                broadcastStatus = broad
                if let auth, auth.isPresent { pendingAuthPrompt = auth } else { pendingAuthPrompt = nil }
            } else {
                let (fetchedStatus, fetchedPlayers, auth, broad) = try await (s1, s2, s3auth, s3broad)
                status = fetchedStatus
                players = fetchedPlayers
                broadcastStatus = broad
                if let auth, auth.isPresent { pendingAuthPrompt = auth } else { pendingAuthPrompt = nil }
            }

            lastUpdated = Date()

            evaluateNotifications(
                previousRunning: runningBeforeRefresh,
                previousPlayerNames: playerNamesBeforeRefresh
            )
        } catch {
        }
    }

    func setActiveServer(baseURL: URL, token: String, serverId: String) async -> Bool {
        updateCredentials(baseURL: baseURL, token: token)
        errorMessage = nil
        do {
            _ = try await requireClient().setActiveServer(serverId: serverId)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func start(baseURL: URL, token: String) async -> Bool {
        updateCredentials(baseURL: baseURL, token: token)
        errorMessage = nil
        do {
            _ = try await requireClient().start()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func stop(baseURL: URL, token: String) async -> Bool {
        updateCredentials(baseURL: baseURL, token: token)
        errorMessage = nil
        do {
            _ = try await requireClient().stop()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func sendCommand(baseURL: URL, token: String, command: String) async -> Bool {
        updateCredentials(baseURL: baseURL, token: token)
        errorMessage = nil
        do {
            _ = try await requireClient().sendCommand(command)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @MainActor func fetchComponentsAndBroadcast(baseURL: URL, token: String) async {
        updateCredentials(baseURL: baseURL, token: token)
        guard let client = try? requireClient() else { return }
        async let c = try? client.getComponents()
        async let b = try? client.getBroadcastStatus()
        async let a = try? client.getAuthPrompt()
        async let s = try? client.getBroadcastAutoStart()
        let (comp, broad, auth, autoStart) = await (c, b, a, s)
        componentsStatus = comp
        broadcastStatus = broad
        broadcastAutoStart = autoStart?.enabled
        if let auth, auth.isPresent { pendingAuthPrompt = auth } else { pendingAuthPrompt = nil }
    }

    func dismissAuthPrompt(baseURL: URL, token: String) async {
        updateCredentials(baseURL: baseURL, token: token)
        _ = try? await requireClient().dismissAuthPrompt()
        pendingAuthPrompt = nil
    }

    // MARK: - Session Log & Player Profiles

    func fetchSessionLog(baseURL: URL, token: String) async {
        updateCredentials(baseURL: baseURL, token: token)
        do {
            sessionLogResponse = try await requireClient().getSessionLog()
        } catch {
            // non-fatal — session log is supplementary
        }
    }

    func fetchPlayerProfiles(baseURL: URL, token: String) async {
        updateCredentials(baseURL: baseURL, token: token)
        do {
            let response = try await requireClient().getPlayerProfiles()
            playerProfilesResponse = response
            // If the server just triggered NBT loading for some profiles, retry once
            // after a short delay so stats are available on the next render.
            if response.isLoadingStats {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if let updated = try? await requireClient().getPlayerProfiles() {
                    playerProfilesResponse = updated
                }
            }
        } catch {
            // non-fatal
        }
    }

    // MARK: - Worlds & Backups

    func fetchWorlds(baseURL: URL, token: String) async {
        updateCredentials(baseURL: baseURL, token: token)
        do {
            worldsResponse = try await requireClient().getWorlds()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fetchBackups(baseURL: URL, token: String) async {
        updateCredentials(baseURL: baseURL, token: token)
        do {
            backupsResponse = try await requireClient().getBackups()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func activateWorldSlot(baseURL: URL, token: String, slotId: String) async -> Bool {
        updateCredentials(baseURL: baseURL, token: token)
        errorMessage = nil
        do {
            _ = try await requireClient().activateWorldSlot(slotId: slotId)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func createBackupNow(baseURL: URL, token: String) async -> Bool {
        updateCredentials(baseURL: baseURL, token: token)
        errorMessage = nil
        do {
            _ = try await requireClient().createBackupNow()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func restoreBackup(baseURL: URL, token: String, backupId: String) async -> Bool {
        updateCredentials(baseURL: baseURL, token: token)
        errorMessage = nil
        do {
            _ = try await requireClient().restoreBackup(backupId: backupId)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
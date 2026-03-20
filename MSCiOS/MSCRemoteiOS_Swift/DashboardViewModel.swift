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

            if servers.isEmpty {
                async let s3 = client.getServers()
                let (fetchedStatus, fetchedPlayers, fetchedServers) = try await (s1, s2, s3)
                status = fetchedStatus
                players = fetchedPlayers
                servers = fetchedServers
            } else {
                let (fetchedStatus, fetchedPlayers) = try await (s1, s2)
                status = fetchedStatus
                players = fetchedPlayers
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
}
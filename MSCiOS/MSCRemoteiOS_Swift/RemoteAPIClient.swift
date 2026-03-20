import Foundation

enum RemoteAPIError: LocalizedError {
    case invalidBaseURL
    case insecureHTTPNotAllowed
    case insecureWebSocketNotAllowed
    case missingToken
    case httpStatus(Int, String?)
    case decodingFailed
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Base URL is invalid."
        case .insecureHTTPNotAllowed:
            return "Blocked: HTTP is only allowed for local/private addresses. Use LAN/VPN or HTTPS."
        case .insecureWebSocketNotAllowed:
            return "Blocked: WS is only allowed for local/private addresses. Use LAN/VPN or WSS."
        case .missingToken:
            return "Token is missing."
        case .httpStatus(let code, let body):
            if let body, !body.isEmpty {
                return "HTTP \(code): \(body)"
            }
            return "HTTP \(code)."
        case .decodingFailed:
            return "Failed to decode server response."
        case .network(let msg):
            return "Network error: \(msg)"
        }
    }
}

final class RemoteAPIClient {
    private let baseURL: URL
    private let token: String

    /// Used for all standard HTTP requests. Short timeouts are appropriate
    /// here — if the server doesn't respond to a status or command request
    /// in 10 seconds, something is genuinely wrong.
    private let session: URLSession

    /// Used exclusively for WebSocket connections. WebSocket connections are
    /// long-lived and may go silent for extended periods between console
    /// messages. Applying timeoutIntervalForRequest (the between-packet
    /// idle timeout) to a WebSocket is incorrect — it will kill a healthy
    /// idle socket after 3 seconds of server silence, which is exactly the
    /// "stream dies immediately" bug. This session has no timeouts so
    /// URLSession never tears it down due to inactivity.
    private let wsSession: URLSession

    init(baseURL: URL, token: String) throws {
        guard baseURL.scheme != nil, baseURL.host != nil else { throw RemoteAPIError.invalidBaseURL }
        guard NetworkSafety.httpIsAllowed(for: baseURL) else { throw RemoteAPIError.insecureHTTPNotAllowed }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RemoteAPIError.missingToken }

        self.baseURL = baseURL
        self.token = trimmed

        let httpConfig = URLSessionConfiguration.ephemeral
        httpConfig.timeoutIntervalForRequest = 10
        httpConfig.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: httpConfig)

        // No timeouts — the WebSocket stays open until explicitly cancelled.
        let wsConfig = URLSessionConfiguration.ephemeral
        wsConfig.timeoutIntervalForRequest = .infinity
        wsConfig.timeoutIntervalForResource = .infinity
        self.wsSession = URLSession(configuration: wsConfig)
    }

    // MARK: - Read-only endpoints

    func getStatus() async throws -> RemoteAPIStatus {
        try await get(path: "/status", query: [:], as: RemoteAPIStatus.self)
    }

    func getServers() async throws -> [ServerDTO] {
        try await get(path: "/servers", query: [:], as: [ServerDTO].self)
    }

    func getConsoleTail(n: Int) async throws -> [ConsoleLineDTO] {
        let clamped = max(1, min(2000, n))
        return try await get(path: "/console/tail", query: ["n": "\(clamped)"], as: [ConsoleLineDTO].self)
    }

    // MARK: - Performance snapshot

    /// Recommended server endpoint:
    /// GET /performance  -> PerformanceSnapshotDTO
    func getPerformanceSnapshot() async throws -> PerformanceSnapshotDTO {
        try await get(path: "/performance", query: [:], as: PerformanceSnapshotDTO.self)
    }

    // MARK: - Players snapshot

    /// GET /players -> PlayersResponse
    /// Returns the online player list from the macOS app.
    /// Returns { players: [], count: 0 } if the server is not running.
    func getPlayers() async throws -> PlayersResponse {
        try await get(path: "/players", query: [:], as: PlayersResponse.self)
    }
    // MARK: - Control endpoints

    func setActiveServer(serverId: String) async throws -> SimpleResult {
        let trimmed = serverId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RemoteAPIError.network("Missing server id.") }
        return try await post(path: "/active-server", body: ActiveServerRequest(serverId: trimmed), as: SimpleResult.self)
    }

    func start() async throws -> SimpleResult {
        try await post(path: "/start", body: EmptyBody(), as: SimpleResult.self)
    }

    func stop() async throws -> SimpleResult {
        try await post(path: "/stop", body: EmptyBody(), as: SimpleResult.self)
    }

    func sendCommand(_ command: String) async throws -> CommandResult {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RemoteAPIError.network("Command is empty.") }
        return try await post(path: "/command", body: CommandRequest(command: trimmed), as: CommandResult.self)
    }

    // MARK: - WebSocket

    func makeConsoleStreamTask() throws -> URLSessionWebSocketTask {
        let wsURL = try makeWebSocketURL(path: "/console/stream")
        var req = URLRequest(url: wsURL)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return wsSession.webSocketTask(with: req)
    }

    // MARK: - Internals

    private struct EmptyBody: Encodable { }

    private struct ActiveServerRequest: Encodable {
        let serverId: String
    }

    private struct CommandRequest: Encodable {
        let command: String
    }

    private func makeHTTPURL(path: String, query: [String: String]) throws -> URL {
        var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)

        // Ensure path joins correctly
        let basePath = (comps?.path ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let reqPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        comps?.path = "/" + ([basePath, reqPath].filter { !$0.isEmpty }.joined(separator: "/"))

        if !query.isEmpty {
            comps?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = comps?.url else { throw RemoteAPIError.invalidBaseURL }
        return url
    }

    private func makeWebSocketURL(path: String) throws -> URL {
        var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        guard let schemeRaw = comps?.scheme?.lowercased() else { throw RemoteAPIError.invalidBaseURL }

        // Convert http/https to ws/wss; if user already entered ws/wss, keep it.
        switch schemeRaw {
        case "http":
            comps?.scheme = "ws"
        case "https":
            comps?.scheme = "wss"
        case "ws", "wss":
            break
        default:
            throw RemoteAPIError.invalidBaseURL
        }

        // Join paths like HTTP helper
        let basePath = (comps?.path ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let reqPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        comps?.path = "/" + ([basePath, reqPath].filter { !$0.isEmpty }.joined(separator: "/"))

        guard let url = comps?.url else { throw RemoteAPIError.invalidBaseURL }

        // Safety: allow WS only on local/private; allow WSS anywhere.
        if (url.scheme ?? "").lowercased() == "ws" {
            guard let host = url.host, NetworkSafety.isLocalOrPrivateHost(host) else {
                throw RemoteAPIError.insecureWebSocketNotAllowed
            }
        }

        return url
    }

    private func get<T: Decodable>(path: String, query: [String: String], as type: T.Type) async throws -> T {
        let url = try makeHTTPURL(path: path, query: query)

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                throw RemoteAPIError.network("No HTTP response.")
            }

            guard (200...299).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8)
                throw RemoteAPIError.httpStatus(http.statusCode, body)
            }

            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw RemoteAPIError.decodingFailed
            }
        } catch let err as RemoteAPIError {
            throw err
        } catch {
            throw RemoteAPIError.network(error.localizedDescription)
        }
    }

    private func post<B: Encodable, T: Decodable>(path: String, body: B, as type: T.Type) async throws -> T {
        let url = try makeHTTPURL(path: path, query: [:])

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            req.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw RemoteAPIError.network("Failed to encode request.")
        }

        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                throw RemoteAPIError.network("No HTTP response.")
            }

            guard (200...299).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8)
                throw RemoteAPIError.httpStatus(http.statusCode, body)
            }

            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw RemoteAPIError.decodingFailed
            }
        } catch let err as RemoteAPIError {
            throw err
        } catch {
            throw RemoteAPIError.network(error.localizedDescription)
        }
    }
}

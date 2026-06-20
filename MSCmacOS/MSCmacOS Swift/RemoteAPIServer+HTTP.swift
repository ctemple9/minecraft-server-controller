import Foundation

extension RemoteAPIServer {
    // MARK: - HTTP parsing

    struct Request {
        let method: String
        let path: String
        let query: [String: String]
        let headers: [String: String]
        let body: Data
        let remainingData: Data
    }

    func parseRequest(from data: Data) -> Request? {
        guard let headerEnd = data.range(of: Data([13, 10, 13, 10])) else { return nil }

        let headerData = data.subdata(in: 0..<headerEnd.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first, !requestLine.isEmpty else { return nil }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        let method = String(parts[0])
        let rawTarget = String(parts[1])

        let (path, query) = parseTarget(rawTarget)

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard !line.isEmpty else { continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[name] = value
        }

        let bodyStart = headerEnd.upperBound

        var contentLength: Int = 0
        if let clRaw = headers["content-length"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           let parsed = Int(clRaw),
           parsed >= 0 {
            contentLength = parsed
        }

        // Hardening: cap request bodies and prevent integer overflow when computing indices.
        if contentLength > Self.maxRequestBodyBytes { return nil }
        guard contentLength <= (Int.max - bodyStart) else { return nil }

        let bodyEnd = bodyStart + contentLength
        guard data.count >= bodyEnd else { return nil }

        let body = contentLength > 0 ? data.subdata(in: bodyStart..<bodyEnd) : Data()
        let remaining = data.count > bodyEnd ? data.subdata(in: bodyEnd..<data.count) : Data()

        return Request(method: method, path: path, query: query, headers: headers, body: body, remainingData: remaining)
    }

    func parseTarget(_ rawTarget: String) -> (String, [String: String]) {
        let parts = rawTarget.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let path = parts.first.map(String.init) ?? rawTarget

        var query: [String: String] = [:]
        if parts.count == 2 {
            let queryString = String(parts[1])
            for pair in queryString.split(separator: "&") {
                if pair.isEmpty { continue }
                let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let kRaw = kv.first.map(String.init) ?? ""
                let vRaw = kv.count == 2 ? (kv[1].isEmpty ? "" : String(kv[1])) : ""

                let k = urlDecode(kRaw)
                let v = urlDecode(vRaw)
                if !k.isEmpty {
                    query[k] = v
                }
            }
        }

        return (path, query)
    }

    func urlDecode(_ s: String) -> String {
        return s.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? s
    }

    // MARK: - Responses

    // Routes that require admin role — guests get 403 on these.
    private static let adminOnlyPOSTPaths: Set<String> = [
        "/command", "/active-server", "/components/update",
        "/broadcast/credentials", "/broadcast/start", "/broadcast/stop",
        "/broadcast/restart", "/broadcast/autostart", "/broadcast/auth-prompt/dismiss",
        "/worlds/activate", "/backups/now", "/backups/restore"
    ]

    func respond(to request: Request, clientFD: Int32) -> Bool {
        let tokenMap = tokenProvider()
        let normalizedMap: [String: TokenRole] = Dictionary(
            uniqueKeysWithValues: tokenMap.compactMap { (k, v) -> (String, TokenRole)? in
                let trimmed = k.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return (trimmed, v)
            }
        )

        let authHeader = request.headers["authorization"] ?? ""
        let trimmedAuth = authHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmedAuth.lowercased()
        let presentedToken: String?
        if lower.hasPrefix("bearer ") {
            presentedToken = String(trimmedAuth.dropFirst("Bearer ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            presentedToken = nil
        }

        guard let presentedToken, !presentedToken.isEmpty,
              let requestRole = normalizedMap[presentedToken] else {
            sendJSON(
                statusCode: 401,
                reason: "Unauthorized",
                jsonObject: ["error": "unauthorized"],
                clientFD: clientFD
            )
            return true
        }

        // Guest tokens may not use admin-only routes.
        if case .guest = requestRole {
            let method = request.method.uppercased()
            let path = request.path
            if method == "POST", Self.adminOnlyPOSTPaths.contains(path) {
                sendJSON(
                    statusCode: 403,
                    reason: "Forbidden",
                    jsonObject: ["error": "forbidden"],
                    clientFD: clientFD
                )
                return true
            }
        }

        let method = request.method.uppercased()
        let path = request.path

        // Hardening: simple per-client rate limit on sensitive POST endpoints.
        if method == "POST", Self.rateLimitedPOSTPaths.contains(path) {
            let clientIP = clientIPs[clientFD] ?? "unknown"
            if !allowPOSTRequest(from: clientIP) {
                sendJSON(
                    statusCode: 429,
                    reason: "Too Many Requests",
                    jsonObject: ["error": "rate_limited"],
                    clientFD: clientFD
                )
                return true
            }
        }

        // WebSocket upgrade endpoint
        if method == "GET",
           path == "/console/stream",
           isWebSocketUpgrade(headers: request.headers) {

            let ok = performWebSocketUpgrade(request: request, clientFD: clientFD)
            if ok {
                clientModes[clientFD] = .webSocket

                let initialTail = tailConsoleLines(n: 200)
                for line in initialTail {
                    sendWebSocketJSON(line, clientFD: clientFD)
                }
                return false
            } else {
                sendJSON(
                    statusCode: 400,
                    reason: "Bad Request",
                    jsonObject: ["error": "websocket_upgrade_failed"],
                    clientFD: clientFD
                )
                return true
            }
        }

        struct SimpleResult: Codable {
            let result: String
            let activeServerId: String?
        }

        struct CommandResult: Codable {
            let result: String
            let activeServerId: String?
            let command: String
        }

        struct CommandRequest: Codable {
            let command: String
        }

        struct ActiveServerRequest: Codable {
            let serverId: String
        }

        switch (method, path) {
        case ("GET", "/servers"):
            let servers = serversProvider()
            let cfg = configServersSnapshot()
            let dtos = servers.map { server -> ServerDTO in
                let configServer = cfg.first(where: { $0.id == server.id })
                let connectionInfo = serverConnectionInfoProvider(server.id)
                return ServerDTO(
                    id: server.id,
                    name: server.name,
                    directory: server.directory,
                    serverType: configServer?.serverType.rawValue ?? "java",
                    gamePort: connectionInfo?.gamePort,
                    hostAddress: connectionInfo?.hostAddress
                )
            }
            sendJSON(statusCode: 200, reason: "OK", encodable: dtos, clientFD: clientFD)
            return true

        case ("GET", "/status"):
            let status = statusProvider()
            sendJSON(statusCode: 200, reason: "OK", encodable: status, clientFD: clientFD)
            return true

        // Performance snapshot
        case ("GET", "/performance"):
            let snapshot = performanceProvider()
            sendJSON(statusCode: 200, reason: "OK", encodable: snapshot, clientFD: clientFD)
            return true

        case ("POST", "/active-server"):
            guard !request.body.isEmpty else {
                sendJSON(
                    statusCode: 400,
                    reason: "Bad Request",
                    jsonObject: ["error": "missing_body"],
                    clientFD: clientFD
                )
                return true
            }

            do {
                let decoded = try JSONDecoder().decode(ActiveServerRequest.self, from: request.body)
                let id = decoded.serverId.trimmingCharacters(in: .whitespacesAndNewlines)

                guard !id.isEmpty else {
                    sendJSON(
                        statusCode: 400,
                        reason: "Bad Request",
                        jsonObject: ["error": "missing_server_id"],
                        clientFD: clientFD
                    )
                    return true
                }

                guard setActiveServerProvider(id) else {
                    sendJSON(
                        statusCode: 404,
                        reason: "Not Found",
                        jsonObject: ["error": "unknown_server"],
                        clientFD: clientFD
                    )
                    return true
                }

                let status = statusProvider()
                sendJSON(
                    statusCode: 200,
                    reason: "OK",
                    encodable: SimpleResult(result: "active_server_set", activeServerId: status.activeServerId),
                    clientFD: clientFD
                )
                return true
            } catch {
                sendJSON(
                    statusCode: 400,
                    reason: "Bad Request",
                    jsonObject: ["error": "invalid_json"],
                    clientFD: clientFD
                )
                return true
            }

        case ("POST", "/start"):

            startProvider()
            let status = statusProvider()
            sendJSON(
                statusCode: 200,
                reason: "OK",
                encodable: SimpleResult(result: "start_requested", activeServerId: status.activeServerId),
                clientFD: clientFD
            )
            return true

        case ("POST", "/stop"):
            stopProvider()
            let status = statusProvider()
            sendJSON(
                statusCode: 200,
                reason: "OK",
                encodable: SimpleResult(result: "stop_requested", activeServerId: status.activeServerId),
                clientFD: clientFD
            )
            return true

        case ("POST", "/command"):
            guard !request.body.isEmpty else {
                sendJSON(
                    statusCode: 400,
                    reason: "Bad Request",
                    jsonObject: ["error": "missing_body"],
                    clientFD: clientFD
                )
                return true
            }

            do {
                let decoded = try JSONDecoder().decode(CommandRequest.self, from: request.body)
                let cmd = decoded.command.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cmd.isEmpty else {
                    sendJSON(
                        statusCode: 400,
                        reason: "Bad Request",
                        jsonObject: ["error": "missing_command"],
                        clientFD: clientFD
                    )
                    return true
                }

                commandProvider(cmd)
                let status = statusProvider()
                sendJSON(
                    statusCode: 200,
                    reason: "OK",
                    encodable: CommandResult(result: "command_sent", activeServerId: status.activeServerId, command: cmd),
                    clientFD: clientFD
                )
                return true
            } catch {
                sendJSON(
                    statusCode: 400,
                    reason: "Bad Request",
                    jsonObject: ["error": "invalid_json"],
                    clientFD: clientFD
                )
                return true
            }

        // Player list
        case ("GET", "/players"):
            let response = playersProvider()
            sendJSON(statusCode: 200, reason: "OK", encodable: response, clientFD: clientFD)
            return true

        // Bedrock allowlist
        case ("GET", "/allowlist"):
            let response = allowlistProvider()
            sendJSON(statusCode: 200, reason: "OK", encodable: response, clientFD: clientFD)
            return true

        // Session log
        case ("GET", "/session-log"):
            let response = sessionLogProvider()
            sendJSON(statusCode: 200, reason: "OK", encodable: response, clientFD: clientFD)
            return true

        // Console tail
        case ("GET", "/console/tail"):
            let nRaw = request.query["n"] ?? ""
            let nParsed = Int(nRaw) ?? 200
            let n = max(1, min(2000, nParsed))
            let lines = tailConsoleLines(n: n)
            sendJSON(statusCode: 200, reason: "OK", encodable: lines, clientFD: clientFD)
            return true

        // Components status
        case ("GET", "/components"):
            handleGetComponents(clientFD: clientFD)
            return false  // async handler sends its own response

        // Component update
        case ("POST", "/components/update"):
            handleUpdateComponent(body: request.body, clientFD: clientFD)
            return false  // async handler sends its own response

        case ("GET", "/broadcast/autostart"):
            handleGetBroadcastAutoStart(clientFD: clientFD)
            return true

        case ("POST", "/broadcast/autostart"):
            handleSetBroadcastAutoStart(body: request.body, clientFD: clientFD)
            return true

        // Broadcast auth prompt
        case ("GET", "/broadcast/auth-prompt"):
            handleGetAuthPrompt(clientFD: clientFD)
            return true

        case ("POST", "/broadcast/auth-prompt/dismiss"):
            handleDismissAuthPrompt(clientFD: clientFD)
            return true

        // Broadcast status
        case ("GET", "/broadcast/status"):
            handleGetBroadcastStatus(clientFD: clientFD)
            return true

        case ("POST", "/broadcast/start"):
            handleStartBroadcast(clientFD: clientFD)
            return true

        case ("POST", "/broadcast/stop"):
            handleStopBroadcast(clientFD: clientFD)
            return true

        // Broadcast restart
        case ("POST", "/broadcast/restart"):
            handleRestartBroadcast(clientFD: clientFD)
            return true

        // Broadcast credentials
        case ("POST", "/broadcast/credentials"):
            handleUpdateBroadcastCredentials(body: request.body, clientFD: clientFD)
            return true

        // Token role info
        case ("GET", "/me"):
            let roleString = (requestRole == .admin) ? "admin" : "guest"
            sendJSON(statusCode: 200, reason: "OK", jsonObject: ["role": roleString], clientFD: clientFD)
            return true

        // Player profiles (all-time, with stats)
        case ("GET", "/players/profiles"):
            let response = playerProfilesProvider()
            sendJSON(statusCode: 200, reason: "OK", encodable: response, clientFD: clientFD)
            return true

        // World slots
        case ("GET", "/worlds"):
            let response = worldSlotsProvider()
            sendJSON(statusCode: 200, reason: "OK", encodable: response, clientFD: clientFD)
            return true

        case ("POST", "/worlds/activate"):
            guard !request.body.isEmpty else {
                sendJSON(statusCode: 400, reason: "Bad Request",
                         jsonObject: ["error": "missing_body"], clientFD: clientFD)
                return true
            }
            struct ActivateSlotRequest: Codable { let slotId: String }
            do {
                let decoded = try JSONDecoder().decode(ActivateSlotRequest.self, from: request.body)
                let id = decoded.slotId.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !id.isEmpty else {
                    sendJSON(statusCode: 400, reason: "Bad Request",
                             jsonObject: ["error": "missing_slot_id"], clientFD: clientFD)
                    return true
                }
                guard activateWorldSlotProvider(id) else {
                    sendJSON(statusCode: 409, reason: "Conflict",
                             jsonObject: ["error": "server_running_or_slot_not_found"], clientFD: clientFD)
                    return true
                }
                sendJSON(statusCode: 200, reason: "OK",
                         jsonObject: ["result": "activation_started"], clientFD: clientFD)
            } catch {
                sendJSON(statusCode: 400, reason: "Bad Request",
                         jsonObject: ["error": "invalid_json"], clientFD: clientFD)
            }
            return true

        // Backups
        case ("GET", "/backups"):
            let response = backupItemsProvider()
            sendJSON(statusCode: 200, reason: "OK", encodable: response, clientFD: clientFD)
            return true

        case ("POST", "/backups/now"):
            createBackupNowProvider()
            sendJSON(statusCode: 200, reason: "OK",
                     jsonObject: ["result": "backup_started"], clientFD: clientFD)
            return true

        case ("POST", "/backups/restore"):
            guard !request.body.isEmpty else {
                sendJSON(statusCode: 400, reason: "Bad Request",
                         jsonObject: ["error": "missing_body"], clientFD: clientFD)
                return true
            }
            struct RestoreBackupRequest: Codable { let backupId: String }
            do {
                let decoded = try JSONDecoder().decode(RestoreBackupRequest.self, from: request.body)
                let filename = decoded.backupId.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !filename.isEmpty else {
                    sendJSON(statusCode: 400, reason: "Bad Request",
                             jsonObject: ["error": "missing_backup_id"], clientFD: clientFD)
                    return true
                }
                guard restoreBackupProvider(filename) else {
                    sendJSON(statusCode: 404, reason: "Not Found",
                             jsonObject: ["error": "backup_not_found"], clientFD: clientFD)
                    return true
                }
                sendJSON(statusCode: 200, reason: "OK",
                         jsonObject: ["result": "restore_started"], clientFD: clientFD)
            } catch {
                sendJSON(statusCode: 400, reason: "Bad Request",
                         jsonObject: ["error": "invalid_json"], clientFD: clientFD)
            }
            return true

        // Watchdog
        case ("GET", "/watchdog/status"):
            let enabled = watchdogStatusProvider()
            sendJSON(statusCode: 200, reason: "OK",
                     jsonObject: ["enabled": enabled ? "true" : "false"],
                     clientFD: clientFD)
            return true

        case ("POST", "/watchdog/enable"):
            if let errorMessage = enableWatchdogProvider() {
                sendJSON(statusCode: 500, reason: "Internal Server Error",
                         jsonObject: ["success": "false", "error": errorMessage],
                         clientFD: clientFD)
            } else {
                sendJSON(statusCode: 200, reason: "OK",
                         jsonObject: ["success": "true"],
                         clientFD: clientFD)
            }
            return true

        case ("POST", "/watchdog/disable"):
            if let errorMessage = disableWatchdogProvider() {
                sendJSON(statusCode: 500, reason: "Internal Server Error",
                         jsonObject: ["success": "false", "error": errorMessage],
                         clientFD: clientFD)
            } else {
                sendJSON(statusCode: 200, reason: "OK",
                         jsonObject: ["success": "true"],
                         clientFD: clientFD)
            }
            return true

        default:
            let knownPaths: Set<String> = [
                "/servers", "/status", "/performance", "/players", "/allowlist", "/session-log",
                "/active-server", "/start", "/stop", "/command",
                "/console/tail", "/console/stream",
                "/components", "/components/update",
                "/broadcast/status", "/broadcast/start", "/broadcast/stop", "/broadcast/restart", "/broadcast/credentials",
                "/broadcast/auth-prompt", "/broadcast/auth-prompt/dismiss",
                "/broadcast/autostart", "/me",
                "/watchdog/status", "/watchdog/enable", "/watchdog/disable",
                "/players/profiles",
                "/worlds", "/worlds/activate",
                "/backups", "/backups/now", "/backups/restore"
            ]
            if knownPaths.contains(path) {
                sendJSON(
                    statusCode: 405,
                    reason: "Method Not Allowed",
                    jsonObject: ["error": "method_not_allowed"],
                    clientFD: clientFD
                )
            } else {
                sendJSON(
                    statusCode: 404,
                    reason: "Not Found",
                    jsonObject: ["error": "not_found"],
                    clientFD: clientFD
                )
            }
            return true
        }
    }

    func configServersSnapshot() -> [ConfigServer] {
        configServersProvider()
    }

    func tailConsoleLines(n: Int) -> [ConsoleLineDTO] {
        let count = consoleBuffer.count
        guard count > 0 else { return [] }
        let take = max(1, min(n, count))
        return Array(consoleBuffer.suffix(take))
    }

    func sendJSON<T: Encodable>(
        statusCode: Int,
        reason: String,
        encodable: T,
        clientFD: Int32
    ) {
        do {
            let data = try JSONEncoder().encode(encodable)
            sendRawJSON(statusCode: statusCode, reason: reason, jsonData: data, clientFD: clientFD)
        } catch {
            sendJSON(
                statusCode: 500,
                reason: "Internal Server Error",
                jsonObject: ["error": "encode_failed"],
                clientFD: clientFD
            )
        }
    }

    func sendJSON(
        statusCode: Int,
        reason: String,
        jsonObject: [String: String],
        clientFD: Int32
    ) {
        do {
            let data = try JSONSerialization.data(withJSONObject: jsonObject, options: [])
            sendRawJSON(statusCode: statusCode, reason: reason, jsonData: data, clientFD: clientFD)
        } catch {
            let data = Data("{\"error\":\"encode_failed\"}".utf8)
            sendRawJSON(statusCode: 500, reason: "Internal Server Error", jsonData: data, clientFD: clientFD)
        }
    }

    func sendRawJSON(
        statusCode: Int,
        reason: String,
        jsonData: Data,
        clientFD: Int32
    ) {
        var response = Data()
        response.append(Data("HTTP/1.1 \(statusCode) \(reason)\r\n".utf8))
        response.append(Data("Content-Type: application/json; charset=utf-8\r\n".utf8))
        response.append(Data("Content-Length: \(jsonData.count)\r\n".utf8))
        response.append(Data("Connection: close\r\n".utf8))
        response.append(Data("\r\n".utf8))
        response.append(jsonData)

        response.withUnsafeBytes { rawBuf in
            guard let base = rawBuf.baseAddress else { return }
            var remaining = rawBuf.count
            var ptr = base.assumingMemoryBound(to: UInt8.self)

            while remaining > 0 {
                let written = write(clientFD, ptr, remaining)
                if written <= 0 { break }
                remaining -= written
                ptr = ptr.advanced(by: written)
            }
        }
    }

}

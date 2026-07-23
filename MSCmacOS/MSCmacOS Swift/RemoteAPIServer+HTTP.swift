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
        "/command", "/active-server", "/servers/rename", "/servers/delete", "/servers/create", "/servers/eula", "/servers/import", "/templates", "/players/skin-override", "/players/hidden", "/components/update", "/components/remove", "/components/install",
        "/components/version",
        "/broadcast/credentials", "/broadcast/start", "/broadcast/stop",
        "/broadcast/restart", "/broadcast/autostart", "/broadcast/auth-prompt/dismiss",
        "/broadcast/download-jar",
        "/worlds/activate", "/worlds/create", "/worlds/rename", "/worlds/replace", "/worlds/repair",
        "/backups/now", "/backups/restore", "/backups/config",
        "/allowlist", "/settings",
        "/resourcepacks/activate", "/resourcepacks/seturl", "/resourcepacks/toggle", "/resourcepacks/remove",
        "/health/repair",
        "/playit/start", "/playit/stop",
        "/duckdns", "/config/geyser", "/config/ram", "/config/java-runtime",
        // Named-user management — owner admin token only (named tokens can never manage users)
        "/users", "/users/revoke", "/users/update"
    ]

    // Maps POST paths to the permission string a named token must hold to use them.
    // Paths absent from this map are accessible to all authenticated tokens (admin, guest, named).
    // Admin and guest tokens bypass this map and use adminOnlyPOSTPaths instead.
    private static let pathPermissions: [String: String] = [
        // serverControl — operate the server process
        "/start": "serverControl",
        "/stop": "serverControl",
        "/command": "serverControl",
        "/active-server": "serverControl",
        // players — allowlist and profile management
        "/allowlist": "players",
        "/players/skin-override": "players",
        "/players/hidden": "players",
        // settings — server configuration files
        "/settings": "settings",
        "/config/geyser": "settings",
        "/config/ram": "settings",
        "/config/java-runtime": "settings",
        "/duckdns": "settings",
        "/backups/config": "settings",
        "/health/repair": "settings",
        // addons — mod/plugin and resource-pack management
        "/components/update": "addons",
        "/components/remove": "addons",
        "/components/install": "addons",
        "/components/version": "addons",
        "/resourcepacks/activate": "addons",
        "/resourcepacks/seturl": "addons",
        "/resourcepacks/toggle": "addons",
        "/resourcepacks/remove": "addons",
        // worlds — world slots and backups
        "/worlds/activate": "worlds",
        "/worlds/create": "worlds",
        "/worlds/rename": "worlds",
        "/worlds/replace": "worlds",
        "/worlds/repair": "worlds",
        "/backups/now": "worlds",
        "/backups/restore": "worlds",
        // broadcast — Xbox/LAN broadcast control
        "/broadcast/start": "broadcast",
        "/broadcast/stop": "broadcast",
        "/broadcast/restart": "broadcast",
        "/broadcast/credentials": "broadcast",
        "/broadcast/autostart": "broadcast",
        "/broadcast/auth-prompt/dismiss": "broadcast",
        "/broadcast/download-jar": "broadcast",
        // networking — tunnel agent control
        "/playit/start": "networking",
        "/playit/stop": "networking",
        // fleet — server list management
        "/servers/rename": "fleet",
        "/servers/delete": "fleet",
        "/servers/create": "fleet",
        "/servers/eula": "fleet",
        "/servers/import": "fleet",
        "/templates": "fleet",
    ]

    // Canonical set of every path the router knows about, used in the default: case to
    // distinguish 405 Method Not Allowed (known path, wrong method) from 404 Not Found.
    // Also referenced by the DEBUG registry assertions below.
    // KEEP IN SYNC with every case in respond(to:clientFD:) and allRouterHandledPaths.
    static let knownPathsCanonical: Set<String> = [
        "/servers", "/servers/rename", "/servers/delete", "/servers/create", "/servers/eula", "/servers/import", "/templates",
        "/status", "/performance",
        "/players", "/players/skin-override", "/players/hidden", "/players/profiles",
        "/allowlist", "/session-log",
        "/active-server", "/start", "/stop", "/command",
        "/console/tail", "/console/stream",
        "/components", "/components/update", "/components/remove", "/components/install",
        "/components/version", "/addons", "/components/client-export",
        "/files", "/files/read",
        "/catalog/search", "/versions", "/java-runtimes",
        "/broadcast/status", "/broadcast/start", "/broadcast/stop", "/broadcast/restart",
        "/broadcast/credentials", "/broadcast/auth-prompt", "/broadcast/auth-prompt/dismiss",
        "/broadcast/autostart", "/broadcast/jar-status", "/broadcast/download-jar", "/me",
        "/watchdog/status", "/watchdog/enable", "/watchdog/disable",
        "/worlds", "/worlds/activate", "/worlds/create", "/worlds/rename",
        "/worlds/replace", "/worlds/repair",
        "/backups", "/backups/now", "/backups/restore", "/backups/config",
        "/settings",
        "/resourcepacks", "/resourcepacks/activate", "/resourcepacks/seturl",
        "/resourcepacks/toggle", "/resourcepacks/remove",
        "/health", "/health/problems", "/health/repair",
        "/connectivity",
        "/playit", "/playit/start", "/playit/stop",
        "/duckdns", "/config/geyser", "/config/ram", "/config/java-runtime",
        "/users", "/users/revoke", "/users/update",
    ]

    // MARK: - DEBUG Registry Integrity Assertions

#if DEBUG
    // Canonical list of every path the respond(to:clientFD:) switch handles.
    // Parameterised pre-switch routes (e.g. GET /players/<id>/skin) are excluded because
    // their paths can't be represented as fixed strings.
    // Keep this in sync with every case arm in respond(to:clientFD:).
    private static let allRouterHandledPaths: Set<String> = [
        // fleet
        "/servers", "/servers/rename", "/servers/delete", "/servers/create", "/servers/eula", "/servers/import", "/templates",
        // status & performance
        "/status", "/performance",
        // server lifecycle
        "/active-server", "/start", "/stop", "/command",
        // players
        "/players", "/players/skin-override", "/players/hidden", "/players/profiles",
        // allowlist
        "/allowlist",
        // session log
        "/session-log",
        // console
        "/console/tail",
        // components & add-ons
        "/components", "/components/update", "/components/remove", "/components/install",
        "/components/version", "/addons", "/components/client-export",
        // files
        "/files", "/files/read",
        // catalog & versions
        "/catalog/search", "/versions", "/java-runtimes",
        // resource packs
        "/resourcepacks", "/resourcepacks/activate", "/resourcepacks/seturl",
        "/resourcepacks/toggle", "/resourcepacks/remove",
        // settings
        "/settings",
        // broadcast
        "/broadcast/status", "/broadcast/start", "/broadcast/stop", "/broadcast/restart",
        "/broadcast/credentials", "/broadcast/auth-prompt", "/broadcast/auth-prompt/dismiss",
        "/broadcast/autostart", "/broadcast/jar-status", "/broadcast/download-jar",
        // token identity
        "/me",
        // worlds
        "/worlds", "/worlds/activate", "/worlds/create", "/worlds/rename",
        "/worlds/replace", "/worlds/repair",
        // connectivity
        "/connectivity",
        // playit
        "/playit", "/playit/start", "/playit/stop",
        // DuckDNS & Geyser & RAM & Java config
        "/duckdns", "/config/geyser", "/config/ram", "/config/java-runtime",
        // health / diagnostics
        "/health", "/health/problems", "/health/repair",
        // backups
        "/backups", "/backups/now", "/backups/restore", "/backups/config",
        // named users
        "/users", "/users/revoke", "/users/update",
        // watchdog
        "/watchdog/status", "/watchdog/enable", "/watchdog/disable",
    ]

    // Paths handled before the switch (WebSocket upgrade block) — present in
    // knownPathsCanonical but not in allRouterHandledPaths.
    private static let preRouterHandledPaths: Set<String> = ["/console/stream"]

    /// Validates all four route-registry invariants at server startup (DEBUG only).
    /// Called from startInternal() on the server queue — pure Set operations, no provider
    /// calls, no main-thread hops, no I/O.
    func assertRegistryConsistency() {

        // ── Assertion 1 ──────────────────────────────────────────────────────────
        // Every pathPermissions key should be in adminOnlyPOSTPaths.
        //
        // KNOWN EXCEPTIONS (by design, not oversight):
        //   /start, /stop — "guest-accessible, named-token-restricted" paths.
        //   Guests may start/stop the server without restriction; named tokens require
        //   the "serverControl" permission.  They are intentionally absent from
        //   adminOnlyPOSTPaths so guest tokens aren't blocked, yet appear in
        //   pathPermissions to gate named-token access.
        let permissionExemptFromAdminOnly: Set<String> = ["/start", "/stop"]
        for path in Self.pathPermissions.keys {
            if permissionExemptFromAdminOnly.contains(path) { continue }
            assert(
                Self.adminOnlyPOSTPaths.contains(path),
                "M2 assertion 1: '\(path)' is in pathPermissions but not in adminOnlyPOSTPaths — " +
                "add it to adminOnlyPOSTPaths or document the exemption in permissionExemptFromAdminOnly."
            )
        }

        // ── Assertion 2 ──────────────────────────────────────────────────────────
        // Every adminOnlyPOSTPaths entry should be in rateLimitedPOSTPaths.
        //
        // SUSPECT EXEMPTIONS — present in adminOnlyPOSTPaths but absent from
        // rateLimitedPOSTPaths.  These were most likely omitted by oversight rather
        // than by deliberate design; they are listed here so the assertion doesn't
        // fire spuriously while the omission is being evaluated.
        // Consider adding them to rateLimitedPOSTPaths in RemoteAPIServer.swift:
        //   - /broadcast/* : mutate external Xbox/LAN broadcast state
        //   - /worlds/activate : destructive slot switch (requires stopped server)
        //   - /backups/now, /backups/restore : slow and destructive — most in need of limiting
        let adminNotRateLimitedExemptions: Set<String> = [
            "/broadcast/credentials", "/broadcast/start", "/broadcast/stop",
            "/broadcast/restart", "/broadcast/autostart", "/broadcast/auth-prompt/dismiss",
            "/worlds/activate",
            "/backups/now", "/backups/restore",
        ]
        for path in Self.adminOnlyPOSTPaths {
            if adminNotRateLimitedExemptions.contains(path) { continue }
            assert(
                Self.rateLimitedPOSTPaths.contains(path),
                "M2 assertion 2: '\(path)' is in adminOnlyPOSTPaths but not in rateLimitedPOSTPaths — " +
                "add it to rateLimitedPOSTPaths or document the exemption in adminNotRateLimitedExemptions."
            )
        }

        // ── Assertion 3 ──────────────────────────────────────────────────────────
        // Every path in all three registries must appear in knownPathsCanonical.
        let known = Self.knownPathsCanonical
        for path in Self.adminOnlyPOSTPaths {
            assert(known.contains(path),
                   "M2 assertion 3: adminOnlyPOSTPaths '\(path)' is missing from knownPathsCanonical.")
        }
        for path in Self.pathPermissions.keys {
            assert(known.contains(path),
                   "M2 assertion 3: pathPermissions '\(path)' is missing from knownPathsCanonical.")
        }
        for path in Self.rateLimitedPOSTPaths {
            assert(known.contains(path),
                   "M2 assertion 3: rateLimitedPOSTPaths '\(path)' is missing from knownPathsCanonical.")
        }

        // ── Assertion 4 ──────────────────────────────────────────────────────────
        // Every router-handled path must be in knownPathsCanonical, and every
        // knownPathsCanonical entry must be handled somewhere (switch or pre-switch).
        let allHandled = Self.allRouterHandledPaths.union(Self.preRouterHandledPaths)
        for path in Self.allRouterHandledPaths {
            assert(known.contains(path),
                   "M2 assertion 4: router-handled path '\(path)' is missing from knownPathsCanonical — add it.")
        }
        for path in known {
            assert(allHandled.contains(path),
                   "M2 assertion 4: knownPathsCanonical '\(path)' is not handled by the router switch " +
                   "or pre-switch handler — add a case or remove it from knownPathsCanonical.")
        }
    }

    /// Spot-checks that additive provider closures have been replaced from their factory
    /// defaults.  Call from AppViewModel.init (both wiring branches) immediately BEFORE
    /// start(), on the main thread — providers use the Thread.isMainThread fast-path and
    /// avoid the DispatchQueue.main.sync hop (no deadlock risk during AppViewModel.init).
    func assertProviderWiringComplete() {
        // backupConfigProvider: factory default returns note:"not_available".
        // After wiring, the real closure returns nil or "no_active_server" — never "not_available".
        let backup = backupConfigProvider()
        assert(
            backup.note != "not_available",
            "M2 wiring: backupConfigProvider still has its factory default — " +
            "ensure ALL additive providers are assigned in both wiring branches of AppViewModel.init."
        )
        // settingsProvider: same sentinel pattern.
        let settings = settingsProvider()
        assert(
            settings.note != "not_available",
            "M2 wiring: settingsProvider still has its factory default — " +
            "ensure ALL additive providers are assigned in both wiring branches of AppViewModel.init."
        )
    }
#endif

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
            let clientIP = clientIPs[clientFD] ?? "unknown"
            let tokenLabel: String = (presentedToken.flatMap { $0.isEmpty ? nil : $0 } != nil) ? "unknown" : "anonymous"
            if checkAndRecordAuthFail(from: clientIP) {
                auditLogger?.log(AuditLogger.Entry(
                    timestamp: Date(), clientIP: clientIP, tokenLabel: tokenLabel,
                    method: request.method, path: request.path, statusCode: 429))
                sendJSON(statusCode: 429, reason: "Too Many Requests",
                         jsonObject: ["error": "rate_limited"], clientFD: clientFD)
            } else {
                auditLogger?.log(AuditLogger.Entry(
                    timestamp: Date(), clientIP: clientIP, tokenLabel: tokenLabel,
                    method: request.method, path: request.path, statusCode: 401))
                sendJSON(statusCode: 401, reason: "Unauthorized",
                         jsonObject: ["error": "unauthorized"], clientFD: clientFD)
            }
            return true
        }

        // Guest tokens may not use admin-only routes.
        if case .guest = requestRole {
            let method = request.method.uppercased()
            let path = request.path
            if method == "POST", Self.adminOnlyPOSTPaths.contains(path) {
                auditLogger?.log(AuditLogger.Entry(
                    timestamp: Date(), clientIP: clientIPs[clientFD] ?? "unknown",
                    tokenLabel: requestRole.auditLabel, method: method, path: path, statusCode: 403))
                sendJSON(
                    statusCode: 403,
                    reason: "Forbidden",
                    jsonObject: ["error": "forbidden"],
                    clientFD: clientFD
                )
                return true
            }
        }

        // Named (permission-scoped) tokens: only allow POST paths they hold the permission for.
        // GET requests are always allowed for authenticated tokens.
        // User-management paths (/users*) are never accessible to named tokens — only the admin.
        if case .named(_, let permissions) = requestRole {
            let method = request.method.uppercased()
            let path = request.path
            if method == "POST" {
                if Self.adminOnlyPOSTPaths.contains(path), !Self.pathPermissions.keys.contains(path) {
                    // Path is admin-only but has no permission category (e.g., /users/*) — deny.
                    auditLogger?.log(AuditLogger.Entry(
                        timestamp: Date(), clientIP: clientIPs[clientFD] ?? "unknown",
                        tokenLabel: requestRole.auditLabel, method: method, path: path, statusCode: 403))
                    sendJSON(statusCode: 403, reason: "Forbidden",
                             jsonObject: ["error": "forbidden"], clientFD: clientFD)
                    return true
                }
                if let required = Self.pathPermissions[path], !permissions.contains(required) {
                    auditLogger?.log(AuditLogger.Entry(
                        timestamp: Date(), clientIP: clientIPs[clientFD] ?? "unknown",
                        tokenLabel: requestRole.auditLabel, method: method, path: path, statusCode: 403))
                    sendJSON(statusCode: 403, reason: "Forbidden",
                             jsonObject: ["error": "forbidden"], clientFD: clientFD)
                    return true
                }
            }
        }

        let method = request.method.uppercased()
        let path = request.path

        // Register a pending audit context for every POST that passes auth.
        // sendRawJSON will flush it with the actual response status code.
        if method == "POST" {
            let ctx = PendingAuditContext(
                timestamp: Date(),
                clientIP: clientIPs[clientFD] ?? "unknown",
                tokenLabel: requestRole.auditLabel,
                method: method,
                path: path
            )
            auditContextLock.lock()
            pendingAuditByFD[clientFD] = ctx
            auditContextLock.unlock()
        }

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

        if method == "GET", path.hasPrefix("/players/"), path.hasSuffix("/skin") {
            let prefix = "/players/"
            let suffix = "/skin"
            let rawId = String(path.dropFirst(prefix.count).dropLast(suffix.count))
            handleGetPlayerSkin(profileId: urlDecode(rawId), clientFD: clientFD)
            return false
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
                    javaFlavor: configServer?.serverType == .java ? configServer?.javaFlavor.rawValue : nil,
                    gamePort: connectionInfo?.gamePort,
                    hostAddress: connectionInfo?.hostAddress
                )
            }
            sendJSON(statusCode: 200, reason: "OK", encodable: dtos, clientFD: clientFD)
            return true

        case ("POST", "/servers/rename"):
            handleRenameServer(body: request.body, clientFD: clientFD)
            return false

        case ("POST", "/servers/delete"):
            handleDeleteServer(body: request.body, clientFD: clientFD)
            return false

        case ("POST", "/servers/create"):
            handleCreateServer(body: request.body, clientFD: clientFD)
            return false

        case ("POST", "/servers/eula"):
            handleAcceptServerEULA(body: request.body, clientFD: clientFD)
            return false

        case ("GET", "/templates"):
            handleGetTemplates(clientFD: clientFD)
            return false

        case ("POST", "/templates"):
            handleMutateTemplates(body: request.body, clientFD: clientFD)
            return false

        case ("POST", "/servers/import"):
            handleImportServer(body: request.body, clientFD: clientFD)
            return false

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

        case ("POST", "/players/skin-override"):
            handleSetPlayerSkinOverride(body: request.body, clientFD: clientFD)
            return false

        case ("POST", "/players/hidden"):
            handleSetHiddenProfile(body: request.body, clientFD: clientFD)
            return false

        // Bedrock allowlist
        case ("GET", "/allowlist"):
            let response = allowlistProvider()
            sendJSON(statusCode: 200, reason: "OK", encodable: response, clientFD: clientFD)
            return true

        // Bedrock allowlist add/remove
        case ("POST", "/allowlist"):
            guard !request.body.isEmpty else {
                sendJSON(statusCode: 400, reason: "Bad Request",
                         jsonObject: ["error": "missing_body"], clientFD: clientFD)
                return true
            }
            do {
                let decoded = try JSONDecoder().decode(AllowlistMutationRequestDTO.self, from: request.body)
                let action = decoded.action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let name = decoded.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard action == "add" || action == "remove" else {
                    sendJSON(statusCode: 400, reason: "Bad Request",
                             jsonObject: ["error": "invalid_action"], clientFD: clientFD)
                    return true
                }
                guard !name.isEmpty else {
                    sendJSON(statusCode: 400, reason: "Bad Request",
                             jsonObject: ["error": "missing_name"], clientFD: clientFD)
                    return true
                }
                let result = mutateAllowlistProvider(action, name)
                if result.success {
                    sendJSON(statusCode: 200, reason: "OK", encodable: result, clientFD: clientFD)
                } else if result.message == "not_bedrock" {
                    sendJSON(statusCode: 409, reason: "Conflict", encodable: result, clientFD: clientFD)
                } else {
                    sendJSON(statusCode: 500, reason: "Internal Server Error", encodable: result, clientFD: clientFD)
                }
            } catch {
                sendJSON(statusCode: 400, reason: "Bad Request",
                         jsonObject: ["error": "invalid_json"], clientFD: clientFD)
            }
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

        // Component update (system components + Modrinth add-ons)
        case ("POST", "/components/update"):
            handleUpdateComponent(body: request.body, clientFD: clientFD)
            return false  // async handler sends its own response

        // Add-on list with update status
        case ("GET", "/addons"):
            handleGetAddons(clientFD: clientFD)
            return false  // async handler sends its own response

        // Server file browser (S1) — admin-only. The previewable content can include
        // secrets (rcon.password in server.properties, API keys in plugin YAMLs), so
        // GETs here must not be readable by guests or named (permission-scoped) tokens.
        case ("GET", "/files"):
            guard case .admin = requestRole else {
                sendJSON(statusCode: 403, reason: "Forbidden",
                         jsonObject: ["error": "forbidden"], clientFD: clientFD)
                return true
            }
            handleGetFiles(path: request.query["path"], clientFD: clientFD)
            return false

        case ("GET", "/files/read"):
            guard case .admin = requestRole else {
                sendJSON(statusCode: 403, reason: "Forbidden",
                         jsonObject: ["error": "forbidden"], clientFD: clientFD)
                return true
            }
            handleReadFile(path: request.query["path"] ?? "", clientFD: clientFD)
            return false

        case ("GET", "/components/client-export"):
            let selected = request.query["selected"]?
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            handleGetClientExport(selectedIds: selected, clientFD: clientFD)
            return false

        // Remove an installed add-on
        case ("POST", "/components/remove"):
            handleRemoveAddon(body: request.body, clientFD: clientFD)
            return true

        // Search the add-on catalog (Modrinth) for the active server
        case ("GET", "/catalog/search"):
            let q = request.query["q"] ?? ""
            let offset = Int(request.query["offset"] ?? "0") ?? 0
            handleCatalogSearch(query: q, offset: offset, clientFD: clientFD)
            return false  // async handler sends its own response

        // Install an add-on from the catalog into the active server
        case ("POST", "/components/install"):
            handleInstallAddon(body: request.body, clientFD: clientFD)
            return false  // async handler sends its own response

        // Detected Java runtimes on this Mac
        case ("GET", "/java-runtimes"):
            handleGetJavaRuntimes(clientFD: clientFD)
            return false  // async handler sends its own response

        // Available server JAR versions for the active server's flavor
        case ("GET", "/versions"):
            handleGetVersions(clientFD: clientFD)
            return false  // async handler sends its own response

        // Available versions for the create-server flow
        case ("GET", "/versions/create"):
            handleGetCreateVersions(serverType: request.query["serverType"],
                                    javaFlavor: request.query["javaFlavor"],
                                    clientFD: clientFD)
            return false  // async handler sends its own response

        // Download / install a chosen server JAR version
        case ("POST", "/components/version"):
            handleChangeVersion(body: request.body, clientFD: clientFD)
            return false  // async handler sends its own response

        // Resource packs — list
        case ("GET", "/resourcepacks"):
            handleGetResourcePacks(clientFD: clientFD)
            return false  // async handler sends its own response

        // Resource packs — activate/clear local pack
        case ("POST", "/resourcepacks/activate"):
            handleActivateResourcePack(body: request.body, clientFD: clientFD)
            return false

        // Resource packs — set a custom URL directly in server.properties
        case ("POST", "/resourcepacks/seturl"):
            handleSetResourcePackURL(body: request.body, clientFD: clientFD)
            return false

        // Resource packs — Geyser enable/disable
        case ("POST", "/resourcepacks/toggle"):
            handleToggleGeyserPack(body: request.body, clientFD: clientFD)
            return false

        // Resource packs — remove from disk
        case ("POST", "/resourcepacks/remove"):
            handleRemoveResourcePack(body: request.body, clientFD: clientFD)
            return false

        // Typed server.properties schema (read + write)
        case ("GET", "/settings"):
            handleGetSettings(clientFD: clientFD)
            return true

        case ("POST", "/settings"):
            handleUpdateSettings(body: request.body, clientFD: clientFD)
            return true

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

        // MCXboxBroadcast JAR management
        case ("GET", "/broadcast/jar-status"):
            handleGetBroadcastJarStatus(clientFD: clientFD)
            return false

        case ("POST", "/broadcast/download-jar"):
            handleDownloadBroadcastJar(clientFD: clientFD)
            return false

        // Token role info
        case ("GET", "/me"):
            let dto: MeResponseDTO
            switch requestRole {
            case .admin:
                dto = MeResponseDTO(role: "admin")
            case .guest:
                dto = MeResponseDTO(role: "guest")
            case .named(let label, let permissions):
                dto = MeResponseDTO(role: "named", name: label, permissions: permissions, isNamedToken: true)
            }
            sendJSON(statusCode: 200, reason: "OK", encodable: dto, clientFD: clientFD)
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

        // World management verbs (P9) — async handlers send their own response.
        case ("POST", "/worlds/create"):
            handleCreateWorld(body: request.body, clientFD: clientFD)
            return false

        case ("POST", "/worlds/rename"):
            handleRenameWorld(body: request.body, clientFD: clientFD)
            return false

        case ("POST", "/worlds/replace"):
            handleReplaceWorld(body: request.body, clientFD: clientFD)
            return false

        case ("POST", "/worlds/repair"):
            handleRepairWorld(body: request.body, clientFD: clientFD)
            return false

        // Connectivity (P11) — async handler sends its own response.
        case ("GET", "/connectivity"):
            handleGetConnectivity(clientFD: clientFD)
            return false

        // Playit tunnel (P12) — async handlers send their own response.
        case ("GET", "/playit"):
            handleGetPlayitStatus(clientFD: clientFD)
            return false

        case ("POST", "/playit/start"):
            handleStartPlayit(clientFD: clientFD)
            return false

        case ("POST", "/playit/stop"):
            handleStopPlayit(clientFD: clientFD)
            return false

        // DuckDNS (P13)
        case ("GET", "/duckdns"):
            handleGetDuckDNS(clientFD: clientFD)
            return false

        case ("POST", "/duckdns"):
            handleUpdateDuckDNS(body: request.body, clientFD: clientFD)
            return false

        // Geyser config (P13)
        case ("GET", "/config/geyser"):
            handleGetGeyserConfig(clientFD: clientFD)
            return false

        case ("POST", "/config/geyser"):
            handleUpdateGeyserConfig(body: request.body, clientFD: clientFD)
            return false

        // RAM allocation
        case ("GET", "/config/ram"):
            handleGetRAMConfig(clientFD: clientFD)
            return false

        case ("POST", "/config/ram"):
            handleUpdateRAMConfig(body: request.body, clientFD: clientFD)
            return false

        // Global Java executable path
        case ("GET", "/config/java-runtime"):
            handleGetJavaConfig(clientFD: clientFD)
            return false

        case ("POST", "/config/java-runtime"):
            handleSetJavaConfig(body: request.body, clientFD: clientFD)
            return false

        // Diagnostics (P10) — async handlers send their own response.
        case ("GET", "/health"):
            handleGetHealth(clientFD: clientFD)
            return false

        case ("GET", "/health/problems"):
            handleGetHealthProblems(clientFD: clientFD)
            return false

        case ("POST", "/health/repair"):
            handleRepairHealthProblem(body: request.body, clientFD: clientFD)
            return false

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

        case ("GET", "/backups/config"):
            let dto = backupConfigProvider()
            sendJSON(statusCode: 200, reason: "OK", encodable: dto, clientFD: clientFD)
            return true

        case ("POST", "/backups/config"):
            guard !request.body.isEmpty else {
                sendJSON(statusCode: 400, reason: "Bad Request",
                         jsonObject: ["error": "missing_body"], clientFD: clientFD)
                return true
            }
            do {
                let decoded = try JSONDecoder().decode(BackupConfigUpdateRequestDTO.self, from: request.body)
                guard decoded.autoBackupEnabled != nil || decoded.autoBackupIntervalMinutes != nil || decoded.autoBackupMaxCount != nil else {
                    sendJSON(statusCode: 400, reason: "Bad Request",
                             jsonObject: ["error": "no_changes"], clientFD: clientFD)
                    return true
                }
                let result = updateBackupConfigProvider(decoded.autoBackupEnabled, decoded.autoBackupIntervalMinutes, decoded.autoBackupMaxCount)
                let status = result.success ? 200 : 409
                sendJSON(statusCode: status, reason: result.success ? "OK" : "Conflict",
                         encodable: result, clientFD: clientFD)
            } catch {
                sendJSON(statusCode: 400, reason: "Bad Request",
                         jsonObject: ["error": "invalid_json"], clientFD: clientFD)
            }
            return true

        // Named users (P17) — admin-only management
        case ("GET", "/users"):
            guard case .admin = requestRole else {
                sendJSON(statusCode: 403, reason: "Forbidden",
                         jsonObject: ["error": "forbidden"], clientFD: clientFD)
                return true
            }
            handleGetUsers(clientFD: clientFD)
            return false

        case ("POST", "/users"):
            handleCreateUser(body: request.body, clientFD: clientFD)
            return false

        case ("POST", "/users/revoke"):
            handleRevokeUser(body: request.body, clientFD: clientFD)
            return false

        case ("POST", "/users/update"):
            handleUpdateUser(body: request.body, clientFD: clientFD)
            return false

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
            let knownPaths = Self.knownPathsCanonical
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

        // Flush pending POST audit entry with the actual response status.
        auditContextLock.lock()
        let pending = pendingAuditByFD.removeValue(forKey: clientFD)
        auditContextLock.unlock()
        if let pending {
            auditLogger?.log(AuditLogger.Entry(
                timestamp: pending.timestamp,
                clientIP: pending.clientIP,
                tokenLabel: pending.tokenLabel,
                method: pending.method,
                path: pending.path,
                statusCode: statusCode
            ))
        }
    }

}

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

    static let rateLimitedPOSTPaths: Set<String> = ["/command", "/start", "/stop", "/active-server"]

    // Console ring buffer (kept on `queue`)
    var consoleBuffer: [ConsoleLineDTO] = []
    private let consoleBufferLimit: Int = 5000

    private let port: UInt16
    private var listenOnAllInterfaces: Bool

    // Providers can change (Preferences updates), so these must be mutable.
    var tokenProvider: () -> Set<String>
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
    private var logger: (String) -> Void

    init(
        port: UInt16,
        listenOnAllInterfaces: Bool,
        tokenProvider: @escaping () -> Set<String>,
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
        self.logger = logger
    }

    func updateProviders(
        tokenProvider: @escaping () -> Set<String>,
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

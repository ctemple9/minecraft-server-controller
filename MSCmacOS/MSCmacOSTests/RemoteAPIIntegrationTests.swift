//
//  RemoteAPIIntegrationTests.swift
//  MSCmacOSTests
//
//  In-process integration tests for the Remote API (T1b / Prompt 2.2).
//
//  These boot the *real* `RemoteAPIServer` on a real (localhost-only) TCP
//  socket with inert stub providers, then drive it over the loopback with
//  `URLSession` (HTTP) and a hand-rolled raw socket (the WebSocket upgrade).
//  Nothing here touches the real config, Keychain, or filesystem — the server
//  is built from `RemoteAPITestSupport.makeInertServer`, whose providers all
//  return canned DTOs, and only `tokenProvider` / `startProvider` /
//  `stopProvider` / `commandProvider` are overridden per-test.
//
//  Port strategy: `RemoteAPIServer.start()` binds `htons(port)` and never
//  exposes the OS-assigned port when given port 0, so we ask the kernel for a
//  free port ourselves (`RawSocket.findFreePort` — bind :0, read it back via
//  getsockname, close), then hand that concrete port to the server. Each test
//  gets a *fresh* server on a fresh port via `setUp`, which also gives each
//  test its own POST rate-limit counter (an instance property on the server),
//  so the auth-matrix tests can't spuriously trip the limiter for one another.
//
//  All sockets are torn down in `tearDown` (server.stop() closes the listen FD
//  and every client FD; the URLSession is invalidated).
//

import XCTest
import Foundation
import Darwin
@testable import Minecraft_Server_Controller

// MARK: - Thread-safe provider call counters

/// Providers are invoked on the server's private dispatch queue; the test
/// thread reads these counters — hence the lock. `@unchecked Sendable` because
/// the NSLock makes the mutation safe by hand.
final class ProviderCallCounters: @unchecked Sendable {
    private let lock = NSLock()
    private var _start = 0
    private var _stop = 0
    private var _command = 0
    private var _lastCommand: String?

    func recordStart()   { lock.lock(); _start += 1; lock.unlock() }
    func recordStop()    { lock.lock(); _stop += 1; lock.unlock() }
    func recordCommand(_ c: String) { lock.lock(); _command += 1; _lastCommand = c; lock.unlock() }

    var startCount: Int   { lock.lock(); defer { lock.unlock() }; return _start }
    var stopCount: Int    { lock.lock(); defer { lock.unlock() }; return _stop }
    var commandCount: Int { lock.lock(); defer { lock.unlock() }; return _command }
    var lastCommand: String? { lock.lock(); defer { lock.unlock() }; return _lastCommand }
}

// MARK: - Base case: boots a real server, drives it over loopback

class RemoteAPIIntegrationTestCase: XCTestCase {

    // Fixed test tokens covering every role the auth matrix exercises.
    static let adminToken = "admin-token-AAA"
    static let guestToken = "guest-token-BBB"
    static let scToken    = "named-serverControl-CCC"   // named, ["serverControl"]
    static let emptyToken = "named-empty-DDD"            // named, [] (zero permissions)

    static var tokenMap: [String: RemoteAPIServer.TokenRole] {
        [
            adminToken: .admin,
            guestToken: .guest,
            scToken:    .named(label: "sc",    permissions: ["serverControl"]),
            emptyToken: .named(label: "empty", permissions: [])
        ]
    }

    var server: RemoteAPIServer!
    var port: UInt16 = 0
    let counters = ProviderCallCounters()

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 5
        cfg.timeoutIntervalForResource = 5
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: cfg)
    }()

    override func setUp() async throws {
        try await super.setUp()

        let counters = self.counters
        let tokens = Self.tokenMap
        let chosenPort = RawSocket.findFreePort()

        let srv = RemoteAPITestSupport.makeInertServer(port: chosenPort)
        // Override only what the auth matrix / rate limiter care about.
        srv.tokenProvider = { tokens }
        srv.startProvider = { counters.recordStart() }
        srv.stopProvider = { counters.recordStop() }
        srv.commandProvider = { counters.recordCommand($0) }
        srv.start()

        self.server = srv
        self.port = chosenPort

        // Wait until the listener is actually accepting (start() is async on the
        // server's queue). An unauthenticated GET /status returns 401 the moment
        // the server is up; -1 means connection refused / not yet listening.
        var ready = false
        for _ in 0..<150 {
            if await self.status("GET", "/status", token: nil) != -1 { ready = true; break }
            try? await Task.sleep(nanoseconds: 20_000_000) // 20 ms
        }
        XCTAssertTrue(ready, "Remote API server never began listening on port \(chosenPort)")
    }

    override func tearDown() async throws {
        server?.stop()
        // Let the server's queue run stopInternal() (closes listen + client FDs).
        try? await Task.sleep(nanoseconds: 60_000_000) // 60 ms
        server = nil
        session.invalidateAndCancel()
        try await super.tearDown()
    }

    /// Sends an HTTP request over loopback and returns the status code (or -1 on
    /// transport failure). POSTs default to an empty body so paths that gate on
    /// auth *before* body parsing return their auth verdict.
    @discardableResult
    func status(_ method: String, _ path: String, token: String?, body: Data? = nil) async -> Int {
        guard let url = URL(string: "http://127.0.0.1:\(port)\(path)") else { return -1 }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if method.uppercased() == "POST" {
            req.httpBody = Data()
        }
        do {
            let (_, resp) = try await session.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode ?? -1
        } catch {
            return -1
        }
    }
}

// MARK: - 1. AUTH MATRIX

final class RemoteAPIAuthMatrixTests: RemoteAPIIntegrationTestCase {

    // No token / wrong token → 401 on everything (GET and POST alike).
    func testUnauthenticatedRequestsAre401() async {
        let noTokenStatus  = await status("GET", "/status", token: nil)
        let badTokenStatus = await status("GET", "/status", token: "not-a-real-token")
        let noTokenStart   = await status("POST", "/start", token: nil)
        let badTokenCommand = await status("POST", "/command", token: "wrong")

        XCTAssertEqual(noTokenStatus, 401)
        XCTAssertEqual(badTokenStatus, 401)
        XCTAssertEqual(noTokenStart, 401)
        XCTAssertEqual(badTokenCommand, 401)
    }

    // Guest: read is allowed; admin-only POSTs are 403; non-admin POSTs pass.
    func testGuestPermissions() async {
        let getStatus = await status("GET", "/status", token: Self.guestToken)
        let postCommand = await status("POST", "/command", token: Self.guestToken)
        let postStart = await status("POST", "/start", token: Self.guestToken)

        XCTAssertEqual(getStatus, 200, "guest may read /status")
        XCTAssertEqual(postCommand, 403, "/command is admin-only → guest forbidden")
        XCTAssertEqual(postStart, 200, "/start is not admin-only → guest allowed")
        XCTAssertEqual(counters.startCount, 1, "guest POST /start reached the start provider")
    }

    // Named token holding ["serverControl"].
    func testNamedTokenServerControlScope() async {
        // Held permission → allowed.
        let postStart = await status("POST", "/start", token: Self.scToken)
        // Path gated behind a *different* permission category → forbidden.
        let postSettings = await status("POST", "/settings", token: Self.scToken)
        // Admin-only path with NO permission category → named tokens can never reach it.
        let postUsers = await status("POST", "/users", token: Self.scToken,
                                     body: Data(#"{"label":"x","role":"guest"}"#.utf8))

        XCTAssertEqual(postStart, 200, "serverControl permission grants POST /start")
        XCTAssertEqual(postSettings, 403, "no 'settings' permission → POST /settings forbidden")
        XCTAssertEqual(postUsers, 403, "/users is admin-only with no permission category")
    }

    // Named token with ZERO permissions. Pins the S1 fix: file reads are now
    // admin-only, so a zero-permission named token is denied /files + /files/read
    // while still able to perform ordinary GETs.
    func testNamedTokenEmptyPermissionsCannotReadFiles() async {
        let getFiles = await status("GET", "/files", token: Self.emptyToken)
        let getFileRead = await status("GET", "/files/read?path=server.properties", token: Self.emptyToken)
        let getStatus = await status("GET", "/status", token: Self.emptyToken)

        // S1 (post-fix): file endpoints are admin-only.
        XCTAssertEqual(getFiles, 403, "S1: GET /files is admin-only, empty-permission named token denied")
        XCTAssertEqual(getFileRead, 403, "S1: GET /files/read is admin-only, empty-permission named token denied")
        // Ordinary reads still work for any authenticated token.
        XCTAssertEqual(getStatus, 200, "authenticated named token may still GET /status")
    }

    // Guests are likewise denied the file endpoints (S1 covers all non-admins).
    func testGuestCannotReadFiles() async {
        let getFiles = await status("GET", "/files", token: Self.guestToken)
        let getFileRead = await status("GET", "/files/read?path=server.properties", token: Self.guestToken)

        XCTAssertEqual(getFiles, 403, "S1: GET /files is admin-only, guest denied")
        XCTAssertEqual(getFileRead, 403, "S1: GET /files/read is admin-only, guest denied")
    }

    // Admin spot-check: every path the other roles were gated on routes correctly.
    func testAdminReachesEverything() async {
        let getStatus = await status("GET", "/status", token: Self.adminToken)
        let postStart = await status("POST", "/start", token: Self.adminToken)
        let postCommand = await status("POST", "/command", token: Self.adminToken,
                                       body: Data(#"{"command":"say hi"}"#.utf8))
        let getFiles = await status("GET", "/files", token: Self.adminToken)
        // Admin passes the /files/read admin guard, then hits missing_path (400) —
        // proves the request was routed, not blocked at the auth layer.
        let getFileRead = await status("GET", "/files/read", token: Self.adminToken)
        // Admin reaches user management (inert provider → 422 not_available), i.e. not 403/401.
        let postUsers = await status("POST", "/users", token: Self.adminToken,
                                     body: Data(#"{"label":"x","role":"guest"}"#.utf8))

        XCTAssertEqual(getStatus, 200)
        XCTAssertEqual(postStart, 200)
        XCTAssertEqual(postCommand, 200)
        XCTAssertEqual(counters.commandCount, 1)
        XCTAssertEqual(counters.lastCommand, "say hi")
        XCTAssertEqual(getFiles, 200, "admin may browse /files")
        XCTAssertEqual(getFileRead, 400, "admin routed past auth to missing_path handling")
        XCTAssertTrue(postUsers != 401 && postUsers != 403,
                      "admin reaches user management (got \(postUsers))")
    }
}

// MARK: - 2. RATE LIMITER

final class RemoteAPIRateLimiterTests: RemoteAPIIntegrationTestCase {

    // >10 POSTs to a rate-limited path within the 5s window from one client → 429.
    // /start is in rateLimitedPOSTPaths; the limiter allows 10 then rejects.
    func testRateLimiterTripsAfterTenPosts() async {
        var codes: [Int] = []
        for _ in 0..<11 {
            codes.append(await status("POST", "/start", token: Self.adminToken))
        }

        let firstTen = Array(codes.prefix(10))
        XCTAssertTrue(firstTen.allSatisfy { $0 == 200 },
                      "first 10 POSTs within the window should succeed, got \(firstTen)")
        XCTAssertEqual(codes[10], 429, "the 11th POST in the window is rate-limited")
    }
}

// MARK: - 3. ROUTING (404 vs 405)

final class RemoteAPIRoutingTests: RemoteAPIIntegrationTestCase {

    func testUnknownPathIs404() async {
        let code = await status("GET", "/this-endpoint-does-not-exist", token: Self.adminToken)
        XCTAssertEqual(code, 404)
    }

    func testKnownPathWrongMethodIs405() async {
        // /status exists but only for GET; POST falls through to the 405 branch.
        let code = await status("POST", "/status", token: Self.adminToken)
        XCTAssertEqual(code, 405)
    }
}

// MARK: - 4. WEBSOCKET UPGRADE

final class RemoteAPIWebSocketTests: RemoteAPIIntegrationTestCase {

    // A correct upgrade handshake returns 101 with the RFC 6455 accept key, and
    // inbound text frames are ignored (no crash, no command execution).
    func testWebSocketUpgradeAndInboundTextIgnored() async {
        let port = self.port
        let token = Self.adminToken

        // Raw socket work runs off the main actor so nothing blocks.
        let result = await Task.detached {
            RawSocket.webSocketExchange(port: port, token: token)
        }.value

        XCTAssertTrue(result.connected, "could not connect to the WebSocket endpoint")
        XCTAssertTrue(result.statusLine.contains("101"),
                      "expected 101 Switching Protocols, got: \(result.statusLine)")
        // RFC 6455 §1.3 canonical vector: key "dGhlIHNhbXBsZSBub25jZQ==" →
        // accept "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=". This independently validates the
        // server's SHA-1 + base64 accept-key computation.
        XCTAssertEqual(result.acceptHeader, "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=",
                       "Sec-WebSocket-Accept did not match the RFC 6455 vector")
        // The server ignores inbound text frames: it neither closed the socket
        // nor executed the payload as a command.
        XCTAssertFalse(result.serverSentClose,
                       "server should not close the connection on an inbound text frame")
        XCTAssertEqual(counters.commandCount, 0,
                       "inbound WebSocket text must never be executed as a command")
    }
}

// MARK: - Raw socket helpers (nonisolated so they run on a background executor)

/// Minimal blocking BSD-socket helpers for the port probe and the WebSocket
/// handshake. Kept off the main actor via `nonisolated` so `Task.detached` can
/// run the blocking I/O without touching the main-actor default isolation.
enum RawSocket {

    struct WSResult: Sendable {
        let connected: Bool
        let statusLine: String
        let acceptHeader: String?
        let serverSentClose: Bool
    }

    /// Ask the kernel for a free localhost TCP port, then release it.
    nonisolated static func findFreePort() -> UInt16 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return UInt16.random(in: 49152...65535) }
        defer { close(fd) }

        var yes: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0 // let the OS choose
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindOK = withUnsafePointer(to: &addr) { p -> Bool in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
                Darwin.bind(fd, sp, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
        guard bindOK else { return UInt16.random(in: 49152...65535) }

        var bound = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameOK = withUnsafeMutablePointer(to: &bound) { p -> Bool in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
                getsockname(fd, sp, &len) == 0
            }
        }
        guard nameOK else { return UInt16.random(in: 49152...65535) }

        let net = bound.sin_port
        return (net << 8) | (net >> 8) // ntohs
    }

    /// Blocking connect to 127.0.0.1:port. Returns the fd or nil.
    nonisolated static func connect(port: UInt16) -> Int32? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = (port << 8) | (port >> 8) // htons
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let ok = withUnsafePointer(to: &addr) { p -> Bool in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
                Darwin.connect(fd, sp, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
        if !ok { close(fd); return nil }
        return fd
    }

    nonisolated static func setRecvTimeout(_ fd: Int32, ms: Int) {
        var tv = timeval(tv_sec: ms / 1000, tv_usec: Int32((ms % 1000) * 1000))
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    nonisolated static func writeAll(_ fd: Int32, _ bytes: [UInt8]) -> Bool {
        var remaining = bytes.count
        var offset = 0
        return bytes.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            while remaining > 0 {
                let n = write(fd, base.advanced(by: offset), remaining)
                if n <= 0 { return false }
                remaining -= n
                offset += n
            }
            return true
        }
    }

    /// Reads until `marker` appears in the stream or the timeout elapses.
    nonisolated static func readUntil(_ fd: Int32, marker: [UInt8], timeoutMs: Int) -> [UInt8] {
        setRecvTimeout(fd, ms: timeoutMs)
        var out = [UInt8]()
        var buf = [UInt8](repeating: 0, count: 4096)
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        while Date() < deadline {
            let n = read(fd, &buf, buf.count)
            if n > 0 {
                out.append(contentsOf: buf[0..<n])
                if containsSubsequence(out, marker) { break }
            } else {
                break
            }
        }
        return out
    }

    /// Single bounded read window; returns whatever arrived (possibly nothing).
    nonisolated static func readWindow(_ fd: Int32, timeoutMs: Int) -> [UInt8] {
        setRecvTimeout(fd, ms: timeoutMs)
        var buf = [UInt8](repeating: 0, count: 4096)
        let n = read(fd, &buf, buf.count)
        if n > 0 { return Array(buf[0..<n]) }
        return []
    }

    nonisolated static func containsSubsequence(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, haystack.count >= needle.count else { return false }
        for i in 0...(haystack.count - needle.count) {
            if Array(haystack[i..<(i + needle.count)]) == needle { return true }
        }
        return false
    }

    /// A masked client text frame (WebSocket clients MUST mask). len assumed ≤125.
    nonisolated static func maskedTextFrame(_ text: String) -> [UInt8] {
        let payload = Array(text.utf8)
        var frame: [UInt8] = [0x81] // FIN + text opcode
        frame.append(0x80 | UInt8(payload.count)) // MASK bit + length
        let mask: [UInt8] = [0x12, 0x34, 0x56, 0x78]
        frame.append(contentsOf: mask)
        for (i, b) in payload.enumerated() { frame.append(b ^ mask[i % 4]) }
        return frame
    }

    /// Performs the full WebSocket exchange: handshake, parse 101 + accept key,
    /// send one masked text frame ("stop" — a command that must be ignored),
    /// then observe that the server neither closed nor executed it.
    nonisolated static func webSocketExchange(port: UInt16, token: String) -> WSResult {
        guard let fd = connect(port: port) else {
            return WSResult(connected: false, statusLine: "", acceptHeader: nil, serverSentClose: false)
        }
        defer { close(fd) }

        let handshake =
            "GET /console/stream HTTP/1.1\r\n" +
            "Host: 127.0.0.1\r\n" +
            "Upgrade: websocket\r\n" +
            "Connection: Upgrade\r\n" +
            "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" +
            "Sec-WebSocket-Version: 13\r\n" +
            "Authorization: Bearer \(token)\r\n" +
            "\r\n"

        guard writeAll(fd, Array(handshake.utf8)) else {
            return WSResult(connected: true, statusLine: "", acceptHeader: nil, serverSentClose: false)
        }

        let respBytes = readUntil(fd, marker: Array("\r\n\r\n".utf8), timeoutMs: 2000)
        let respText = String(decoding: respBytes, as: UTF8.self)
        let lines = respText.components(separatedBy: "\r\n")
        let statusLine = lines.first ?? ""
        var accept: String?
        for line in lines.dropFirst() {
            let lower = line.lowercased()
            if lower.hasPrefix("sec-websocket-accept:") {
                if let colon = line.firstIndex(of: ":") {
                    accept = String(line[line.index(after: colon)...])
                        .trimmingCharacters(in: .whitespaces)
                }
            }
        }

        // Send a text frame carrying a would-be command; the server ignores text.
        _ = writeAll(fd, maskedTextFrame("stop"))

        // Give the server a moment to (mis)handle it. Expect silence (still open,
        // idle). A close frame would start with 0x88.
        let post = readWindow(fd, timeoutMs: 400)
        let serverSentClose = post.first.map { ($0 & 0x0F) == 0x08 } ?? false

        return WSResult(connected: true,
                        statusLine: statusLine,
                        acceptHeader: accept,
                        serverSentClose: serverSentClose)
    }
}

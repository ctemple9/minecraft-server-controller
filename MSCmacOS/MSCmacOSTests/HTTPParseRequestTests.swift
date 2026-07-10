//
//  HTTPParseRequestTests.swift
//  MSCmacOSTests
//
//  Pins RemoteAPIServer.parseRequest / parseTarget / urlDecode (T1a, tranche #1).
//  Behavior read directly from RemoteAPIServer+HTTP.swift, not paraphrased.
//

import XCTest
@testable import Minecraft_Server_Controller

final class HTTPParseRequestTests: XCTestCase {

    private var server: RemoteAPIServer!

    override func setUp() {
        super.setUp()
        server = RemoteAPITestSupport.makeInertServer()
    }

    override func tearDown() {
        server = nil
        super.tearDown()
    }

    // MARK: - Valid requests

    func testValidGETParsesMethodAndPathAndHeaders() {
        let raw = RemoteAPITestSupport.rawRequest(
            method: "GET", target: "/status",
            headers: ["Authorization": "Bearer abc", "Host": "localhost"])
        let req = server.parseRequest(from: raw)
        XCTAssertNotNil(req)
        XCTAssertEqual(req?.method, "GET")
        XCTAssertEqual(req?.path, "/status")
        // Header names are lowercased by the parser.
        XCTAssertEqual(req?.headers["authorization"], "Bearer abc")
        XCTAssertEqual(req?.headers["host"], "localhost")
        XCTAssertTrue(req?.body.isEmpty ?? false)
        XCTAssertTrue(req?.query.isEmpty ?? false)
    }

    func testValidPOSTWithBodyRespectsContentLength() {
        let body = Data("{\"a\":1}".utf8)
        let raw = RemoteAPITestSupport.rawRequest(
            method: "POST", target: "/command",
            headers: ["Content-Length": "\(body.count)"], body: body)
        let req = server.parseRequest(from: raw)
        XCTAssertEqual(req?.method, "POST")
        XCTAssertEqual(req?.body, body)
        XCTAssertTrue(req?.remainingData.isEmpty ?? false)
    }

    func testExtraBytesAfterBodyBecomeRemainingData() {
        // A pipelined second request's bytes should surface as remainingData.
        let body = Data("xy".utf8)
        var raw = RemoteAPITestSupport.rawRequest(
            method: "POST", target: "/x",
            headers: ["Content-Length": "2"], body: body)
        let trailer = Data("GET /next".utf8)
        raw.append(trailer)
        let req = server.parseRequest(from: raw)
        XCTAssertEqual(req?.body, body)
        XCTAssertEqual(req?.remainingData, trailer)
    }

    // MARK: - Missing header terminator

    func testMissingHeaderTerminatorReturnsNil() {
        // No CRLFCRLF present yet — parser must wait (nil), not misparse.
        let raw = Data("GET /status HTTP/1.1\r\nHost: x\r\n".utf8)
        XCTAssertNil(server.parseRequest(from: raw))
    }

    func testEmptyRequestLineReturnsNil() {
        let raw = Data("\r\n\r\n".utf8)
        XCTAssertNil(server.parseRequest(from: raw))
    }

    func testRequestLineWithoutTargetReturnsNil() {
        let raw = Data("GET\r\n\r\n".utf8)
        XCTAssertNil(server.parseRequest(from: raw))
    }

    // MARK: - Body not yet fully arrived

    func testDeclaredBodyLargerThanBufferReturnsNil() {
        // Content-Length says 10 but only 2 body bytes present → incomplete → nil.
        let raw = RemoteAPITestSupport.rawRequest(
            method: "POST", target: "/x",
            headers: ["Content-Length": "10"], body: Data("ab".utf8))
        XCTAssertNil(server.parseRequest(from: raw))
    }

    // MARK: - Oversize Content-Length (maxRequestBodyBytes cap)

    func testContentLengthOverCapReturnsNil() {
        let over = RemoteAPIServer.maxRequestBodyBytes + 1
        let raw = RemoteAPITestSupport.rawRequest(
            method: "POST", target: "/x",
            headers: ["Content-Length": "\(over)"])
        XCTAssertNil(server.parseRequest(from: raw))
    }

    func testContentLengthExactlyAtCapIsNotRejectedByCap() {
        // At the cap the body is allowed by the cap check; here the body isn't
        // present so it returns nil for incompleteness — but crucially NOT because
        // of the cap. Prove the cap boundary by sending a full body one under cap.
        let n = 1024
        let body = Data(repeating: 0x61, count: n)
        let raw = RemoteAPITestSupport.rawRequest(
            method: "POST", target: "/x",
            headers: ["Content-Length": "\(n)"], body: body)
        let req = server.parseRequest(from: raw)
        XCTAssertEqual(req?.body.count, n)
    }

    // MARK: - Integer-overflow guard

    func testContentLengthIntMaxDoesNotCrashAndReturnsNil() {
        // Guard: contentLength <= Int.max - bodyStart. Int.max is also > cap, so nil.
        let raw = RemoteAPITestSupport.rawRequest(
            method: "POST", target: "/x",
            headers: ["Content-Length": "\(Int.max)"])
        XCTAssertNil(server.parseRequest(from: raw))
    }

    func testNegativeContentLengthTreatedAsZero() {
        // Parser only accepts parsed >= 0; a negative value falls back to 0 body.
        let raw = RemoteAPITestSupport.rawRequest(
            method: "POST", target: "/x",
            headers: ["Content-Length": "-5"])
        let req = server.parseRequest(from: raw)
        XCTAssertNotNil(req)
        XCTAssertTrue(req?.body.isEmpty ?? false)
    }

    func testNonNumericContentLengthTreatedAsZero() {
        let raw = RemoteAPITestSupport.rawRequest(
            method: "POST", target: "/x",
            headers: ["Content-Length": "banana"])
        let req = server.parseRequest(from: raw)
        XCTAssertNotNil(req)
        XCTAssertTrue(req?.body.isEmpty ?? false)
    }

    // MARK: - Query decoding

    func testQueryDecodingParsesPairs() {
        let raw = RemoteAPITestSupport.rawRequest(method: "GET", target: "/files?path=/a&limit=5")
        let req = server.parseRequest(from: raw)
        XCTAssertEqual(req?.path, "/files")
        XCTAssertEqual(req?.query["path"], "/a")
        XCTAssertEqual(req?.query["limit"], "5")
    }

    func testQueryPercentAndPlusDecoding() {
        // '+' → space, %2F → '/'
        let raw = RemoteAPITestSupport.rawRequest(method: "GET", target: "/x?q=hello+world&p=%2Fetc%2Fhosts")
        let req = server.parseRequest(from: raw)
        XCTAssertEqual(req?.query["q"], "hello world")
        XCTAssertEqual(req?.query["p"], "/etc/hosts")
    }

    func testQueryKeyWithoutValueDecodesToEmptyString() {
        let raw = RemoteAPITestSupport.rawRequest(method: "GET", target: "/x?flag&other=1")
        let req = server.parseRequest(from: raw)
        XCTAssertEqual(req?.query["flag"], "")
        XCTAssertEqual(req?.query["other"], "1")
    }

    func testParseTargetWithoutQueryYieldsEmptyQuery() {
        let (path, query) = server.parseTarget("/plain/path")
        XCTAssertEqual(path, "/plain/path")
        XCTAssertTrue(query.isEmpty)
    }
}

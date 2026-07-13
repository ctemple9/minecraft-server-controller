//
//  NetworkSafetyTests.swift
//  MSCmacOSTests
//
//  Tranche #6. The audit's `NetworkSafety` type is iOS-only; on macOS the twin is
//  `MSCSettingsView.isLocalOrPrivateHost(_:)`, which is a `private` method on a
//  SwiftUI View and therefore NOT reachable even via `@testable import`. Per the
//  prompt's explicit allowance ("port a copy … choose what's testable today and
//  note the choice"), this suite pins a VERBATIM PORT of the iOS NetworkSafety rule
//  set (including the IPv6 additions from S5). If NetworkSafety.swift changes,
//  update this port in lockstep.
//
//  Source of truth: NetworkSafety.swift (iOS) — MSCSettingsView.isLocalOrPrivateHost
//  is the macOS twin but diverges for IPv6 (macOS pairing uses different input paths).
//

import XCTest

/// Verbatim port of MSCSettingsView.isLocalOrPrivateHost — keep in sync by hand.
/// IPv6 additions (::1, fe80::/10, fd00::/8) are also mirrored from NetworkSafety.swift (iOS).
private func isLocalOrPrivateHost(_ host: String) -> Bool {
    let h = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !h.isEmpty else { return false }
    if h == "localhost" || h == "127.0.0.1" { return true }
    if h.hasSuffix(".local") { return true }
    if h.hasSuffix(".ts.net") { return true }

    // IPv6: colons present and no dots (excludes IPv4-mapped ::ffff:a.b.c.d forms)
    if h.contains(":") && !h.contains(".") {
        if h == "::1" { return true }          // loopback (RFC 4291)
        if h.hasPrefix("fe80:") { return true } // link-local (fe80::/10)
        if h.hasPrefix("fd") { return true }    // ULA (fd00::/8, RFC 4193)
        return false
    }

    // IPv4 — verbatim port of MSCSettingsView
    if h.hasPrefix("10.") { return true }
    if h.hasPrefix("192.168.") { return true }
    if h.hasPrefix("172.") {
        let parts = h.split(separator: ".")
        if parts.count >= 2, let second = Int(parts[1]) {
            if (16...31).contains(second) { return true }
        }
    }
    if h.hasPrefix("169.254.") { return true }
    return false
}

final class NetworkSafetyTests: XCTestCase {

    func testLoopbackAndLocalhost() {
        XCTAssertTrue(isLocalOrPrivateHost("127.0.0.1"))
        XCTAssertTrue(isLocalOrPrivateHost("localhost"))
        XCTAssertTrue(isLocalOrPrivateHost("  LOCALHOST  "))   // trimmed + lowercased
    }

    func testMDNSLocalSuffix() {
        XCTAssertTrue(isLocalOrPrivateHost("my-mac.local"))
    }

    func testPrivateClassA10() {
        XCTAssertTrue(isLocalOrPrivateHost("10.0.0.5"))
    }

    func testPrivateClassC192_168() {
        XCTAssertTrue(isLocalOrPrivateHost("192.168.1.42"))
    }

    func test172PrivateRangeBoundaries() {
        XCTAssertTrue(isLocalOrPrivateHost("172.16.0.1"))   // low boundary
        XCTAssertTrue(isLocalOrPrivateHost("172.31.255.1")) // high boundary
        XCTAssertFalse(isLocalOrPrivateHost("172.15.0.1"))  // just below range
        XCTAssertFalse(isLocalOrPrivateHost("172.32.0.1"))  // just above range
    }

    func testLinkLocal169_254() {
        XCTAssertTrue(isLocalOrPrivateHost("169.254.1.1"))
    }

    func testPublicAddressesRejected() {
        XCTAssertFalse(isLocalOrPrivateHost("8.8.8.8"))
        XCTAssertFalse(isLocalOrPrivateHost("1.2.3.4"))
        // Tailscale CGNAT 100.x is intentionally NOT matched by this helper
        // (preferredPairingHost handles 100.* separately as a first-choice host).
        XCTAssertFalse(isLocalOrPrivateHost("100.64.0.1"))
    }

    func testEmptyRejected() {
        XCTAssertFalse(isLocalOrPrivateHost(""))
        XCTAssertFalse(isLocalOrPrivateHost("   "))
    }

    // MARK: - IPv6 (S5) — URL.host always strips brackets, so test bare forms

    func testIPv6Loopback() {
        XCTAssertTrue(isLocalOrPrivateHost("::1"))
    }

    func testIPv6LinkLocal() {
        XCTAssertTrue(isLocalOrPrivateHost("fe80::1"))
        XCTAssertTrue(isLocalOrPrivateHost("fe80::aabb:ccdd:eeff"))
    }

    func testIPv6ULA() {
        XCTAssertTrue(isLocalOrPrivateHost("fd00::1"))
        XCTAssertTrue(isLocalOrPrivateHost("fd12:3456:789a::1"))
    }

    func testIPv6PublicRejected() {
        XCTAssertFalse(isLocalOrPrivateHost("2001:db8::1"))    // documentation range
        XCTAssertFalse(isLocalOrPrivateHost("2606:4700::1"))   // public Cloudflare
    }

    func testTailscaleMagicDNS() {
        XCTAssertTrue(isLocalOrPrivateHost("my-mac.ts.net"))
        XCTAssertFalse(isLocalOrPrivateHost("example.ts.net.evil.com"))
    }
}

//
//  NetworkSafetyTests.swift
//  MSCmacOSTests
//
//  Tranche #6. The audit's `NetworkSafety` type is iOS-only; on macOS the twin is
//  `MSCSettingsView.isLocalOrPrivateHost(_:)`, which is a `private` method on a
//  SwiftUI View and therefore NOT reachable even via `@testable import`. Per the
//  prompt's explicit allowance ("port a copy … choose what's testable today and
//  note the choice"), this suite pins a VERBATIM PORT of that rule set. If the real
//  implementation in MSCSettingsView.swift changes, update this copy in lockstep.
//
//  Source of truth: MSCSettingsView.swift `isLocalOrPrivateHost(_:)` (U1 pairing fix).
//

import XCTest

/// Verbatim port of MSCSettingsView.isLocalOrPrivateHost — keep in sync by hand.
private func isLocalOrPrivateHost(_ host: String) -> Bool {
    let h = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !h.isEmpty else { return false }
    if h == "localhost" || h == "127.0.0.1" { return true }
    if h.hasSuffix(".local") { return true }
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
}

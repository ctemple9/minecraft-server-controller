//
//  RemoteAPITestSupport.swift
//  MSCmacOSTests
//
//  Shared helpers for the pure-logic unit suites (T1a).
//
//  `RemoteAPIServer.parseRequest` / `parseTarget` / `urlDecode` are *instance*
//  methods, but they touch no instance state beyond the `maxRequestBodyBytes`
//  static — so we build a throwaway server with canned providers just to have a
//  receiver to call them on. `init` never binds a socket (only `start()` does),
//  so constructing one is cheap and side-effect-free. A later prompt (2.2) will
//  reuse/replace this factory for the in-process integration suite.
//

import Foundation
import XCTest
@testable import Minecraft_Server_Controller

enum RemoteAPITestSupport {

    /// A `RemoteAPIServer` wired with inert stub providers. Does not listen.
    static func makeInertServer(port: UInt16 = 0) -> RemoteAPIServer {
        RemoteAPIServer(
            port: port,
            listenOnAllInterfaces: false,
            tokenProvider: { [:] },
            serversProvider: { [] },
            statusProvider: { RemoteAPIStatus(running: false, activeServerId: nil, pid: nil) },
            performanceProvider: {
                RemoteAPIServer.PerformanceSnapshotDTO(
                    ts: "", tps1m: nil, playersOnline: nil, cpuPercent: nil,
                    ramUsedMB: nil, ramMaxMB: nil, worldSizeMB: nil, serverType: nil)
            },
            startProvider: {},
            stopProvider: {},
            commandProvider: { _ in },
            setActiveServerProvider: { _ in false },
            playersProvider: { RemoteAPIServer.PlayersResponseDTO(players: [], count: 0) },
            allowlistProvider: { RemoteAPIServer.AllowlistResponseDTO(serverType: "java", entries: []) },
            sessionLogProvider: { RemoteAPIServer.SessionLogResponseDTO(activeServerId: nil, events: []) },
            configServersProvider: { [] },
            serverConnectionInfoProvider: { _ in nil },
            componentsProvider: {
                RemoteAPIServer.ComponentsStatusDTO(components: [], restartRequiredToApply: false)
            },
            updateComponentProvider: { _, _ in },
            broadcastStatusProvider: {
                RemoteAPIServer.BroadcastStatusDTO(xboxBroadcastRunning: false, bedrockBroadcastRunning: false)
            },
            restartBroadcastProvider: {},
            startBroadcastProvider: {},
            stopBroadcastProvider: {},
            updateBroadcastCredentialsProvider: { _ in false },
            authPromptProvider: {
                RemoteAPIServer.BroadcastAuthPromptDTO(isPresent: false, code: nil, linkURL: nil)
            },
            dismissAuthPromptProvider: {},
            broadcastAutoStartProvider: { RemoteAPIServer.BroadcastAutoStartDTO(enabled: false) },
            setBroadcastAutoStartProvider: { _ in },
            logger: { _ in }
        )
    }

    /// Builds a raw HTTP request byte-buffer with CRLF line endings.
    static func rawRequest(method: String,
                           target: String,
                           headers: [String: String] = [:],
                           body: Data = Data()) -> Data {
        var head = "\(method) \(target) HTTP/1.1\r\n"
        for (k, v) in headers { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        var data = Data(head.utf8)
        data.append(body)
        return data
    }
}

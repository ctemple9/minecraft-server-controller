// UDPRelay.swift
//  MinecraftServerController
//
// Host↔guest UDP relay for the VM Bedrock backend. Binds <listenHost>:<port> and
// forwards each client UDP flow to the guest BDS at <guestHost>:<port>, relaying
// replies back. This is the `-p <port>:<port>/udp` equivalent: it lets LAN clients
// (0.0.0.0) and playit (127.0.0.1) reach BDS running inside the VM.
//
// Built on Network.framework: a UDP NWListener yields one NWConnection per client
// flow, so multi-client isolation is automatic. Validated end-to-end against the
// appliance (RakNet ping/pong through 127.0.0.1:19132). No special entitlement.

import Foundation
import Network

final class UDPRelay {
    private let listener: NWListener
    private let guestHost: NWEndpoint.Host
    private let guestPort: NWEndpoint.Port
    private let queue = DispatchQueue(label: "msc.udp.relay")
    /// Keep each client's upstream connection alive for the flow's lifetime.
    private var upstreams: [ObjectIdentifier: NWConnection] = [:]

    init(listenHost: String, listenPort: UInt16, guestHost: String, guestPort: UInt16) throws {
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(listenHost),
                                                  port: NWEndpoint.Port(rawValue: listenPort)!)
        self.listener = try NWListener(using: params)
        self.guestHost = NWEndpoint.Host(guestHost)
        self.guestPort = NWEndpoint.Port(rawValue: guestPort)!
    }

    func start() {
        listener.newConnectionHandler = { [weak self] client in self?.handleClient(client) }
        listener.start(queue: queue)
    }

    func cancel() {
        listener.cancel()
        upstreams.values.forEach { $0.cancel() }
        upstreams.removeAll()
    }

    private func handleClient(_ client: NWConnection) {
        let up = NWConnection(host: guestHost, port: guestPort, using: .udp)
        upstreams[ObjectIdentifier(client)] = up
        client.start(queue: queue)
        up.start(queue: queue)
        pump(from: client, to: up)   // client -> guest
        pump(from: up, to: client)   // guest -> client
    }

    /// Continuously forward datagrams from one UDP connection to another.
    private func pump(from src: NWConnection, to dst: NWConnection) {
        src.receiveMessage { [weak self] data, _, _, error in
            if let data, !data.isEmpty {
                dst.send(content: data, completion: .idempotent)
            }
            if error == nil { self?.pump(from: src, to: dst) }
        }
    }
}

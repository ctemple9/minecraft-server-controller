//
//  ResourcePackHostServer.swift
//  MinecraftServerController
//
//  A tiny static HTTP file server used to host Java resource packs so that
//  connecting Java clients can download them. Java's `resource-pack` property
//  in server.properties must be a URL the *client* can reach — it cannot be a
//  local file path — so the app serves the server's `resource-packs/` folder
//  over HTTP on a configurable port.
//
//  Scope is intentionally minimal: it answers GET requests for a single file
//  in the served directory and nothing else. It is NOT a general web server.
//

import Foundation
import Network

final class ResourcePackHostServer {

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "ResourcePackHostServer.queue")

    private(set) var servedDirectory: URL?
    private(set) var boundPort: UInt16 = 0
    private(set) var isRunning = false

    /// Start serving `directory` on `port`. Restarts if already running.
    /// Binds to all interfaces so the forwarded WAN port reaches it.
    @discardableResult
    func start(directory: URL, port: UInt16) -> Bool {
        stop()
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }
        servedDirectory = directory

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params, on: nwPort)
            self.listener = listener

            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.isRunning = true
                case .failed, .cancelled:
                    self?.isRunning = false
                default:
                    break
                }
            }
            listener.start(queue: queue)
            boundPort = port
            return true
        } catch {
            isRunning = false
            return false
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        boundPort = 0
    }

    // MARK: - Connection handling

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(connection, buffer: Data())
    }

    private func receiveRequest(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }

            var buffer = buffer
            if let data { buffer.append(data) }

            // Wait for the end of the HTTP request headers.
            if buffer.range(of: Data("\r\n\r\n".utf8)) != nil {
                let header = String(decoding: buffer, as: UTF8.self)
                self.respond(connection, requestHeader: header)
            } else if error != nil || isComplete || buffer.count > 64_000 {
                connection.cancel()
            } else {
                self.receiveRequest(connection, buffer: buffer)
            }
        }
    }

    private func respond(_ connection: NWConnection, requestHeader: String) {
        guard let requestLine = requestHeader.split(separator: "\r\n", maxSplits: 1).first else {
            sendNotFound(connection); return
        }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else {
            sendNotFound(connection); return
        }

        let rawPath = String(parts[1])
        let decoded = rawPath.removingPercentEncoding ?? rawPath
        // lastPathComponent strips any directory traversal (../) — we only ever
        // serve a flat file out of the served directory.
        let fileName = (decoded as NSString).lastPathComponent

        guard !fileName.isEmpty, fileName != "/", fileName != "..",
              let dir = servedDirectory else {
            sendNotFound(connection); return
        }

        let fileURL = dir.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let fileData = try? Data(contentsOf: fileURL) else {
            sendNotFound(connection); return
        }

        var head = "HTTP/1.1 200 OK\r\n"
        head += "Content-Type: application/zip\r\n"
        head += "Content-Length: \(fileData.count)\r\n"
        head += "Connection: close\r\n\r\n"

        var response = Data(head.utf8)
        response.append(fileData)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendNotFound(_ connection: NWConnection) {
        let response = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

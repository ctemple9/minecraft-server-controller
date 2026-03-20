import Foundation

extension RemoteAPIServer {
    // MARK: - WebSocket

    func isWebSocketUpgrade(headers: [String: String]) -> Bool {
        let upgrade = headers["upgrade"]?.lowercased() ?? ""
        let connection = headers["connection"]?.lowercased() ?? ""
        return upgrade == "websocket" && connection.contains("upgrade")
    }

    func performWebSocketUpgrade(request: Request, clientFD: Int32) -> Bool {
        guard let secKey = request.headers["sec-websocket-key"], !secKey.isEmpty else {
            return false
        }

        let accept = webSocketAcceptKey(for: secKey)

        var response = Data()
        response.append(Data("HTTP/1.1 101 Switching Protocols\r\n".utf8))
        response.append(Data("Upgrade: websocket\r\n".utf8))
        response.append(Data("Connection: Upgrade\r\n".utf8))
        response.append(Data("Sec-WebSocket-Accept: \(accept)\r\n".utf8))
        response.append(Data("\r\n".utf8))

        return writeAll(response, to: clientFD)
    }

    func webSocketAcceptKey(for clientKey: String) -> String {
        let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let joined = clientKey.trimmingCharacters(in: .whitespacesAndNewlines) + magic
        let digest = SHA1.hash(Data(joined.utf8))
        return Data(digest).base64EncodedString()
    }

    func sendWebSocketJSON(_ dto: ConsoleLineDTO, clientFD: Int32) {
        do {
            let data = try JSONEncoder().encode(dto)
            if let text = String(data: data, encoding: .utf8) {
                _ = sendWebSocketText(text, clientFD: clientFD)
            }
        } catch {
            // Ignore encoding failures for streaming
        }
    }

    func sendWebSocketText(_ text: String, clientFD: Int32) -> Bool {
        let payload = Data(text.utf8)
        var frame = Data()

        frame.append(0x81) // FIN + Text opcode

        let len = payload.count
        if len <= 125 {
            frame.append(UInt8(len))
        } else if len <= 65535 {
            frame.append(126)
            frame.appendUInt16BE(UInt16(len))
        } else {
            frame.append(127)
            frame.appendUInt64BE(UInt64(len))
        }

        frame.append(payload)
        return writeAll(frame, to: clientFD)
    }

    func sendWebSocketPong(_ payload: Data, clientFD: Int32) {
        var frame = Data()
        frame.append(0x8A) // FIN + pong

        let len = payload.count
        if len <= 125 {
            frame.append(UInt8(len))
        } else if len <= 65535 {
            frame.append(126)
            frame.appendUInt16BE(UInt16(len))
        } else {
            frame.append(127)
            frame.appendUInt64BE(UInt64(len))
        }

        frame.append(payload)
        _ = writeAll(frame, to: clientFD)
    }

    func sendWebSocketClose(clientFD: Int32) {
        var frame = Data()
        frame.append(0x88) // FIN + close
        frame.append(0x00) // no payload
        _ = writeAll(frame, to: clientFD)
    }

    func parseWebSocketFrames(clientFD: Int32) {
        guard var buffer = clientBuffers[clientFD] else { return }

        while true {
            if buffer.count < 2 { break }

            let b0 = buffer[0]
            let b1 = buffer[1]

            let fin = (b0 & 0x80) != 0
            let opcode = b0 & 0x0F

            let masked = (b1 & 0x80) != 0
            var payloadLen = Int(b1 & 0x7F)

            var offset = 2

            if payloadLen == 126 {
                if buffer.count < offset + 2 { break }
                payloadLen = Int(buffer.readUInt16BE(at: offset))
                offset += 2
            } else if payloadLen == 127 {
                if buffer.count < offset + 8 { break }
                let big = buffer.readUInt64BE(at: offset)
                if big > UInt64(Int.max) {
                    sendWebSocketClose(clientFD: clientFD)
                    teardownClient(clientFD)
                    return
                }
                payloadLen = Int(big)
                offset += 8
            }

            if payloadLen > Self.maxWebSocketClientFrameBytes {
                sendWebSocketClose(clientFD: clientFD)
                teardownClient(clientFD)
                return
            }

            var maskKey: [UInt8] = []
            if masked {
                if buffer.count < offset + 4 { break }
                maskKey = [buffer[offset], buffer[offset + 1], buffer[offset + 2], buffer[offset + 3]]
                offset += 4
            }

            if buffer.count < offset + payloadLen { break }

            var payload = buffer.subdata(in: offset..<(offset + payloadLen))

            buffer.removeSubrange(0..<(offset + payloadLen))

            if masked, maskKey.count == 4, payload.count > 0 {
                var bytes = [UInt8](payload)
                for i in 0..<bytes.count {
                    bytes[i] = bytes[i] ^ maskKey[i % 4]
                }
                payload = Data(bytes)
            }

            switch opcode {
            case 0x8: // close
                sendWebSocketClose(clientFD: clientFD)
                teardownClient(clientFD)
                return

            case 0x9: // ping
                sendWebSocketPong(payload, clientFD: clientFD)

            case 0xA: // pong
                break

            case 0x1: // text
                // Command messages are intentionally ignored over WebSocket
                break

            default:
                break
            }

            if !fin {
                // Ignoring fragmentation for now
            }
        }

        clientBuffers[clientFD] = buffer
    }

}

import Foundation

// MARK: - Component & Broadcast route handlers
//
// Called from RemoteAPIServer+HTTP.swift for:
//   GET  /components
//   POST /components/update
//   GET  /broadcast/status
//   POST /broadcast/restart
//   POST /broadcast/credentials

extension RemoteAPIServer {

    // MARK: - GET /components

    func handleGetComponents(clientFD: Int32) {
        Task { [weak self] in
            guard let self else { return }
            let dto = await componentsProvider()
            sendJSON(statusCode: 200, reason: "OK", encodable: dto, clientFD: clientFD)
        }
    }

    // MARK: - POST /components/update

    func handleUpdateComponent(body: Data, clientFD: Int32) {
        guard !body.isEmpty else {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "missing_body"], clientFD: clientFD)
            return
        }

        do {
            let decoded = try JSONDecoder().decode(ComponentUpdateRequestDTO.self, from: body)
            let component = decoded.component.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            guard ["paper", "geyser", "floodgate"].contains(component) else {
                sendJSON(statusCode: 400, reason: "Bad Request",
                         jsonObject: ["error": "unknown_component"], clientFD: clientFD)
                return
            }

            let capturedFD = clientFD
            updateComponentProvider(component) { [weak self] result in
                guard let self else { return }
                let status = result.success ? 200 : 500
                let reason = result.success ? "OK" : "Internal Server Error"
                self.sendJSON(statusCode: status, reason: reason, encodable: result, clientFD: capturedFD)
            }
        } catch {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "invalid_json"], clientFD: clientFD)
        }
    }

    // MARK: - GET /broadcast/autostart

    func handleGetBroadcastAutoStart(clientFD: Int32) {
        let dto = broadcastAutoStartProvider()
        sendJSON(statusCode: 200, reason: "OK", encodable: dto, clientFD: clientFD)
    }

    // MARK: - POST /broadcast/autostart

    func handleSetBroadcastAutoStart(body: Data, clientFD: Int32) {
        struct Body: Decodable { let enabled: Bool }
        guard let decoded = try? JSONDecoder().decode(Body.self, from: body) else {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "invalid_json"], clientFD: clientFD)
            return
        }
        setBroadcastAutoStartProvider(decoded.enabled)
        sendJSON(statusCode: 200, reason: "OK",
                 encodable: BroadcastAutoStartDTO(enabled: decoded.enabled), clientFD: clientFD)
    }

    // MARK: - GET /broadcast/auth-prompt

    func handleGetAuthPrompt(clientFD: Int32) {
        let dto = authPromptProvider()
        sendJSON(statusCode: 200, reason: "OK", encodable: dto, clientFD: clientFD)
    }

    // MARK: - POST /broadcast/auth-prompt/dismiss

    func handleDismissAuthPrompt(clientFD: Int32) {
        dismissAuthPromptProvider()
        sendJSON(statusCode: 200, reason: "OK",
                 jsonObject: ["result": "dismissed"], clientFD: clientFD)
    }

    // MARK: - POST /broadcast/start

    func handleStartBroadcast(clientFD: Int32) {
        startBroadcastProvider()
        sendJSON(statusCode: 200, reason: "OK",
                 jsonObject: ["result": "broadcast_start_requested"], clientFD: clientFD)
    }

    // MARK: - POST /broadcast/stop

    func handleStopBroadcast(clientFD: Int32) {
        stopBroadcastProvider()
        sendJSON(statusCode: 200, reason: "OK",
                 jsonObject: ["result": "broadcast_stop_requested"], clientFD: clientFD)
    }

    // MARK: - GET /broadcast/status

    func handleGetBroadcastStatus(clientFD: Int32) {
        let dto = broadcastStatusProvider()
        sendJSON(statusCode: 200, reason: "OK", encodable: dto, clientFD: clientFD)
    }

    // MARK: - POST /broadcast/restart

    func handleRestartBroadcast(clientFD: Int32) {
        restartBroadcastProvider()
        sendJSON(statusCode: 200, reason: "OK",
                 jsonObject: ["result": "broadcast_restart_requested"], clientFD: clientFD)
    }

    // MARK: - POST /broadcast/credentials

    func handleUpdateBroadcastCredentials(body: Data, clientFD: Int32) {
        guard !body.isEmpty else {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "missing_body"], clientFD: clientFD)
            return
        }

        do {
            let decoded = try JSONDecoder().decode(BroadcastCredentialsDTO.self, from: body)

            guard !decoded.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !decoded.password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !decoded.gamertag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                sendJSON(statusCode: 400, reason: "Bad Request",
                         jsonObject: ["error": "missing_fields"], clientFD: clientFD)
                return
            }

            let ok = updateBroadcastCredentialsProvider(decoded)
            if ok {
                sendJSON(statusCode: 200, reason: "OK",
                         jsonObject: ["result": "credentials_updated"], clientFD: clientFD)
            } else {
                sendJSON(statusCode: 500, reason: "Internal Server Error",
                         jsonObject: ["error": "update_failed"], clientFD: clientFD)
            }
        } catch {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "invalid_json"], clientFD: clientFD)
        }
    }
}

import Foundation

extension RemoteAPIServer {

    // MARK: - GET /users

    func handleGetUsers(clientFD: Int32) {
        Task { [weak self] in
            guard let self else { return }
            let dto = await listUsersProvider()
            sendJSON(statusCode: 200, reason: "OK", encodable: dto, clientFD: clientFD)
        }
    }

    // MARK: - POST /users

    func handleCreateUser(body: Data, clientFD: Int32) {
        struct Body: Decodable {
            let label: String
            let role: String
            let permissions: [String]?
            let expiresInDays: Int?
        }
        guard let req = try? JSONDecoder().decode(Body.self, from: body) else {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "invalid_json"], clientFD: clientFD)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let result = await createUserProvider(req.label, req.role, req.permissions, req.expiresInDays)
            let status = result.success ? 200 : (result.message == "label_empty" ? 400 : 422)
            sendJSON(statusCode: status, reason: result.success ? "OK" : "Unprocessable",
                     encodable: result, clientFD: clientFD)
        }
    }

    // MARK: - POST /users/revoke

    func handleRevokeUser(body: Data, clientFD: Int32) {
        struct Body: Decodable { let userId: String }
        guard let req = try? JSONDecoder().decode(Body.self, from: body) else {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "invalid_json"], clientFD: clientFD)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let result = await revokeUserProvider(req.userId)
            let status = result.success ? 200 : (result.message == "not_found" ? 404 : 500)
            sendJSON(statusCode: status, reason: result.success ? "OK" : "Error",
                     encodable: result, clientFD: clientFD)
        }
    }

    // MARK: - POST /users/update

    func handleUpdateUser(body: Data, clientFD: Int32) {
        struct Body: Decodable {
            let userId: String
            let label: String?
            let role: String?
            let permissions: [String]?
            let expiresInDays: Int?     // -1 = clear expiry, nil = no change, >0 = set days from now
        }
        guard let req = try? JSONDecoder().decode(Body.self, from: body) else {
            sendJSON(statusCode: 400, reason: "Bad Request",
                     jsonObject: ["error": "invalid_json"], clientFD: clientFD)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let result = await updateUserProvider(req.userId, req.label, req.role, req.permissions, req.expiresInDays)
            let status: Int
            switch result.message {
            case "not_found":    status = 404
            case "label_empty":  status = 400
            default:             status = result.success ? 200 : 422
            }
            sendJSON(statusCode: status, reason: result.success ? "OK" : "Error",
                     encodable: result, clientFD: clientFD)
        }
    }
}

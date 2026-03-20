//
//  ServerEditorModels.swift
//  MinecraftServerController
//

import Foundation

/// Whether the editor is creating a new server or editing an existing one.
enum ServerEditorMode {
    case new
    case edit
}

/// Simple form backing struct with Strings for text fields.
/// Note: ConfigServer.minRam / maxRam are treated as GB here.
struct ServerEditorData {
    var id: String
    var displayName: String
    var serverDir: String
    var paperJarPath: String
    var minRamGB: String
    var maxRamGB: String
    var notes: String

    // Bug 1 fix: preserve serverType so Bedrock servers are not silently reset to .java on save.
    var serverType: ServerType

    /// Default empty form for "Add Server".
    static func empty() -> ServerEditorData {
        ServerEditorData(
            id: UUID().uuidString,
            displayName: "",
            serverDir: "",
            paperJarPath: "",
            minRamGB: "2",
            maxRamGB: "4",
            notes: "",
            serverType: .java
        )
    }

    init(id: String,
         displayName: String,
         serverDir: String,
         paperJarPath: String,
         minRamGB: String,
         maxRamGB: String,
         notes: String,
         serverType: ServerType = .java) {
        self.id = id
        self.displayName = displayName
        self.serverDir = serverDir
        self.paperJarPath = paperJarPath
        self.minRamGB = minRamGB
        self.maxRamGB = maxRamGB
        self.notes = notes
        self.serverType = serverType
    }

    /// Build editor data from a ConfigServer.
    init(from server: ConfigServer) {
        self.id = server.id
        self.displayName = server.displayName
        self.serverDir = server.serverDir
        self.paperJarPath = server.paperJarPath
        self.minRamGB = "\(server.minRam)"
        self.maxRamGB = "\(server.maxRam)"
        self.notes = server.notes
        // Bug 1 fix: copy serverType from the source ConfigServer.
        self.serverType = server.serverType
    }

    /// Convert form data back into a ConfigServer for saving.
    func toConfigServer() -> ConfigServer {
        let min = Int(minRamGB) ?? 2
        let max = Int(maxRamGB) ?? Swift.max(min, 4)

        // Bug 1 fix: pass serverType through so a Bedrock server stays Bedrock after editing.
        var result = ConfigServer(
            id: id,
            displayName: displayName,
            serverDir: serverDir,
            paperJarPath: paperJarPath,
            minRamGB: min,
            maxRamGB: max,
            notes: notes
        )
        result.serverType = serverType
        return result
    }
}


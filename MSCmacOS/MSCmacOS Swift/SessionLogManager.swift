//
//  SessionLogManager.swift
//  MinecraftServerController
//
//
//  Owns the SessionEvent model and all disk I/O for {serverDir}/session_log.json.
//  Thread-safety: all public methods are called on the MainActor (via AppViewModel).

import Foundation

// MARK: - Model

/// A single player join or leave event, persisted to session_log.json.
struct SessionEvent: Identifiable, Codable, Hashable {
    let id: UUID
    let playerName: String
    let eventType: SessionEventType
    let timestamp: Date

    enum SessionEventType: String, Codable, Hashable {
        case joined
        case left
    }

    init(id: UUID = UUID(), playerName: String, eventType: SessionEventType, timestamp: Date = Date()) {
        self.id = id
        self.playerName = playerName
        self.eventType = eventType
        self.timestamp = timestamp
    }
}

// MARK: - Manager

/// Reads, writes, and appends session events for a single server directory.
/// The file is {serverDir}/session_log.json.
struct SessionLogManager {

    // MARK: - URL helpers

    static func logFileURL(serverDir: String) -> URL {
        URL(fileURLWithPath: serverDir, isDirectory: true)
            .appendingPathComponent("session_log.json")
    }

    // MARK: - Read

    /// Load all persisted events for a server directory. Returns [] on any error.
    static func loadEvents(serverDir: String) -> [SessionEvent] {
        let url = logFileURL(serverDir: serverDir)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([SessionEvent].self, from: data)
        } catch {
            return []
        }
    }

    // MARK: - Write

    /// Persist the full event list to disk. Silently swallows write errors
    /// (caller logs via AppViewModel if needed).
    static func saveEvents(_ events: [SessionEvent], serverDir: String) throws {
        let url = logFileURL(serverDir: serverDir)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(events)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Append

    /// Append a single event and flush to disk immediately.
    /// Returns the updated full list on success; throws on write failure.
    @discardableResult
    static func appendEvent(
        _ event: SessionEvent,
        toServerDir serverDir: String,
        existing: inout [SessionEvent]
    ) throws -> [SessionEvent] {
        existing.append(event)
        try saveEvents(existing, serverDir: serverDir)
        return existing
    }

    // MARK: - Clear

    /// Wipe the log file entirely.
    static func clearEvents(serverDir: String) throws {
        let url = logFileURL(serverDir: serverDir)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

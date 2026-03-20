//
//  AppViewModel+SessionLog.swift
//  MinecraftServerController
//
//  Owns session event parsing, loading, appending, and clearing for the
//  selected server.

import Foundation

extension AppViewModel {

    // MARK: - Load on server switch

    func loadSessionLogForSelectedServer() {
        guard let server = selectedServer,
              let cfg = configServer(for: server) else {
            sessionEvents = []
            return
        }
        sessionEvents = SessionLogManager.loadEvents(serverDir: cfg.serverDir)
    }

    // MARK: - Clear log

    func clearSessionLog() {
        guard let server = selectedServer,
              let cfg = configServer(for: server) else { return }
        do {
            try SessionLogManager.clearEvents(serverDir: cfg.serverDir)
            sessionEvents = []
            logAppMessage("[Session] Cleared session log for \(cfg.displayName).")
        } catch {
            logAppMessage("[Session] Failed to clear session log: \(error.localizedDescription)")
        }
    }

    // MARK: - Record a new event (called from output parsing)

    /// Append a join or leave event for the selected server and persist it.
    func recordSessionEvent(playerName: String, eventType: SessionEvent.SessionEventType) {
        guard let server = selectedServer,
              let cfg = configServer(for: server) else { return }

        let event = SessionEvent(playerName: playerName, eventType: eventType)
        do {
            try SessionLogManager.appendEvent(event, toServerDir: cfg.serverDir, existing: &sessionEvents)
        } catch {
            logAppMessage("[Session] Failed to persist session event for \(playerName): \(error.localizedDescription)")
        }
    }

    // MARK: - Grouped day sections for the timeline UI

    /// Events grouped into chronological day buckets, most-recent day first.
    var sessionEventsByDay: [(day: Date, events: [SessionEvent])] {
        let calendar = Calendar.current

        // Group by calendar day
        var dict: [Date: [SessionEvent]] = [:]
        for event in sessionEvents {
            let day = calendar.startOfDay(for: event.timestamp)
            dict[day, default: []].append(event)
        }

        // Sort days descending; events within each day ascending
        return dict
            .sorted { $0.key > $1.key }
            .map { (day: $0.key, events: $0.value.sorted { $0.timestamp < $1.timestamp }) }
    }

    // MARK: - Duration helper

    /// Given a join event, look forward in the same session log for the
    /// matching leave event for that player. Returns the duration string if
    /// both ends are found, nil otherwise.
    func sessionDuration(after joinEvent: SessionEvent) -> String? {
        guard joinEvent.eventType == .joined else { return nil }

        // Look forward in the full list from this event's position
        guard let startIdx = sessionEvents.firstIndex(where: { $0.id == joinEvent.id }) else {
            return nil
        }

        let afterJoin = sessionEvents[(startIdx + 1)...]
        guard let leaveEvent = afterJoin.first(where: {
            $0.playerName.caseInsensitiveCompare(joinEvent.playerName) == .orderedSame &&
            $0.eventType == .left
        }) else { return nil }

        let seconds = Int(leaveEvent.timestamp.timeIntervalSince(joinEvent.timestamp))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let rem = minutes % 60
        return "\(hours)h \(rem)m"
    }
}

//
//  AppViewModel+Notifications.swift
//  MinecraftServerController
//
//  Delivers macOS notifications for player join/leave and server start/stop
//  events. Per-server preferences gate which event types fire.

import Foundation
import UserNotifications

// MARK: - Notification event types

enum ServerNotificationEvent {
    case serverStarted
    case serverStopped
    case playerJoined(playerName: String)
    case playerLeft(playerName: String)
}

// MARK: - AppViewModel notification extension

extension AppViewModel {

    // MARK: - Permission request

    /// Request UNUserNotificationCenter authorization.
    /// Call once at app launch (or lazily before first notification).
    /// Safe to call multiple times — UNUserNotificationCenter deduplicates.
    func requestNotificationPermissionIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                Task { @MainActor in
                    self.logAppMessage("[Notifications] Authorization error: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Core dispatch

    /// Fires a notification for the given event if the per-server prefs allow it.
    /// - Parameters:
    ///   - event: The notification event type.
    ///   - serverName: Display name of the server, used in notification body.
    ///   - serverId: Used to look up per-server preferences.
    func fireNotificationIfEnabled(event: ServerNotificationEvent, serverName: String, serverId: String) {
        // Look up per-server preferences from persisted config.
        guard let prefs = notificationPrefs(forServerId: serverId) else { return }

        let allowed: Bool
        switch event {
        case .serverStarted:   allowed = prefs.notifyOnStart
        case .serverStopped:   allowed = prefs.notifyOnStop
        case .playerJoined:    allowed = prefs.notifyOnPlayerJoin
        case .playerLeft:      allowed = prefs.notifyOnPlayerLeave
        }
        guard allowed else { return }

        let (title, body) = notificationContent(for: event, serverName: serverName)
        scheduleLocalNotification(identifier: notificationIdentifier(for: event, serverId: serverId),
                                   title: title,
                                   body: body)
    }

    // MARK: - Notification content

    private func notificationContent(for event: ServerNotificationEvent,
                                     serverName: String) -> (title: String, body: String) {
        switch event {
        case .serverStarted:
            return ("Server Started", "\(serverName) is now online.")
        case .serverStopped:
            return ("Server Stopped", "\(serverName) has stopped.")
        case .playerJoined(let name):
            return ("Player Joined", "\(name) joined \(serverName)")
        case .playerLeft(let name):
            return ("Player Left", "\(name) left \(serverName)")
        }
    }

    // MARK: - Unique identifier per event (prevents stacking duplicates)

    private func notificationIdentifier(for event: ServerNotificationEvent, serverId: String) -> String {
        let base = "msc.\(serverId)"
        switch event {
        case .serverStarted:           return "\(base).started"
        case .serverStopped:           return "\(base).stopped"
        case .playerJoined(let name):  return "\(base).joined.\(name)"
        case .playerLeft(let name):    return "\(base).left.\(name)"
        }
    }

    // MARK: - UNUserNotificationCenter delivery

    private func scheduleLocalNotification(identifier: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil  // deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Task { @MainActor in
                    self.logAppMessage("[Notifications] Delivery error for '\(title)': \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Per-server prefs access helpers

    /// Returns the notification preferences for a given server ID, or nil if not found.
    func notificationPrefs(forServerId serverId: String) -> ServerNotificationPrefs? {
        configManager.config.servers.first(where: { $0.id == serverId })?.notificationPrefs
    }

    /// Persists updated notification preferences for a server.
    func setNotificationPrefs(_ prefs: ServerNotificationPrefs, forServerId serverId: String) {
        guard let idx = configManager.config.servers.firstIndex(where: { $0.id == serverId }) else { return }
        configManager.config.servers[idx].notificationPrefs = prefs
        configManager.save()
        logAppMessage("[Notifications] Updated notification preferences for \(configManager.config.servers[idx].displayName).")
    }
}

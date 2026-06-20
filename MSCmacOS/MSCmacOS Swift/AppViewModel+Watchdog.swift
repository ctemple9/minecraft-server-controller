//
//  AppViewModel+Watchdog.swift
//  MinecraftServerController
//

import Foundation

extension AppViewModel {

    // MARK: - Async API (Preferences toggle)

    func enableWatchdog() async throws {
        let bundlePath = Bundle.main.bundlePath
        try await Task.detached(priority: .utility) {
            try WatchdogRunner.enable(bundlePath: bundlePath)
        }.value
        watchdogEnabled = true
        logAppMessage("[Watchdog] Enabled — MSC will relaunch on crash.")
    }

    func disableWatchdog() async throws {
        try await Task.detached(priority: .utility) {
            try WatchdogRunner.disable()
        }.value
        watchdogEnabled = false
        logAppMessage("[Watchdog] Disabled.")
    }

    // MARK: - Startup check (called from init, synchronous entry point)

    func checkWatchdogStatus() {
        let currentBundlePath = Bundle.main.bundlePath
        Task.detached { [weak self] in
            let status = WatchdogRunner.checkStatus()

            if status.isLoaded {
                // Regenerate plist if the app was moved since last enable.
                if let stored = status.storedBundlePath,
                   stored != currentBundlePath,
                   !currentBundlePath.isEmpty {
                    if (try? WatchdogRunner.enable(bundlePath: currentBundlePath)) != nil {
                        await MainActor.run { self?.logAppMessage("[Watchdog] Updated plist with new app path.") }
                    }
                }
                // Mark this session as active so the watchdog script can detect a crash.
                WatchdogRunner.markSessionActive()
            }

            await MainActor.run { self?.watchdogEnabled = status.isLoaded }
        }
    }

    // MARK: - Sync API (Remote API HTTP handler thread)

    nonisolated func enableWatchdogSync() -> String? {
        let bundlePath = Bundle.main.bundlePath
        do {
            try WatchdogRunner.enable(bundlePath: bundlePath)
            WatchdogRunner.markSessionActive()
            DispatchQueue.main.async { [weak self] in self?.watchdogEnabled = true }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    nonisolated func disableWatchdogSync() -> String? {
        do {
            try WatchdogRunner.disable()
            DispatchQueue.main.async { [weak self] in self?.watchdogEnabled = false }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

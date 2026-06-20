//
//  AppViewModel+JavaProcessCleanup.swift
//  MinecraftServerController
//
//  Scans for orphaned Java server processes left over from a crash or
//  unclean exit and offers to terminate them before starting a new server.
//

import Foundation
import Darwin

extension AppViewModel {

    struct JavaServerProcessMatch: Identifiable {
        let pid: pid_t
        let command: String
        let isCurrentManagedServer: Bool

        var id: pid_t { pid }
    }

    enum JavaProcessCleanupResult {
        case gracefullyStoppedCurrentServer
        case terminatedGhostProcesses(count: Int)
        case noMatchingProcesses
        case failed(message: String)
    }

    // Called from AppViewModel.init() — scans for orphaned Java processes from a prior
    // crash and publishes the count so the UI can show a warning banner.
    // PIDs to exclude are captured synchronously on the main actor here, then the
    // blocking ps call runs in a Task.detached so the main thread is never stalled.
    func checkForOrphansOnStartup() {
        let excluded: Set<pid_t> = [
            pid_t(ProcessInfo.processInfo.processIdentifier),
            javaBackend.processID,
            broadcastManager.processID
        ].compactMap { $0 }.reduce(into: Set()) { $0.insert($1) }

        Task.detached { [weak self] in
            let count = (try? JavaProcessScanner.scan(excludedPIDs: excluded).count) ?? 0
            await MainActor.run { self?.orphanedJavaProcessCount = count }
        }
    }

    // Called from applicationWillTerminate — synchronously force-kills all running
    // server processes so they don't outlive the app on a normal quit.
    func forceTerminateAllRunningProcesses() {
        if isServerRunning {
            activeBackend?.terminate()
        }
        if let matches = try? findKillableJavaServerProcesses() {
            for match in matches {
                Darwin.kill(match.pid, SIGKILL)
            }
        }
    }

    // Called by PreferencesProcessCleanupSection. Captures excluded PIDs on the
    // main actor synchronously, then does the blocking ps scan in Task.detached.
    func scanOrphansInBackground(completion: @escaping @MainActor (Int) -> Void) {
        let excluded: Set<pid_t> = [
            pid_t(ProcessInfo.processInfo.processIdentifier),
            javaBackend.processID,
            broadcastManager.processID
        ].compactMap { $0 }.reduce(into: Set()) { $0.insert($1) }

        Task.detached {
            let count = (try? JavaProcessScanner.scan(excludedPIDs: excluded).count) ?? 0
            await MainActor.run { completion(count) }
        }
    }

    func killJavaServerProcesses() {
        switch killJavaServerProcessesInternal() {
        case .gracefullyStoppedCurrentServer:
            logAppMessage("[App] Used normal stop flow for the currently running Java server.")

        case .terminatedGhostProcesses(let count):
            let noun = count == 1 ? "process" : "processes"
            logAppMessage("[App] Terminated \(count) ghost Java server \(noun).")
            refreshHealthCardsForSelectedServer()

        case .noMatchingProcesses:
            showError(
                title: "No Java Server Process Found",
                message: "MSC could not find a running Java server process to terminate."
            )

        case .failed(let message):
            showError(title: "Kill Java Process Failed", message: message)
        }
    }

    private func killJavaServerProcessesInternal() -> JavaProcessCleanupResult {
        let currentJavaServerIsRunning = isServerRunning && ((activeBackend as AnyObject?) === javaBackend)
        if currentJavaServerIsRunning {
            stopServer()
            return .gracefullyStoppedCurrentServer
        }

        let matches: [JavaServerProcessMatch]
        do {
            matches = try findKillableJavaServerProcesses()
        } catch {
            return .failed(message: error.localizedDescription)
        }

        guard !matches.isEmpty else {
            logAppMessage("[App] No matching ghost Java server processes found.")
            return .noMatchingProcesses
        }

        var terminatedCount = 0
        var failureMessages: [String] = []

        for match in matches {
            if Darwin.kill(match.pid, SIGTERM) == 0 {
                terminatedCount += 1
                logAppMessage("[App] Terminated Java server process pid=\(match.pid).")
            } else {
                let reason = String(cString: strerror(errno))
                failureMessages.append("pid \(match.pid): \(reason)")
                logAppMessage("[App] Failed to terminate Java server process pid=\(match.pid): \(reason)")
            }
        }

        if terminatedCount > 0 {
            return .terminatedGhostProcesses(count: terminatedCount)
        }

        return .failed(message: failureMessages.joined(separator: "\n"))
    }

    func findKillableJavaServerProcesses() throws -> [JavaServerProcessMatch] {
        let excludedPIDs: Set<pid_t> = [
            pid_t(ProcessInfo.processInfo.processIdentifier),
            javaBackend.processID,
            broadcastManager.processID
        ].compactMap { $0 }.reduce(into: Set()) { $0.insert($1) }

        return try JavaProcessScanner.scan(excludedPIDs: excludedPIDs)
            .map { entry in
                JavaServerProcessMatch(
                    pid: entry.pid,
                    command: entry.command,
                    isCurrentManagedServer: javaBackend.processID == entry.pid
                )
            }
    }
}


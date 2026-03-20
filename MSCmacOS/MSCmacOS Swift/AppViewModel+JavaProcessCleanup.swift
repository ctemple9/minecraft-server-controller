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

    private func findKillableJavaServerProcesses() throws -> [JavaServerProcessMatch] {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,command="]
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw NSError(
                domain: "MinecraftServerController.JavaProcessCleanup",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not inspect running processes: \(error.localizedDescription)"]
            )
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let currentAppPID = ProcessInfo.processInfo.processIdentifier
        let managedJavaPID = javaBackend.processID
        let excludedPIDs: Set<pid_t> = [currentAppPID, managedJavaPID, broadcastManager.processID, bedrockConnectManager.processID]
            .compactMap { $0 }
            .reduce(into: Set<pid_t>()) { $0.insert($1) }

        return output
            .split(whereSeparator: \.isNewline)
            .compactMap { parseJavaServerProcessLine(String($0), excludedPIDs: excludedPIDs) }
    }

    private func parseJavaServerProcessLine(_ line: String, excludedPIDs: Set<pid_t>) -> JavaServerProcessMatch? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let scanner = Scanner(string: trimmed)
        guard let pidInt = scanner.scanInt() else { return nil }
        let pid = pid_t(pidInt)
        guard !excludedPIDs.contains(pid) else { return nil }

        let commandStart = trimmed.index(trimmed.startIndex, offsetBy: scanner.currentIndex.utf16Offset(in: trimmed))
        let command = String(trimmed[commandStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return nil }

        let lower = command.lowercased()
        guard lower.contains("java") else { return nil }
        guard lower.contains("-jar") else { return nil }
        guard lower.contains("--nogui") || lower.contains("paper") || lower.contains("purpur") || lower.contains("spigot") else {
            return nil
        }
        guard !lower.contains("bedrockconnect") else { return nil }
        guard !lower.contains("mcxboxbroadcast") else { return nil }

        let isCurrentManagedServer = javaBackend.processID == pid
        return JavaServerProcessMatch(pid: pid, command: command, isCurrentManagedServer: isCurrentManagedServer)
    }
}

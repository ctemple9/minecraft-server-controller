//
//  JavaProcessScanner.swift
//  MinecraftServerController
//
//  Standalone ps scanner with no actor isolation — safe to call from
//  Task.detached without hopping to @MainActor.
//

import Foundation
import Darwin

struct JavaProcessEntry {
    let pid: pid_t
    let command: String
}

enum JavaProcessScanner {
    // nonisolated opts out of @MainActor since this project uses -default-isolation=MainActor.
    // The scan is pure I/O + computation and is safe to call from any thread.
    nonisolated static func scan(excludedPIDs: Set<pid_t>) throws -> [JavaProcessEntry] {
        let proc = Process()
        let outputPipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        // -ww: unlimited output width — without this, ps truncates long JVM
        // command lines to ~80 chars when run without a terminal, which cuts off
        // the JAR filename and --nogui flag that the filter matches against.
        proc.arguments = ["-axww", "-o", "pid=,command="]
        proc.standardOutput = outputPipe
        proc.standardError = Pipe()

        do {
            try proc.run()
        } catch {
            throw NSError(
                domain: "MinecraftServerController.JavaProcessCleanup",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not inspect running processes: \(error.localizedDescription)"]
            )
        }

        // Read BEFORE waitUntilExit — with -ww, ps output can exceed the 64KB pipe
        // buffer, causing ps to block on write while waitUntilExit blocks on exit.
        // Reading first drains the buffer so ps can finish writing and exit cleanly.
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""

        return output
            .split(whereSeparator: \.isNewline)
            .compactMap { parseLine(String($0), excludedPIDs: excludedPIDs) }
    }

    private nonisolated static func parseLine(_ line: String, excludedPIDs: Set<pid_t>) -> JavaProcessEntry? {
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
        guard !lower.contains("mcxboxbroadcast") else { return nil }

        return JavaProcessEntry(pid: pid, command: command)
    }
}

//
//  AuditLogger.swift
//  MinecraftServerController
//
//  Lightweight JSONL audit trail for Remote API POST mutations and auth failures.
//  All file I/O runs on a dedicated serial writer queue — the socket queue hands off
//  a plain struct and returns immediately.
//

import Foundation

final class AuditLogger {

    struct Entry {
        let timestamp: Date
        let clientIP: String
        let tokenLabel: String
        let method: String
        let path: String
        let statusCode: Int
    }

    // Injected for tests — called on the writer queue after each entry is flushed.
    var testObserver: ((Entry) -> Void)?

    private let writerQueue = DispatchQueue(label: "AuditLogger.writer", qos: .utility)
    private let loggerFn: (String) -> Void

    private static let retentionDays = 30

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let fileDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    init(logger: @escaping (String) -> Void) {
        self.loggerFn = logger
    }

    // MARK: - Public API

    func pruneOldFilesAsync() {
        writerQueue.async { [weak self] in self?.pruneOldFiles() }
    }

    func log(_ entry: Entry) {
        writerQueue.async { [weak self] in self?.write(entry) }
    }

    // MARK: - Private

    private func auditDirectory() -> URL? {
        guard let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return appSupport
            .appendingPathComponent("MinecraftServerController", isDirectory: true)
            .appendingPathComponent("audit", isDirectory: true)
    }

    private func auditFileURL(for date: Date) -> URL? {
        guard let dir = auditDirectory() else { return nil }
        let name = "audit-\(Self.fileDateFormatter.string(from: date)).jsonl"
        return dir.appendingPathComponent(name)
    }

    private func pruneOldFiles() {
        guard let dir = auditDirectory() else { return }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return }
        let cutoff = Date().addingTimeInterval(-Double(Self.retentionDays) * 86_400)
        for url in contents
        where url.pathExtension == "jsonl" && url.lastPathComponent.hasPrefix("audit-") {
            if let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate,
               created < cutoff {
                try? fm.removeItem(at: url)
            }
        }
    }

    private func write(_ entry: Entry) {
        guard let fileURL = auditFileURL(for: entry.timestamp) else { return }
        let dir = fileURL.deletingLastPathComponent()
        let fm = FileManager.default

        if !fm.fileExists(atPath: dir.path) {
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
            } catch {
                loggerFn("[AuditLog] Cannot create audit directory: \(error.localizedDescription)")
                return
            }
        }

        // Build the JSONL line manually — no JSONEncoder per spec (hot-path constraint).
        let ts = Self.isoFormatter.string(from: entry.timestamp)
        let line =
            #"{"ts":"\#(esc(ts))","ip":"\#(esc(entry.clientIP))","token":"\#(esc(entry.tokenLabel))","method":"\#(esc(entry.method))","path":"\#(esc(entry.path))","status":\#(entry.statusCode)}"#
            + "\n"

        guard let data = line.data(using: .utf8) else { return }

        if fm.fileExists(atPath: fileURL.path) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
            } else {
                loggerFn("[AuditLog] Cannot open audit file for appending.")
            }
        } else {
            do {
                try data.write(to: fileURL, options: [])
            } catch {
                loggerFn("[AuditLog] Cannot create audit file: \(error.localizedDescription)")
            }
        }

        testObserver?(entry)
    }

    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\n", with: "\\n")
         .replacingOccurrences(of: "\r", with: "\\r")
    }
}

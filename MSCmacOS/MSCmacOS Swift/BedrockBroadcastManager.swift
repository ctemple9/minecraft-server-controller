//
//  BedrockBroadcastManager.swift
//  MinecraftServerController
//
//  Manages the MCXboxBroadcast Standalone process for Bedrock/BDS servers.
//  Runs `java -jar MCXboxBroadcastStandalone.jar` natively — no Docker needed.
//  Same JAR as the Java-server broadcast (XboxBroadcastProcessManager).
//
//  How MCXboxBroadcast Standalone works:
//   1. It authenticates with Xbox Live as an alt account.
//   2. When a Bedrock friend taps "Join Game", Xbox Live routes them to the process
//      via NetherNet. The process sends a fake StartGame packet, then immediately
//      sends a TransferPacket pointing the client to session-info.ip:port.
//   3. The client then connects DIRECTLY to BDS using that IP and port.
//
//  All configuration is via config.yml — there are NO environment variables.
//  We write config.yml before each start so ip/port stay current.
//  Auth tokens live in cache/cache.json and survive process restarts.
//

import Foundation

final class BedrockBroadcastManager {

    enum BroadcastError: Swift.Error {
        case alreadyRunning
        case failedToStart(String)
    }

    var onOutputLine: ((String) -> Void)?
    var onDidTerminate: (() -> Void)?

    private var process: Process?
    private var outputPipe: Pipe?
    private var pendingOutput = Data()

    var isRunning: Bool { process?.isRunning ?? false }

    // MARK: - Data directory

    /// Host directory where config.yml and cache/cache.json (auth token) live.
    /// Passed as the working directory to the JAR so it finds config.yml automatically.
    static func dataDirectoryURL(for server: ConfigServer) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("MSC")
            .appendingPathComponent("MCXboxBroadcastBDS")
            .appendingPathComponent(server.id)
    }

    // MARK: - config.yml

    /// Writes config.yml to the data directory.
    /// Called before every start so ip/port stay in sync.
    /// Does NOT touch cache/cache.json (auth tokens).
    static func writeConfig(to dataDir: URL, serverName: String, ip: String, port: Int) throws {
        let safeName = serverName.replacingOccurrences(of: "\"", with: "\\\"")
        let yaml = """
        session:
          update-interval: 30
          query-server: true
          web-query-fallback: true
          config-fallback: true
          session-info:
            host-name: "\(safeName)"
            world-name: "\(safeName)"
            players: 0
            max-players: 20
            ip: "\(ip)"
            port: \(port)
        debug-mode: false
        suppress-session-update-message: false
        friend-sync:
          update-interval: 60
          auto-follow: true
          auto-unfollow: true
          initial-invite: true
          expiry:
            enabled: true
            days: 15
            check: 1800
        notifications:
          enabled: false
          webhook-url: ""
        """
        let configURL = dataDir.appendingPathComponent("config.yml")
        try yaml.write(to: configURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Start

    func start(for server: ConfigServer, ip: String, port: Int?, javaPath: String, jarPath: String) throws {
        guard !isRunning else { throw BroadcastError.alreadyRunning }

        pendingOutput.removeAll(keepingCapacity: false)

        // Prepare data directory + config.yml
        let dataDir = Self.dataDirectoryURL(for: server)
        do {
            try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        } catch {
            throw BroadcastError.failedToStart("Could not create config directory: \(error.localizedDescription)")
        }
        let resolvedPort = port ?? 19132
        do {
            try Self.writeConfig(to: dataDir, serverName: server.displayName, ip: ip, port: resolvedPort)
        } catch {
            throw BroadcastError.failedToStart("Could not write config.yml: \(error.localizedDescription)")
        }

        // Validate java path.
        // "java" (no slash) is a command name — use /usr/bin/env so the shell's PATH is searched.
        // "/path/to/java" (contains slash) is an absolute path — verify it exists first.
        let expandedJava = (javaPath.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard !expandedJava.isEmpty else {
            throw BroadcastError.failedToStart("Java path is empty — please set it in Preferences.")
        }
        let javaExecURL: URL
        let javaPrefixArgs: [String]
        if expandedJava.contains("/") {
            guard FileManager.default.fileExists(atPath: expandedJava) else {
                throw BroadcastError.failedToStart("Java not found at: \(expandedJava)")
            }
            javaExecURL = URL(fileURLWithPath: expandedJava)
            javaPrefixArgs = []
        } else {
            javaExecURL = URL(fileURLWithPath: "/usr/bin/env")
            javaPrefixArgs = [expandedJava]
        }

        let trimmedJar = jarPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedJar.isEmpty else {
            throw BroadcastError.failedToStart("MCXboxBroadcast JAR path is not configured. Download it in Edit Server → Broadcast.")
        }
        let expandedJar = (trimmedJar as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expandedJar) else {
            throw BroadcastError.failedToStart("MCXboxBroadcast JAR not found at: \(expandedJar). Download it in Edit Server → Broadcast.")
        }

        // Launch java -jar <jar> with the data directory as the working directory
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = javaExecURL
        proc.arguments = javaPrefixArgs + ["-jar", expandedJar]
        proc.currentDirectoryURL = dataDir
        proc.standardOutput = pipe
        proc.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            if data.isEmpty { self.flushPendingOutput(); return }
            self.handleIncoming(data: data)
        }

        proc.terminationHandler = { [weak self] _ in
            guard let self else { return }
            self.flushPendingOutput()
            self.cleanupProcess()
            self.onDidTerminate?()
        }

        self.process = proc
        self.outputPipe = pipe

        do {
            try proc.run()
        } catch {
            cleanupProcess()
            throw BroadcastError.failedToStart(error.localizedDescription)
        }
    }

    // MARK: - Stop

    func stop() {
        guard let proc = process else { cleanupProcess(); return }
        if proc.isRunning {
            proc.terminate()
        } else {
            flushPendingOutput()
            cleanupProcess()
            onDidTerminate?()
        }
    }

    // MARK: - Output

    private func handleIncoming(data: Data) {
        pendingOutput.append(data)
        let newline = Data([0x0A])
        while let range = pendingOutput.firstRange(of: newline) {
            let lineData = pendingOutput.subdata(in: 0..<range.lowerBound)
            pendingOutput.removeSubrange(0..<range.upperBound)
            let line = String(data: lineData, encoding: .utf8) ?? String(decoding: lineData, as: UTF8.self)
            onOutputLine?(line)
        }
    }

    private func flushPendingOutput() {
        guard !pendingOutput.isEmpty else { return }
        let data = pendingOutput
        pendingOutput.removeAll(keepingCapacity: false)
        let line = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        onOutputLine?(line)
    }

    private func cleanupProcess() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe?.fileHandleForReading.closeFile()
        outputPipe = nil
        process = nil
    }
}

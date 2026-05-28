//
//  BedrockBroadcastManager.swift
//  MinecraftServerController
//
//  Manages the MCXboxBroadcast Standalone Docker container for Bedrock/BDS servers.
//
//  How MCXboxBroadcast Standalone works:
//   1. It authenticates with Xbox Live as an alt account.
//   2. When a Bedrock friend taps "Join Game", Xbox Live routes them to the container
//      via NetherNet. The container sends a fake StartGame packet, then immediately
//      sends a TransferPacket pointing the client to session-info.ip:port.
//   3. The client then connects DIRECTLY to BDS using that IP and port.
//
//  All configuration is via config.yml — there are NO environment variables.
//  We write config.yml before each start so ip/port stay current.
//  Auth tokens live in cache/cache.json and survive container recreations.
//

import Foundation

final class BedrockBroadcastManager {

    enum BroadcastError: Swift.Error {
        case alreadyRunning
        case dockerNotAvailable(String)
        case failedToStart(String)
    }

    var onOutputLine: ((String) -> Void)?
    var onDidTerminate: (() -> Void)?

    private var logsProcess: Process?
    private(set) var currentContainerName: String?

    var isRunning: Bool {
        guard let name = currentContainerName,
              let docker = DockerUtility.dockerPath() else { return false }
        return DockerUtility.isContainerRunning(name: name, dockerPath: docker)
    }

    // MARK: - Container naming

    static func containerName(for server: ConfigServer) -> String {
        let safe = server.id
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9-]", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "msc-broadcast-\(safe)"
    }

    // MARK: - Data directory

    /// Host directory mounted to /opt/app/config inside the container.
    /// MCXboxBroadcast writes config.yml and cache/cache.json (auth token) here.
    static func dataDirectoryURL(for server: ConfigServer) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("MSC")
            .appendingPathComponent("MCXboxBroadcastBDS")
            .appendingPathComponent(server.id)
    }

    // MARK: - config.yml

    /// Writes config.yml to the data directory.
    /// Called before every container start so ip/port stay in sync.
    /// Does NOT touch cache/cache.json (auth tokens).
    static func writeConfig(to dataDir: URL, serverName: String, ip: String, port: Int) throws {
        // Escape double-quotes for YAML string values.
        let safeName = serverName.replacingOccurrences(of: "\"", with: "\\\"")

        let yaml = """
        session:
          update-interval: 30
          query-server: true
          # Fall back to config values when MCXboxBroadcast can't ping BDS directly
          # (common in Docker bridge networking on Mac).
          web-query-fallback: true
          config-fallback: true
          session-info:
            host-name: "\(safeName)"
            world-name: "\(safeName)"
            players: 0
            max-players: 20
            # ip is the address Bedrock CLIENTS will be transferred to — must be
            # the Mac's LAN IP (or public IP for external players), NOT a Docker
            # internal hostname like host.docker.internal.
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

    func start(for server: ConfigServer, ip: String, port: Int?) throws {
        guard let docker = DockerUtility.dockerPath() else {
            let reason = DockerUtility.dockerNotAvailableReason() ?? "Docker not found."
            throw BroadcastError.dockerNotAvailable(reason)
        }

        let name = Self.containerName(for: server)

        if DockerUtility.isContainerRunning(name: name, dockerPath: docker) {
            throw BroadcastError.alreadyRunning
        }

        // Remove any stopped container with the same name so `docker run` succeeds.
        if DockerUtility.containerExists(name: name, dockerPath: docker) {
            DockerUtility.runCapture(executable: docker, args: ["rm", name])
        }

        // Ensure the config/auth persistence directory exists.
        let dataDir = Self.dataDirectoryURL(for: server)
        do {
            try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        } catch {
            throw BroadcastError.failedToStart("Could not create config directory: \(error.localizedDescription)")
        }

        // Write config.yml with the caller-supplied IP and port.
        // The caller resolves the right IP based on the user's IP mode preference.
        let resolvedPort = port ?? 19132
        do {
            try Self.writeConfig(to: dataDir, serverName: server.displayName, ip: ip, port: resolvedPort)
        } catch {
            throw BroadcastError.failedToStart("Could not write config.yml: \(error.localizedDescription)")
        }

        // No env vars needed — all config is in config.yml.
        // Mount the config dir to /opt/app/config (the image's WORKDIR).
        let args: [String] = [
            "run", "-d",
            "--name", name,
            "-v", "\(dataDir.path):/opt/app/config",
            "--restart=no",
            "ghcr.io/mcxboxbroadcast/standalone:latest"
        ]

        let result = DockerUtility.runCapture(executable: docker, args: args)
        guard let result, result.exitCode == 0 else {
            let msg = result?.output.trimmingCharacters(in: .whitespacesAndNewlines) ?? "docker run failed"
            throw BroadcastError.failedToStart(msg)
        }

        currentContainerName = name
        startLogStreaming(containerName: name, dockerPath: docker)
    }

    // MARK: - Stop

    func stop() {
        logsProcess?.terminate()
        logsProcess = nil
        if let name = currentContainerName, let docker = DockerUtility.dockerPath() {
            DockerUtility.runCapture(executable: docker, args: ["stop", name])
            DockerUtility.runCapture(executable: docker, args: ["rm", name])
        }
        currentContainerName = nil
    }

    // MARK: - Log streaming

    private func startLogStreaming(containerName: String, dockerPath: String) {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: dockerPath)
        p.arguments = ["logs", "-f", containerName]
        p.environment = DockerUtility.dockerEnvironment()
        p.standardOutput = pipe
        p.standardError = pipe

        var pending = Data()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            pending.append(data)
            while let nl = pending.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = pending[..<nl]
                pending.removeSubrange(...nl)
                if let line = String(data: lineData, encoding: .utf8)?
                    .trimmingCharacters(in: CharacterSet.controlCharacters.union(.whitespaces)),
                   !line.isEmpty {
                    self?.onOutputLine?(line)
                }
            }
        }

        p.terminationHandler = { [weak self] _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async { self?.onDidTerminate?() }
        }

        do {
            try p.run()
            logsProcess = p
        } catch {
            onOutputLine?("[BroadcastBDS] Failed to stream logs: \(error.localizedDescription)")
        }
    }
}

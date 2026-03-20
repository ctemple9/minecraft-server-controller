// BedrockServerBackend.swift
//  MinecraftServerController
//
//
// Architecture:
//   - Runs the official itzg/minecraft-bedrock-server image in a DETACHED container.
//   - Container name is derived from the ConfigServer ID so it is deterministic
//     and survives app restarts (we can always find the container by name).
//   - World data is bind-mounted from serverDir → /data inside the container,
//     so world files persist on the host between container restarts.
//   - Output is streamed via "docker logs -f" on a background thread, not via
//     docker attach. This is more robust for detached containers.
//   - Commands are sent via "docker exec <name> send-command <cmd>".
//     The itzg image ships a "send-command" helper that pipes to BDS stdin.
//   - Port: UDP 19132 (Bedrock) — never TCP.

import Foundation
import AppKit

// MARK: - Docker utility

/// Lightweight, synchronous Docker CLI wrapper.
/// All methods are safe to call from any thread.
enum DockerUtility {

    // MARK: Docker binary resolution

    /// Resolves the Docker CLI binary path.
    static func dockerPath() -> String? {
        let candidates = [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/usr/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker"
        ]
        let fm = FileManager.default
        for path in candidates {
            if fm.isExecutableFile(atPath: path) { return path }
        }
        if let found = runCapture(executable: "/usr/bin/which", args: ["docker"]),
           found.exitCode == 0 {
            let resolved = found.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !resolved.isEmpty, fm.isExecutableFile(atPath: resolved) {
                return resolved
            }
        }
        return nil
    }

    static func dockerEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let helperBin = "/Applications/Docker.app/Contents/Resources/bin"
        let currentPath = env["PATH"] ?? ""
        if !currentPath.split(separator: ":").contains(helperBin[...]) {
            env["PATH"] = currentPath.isEmpty ? helperBin : "\(currentPath):\(helperBin)"
        }
        return env
    }

    @discardableResult
    static func openDockerDesktopIfInstalled() -> Bool {
        let dockerApp = URL(fileURLWithPath: "/Applications/Docker.app")
        guard FileManager.default.fileExists(atPath: dockerApp.path) else { return false }
        do {
            try NSWorkspace.shared.launchApplication(at: dockerApp,
                                                    options: [.withoutActivation],
                                                    configuration: [:])
            return true
        } catch {
            return false
        }
    }

    static func waitForDockerDaemon(timeout: TimeInterval = 45.0, pollInterval: TimeInterval = 1.0) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isDockerAvailable() { return true }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        return isDockerAvailable()
    }

    static func ensureDockerAvailable(autoLaunch: Bool = true) -> Bool {
        if isDockerAvailable() { return true }
        if autoLaunch { _ = openDockerDesktopIfInstalled() }
        return waitForDockerDaemon()
    }

    // MARK: Docker status checks

    static func isDockerAvailable() -> Bool {
        guard let docker = dockerPath() else { return false }
        guard let result = runCapture(executable: docker, args: ["info", "--format", "{{.ID}}"] ) else {
            return false
        }
        return result.exitCode == 0
    }

    static func dockerNotAvailableReason() -> String? {
        guard dockerPath() != nil else {
            return "Docker is not installed. Install Docker Desktop from docker.com, then restart the app."
        }
        guard isDockerAvailable() else {
            return "Docker is installed but the daemon is not running. Open Docker Desktop and wait for it to start, then try again."
        }
        return nil
    }

    // MARK: Image management

    static func isImagePresent(_ image: String, dockerPath: String) -> Bool {
        guard let result = runCapture(executable: dockerPath, args: ["image", "inspect", "--format", "{{.Id}}", image]) else {
            return false
        }
        return result.exitCode == 0
    }

    @discardableResult
    static func pullImage(_ image: String,
                          dockerPath: String,
                          onLine: ((String) -> Void)? = nil) -> CapturedRun? {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: dockerPath)
        p.arguments = ["pull", image]
        p.environment = dockerEnvironment()
        p.standardOutput = pipe
        p.standardError = pipe

        var buffer = Data()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            buffer.append(data)
            drainLines(from: &buffer, emit: onLine)
        }

        do {
            try p.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            onLine?("Failed to run docker pull: \(error.localizedDescription)")
            return nil
        }

        p.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil

        if !buffer.isEmpty {
            let remaining = String(data: buffer, encoding: .utf8) ?? String(decoding: buffer, as: UTF8.self)
            let trimmed = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { onLine?(trimmed) }
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let success = p.terminationStatus == 0 || isImagePresent(image, dockerPath: dockerPath)
        return CapturedRun(exitCode: success ? 0 : p.terminationStatus, output: output)
    }

    // MARK: Container state

    static func isContainerRunning(name: String, dockerPath: String) -> Bool {
        guard let result = runCapture(executable: dockerPath, args: [
            "inspect", "--format", "{{.State.Running}}", name
        ]) else { return false }
        return result.exitCode == 0 && result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    static func containerExists(name: String, dockerPath: String) -> Bool {
        guard let result = runCapture(executable: dockerPath, args: [
            "inspect", "--format", "{{.Name}}", name
        ]) else { return false }
        return result.exitCode == 0
    }

    // MARK: - Synchronous run-and-capture

    struct CapturedRun {
        let exitCode: Int32
        let output: String
    }

    static func runCapture(executable: String, args: [String]) -> CapturedRun? {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        p.environment = dockerEnvironment()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
        } catch {
            return nil
        }
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        return CapturedRun(exitCode: p.terminationStatus, output: text)
    }

    private static func drainLines(from buffer: inout Data, emit: ((String) -> Void)?) {
        let newline = Data([0x0A])
        while let range = buffer.firstRange(of: newline) {
            let lineData = buffer.subdata(in: 0..<range.lowerBound)
            buffer.removeSubrange(0..<range.upperBound)
            let line = String(data: lineData, encoding: .utf8) ?? String(decoding: lineData, as: UTF8.self)
            let trimmed = line.trimmingCharacters(in: .newlines)
            if !trimmed.isEmpty { emit?(trimmed) }
        }
    }
}

// MARK: - BedrockServerBackend

/// ServerBackend implementation that runs Bedrock Dedicated Server inside a Docker container.
///
/// Container lifecycle:
///   start() → docker run -d  →  docker logs -f (streams output on background thread)
///   stop()  → docker exec send-command stop  →  docker stop  →  docker rm
///   sendCommand() → docker exec <name> send-command <cmd>
///
/// The container name is derived from the ConfigServer.id so it is deterministic
/// and unique per server. Format: "psc-bds-<first-12-chars-of-id>"
final class BedrockServerBackend: ServerBackend {

    // MARK: - ServerBackend conformance

    var onOutputLine: ((String) -> Void)?
    var onDidTerminate: (() -> Void)?
    var lastCommandError: String? = nil

    var isRunning: Bool {
        guard let docker = resolvedDockerPath, let name = currentContainerName else {
            return false
        }
        return DockerUtility.isContainerRunning(name: name, dockerPath: docker)
    }

    // MARK: - Internal state

    private var resolvedDockerPath: String?
    private var currentContainerName: String?

    /// The log-streaming process ("docker logs -f ...").
    /// Kept as a reference so we can terminate it when the server stops.
    private var logProcess: Process?
    private var logOutputPipe: Pipe?

    /// Buffer for partial log lines (same pattern as ServerProcessManager).
    private var pendingOutput = Data()

    /// Serialises access to pendingOutput and the log process from the output handler thread.
    private let outputLock = NSLock()

    // MARK: - Container name helpers

    /// Derives a deterministic container name from the server ID.
    /// Docker container names must match [a-zA-Z0-9][a-zA-Z0-9_.-]*
    /// ConfigServer.id is a UUID string; we strip hyphens and take the first 12 chars.
    static func containerName(forServerId id: String) -> String {
        let stripped = id.replacingOccurrences(of: "-", with: "")
        let prefix = String(stripped.prefix(12))
        return "psc-bds-\(prefix)"
    }

    // MARK: - Start

    func start(config: ConfigServer, appConfig: AppConfig) throws {
        // 1. Resolve Docker binary — fail fast with a clear error if missing.
        guard let docker = DockerUtility.dockerPath() else {
            throw ServerBackendError.failedToStart(makeError(
                "Docker is not installed. Install Docker Desktop from docker.com to run Bedrock servers."
            ))
        }

        // 2. Check that the daemon is actually running, auto-launching Docker Desktop when possible.
        guard DockerUtility.ensureDockerAvailable(autoLaunch: true) else {
            throw ServerBackendError.failedToStart(makeError(
                "Docker is installed but not running. MSC tried to open Docker Desktop, but the daemon did not become ready in time."
            ))
        }

        // 3. Guard against double-start.
        let name = Self.containerName(forServerId: config.id)
        if DockerUtility.isContainerRunning(name: name, dockerPath: docker) {
            throw ServerBackendError.alreadyRunning
        }

        // 4. Remove any leftover stopped container with the same name.
        //    This happens if the app crashed or the container was stopped externally.
        if DockerUtility.containerExists(name: name, dockerPath: docker) {
            emitLine("[Docker] Removing leftover container '\(name)'...")
            _ = DockerUtility.runCapture(executable: docker, args: ["rm", "-f", name])
        }

        // 5. Determine which Docker image to use.
        let image = config.bedrockDockerImage ?? "itzg/minecraft-bedrock-server"

        // 6. Pull the image if not present locally (streams progress to the console).
        if !DockerUtility.isImagePresent(image, dockerPath: docker) {
            emitLine("[Docker] Image '\(image)' not found locally. Pulling — this may take a minute...")
            try pullImage(image, dockerPath: docker)
            emitLine("[Docker] Image pull complete.")
        } else {
            emitLine("[Docker] Image '\(image)' found locally.")
        }

        // 7. Build the docker run arguments.
                //    Key decisions:
                //    - "-d" runs detached so we get a container ID back immediately.
                //    - "--name" gives the container a deterministic name for all subsequent operations.
                //    - "-p <port>:<port>/udp" maps the Bedrock port. UDP is required — not TCP.
                //    - "-v serverDir:/data" bind-mounts world data to the host so it persists.
                //    - "-e EULA=TRUE" accepts the Mojang EULA automatically (the host already accepted it).
                //    - We pass the current saved Bedrock properties into the container so the image
                //      does not revert server.properties back to its default startup values.
                //    - "--restart=no" prevents Docker from auto-restarting the container; the app controls lifecycle.
                //    - "--rm" is NOT used — we want the container to survive for log inspection after stop.
                let serverDir = config.serverDir
                let savedProps = BedrockPropertiesManager.readModel(serverDir: serverDir)
                let port = savedProps.serverPort
                let portV6 = savedProps.serverPortV6
                let portMapping = "\(port):\(port)/udp"
                let volumeMapping = "\(serverDir):/data"

                var runArgs: [String] = [
                    "run",
                    "-d",
                    "--name", name,
                    "-p", portMapping,
                    "-v", volumeMapping,
                    "-e", "EULA=TRUE",
                    "-e", "SERVER_NAME=\(config.displayName)",
                    "-e", "LEVEL_NAME=\(savedProps.levelName)",
                    "-e", "MAX_PLAYERS=\(savedProps.maxPlayers)",
                    "-e", "ONLINE_MODE=\(savedProps.onlineMode ? "true" : "false")",
                    "-e", "ALLOW_CHEATS=\(savedProps.allowCheats ? "true" : "false")",
                    "-e", "DIFFICULTY=\(savedProps.difficulty.bdsKey)",
                    "-e", "GAMEMODE=\(savedProps.gamemode.bdsKey)",
                    "-e", "SERVER_PORT=\(port)",
                    "-e", "SERVER_PORT_V6=\(portV6)",
                    "--restart=no"
                ]

                // Pin to a specific BDS version if configured.
                // The itzg image reads BEDROCK_SERVER_VERSION at container start.
                // nil, empty, or "LATEST" means use the image default (latest stable).
                if let version = config.bedrockVersion,
                   !version.isEmpty,
                   version.uppercased() != "LATEST" {
                    runArgs.append(contentsOf: ["-e", "BEDROCK_SERVER_VERSION=\(version)"])
                }

                runArgs.append(image)

                emitLine("[Docker] Starting container '\(name)' on UDP port \(port)...")
        // 8. Launch the detached container.
        guard let runResult = DockerUtility.runCapture(executable: docker, args: runArgs) else {
            throw ServerBackendError.failedToStart(makeError(
                "Failed to execute docker run. Is Docker accessible?"
            ))
        }

        guard runResult.exitCode == 0 else {
            let detail = runResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ServerBackendError.failedToStart(makeError(
                "docker run failed (exit \(runResult.exitCode)): \(detail)"
            ))
        }

        // 9. Store state.
        resolvedDockerPath = docker
        currentContainerName = name

        // 10. Start streaming container logs on a background thread.
        startLogStreaming(containerName: name, dockerPath: docker)

        emitLine("[Docker] Container '\(name)' started. Streaming output...")
    }

    // MARK: - Stop

    @discardableResult
    func stop() -> Bool {
        guard let docker = resolvedDockerPath, let name = currentContainerName else {
            lastCommandError = "No active container to stop."
            return false
        }

        // 1. Attempt graceful stop via send-command (gives BDS a chance to save the world).
        //    This is equivalent to typing "stop" in the BDS console.
        //    We ignore errors here — if BDS is unresponsive we fall through to docker stop.
        emitLine("[Docker] Sending 'stop' command to BDS...")
        _ = DockerUtility.runCapture(executable: docker, args: [
            "exec", name, "send-command", "stop"
        ])

        // 2. docker stop with a 30s timeout gives BDS time to finish saving.
        emitLine("[Docker] Stopping container '\(name)'...")
        guard let stopResult = DockerUtility.runCapture(executable: docker, args: [
            "stop", "--time", "30", name
        ]) else {
            lastCommandError = "Failed to execute docker stop."
            return false
        }

        if stopResult.exitCode != 0 {
            let detail = stopResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            lastCommandError = "docker stop failed: \(detail)"
            emitLine("[Docker] docker stop returned non-zero: \(detail)")
            // Don't return false here — fall through and clean up anyway.
        }

        // 3. Stop the log-streaming process.
        terminateLogProcess()

        // 4. Remove the container so the name is free for the next start.
        //    We keep world data because it lives on the host volume, not inside the container.
        _ = DockerUtility.runCapture(executable: docker, args: ["rm", "-f", name])

        // 5. Signal termination to AppViewModel.
        currentContainerName = nil
        fireDidTerminate()

        return true
    }

    // MARK: - Terminate (force kill)

        /// Forcibly kills the container without a graceful stop.
        /// Used by AppDelegate on app quit. Skips the send-command step.
        func terminate() {
            guard let docker = resolvedDockerPath, let name = currentContainerName else { return }
            terminateLogProcess()
            _ = DockerUtility.runCapture(executable: docker, args: ["kill", name])
            _ = DockerUtility.runCapture(executable: docker, args: ["rm", "-f", name])
            currentContainerName = nil
            fireDidTerminate()
        }

        // MARK: - Send command

        @discardableResult
        func sendCommand(_ command: String) -> Bool {
        guard let docker = resolvedDockerPath, let name = currentContainerName else {
            lastCommandError = "Server is not running."
            return false
        }

        guard DockerUtility.isContainerRunning(name: name, dockerPath: docker) else {
            lastCommandError = "Container is not running."
            return false
        }

        // The itzg image ships a "send-command" script that pipes stdin to BDS.
        // Usage: docker exec <container> send-command <command>
        // The command is a single string argument; send-command handles the newline.
        guard let result = DockerUtility.runCapture(executable: docker, args: [
            "exec", name, "send-command", command
        ]) else {
            lastCommandError = "Failed to execute docker exec."
            return false
        }

        if result.exitCode != 0 {
            let detail = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            lastCommandError = "docker exec send-command failed: \(detail)"
            return false
        }

        lastCommandError = nil
        return true
    }

    // MARK: - Image pull (with streaming output)

    /// Pulls the given Docker image, streaming progress lines to onOutputLine.
    /// Throws ServerBackendError.failedToStart on failure.
    private func pullImage(_ image: String, dockerPath: String) throws {
        guard let result = DockerUtility.pullImage(image, dockerPath: dockerPath, onLine: { [weak self] line in
            self?.emitLine(line)
        }) else {
            throw ServerBackendError.failedToStart(makeError(
                "Failed to run docker pull. Is Docker accessible?"
            ))
        }

        guard result.exitCode == 0 else {
            let detail = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ServerBackendError.failedToStart(makeError(
                detail.isEmpty
                    ? "docker pull '\(image)' failed with exit code \(result.exitCode)."
                    : detail
            ))
        }
    }

    // MARK: - Log streaming

    /// Starts "docker logs -f --tail=200 <name>" on a background thread.
    /// Output lines are forwarded to onOutputLine.
    ///
    /// We intentionally include a recent tail so the app captures the Bedrock
    /// startup lines even when the detached container begins logging before the
    /// app attaches to docker logs.
    private func startLogStreaming(containerName: String, dockerPath: String) {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: dockerPath)
        p.arguments = ["logs", "-f", "--tail=200", containerName]
        p.standardOutput = pipe
        p.standardError = pipe  // BDS writes to stderr too

        logOutputPipe = pipe
        logProcess = p

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            if data.isEmpty {
                // EOF — container stopped.
                self.flushPendingOutput()
                // Fire termination if the container is gone and we haven't already.
                if let docker = self.resolvedDockerPath,
                   let name = self.currentContainerName,
                   !DockerUtility.isContainerRunning(name: name, dockerPath: docker) {
                    self.terminateLogProcess()
                    self.currentContainerName = nil
                    self.fireDidTerminate()
                }
                return
            }
            self.handleIncoming(data: data)
        }

        p.terminationHandler = { [weak self] process in
            guard let self else { return }
            self.flushPendingOutput()
            // If we reach here without stop() having been called, the container died unexpectedly.
            if self.currentContainerName != nil {
                self.currentContainerName = nil
                self.fireDidTerminate()
            }
        }

        do {
            try p.run()
        } catch {
            emitLine("[Docker] Warning: failed to start log streaming: \(error.localizedDescription)")
        }
    }

    private func terminateLogProcess() {
        logOutputPipe?.fileHandleForReading.readabilityHandler = nil
        logOutputPipe?.fileHandleForReading.closeFile()
        if logProcess?.isRunning == true {
            logProcess?.terminate()
        }
        logProcess = nil
        logOutputPipe = nil
    }

    // MARK: - Output line handling (mirrors ServerProcessManager)

    private func handleIncoming(data: Data) {
        outputLock.lock()
        pendingOutput.append(data)
        let newline = Data([0x0A])
        while let range = pendingOutput.firstRange(of: newline) {
            let lineData = pendingOutput.subdata(in: 0..<range.lowerBound)
            pendingOutput.removeSubrange(0..<range.upperBound)
            let line = String(data: lineData, encoding: .utf8)
                ?? String(decoding: lineData, as: UTF8.self)
            outputLock.unlock()
            emitLine(line)
            outputLock.lock()
        }
        outputLock.unlock()
    }

    private func flushPendingOutput() {
        outputLock.lock()
        guard !pendingOutput.isEmpty else {
            outputLock.unlock()
            return
        }
        let data = pendingOutput
        pendingOutput.removeAll(keepingCapacity: false)
        outputLock.unlock()

        let line = String(data: data, encoding: .utf8)
            ?? String(decoding: data, as: UTF8.self)
        emitLine(line)
    }

    /// Drains complete newline-terminated lines from a mutable Data buffer,
    /// calling `emit` for each one. Used during image pull streaming.
    private func drainLines(from buffer: inout Data, emit: (String) -> Void) {
        let newline = Data([0x0A])
        while let range = buffer.firstRange(of: newline) {
            let lineData = buffer.subdata(in: 0..<range.lowerBound)
            buffer.removeSubrange(0..<range.upperBound)
            let line = String(data: lineData, encoding: .utf8)
                ?? String(decoding: lineData, as: UTF8.self)
            emit(line)
        }
    }

    // MARK: - Helpers

    private func emitLine(_ line: String) {
        onOutputLine?(line)
    }

    private func fireDidTerminate() {
        DispatchQueue.main.async { [weak self] in
            self?.onDidTerminate?()
        }
    }

    private func makeError(_ message: String) -> NSError {
        NSError(
            domain: "MinecraftServerController.BedrockServerBackend",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}


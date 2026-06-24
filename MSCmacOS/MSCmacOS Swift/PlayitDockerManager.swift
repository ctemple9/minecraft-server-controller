//
//  PlayitDockerManager.swift
//  MinecraftServerController
//
//  Manages a single shared Docker container that runs the playit Linux binary
//  alongside socat proxies for all tunnel types (Java TCP, Bedrock UDP, Voice Chat UDP).
//
//  Architecture:
//   - One container "msc_playit_agent" is shared across all servers (only one runs at a time).
//   - On start: writes Dockerfile + entrypoint.sh, builds image if absent, starts container.
//   - socat proxies forward container ports to host.docker.internal (the Mac host).
//   - playit Linux binary auto-creates tunnels for active ports on first connection.
//   - Config persists in Application Support so secret key survives restarts.
//   - Logs are streamed via "docker logs -f" — claim URL and tunnel addresses are parsed.
//

import Foundation

final class PlayitDockerManager {

    static let imageName      = "msc-playit-agent"
    static let containerName  = "msc_playit_agent"

    var onOutputLine: ((String) -> Void)?
    var onDidTerminate: (() -> Void)?

    private var logProcess: Process?
    private var logPipe: Pipe?
    private var pendingOutput = Data()
    private let outputLock = NSLock()
    private var stoppedIntentionally = false
    private var didFireTerminate = false

    // MARK: - State

    /// Cached running state — avoids a synchronous docker inspect on every check.
    private(set) var isRunning: Bool = false

    // MARK: - Image build

    /// Returns true if the msc-playit-agent image already exists.
    func imageExists(dockerPath: String) -> Bool {
        DockerUtility.isImagePresent(Self.imageName, dockerPath: dockerPath)
    }

    /// Writes Dockerfile + entrypoint.sh to a build context dir and runs docker build.
    func buildImage(configDir: URL, dockerPath: String) -> Bool {
        let buildCtx = configDir.appendingPathComponent("build-context", isDirectory: true)
        let fm = FileManager.default
        try? fm.createDirectory(at: buildCtx, withIntermediateDirectories: true)

        let dockerfile = """
        FROM alpine:3.19
        RUN apk add --no-cache socat wget ca-certificates
        RUN ARCH=$(uname -m) && \\
            case "$ARCH" in \\
              x86_64)  PLAYIT_ARCH="amd64" ;; \\
              aarch64) PLAYIT_ARCH="aarch64" ;; \\
              *) echo "Unsupported arch: $ARCH" >&2 && exit 1 ;; \\
            esac && \\
            wget -q -O /usr/local/bin/playit \\
              "https://github.com/playit-cloud/playit-agent/releases/latest/download/playit-linux-${PLAYIT_ARCH}" && \\
            chmod +x /usr/local/bin/playit
        COPY entrypoint.sh /entrypoint.sh
        RUN chmod +x /entrypoint.sh
        ENTRYPOINT ["/entrypoint.sh"]
        """

        let entrypoint = """
        #!/bin/sh
        HOST="${HOST_GATEWAY:-host.docker.internal}"

        # TCP proxy for Java Minecraft
        if [ "${JAVA_PORT:-0}" -gt 0 ]; then
            socat TCP4-LISTEN:${JAVA_PORT},reuseaddr,fork \\
                  TCP4:${HOST}:${JAVA_PORT} &
        fi

        # UDP proxy for Bedrock / Geyser — bidirectional
        if [ "${BEDROCK_PORT:-0}" -gt 0 ]; then
            socat UDP4-LISTEN:${BEDROCK_PORT},reuseaddr,fork \\
                  UDP4:${HOST}:${BEDROCK_PORT} &
        fi

        # UDP proxy for Simple Voice Chat — bidirectional
        if [ "${VOICE_PORT:-0}" -gt 0 ]; then
            socat UDP4-LISTEN:${VOICE_PORT},reuseaddr,fork \\
                  UDP4:${HOST}:${VOICE_PORT} &
        fi

        if [ -z "${PLAYIT_SECRET}" ]; then
            echo "[MSC] No playit secret key configured. Enable the tunnel in Server Settings and add your secret key." >&2
            exit 1
        fi

        exec /usr/local/bin/playit --secret "${PLAYIT_SECRET}" --platform-docker
        """

        do {
            try dockerfile.write(to: buildCtx.appendingPathComponent("Dockerfile"), atomically: true, encoding: .utf8)
            try entrypoint.write(to: buildCtx.appendingPathComponent("entrypoint.sh"), atomically: true, encoding: .utf8)
        } catch {
            emitLine("[Playit] Failed to write build context: \(error.localizedDescription)")
            return false
        }

        let result = DockerUtility.runCapture(
            executable: dockerPath,
            args: ["build", "-t", Self.imageName, buildCtx.path]
        )
        if let result, result.exitCode == 0 {
            emitLine("[Playit] Docker image built successfully.")
            return true
        }
        emitLine("[Playit] Docker image build failed: \(result?.output ?? "unknown error")")
        return false
    }

    // MARK: - Container lifecycle

    func start(
        secretKey: String,
        javaPort: Int?,
        bedrockPort: Int?,
        voicePort: Int?,
        configDir: URL
    ) throws {
        guard let docker = DockerUtility.dockerPath() else {
            throw PlayitError.dockerNotAvailable
        }

        stoppedIntentionally = false
        didFireTerminate = false

        // Ensure config directory exists (playit stores secret key here)
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        // Build image on first use
        if !imageExists(dockerPath: docker) {
            emitLine("[Playit] Building Docker image (first-time setup, may take a minute)…")
            guard buildImage(configDir: configDir, dockerPath: docker) else {
                throw PlayitError.imageBuildFailed
            }
        }

        // Remove any leftover container
        if DockerUtility.containerExists(name: Self.containerName, dockerPath: docker) {
            DockerUtility.runCapture(executable: docker, args: ["rm", "-f", Self.containerName])
        }

        var runArgs = [
            "run", "-d",
            "--name", Self.containerName,
            "--add-host", "host.docker.internal:host-gateway",
            "--restart", "no",
            "-e", "PLAYIT_SECRET=\(secretKey)",
            "-e", "JAVA_PORT=\(javaPort ?? 0)",
            "-e", "BEDROCK_PORT=\(bedrockPort ?? 0)",
            "-e", "VOICE_PORT=\(voicePort ?? 0)",
            Self.imageName
        ]

        guard let result = DockerUtility.runCapture(executable: docker, args: runArgs),
              result.exitCode == 0 else {
            let detail = DockerUtility.runCapture(
                executable: docker,
                args: ["run", "--rm", Self.imageName, "echo", "test"]
            )?.output ?? ""
            throw PlayitError.containerStartFailed(detail)
        }

        isRunning = true
        emitLine("[Playit] Container started.")
        startLogStreaming(dockerPath: docker)
    }

    /// Stop must be called from a background thread — docker stop blocks for up to 5s.
    func stop() {
        stoppedIntentionally = true
        isRunning = false
        terminateLogStream()

        guard let docker = DockerUtility.dockerPath() else { return }
        DockerUtility.runCapture(executable: docker, args: ["stop", "-t", "5", Self.containerName])
        DockerUtility.runCapture(executable: docker, args: ["rm", "-f", Self.containerName])
    }

    // MARK: - Log streaming

    private func startLogStreaming(dockerPath: String) {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: dockerPath)
        p.arguments = ["logs", "-f", "--tail=100", Self.containerName]
        p.standardOutput = pipe
        p.standardError = pipe
        p.environment = DockerUtility.dockerEnvironment()

        logPipe = pipe
        logProcess = p

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            if data.isEmpty {
                self.flushPendingOutput()
                self.fireTerminateOnce()
                return
            }
            self.handleIncoming(data: data)
        }

        p.terminationHandler = { [weak self] _ in
            guard let self else { return }
            self.flushPendingOutput()
            self.isRunning = false
            self.fireTerminateOnce()
        }

        do { try p.run() } catch {
            emitLine("[Playit] Failed to stream logs: \(error.localizedDescription)")
        }
    }

    private func terminateLogStream() {
        logPipe?.fileHandleForReading.readabilityHandler = nil
        logPipe?.fileHandleForReading.closeFile()
        if logProcess?.isRunning == true { logProcess?.terminate() }
        logProcess = nil
        logPipe = nil
    }

    // MARK: - One-shot termination

    private func fireTerminateOnce() {
        outputLock.lock()
        let shouldFire = !stoppedIntentionally && !didFireTerminate
        if shouldFire { didFireTerminate = true }
        outputLock.unlock()
        if shouldFire { onDidTerminate?() }
    }

    // MARK: - Output buffering

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
        guard !pendingOutput.isEmpty else { outputLock.unlock(); return }
        let data = pendingOutput
        pendingOutput.removeAll(keepingCapacity: false)
        outputLock.unlock()
        let line = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        emitLine(line)
    }

    private func emitLine(_ line: String) {
        onOutputLine?(line)
    }

    // MARK: - Errors

    enum PlayitError: LocalizedError {
        case dockerNotAvailable
        case imageBuildFailed
        case containerStartFailed(String)

        var errorDescription: String? {
            switch self {
            case .dockerNotAvailable:
                return "Docker is not available. Make sure Docker Desktop is running."
            case .imageBuildFailed:
                return "Failed to build the playit Docker image. Check your internet connection."
            case .containerStartFailed(let detail):
                return "Failed to start playit container: \(detail)"
            }
        }
    }
}

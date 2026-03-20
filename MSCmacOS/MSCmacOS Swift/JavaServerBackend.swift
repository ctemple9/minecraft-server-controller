// JavaServerBackend.swift
// MinecraftServerController

import Foundation

/// Adapts the existing `ServerProcessManager` to conform to `ServerBackend`.
///
/// This is a pure delegation layer — all logic stays in `ServerProcessManager`.
/// AppViewModel calls this through the
/// `ServerBackend` protocol and never touches `ServerProcessManager` directly.
final class JavaServerBackend: ServerBackend {

    // MARK: - Private

    private let processManager = ServerProcessManager()

    // MARK: - ServerBackend: Callbacks

    var onOutputLine: ((String) -> Void)? {
        get { processManager.onOutputLine }
        set { processManager.onOutputLine = newValue }
    }

    var onDidTerminate: (() -> Void)? {
        get { processManager.onDidTerminate }
        set { processManager.onDidTerminate = newValue }
    }

    // MARK: - ServerBackend: State

    var isRunning: Bool {
        processManager.isRunning
    }

    // MARK: - PID (Java-only; not part of the protocol)

    /// PID of the underlying Java process, if running.
    /// Used by AppViewModel for CPU/RAM metrics (ps -p <pid>).
    /// BedrockServerBackend has no equivalent concept.
    var processID: pid_t? {
        processManager.processID
    }

    // MARK: - ServerBackend: I/O

    var lastCommandError: String? {
        processManager.lastStdinWriteError
    }

    @discardableResult
    func sendCommand(_ command: String) -> Bool {
        processManager.sendCommand(command)
    }

    // MARK: - ServerBackend: Lifecycle

    /// Start the Java/Paper server using the provided ConfigServer and AppConfig.
    ///
    /// Reads javaPath, extraFlags, paperJarPath, minRam, maxRam from the two
    /// config objects — exactly as AppViewModel.startServer() did before this refactor.
    func start(config: ConfigServer, appConfig: AppConfig) throws {
        let serverDirURL = URL(fileURLWithPath: config.serverDir)

        let jarPath = config.paperJarPath.isEmpty
            ? serverDirURL.appendingPathComponent("paper.jar").path
            : config.paperJarPath

        do {
            try processManager.startServer(
                javaPath: appConfig.javaPath,
                extraFlags: appConfig.extraFlags,
                serverDirectory: serverDirURL,
                paperJarPath: jarPath,
                minRamGB: config.minRam,
                maxRamGB: config.maxRam
            )
        } catch let error as ServerProcessManager.ServerProcessError {
            // Translate to the protocol-level error type so callers are
            // insulated from the concrete ServerProcessManager type.
            switch error {
            case .alreadyRunning:
                throw ServerBackendError.alreadyRunning
            case .failedToStart(let underlying):
                throw ServerBackendError.failedToStart(underlying)
            }
        }
    }

    /// Send "stop" over stdin — the standard Paper/Vanilla graceful stop command.
    @discardableResult
    func stop() -> Bool {
        processManager.requestStop()
    }

    /// Forcibly terminate the process (SIGTERM).
    func terminate() {
        processManager.terminate()
    }
}

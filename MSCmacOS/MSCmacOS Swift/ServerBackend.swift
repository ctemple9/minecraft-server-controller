// ServerBackend.swift
// MinecraftServerController

import Foundation

// MARK: - ServerBackend protocol

/// Defines the contract for any server process backend (Java or Bedrock).
///
/// AppViewModel holds a `ServerBackend` reference and routes all start/stop/command
/// calls through it, without ever needing to know which concrete type is active.
///
/// Conforming types:
///   - JavaServerBackend     — wraps ServerProcessManager (JVM + Paper JAR)
///   - VMBedrockServerBackend — wraps a Virtualization.framework VM running BDS; the
///     default Bedrock backend (`AppConfig.useVMBedrockBackend`, on by default)
///   - BedrockServerBackend  — wraps the Docker CLI; the original Bedrock backend,
///     still selectable via the "Bedrock Runtime" toggle in Settings for users who
///     opt out of the VM path
protocol ServerBackend: AnyObject {

    // MARK: Lifecycle

    /// Start the server using the provided config.
    /// - Throws: `ServerBackendError` on failure.
    func start(config: ConfigServer, appConfig: AppConfig) throws

    /// Send a graceful stop request (e.g. "stop" over stdin for Java).
    /// Returns true if the request was delivered successfully.
    @discardableResult
    func stop() -> Bool

    /// Forcibly terminate the backend process without a graceful stop.
    func terminate()

    // MARK: State

    /// True while the server process (or container) is running.
    var isRunning: Bool { get }

    // MARK: I/O

    /// Send a raw command string to the server's stdin (or container stdin).
    /// Returns true on success, false on failure.
    @discardableResult
    func sendCommand(_ command: String) -> Bool

    /// Last error string from a failed `sendCommand` call, if any.
    var lastCommandError: String? { get }

    // MARK: Callbacks

    /// Called on every complete output line from the server process.
    /// The line does NOT include the trailing newline.
    var onOutputLine: ((String) -> Void)? { get set }

    /// Called when the server process terminates for any reason.
    var onDidTerminate: (() -> Void)? { get set }
}

// MARK: - ServerBackendError

/// Unified error type for backend start failures.
/// Mirrors ServerProcessManager.ServerProcessError so callers don't need
/// to import the concrete type.
enum ServerBackendError: Error {
    case alreadyRunning
    case failedToStart(Error)
}

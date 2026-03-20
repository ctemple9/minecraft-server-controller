// ServerProcessManager.swift
//  MinecraftServerController

import Foundation

/// A small, UI-agnostic wrapper around `Process` that:
/// - Builds the Java command
/// - Starts the server in a given working directory
/// - Streams stdout/stderr as lines via callbacks
/// - Lets you send commands to stdin (e.g. "stop")
/// Manages the Paper server process lifecycle and streams output lines to the caller.
final class ServerProcessManager {

    enum ServerProcessError: Swift.Error {
        case alreadyRunning
        case failedToStart(Swift.Error)
    }

    // MARK: - Public callbacks

    /// Called whenever a *full line* of output is available from the process.
    /// The `line` does NOT include the trailing newline.
    var onOutputLine: ((String) -> Void)?

    /// Called when the process terminates.
    var onDidTerminate: (() -> Void)?

    // MARK: - Internal state

    private var process: Process?
    private var outputPipe: Pipe?
    private var inputPipe: Pipe?

    private(set) var lastStdinWriteError: String?

    /// Buffer to accumulate partial lines until we see a newline.
    private var pendingOutput = Data()

    // MARK: - Validation

    private struct JavaLaunchInfo {
        let executableURL: URL
        /// Arguments that must come *before* any JVM flags (only used when launching via /usr/bin/env).
        let prefixArguments: [String]
        /// Human-friendly label used in error messages.
        let display: String
    }

    private func validationError(_ message: String) -> NSError {
        NSError(
            domain: "MinecraftServerController.JavaValidation",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    private func expandingTilde(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    /// Lightweight validation that the user's Java path is non-empty, resolves to an executable,
    /// and appears to be a JVM (via `-version`).
    private func validatedJavaLaunchInfo(javaPath: String) throws -> JavaLaunchInfo {
        let trimmed = javaPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ServerProcessError.failedToStart(
                validationError("Java path is empty — please set it in Preferences.")
            )
        }

        let expanded = expandingTilde(trimmed)

        // Absolute/explicit path case
        if expanded.contains("/") {
            let fm = FileManager.default
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: expanded, isDirectory: &isDir) else {
                throw ServerProcessError.failedToStart(
                    validationError("Java path does not exist: \(expanded)")
                )
            }
            guard !isDir.boolValue else {
                throw ServerProcessError.failedToStart(
                    validationError("Java path points to a directory (expected an executable): \(expanded)")
                )
            }
            guard fm.isExecutableFile(atPath: expanded) else {
                throw ServerProcessError.failedToStart(
                    validationError("Java path is not executable: \(expanded)")
                )
            }

            // JVM sanity check
            try validateLooksLikeJava(executableURL: URL(fileURLWithPath: expanded), arguments: ["-version"], display: expanded)

            return JavaLaunchInfo(executableURL: URL(fileURLWithPath: expanded), prefixArguments: [], display: expanded)
        }

        // Command-on-PATH case ("java" or custom command)
        let whichURL = URL(fileURLWithPath: "/usr/bin/which")
        let which = try runAndCapture(executableURL: whichURL, arguments: [expanded])
        let resolved = which.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard which.exitCode == 0, !resolved.isEmpty else {
            throw ServerProcessError.failedToStart(
                validationError("Java command not found on PATH: \(expanded) — please set an absolute Java path in Preferences.")
            )
        }

        // JVM sanity check via env to match the actual launch behavior
        let envURL = URL(fileURLWithPath: "/usr/bin/env")
        try validateLooksLikeJava(executableURL: envURL, arguments: [expanded, "-version"], display: expanded)

        return JavaLaunchInfo(executableURL: envURL, prefixArguments: [expanded], display: expanded)
    }

    private struct CapturedRun {
        let exitCode: Int32
        let output: String
    }

    private func runAndCapture(executableURL: URL, arguments: [String]) throws -> CapturedRun {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = executableURL
        p.arguments = arguments
        p.standardOutput = pipe
        p.standardError = pipe

        do {
            try p.run()
        } catch {
            throw error
        }

        p.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)

        return CapturedRun(exitCode: p.terminationStatus, output: text)
    }

    private func validateLooksLikeJava(executableURL: URL, arguments: [String], display: String) throws {
        let result: CapturedRun
        do {
            result = try runAndCapture(executableURL: executableURL, arguments: arguments)
        } catch {
            throw ServerProcessError.failedToStart(
                validationError("Failed to run Java at \(display): \(error.localizedDescription)")
            )
        }

        let lower = result.output.lowercased()
        let looksLikeJava = lower.contains("openjdk")
            || lower.contains("java version")
            || lower.contains("java(tm)")
            || lower.contains("runtime environment")
            || lower.contains("hotspot")

        guard looksLikeJava else {
            let firstLine = result.output
                .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
                .first
                .map(String.init)
                ?? "(no output)"

            throw ServerProcessError.failedToStart(
                validationError("Java path does not appear to be a JVM: \(display)\n\nOutput: \(firstLine)")
            )
        }
    }

    var isRunning: Bool {
        process?.isRunning ?? false
    }

   /// PID of the Java server process, if running.
   var processID: pid_t? {
       process?.processIdentifier
   }

    // MARK: - Public API

    /// Start a Paper server using the provided config + server info.
    ///
    /// - Parameters:
    ///   - javaPath: Value from config (e.g. "java" or "/usr/bin/java")
    ///   - extraFlags: Extra JVM flags as a single string (same as Python config.extra_flags)
    ///   - serverDirectory: The server's working directory (cwd)
    ///   - paperJarPath: Full path to the Paper jar (or we’ll derive name & use cwd)
    ///   - minRamGB / maxRamGB: Values like 1, 3 → "-Xms1G" "-Xmx3G"
    func startServer(
        javaPath: String,
        extraFlags: String?,
        serverDirectory: URL,
        paperJarPath: String,
        minRamGB: Int,
        maxRamGB: Int
    ) throws {
        // Mirror Python behavior: only one process at a time.
        if isRunning {
            throw ServerProcessError.alreadyRunning
        }

        pendingOutput.removeAll(keepingCapacity: false)

        // Validate Java path before launching (clear user-facing error via thrown NSError)
        let java = try validatedJavaLaunchInfo(javaPath: javaPath)

        let process = Process()
        let outputPipe = Pipe()
        let inputPipe = Pipe()

        // ----- Build executable + args (mirrors your Python build_java_command) -----

        // These flags suppress Gatekeeper popups caused by JNA and jline
        // trying to load unsigned native libraries inside the sandbox.
        // They must be JVM flags (before -jar), not app arguments.
        let sandboxSuppressFlags = [
            "-Djna.nosys=true",
            "-Djna.nounpack=true",       // stops JNA from extracting its bundled native lib
            "-Djline.terminal=dumb",
            "-Dio.netty.noUnsafe=true",  // stops Netty trying to load kqueue native transport
        
        ]

        var executableURL: URL = java.executableURL
        var arguments: [String] = java.prefixArguments

        arguments.append(contentsOf: [
            "-Xms\(minRamGB)G",
            "-Xmx\(maxRamGB)G",
        ])

        arguments.append(contentsOf: sandboxSuppressFlags)

        // Extra JVM flags (space-separated), same idea as Python's extra_flags.split()
        if let extraFlags, !extraFlags.trimmingCharacters(in: .whitespaces).isEmpty {
            let parts = extraFlags.split { $0.isWhitespace }.map(String.init)
            arguments.append(contentsOf: parts)
        }

        // Paper jar: use basename only, cwd = serverDirectory (like Python)
        let jarURL = URL(fileURLWithPath: expandingTilde(paperJarPath))
        let jarName = jarURL.lastPathComponent

        // Validate that the jar exists *in* the working directory, because we launch via jarName.
        let jarInWorkingDir = serverDirectory.appendingPathComponent(jarName)
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: jarInWorkingDir.path, isDirectory: &isDir) || isDir.boolValue {
            throw ServerProcessError.failedToStart(
                validationError("Paper JAR not found in server folder: \(jarInWorkingDir.path)")
            )
        }
        arguments.append(contentsOf: ["-jar", jarName, "--nogui"])

        // ----- Wire up the Process -----

        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = serverDirectory

        process.standardOutput = outputPipe
        process.standardError = outputPipe  // stderr → stdout, just like subprocess.STDOUT
        process.standardInput = inputPipe

        // Live output reader
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            if data.isEmpty {
                // EOF – flush any remaining buffered text as one final "line"
                self.flushPendingOutput()
                return
            }
            self.handleIncoming(data: data)
        }

        process.terminationHandler = { [weak self] _ in
            guard let self else { return }
            self.flushPendingOutput()
            self.cleanupProcess()
            self.onDidTerminate?()
        }

        self.process = process
        self.outputPipe = outputPipe
        self.inputPipe = inputPipe

        do {
            try process.run()
        } catch {
            cleanupProcess()
            throw ServerProcessError.failedToStart(error)
        }
    }

    /// Sends an arbitrary command to the server's stdin (adds a newline).
    /// Returns false (and populates `lastStdinWriteError`) if the command could not be written.
    @discardableResult
    func sendCommand(_ command: String) -> Bool {
        guard let input = inputPipe?.fileHandleForWriting, isRunning else {
            lastStdinWriteError = "Server is not running."
            return false
        }

        guard let data = (command + "\n").data(using: .utf8) else {
            lastStdinWriteError = "Failed to encode command as UTF-8."
            return false
        }

        do {
            try input.write(contentsOf: data)
            lastStdinWriteError = nil
            return true
        } catch {
            lastStdinWriteError = error.localizedDescription
            return false
        }
    }

    /// Convenience for sending "stop" (mirrors Python stop_server behavior).
    @discardableResult
    func requestStop() -> Bool {
        sendCommand("stop")
    }

    /// Forcefully terminate the process (if still running).
    func terminate() {
        guard let process else {
            cleanupProcess()
            return
        }

        if process.isRunning {
            process.terminate()
            // IMPORTANT: keep our strong reference until terminationHandler runs,
            // so the process lifecycle completes and callbacks fire consistently.
        } else {
            flushPendingOutput()
            cleanupProcess()
            onDidTerminate?()
        }
    }

    // MARK: - Output handling

    private func handleIncoming(data: Data) {
        pendingOutput.append(data)

        // Split by newline (0x0A) and emit full lines.
        let newline = Data([0x0A])

        while let range = pendingOutput.firstRange(of: newline) {
            let lineData = pendingOutput.subdata(in: 0..<range.lowerBound)
            pendingOutput.removeSubrange(0..<range.upperBound)

            let line = String(data: lineData, encoding: .utf8)
                ?? String(decoding: lineData, as: UTF8.self)

            onOutputLine?(line)
        }
    }

    private func flushPendingOutput() {
        guard !pendingOutput.isEmpty else { return }
        let data = pendingOutput
        pendingOutput.removeAll(keepingCapacity: false)

        let line = String(data: data, encoding: .utf8)
            ?? String(decoding: data, as: UTF8.self)

        onOutputLine?(line)
    }

    private func cleanupProcess() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe?.fileHandleForReading.closeFile()
        inputPipe?.fileHandleForWriting.closeFile()
        outputPipe = nil
        inputPipe = nil
        process = nil
    }
}


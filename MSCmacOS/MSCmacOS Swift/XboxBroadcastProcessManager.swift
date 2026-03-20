//
//  XboxBroadcastProcessManager.swift
//  MinecraftServerController
//

import Foundation

/// Minimal process wrapper for MCXboxBroadcastStandalone.jar.
/// Very similar to ServerProcessManager, but:
/// - No stdin commands
/// - Just starts/stops and streams output lines.
/// Manages the MCXboxBroadcastStandalone helper process lifecycle and streams output lines to the caller.
final class XboxBroadcastProcessManager {

    enum BroadcastError: Swift.Error {
        case alreadyRunning
        case failedToStart(Swift.Error)
    }

    /// Called whenever a full line of output is available.
    var onOutputLine: ((String) -> Void)?

    /// Called when the process terminates.
    var onDidTerminate: (() -> Void)?

    private var process: Process?
    private var outputPipe: Pipe?
    private var pendingOutput = Data()

    // MARK: - Validation

    private struct JavaLaunchInfo {
        let executableURL: URL
        let prefixArguments: [String]
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

        try p.run()
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
            throw BroadcastError.failedToStart(
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

            throw BroadcastError.failedToStart(
                validationError("Java path does not appear to be a JVM: \(display)\n\nOutput: \(firstLine)")
            )
        }
    }

    private func validatedJavaLaunchInfo(javaPath: String) throws -> JavaLaunchInfo {
        let trimmed = javaPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw BroadcastError.failedToStart(
                validationError("Java path is empty — please set it in Preferences.")
            )
        }

        let expanded = expandingTilde(trimmed)

        if expanded.contains("/") {
            let fm = FileManager.default
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: expanded, isDirectory: &isDir) else {
                throw BroadcastError.failedToStart(
                    validationError("Java path does not exist: \(expanded)")
                )
            }
            guard !isDir.boolValue else {
                throw BroadcastError.failedToStart(
                    validationError("Java path points to a directory (expected an executable): \(expanded)")
                )
            }
            guard fm.isExecutableFile(atPath: expanded) else {
                throw BroadcastError.failedToStart(
                    validationError("Java path is not executable: \(expanded)")
                )
            }

            try validateLooksLikeJava(executableURL: URL(fileURLWithPath: expanded), arguments: ["-version"], display: expanded)
            return JavaLaunchInfo(executableURL: URL(fileURLWithPath: expanded), prefixArguments: [], display: expanded)
        }

        let whichURL = URL(fileURLWithPath: "/usr/bin/which")
        let which = try runAndCapture(executableURL: whichURL, arguments: [expanded])
        let resolved = which.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard which.exitCode == 0, !resolved.isEmpty else {
            throw BroadcastError.failedToStart(
                validationError("Java command not found on PATH: \(expanded) — please set an absolute Java path in Preferences.")
            )
        }

        let envURL = URL(fileURLWithPath: "/usr/bin/env")
        try validateLooksLikeJava(executableURL: envURL, arguments: [expanded, "-version"], display: expanded)
        return JavaLaunchInfo(executableURL: envURL, prefixArguments: [expanded], display: expanded)
    }

    var isRunning: Bool {
        process?.isRunning ?? false
    }

    /// PID of the XboxBroadcast process, if running.
    var processID: pid_t? {
        process?.processIdentifier
    }

    /// Start MCXboxBroadcastStandalone.jar using the given Java + JAR path
    /// and working directory (where config.yml lives).
    func startBroadcast(
        javaPath: String,
        jarPath: String,
        workingDirectory: URL
    ) throws {
        if isRunning {
            throw BroadcastError.alreadyRunning
        }

        pendingOutput.removeAll(keepingCapacity: false)

        // Validate Java path before launch
        let java = try validatedJavaLaunchInfo(javaPath: javaPath)

        // Validate jar path (absolute or relative to workingDirectory)
        let jarExpanded = expandingTilde(jarPath.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !jarExpanded.isEmpty else {
            throw BroadcastError.failedToStart(validationError("XboxBroadcast JAR path is empty."))
        }
        let jarURL: URL = jarExpanded.contains("/")
            ? URL(fileURLWithPath: jarExpanded)
            : workingDirectory.appendingPathComponent(jarExpanded)
        var jarIsDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: jarURL.path, isDirectory: &jarIsDir) || jarIsDir.boolValue {
            throw BroadcastError.failedToStart(validationError("XboxBroadcast JAR does not exist: \(jarURL.path)"))
        }

        let process = Process()
        let outputPipe = Pipe()

        var executableURL: URL = java.executableURL
        var arguments: [String] = java.prefixArguments
        arguments.append(contentsOf: ["-jar", jarURL.path])

        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory

        process.standardOutput = outputPipe
        process.standardError = outputPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            if data.isEmpty {
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

        do {
            try process.run()
        } catch {
            cleanupProcess()
            throw BroadcastError.failedToStart(error)
        }
    }

    /// Stop the broadcaster if it is running.
    func terminate() {
        guard let process else {
            cleanupProcess()
            return
        }

        if process.isRunning {
            process.terminate()
            // IMPORTANT: keep our strong reference until terminationHandler runs.
        } else {
            flushPendingOutput()
            cleanupProcess()
            onDidTerminate?()
        }
    }

    // MARK: - Output handling

    private func handleIncoming(data: Data) {
        pendingOutput.append(data)

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
        outputPipe = nil
        process = nil
    }
}

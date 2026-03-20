//
//  BedrockConnectProcessManager.swift
//  MinecraftServerController
//

import Foundation

/// Minimal process wrapper for BedrockConnect.jar.
/// Structurally identical to XboxBroadcastProcessManager — global lifecycle,
/// no stdin commands, streams output lines to the callback.
/// Manages the BedrockConnect helper process lifecycle and streams its output.
final class BedrockConnectProcessManager {

    /// Errors thrown when starting or managing the BedrockConnect process.
    enum BedrockConnectError: Swift.Error {
        case alreadyRunning
        case failedToStart(Swift.Error)
    }

    /// Called whenever a full line of output is available.
    var onOutputLine: ((String) -> Void)?

    /// Called when the process terminates for any reason.
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
            throw BedrockConnectError.failedToStart(
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

            throw BedrockConnectError.failedToStart(
                validationError("Java path does not appear to be a JVM: \(display)\n\nOutput: \(firstLine)")
            )
        }
    }

    private func validatedJavaLaunchInfo(javaPath: String) throws -> JavaLaunchInfo {
        let trimmed = javaPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw BedrockConnectError.failedToStart(
                validationError("Java path is empty — please set it in Preferences.")
            )
        }

        let expanded = expandingTilde(trimmed)

        if expanded.contains("/") {
            let fm = FileManager.default
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: expanded, isDirectory: &isDir) else {
                throw BedrockConnectError.failedToStart(
                    validationError("Java path does not exist: \(expanded)")
                )
            }
            guard !isDir.boolValue else {
                throw BedrockConnectError.failedToStart(
                    validationError("Java path points to a directory (expected an executable): \(expanded)")
                )
            }
            guard fm.isExecutableFile(atPath: expanded) else {
                throw BedrockConnectError.failedToStart(
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
            throw BedrockConnectError.failedToStart(
                validationError("Java command not found on PATH: \(expanded) — please set an absolute Java path in Preferences.")
            )
        }

        let envURL = URL(fileURLWithPath: "/usr/bin/env")
        try validateLooksLikeJava(executableURL: envURL, arguments: [expanded, "-version"], display: expanded)
        return JavaLaunchInfo(executableURL: envURL, prefixArguments: [expanded], display: expanded)
    }

    /// `true` when the BedrockConnect process is currently running.
    var isRunning: Bool {
        process?.isRunning ?? false
    }

    /// PID of the BedrockConnect process, if running.
    var processID: pid_t? {
        process?.processIdentifier
    }

    /// Start BedrockConnect.jar with the given Java path and JAR path.
        /// The working directory must contain a valid servers.json file.
        func startBedrockConnect(
            javaPath: String,
            jarPath: String,
            workingDirectory: URL,
            dnsPort: Int? = nil
        ) throws {
        if isRunning {
            throw BedrockConnectError.alreadyRunning
        }

        pendingOutput.removeAll(keepingCapacity: false)

        // Validate Java path before launch
        let java = try validatedJavaLaunchInfo(javaPath: javaPath)

        // Validate jar path (absolute or relative to workingDirectory)
        let jarExpanded = expandingTilde(jarPath.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !jarExpanded.isEmpty else {
            throw BedrockConnectError.failedToStart(validationError("BedrockConnect JAR path is empty."))
        }
        let jarURL: URL = jarExpanded.contains("/")
            ? URL(fileURLWithPath: jarExpanded)
            : workingDirectory.appendingPathComponent(jarExpanded)
        var jarIsDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: jarURL.path, isDirectory: &jarIsDir) || jarIsDir.boolValue {
            throw BedrockConnectError.failedToStart(validationError("BedrockConnect JAR does not exist: \(jarURL.path)"))
        }

        let process = Process()
        let outputPipe = Pipe()

            var executableURL: URL = java.executableURL
                    var arguments: [String] = java.prefixArguments
                    arguments.append(contentsOf: ["-jar", jarURL.path])

                    if let dnsPort, dnsPort > 0 {
                        arguments.append("port=\(dnsPort)")
                    }

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
            throw BedrockConnectError.failedToStart(error)
        }
    }

    /// Terminate the Bedrock Connect process if it is running.
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

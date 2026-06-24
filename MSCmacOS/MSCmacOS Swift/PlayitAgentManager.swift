//
//  PlayitAgentManager.swift
//  MinecraftServerController
//
//  Manages the playit CLI agent process lifecycle.
//  The binary is a native executable (not a JAR), so no Java validation needed.
//

import Foundation

final class PlayitAgentManager {

    /// Called on every full line of stdout/stderr output.
    var onOutputLine: ((String) -> Void)?

    /// Called when the process exits for any reason.
    var onDidTerminate: (() -> Void)?

    private var process: Process?
    private var outputPipe: Pipe?
    private var pendingOutput = Data()

    var isRunning: Bool { process?.isRunning ?? false }

    // MARK: - Start

    enum AgentError: Swift.Error {
        case alreadyRunning
        case failedToStart(Swift.Error)
    }

    func start(binaryURL: URL, configURL: URL) throws {
        guard !isRunning else { throw AgentError.alreadyRunning }

        pendingOutput.removeAll(keepingCapacity: false)

        let proc = Process()
        let pipe = Pipe()

        proc.executableURL = binaryURL
        proc.arguments = ["--config", configURL.path]
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
            throw AgentError.failedToStart(error)
        }
    }

    // MARK: - Stop

    func terminate() {
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

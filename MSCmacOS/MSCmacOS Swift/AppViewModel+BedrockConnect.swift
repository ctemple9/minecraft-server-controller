//
//  AppViewModel+BedrockConnect.swift
//  MinecraftServerController
//
//  Global Bedrock Connect process management.
//  Bedrock Connect is not per-server — one instance serves all configured servers at once.
//

import Foundation
import AppKit

extension AppViewModel {

    // MARK: - Directory helpers

    /// Working directory for Bedrock Connect (where servers.json lives):
    ///   ~/Library/Application Support/MinecraftServerController/BedrockConnect/
    var bedrockConnectWorkingDirectoryURL: URL {
        configManager.appDirectoryURL
            .appendingPathComponent("BedrockConnect", isDirectory: true)
    }

    /// Folder where all downloaded BedrockConnect JARs live.
    ///   ~/Library/Application Support/MinecraftServerController/BedrockConnect/JARs/
    var bedrockConnectJarLibraryURL: URL {
        bedrockConnectWorkingDirectoryURL
            .appendingPathComponent("JARs", isDirectory: true)
    }

    // MARK: - servers.json generation

    /// Build the servers.json content that Bedrock Connect reads at startup.
    ///
    /// Only servers that have a Bedrock port configured are included.
    /// The host used is the Mac's current local IP address.
    ///
    /// Format expected by Bedrock Connect:
    ///   [{"name":"My Server","motd":"My Server","ip":"192.168.x.x","port":19132}]
    func generateBedrockConnectServersJSON() -> Data? {
        let localIP = AppUtilities.localIPAddress() ?? "127.0.0.1"

        struct BCServerEntry: Encodable {
            let name: String
            let motd: String
            let ip: String
            let port: Int
        }

        let entries: [BCServerEntry] = configManager.config.servers.compactMap { server in
            guard let port = effectiveBedrockPort(for: server) else {
                return nil   // silently exclude servers without a Bedrock port
            }
            return BCServerEntry(
                name: server.displayName,
                motd: server.displayName,
                ip: localIP,
                port: port
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        return try? encoder.encode(entries)
    }

    /// Write servers.json to the Bedrock Connect working directory.
    /// Returns the working directory URL on success, nil on failure.
    private func writeBedrockConnectServersJSON() -> URL? {
        let workDir = bedrockConnectWorkingDirectoryURL
        let fm = FileManager.default

        do {
            try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        } catch {
            logAppMessage("[BedrockConnect] Failed to create working directory: \(error.localizedDescription)")
            return nil
        }

        guard let jsonData = generateBedrockConnectServersJSON() else {
            logAppMessage("[BedrockConnect] Failed to generate servers.json.")
            return nil
        }

        let jsonURL = workDir.appendingPathComponent("servers.json")
        do {
            try jsonData.write(to: jsonURL, options: [.atomic])
            logAppMessage("[BedrockConnect] Wrote servers.json to \(jsonURL.path).")
            return workDir
        } catch {
            logAppMessage("[BedrockConnect] Failed to write servers.json: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Process control

    /// Start Bedrock Connect globally.
    /// Generates servers.json from all servers that have a Bedrock port, then launches the JAR.
    func startBedrockConnect() {
        guard !bedrockConnectManager.isRunning else {
            logAppMessage("[BedrockConnect] Already running.")
            return
        }

        guard let jarPath = configManager.config.bedrockConnectJarPath?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !jarPath.isEmpty else {
            logAppMessage("[BedrockConnect] JAR path not configured.")
            showError(title: "Bedrock Connect", message: "No JAR path configured. Set one up in the JAR Manager.")
            return
        }

        guard let workDir = writeBedrockConnectServersJSON() else {
            // Error already logged inside writeBedrockConnectServersJSON
            return
        }

        let javaPath = configManager.config.javaPath
                let dnsPort = configManager.config.bedrockConnectDNSPort

                do {
                    try bedrockConnectManager.startBedrockConnect(
                        javaPath: javaPath,
                        jarPath: jarPath,
                        workingDirectory: workDir,
                        dnsPort: dnsPort
                    )
                    isBedrockConnectRunning = true
                    let launchedPort = dnsPort ?? 19132
                    logAppMessage("[BedrockConnect] Started Bedrock Connect on port \(launchedPort).")
        } catch let error as BedrockConnectProcessManager.BedrockConnectError {
            switch error {
            case .alreadyRunning:
                logAppMessage("[BedrockConnect] Already running.")
            case .failedToStart(let underlying):
                logAppMessage("[BedrockConnect] Failed to start: \(underlying.localizedDescription)")
                showError(title: "Bedrock Connect Failed", message: underlying.localizedDescription)
            }
        } catch {
            logAppMessage("[BedrockConnect] Failed to start: \(error.localizedDescription)")
            showError(title: "Bedrock Connect Failed", message: error.localizedDescription)
        }
    }
    

    /// Stop Bedrock Connect if it is running.
    func stopBedrockConnect() {
        guard bedrockConnectManager.isRunning else {
            logAppMessage("[BedrockConnect] Not running.")
            return
        }
        bedrockConnectManager.terminate()
        isBedrockConnectRunning = false
        logAppMessage("[BedrockConnect] Stopped Bedrock Connect.")
    }

    // MARK: - Output line handling

    /// Handle a line of output from the Bedrock Connect process.
    /// Logs every line, and surfaces port-bind failures as visible errors.
    func handleBedrockConnectOutputLine(_ line: String) {
        logAppMessage("[BedrockConnect] \(line)")

        // Detect bind failures and surface them as visible errors.
                let lower = line.lowercased()
                let configuredPort = configManager.config.bedrockConnectDNSPort ?? 19132
                let isPortError = (lower.contains("address already in use") ||
                                   lower.contains("failed to bind") ||
                                   lower.contains("bindexception") ||
                                   lower.contains("could not bind")) &&
                                  (lower.contains("\(configuredPort)") || lower.contains("bind"))

                if isPortError {
                    showError(
                        title: "Bedrock Connect — Port Conflict",
                        message: "Bedrock Connect could not bind to port \(configuredPort). Another process may already be using that port. Stop any other DNS or Bedrock services and try again."
                    )
                }
    }

    // MARK: - Download

    /// Download the latest BedrockConnect JAR into the library folder,
    /// using the GitHub release tag in the filename (e.g. BedrockConnect-1.62.jar).
    func downloadOrUpdateBedrockConnectJar() {
        let libraryDir = bedrockConnectJarLibraryURL

        Task.detached { [weak self] in
            guard let self else { return }
            let fm = FileManager.default

            do {
                try fm.createDirectory(at: libraryDir, withIntermediateDirectories: true)
            } catch {
                await MainActor.run { self.logAppMessage("[BedrockConnect] Failed to create library folder: \(error.localizedDescription)") }
                return
            }

            let tempURL = libraryDir.appendingPathComponent("BedrockConnect-downloading.jar")

            do {
                let tag = try await BedrockConnectDownloader.downloadLatestJar(to: tempURL)
                let version = tag?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
                let finalName = "BedrockConnect-\(version).jar"
                let finalURL = libraryDir.appendingPathComponent(finalName)

                if fm.fileExists(atPath: finalURL.path) { try fm.removeItem(at: finalURL) }
                try fm.moveItem(at: tempURL, to: finalURL)

                await MainActor.run {
                    self.configManager.setBedrockConnectJarPath(finalURL.path)
                    self.logAppMessage("[BedrockConnect] Downloaded \(finalName).")
                    self.loadBedrockConnectJars()
                }
            } catch {
                try? fm.removeItem(at: tempURL)
                await MainActor.run {
                    self.logAppMessage("[BedrockConnect] Download failed: \(error.localizedDescription)")
                    self.showError(title: "Bedrock Connect Download Failed", message: error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Library management

    /// Scan the library folder and repopulate `bedrockConnectJarItems`, newest first (by modification date).
    func loadBedrockConnectJars() {
        let fm = FileManager.default
        let dir = bedrockConnectJarLibraryURL

        // Ensure the folder exists so Browse opens into it on first use.
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        guard let contents = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            bedrockConnectJarItems = []
            return
        }

        let jars = contents
            .filter { $0.pathExtension.lowercased() == "jar" }
            .sorted { a, b in
                let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return dateA > dateB
            }

        bedrockConnectJarItems = jars.map { JarLibraryItem(url: $0) }
    }

    /// Set the given library item as the active BedrockConnect JAR.
    func setActiveBedrockConnectJar(_ item: JarLibraryItem) {
        configManager.setBedrockConnectJarPath(item.url.path)
        logAppMessage("[BedrockConnect] Active JAR set to \(item.filename).")
    }

    /// Delete a JAR from the library. Clears the active config path if it was the active JAR.
    func deleteBedrockConnectJarItem(_ item: JarLibraryItem) {
        try? FileManager.default.removeItem(at: item.url)

        if configManager.config.bedrockConnectJarPath == item.url.path {
            configManager.setBedrockConnectJarPath(nil)
        }

        logAppMessage("[BedrockConnect] Removed \(item.filename) from library.")
        loadBedrockConnectJars()
    }

    /// Copy a user-chosen JAR into the library folder, then set it as active.
    func addBedrockConnectJarFromBrowse(_ sourceURL: URL) {
        let fm = FileManager.default
        let dir = bedrockConnectJarLibraryURL
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(sourceURL.lastPathComponent)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: sourceURL, to: dest)
            configManager.setBedrockConnectJarPath(dest.path)
            logAppMessage("[BedrockConnect] Added \(sourceURL.lastPathComponent) to library and set as active.")
            loadBedrockConnectJars()
        } catch {
            logAppMessage("[BedrockConnect] Failed to import JAR: \(error.localizedDescription)")
        }
    }

    // MARK: - JAR management helpers

    /// True if the configured Bedrock Connect JAR path exists on disk.
    var isBedrockConnectJarInstalled: Bool {
        if let path = configManager.config.bedrockConnectJarPath,
           !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return FileManager.default.fileExists(atPath: path)
        }
        return false
    }

    /// Open the BedrockConnect JAR library folder in Finder.
    func openBedrockConnectJarFolder() {
        let dir = bedrockConnectJarLibraryURL
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }

    /// Open the Bedrock Connect working directory (servers.json) in Finder.
    func openBedrockConnectFolder() {
        let dir = bedrockConnectWorkingDirectoryURL
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        openBedrockConnectFolderInternal(dir)
    }

    /// Internal helper — opens a URL in Finder.
    private func openBedrockConnectFolderInternal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
    /// Toggles bedrockConnectStandaloneEnabled for the currently selected Bedrock server
        /// and persists the change to config.
        
}

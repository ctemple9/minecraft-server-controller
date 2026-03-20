//
//  AppViewModel+XboxBroadcastDownload.swift
//  MinecraftServerController
//

import Foundation
import AppKit

extension AppViewModel {

    // MARK: - Directory

    /// Folder where all downloaded XboxBroadcast JARs live.
    ///   ~/Library/Application Support/MinecraftServerController/MCXboxBroadcast/JARs/
    var xboxBroadcastJarLibraryURL: URL {
        configManager.appDirectoryURL
            .appendingPathComponent("MCXboxBroadcast", isDirectory: true)
            .appendingPathComponent("JARs", isDirectory: true)
    }

    // MARK: - Library management

    /// Scan the library folder and repopulate `xboxBroadcastJarItems`, newest first (by modification date).
    func loadXboxBroadcastJars() {
        let fm = FileManager.default
        let dir = xboxBroadcastJarLibraryURL

        // Ensure the folder exists so Browse opens into it on first use.
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        guard let contents = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            xboxBroadcastJarItems = []
            return
        }

        let jars = contents
            .filter { $0.pathExtension.lowercased() == "jar" }
            .sorted { a, b in
                let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return dateA > dateB
            }

        xboxBroadcastJarItems = jars.map { JarLibraryItem(url: $0) }
    }

    /// Set the given library item as the active XboxBroadcast JAR.
    func setActiveXboxBroadcastJar(_ item: JarLibraryItem) {
        configManager.setXboxBroadcastJarPath(item.url.path)
        logAppMessage("[Broadcast] Active JAR set to \(item.filename).")
        refreshComponentsSnapshotLocalAndTemplate(clearOnline: false)
    }

    /// Delete a JAR from the library. Clears the active config path if it was the active JAR.
    func deleteXboxBroadcastJarItem(_ item: JarLibraryItem) {
        try? FileManager.default.removeItem(at: item.url)

        if configManager.config.xboxBroadcastJarPath == item.url.path {
            configManager.setXboxBroadcastJarPath(nil)
        }

        logAppMessage("[Broadcast] Removed \(item.filename) from library.")
        loadXboxBroadcastJars()
        refreshComponentsSnapshotLocalAndTemplate(clearOnline: false)
    }

    /// Copy a user-chosen JAR into the library folder, then set it as active.
    func addXboxBroadcastJarFromBrowse(_ sourceURL: URL) {
        let fm = FileManager.default
        let dir = xboxBroadcastJarLibraryURL
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(sourceURL.lastPathComponent)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: sourceURL, to: dest)
            configManager.setXboxBroadcastJarPath(dest.path)
            logAppMessage("[Broadcast] Added \(sourceURL.lastPathComponent) to library and set as active.")
            loadXboxBroadcastJars()
            refreshComponentsSnapshotLocalAndTemplate(clearOnline: false)
        } catch {
            logAppMessage("[Broadcast] Failed to import JAR: \(error.localizedDescription)")
        }
    }

    /// Open the XboxBroadcast JAR library folder in Finder.
    func openXboxBroadcastJarFolder() {
        let dir = xboxBroadcastJarLibraryURL
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }

    // MARK: - Status helpers

    var isXboxBroadcastHelperInstalled: Bool {
        if let path = configManager.config.xboxBroadcastJarPath,
           !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return FileManager.default.fileExists(atPath: path)
        }
        return false
    }

    // MARK: - Download

    /// Download the latest MCXboxBroadcastStandalone.jar into the library folder,
    /// using the GitHub release tag as part of the filename (e.g. MCXboxBroadcastStandalone-v3.0.2.jar).
    func downloadOrUpdateXboxBroadcastJar() {
        let libraryDir = xboxBroadcastJarLibraryURL

        Task.detached { [weak self] in
            guard let self else { return }
            let fm = FileManager.default

            do {
                try fm.createDirectory(at: libraryDir, withIntermediateDirectories: true)
            } catch {
                await MainActor.run { self.logAppMessage("[Broadcast] Failed to create library folder: \(error.localizedDescription)") }
                return
            }

            let tempURL = libraryDir.appendingPathComponent("MCXboxBroadcastStandalone-downloading.jar")

            do {
                let tag = try await XboxBroadcastDownloader.downloadStandaloneJar(to: tempURL)
                let version = tag?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
                let finalName = "MCXboxBroadcastStandalone-\(version).jar"
                let finalURL = libraryDir.appendingPathComponent(finalName)

                if fm.fileExists(atPath: finalURL.path) { try fm.removeItem(at: finalURL) }
                try fm.moveItem(at: tempURL, to: finalURL)

                await MainActor.run {
                    self.configManager.setXboxBroadcastJarPath(finalURL.path)
                    self.logAppMessage("[Broadcast] Downloaded \(finalName).")
                    self.loadXboxBroadcastJars()
                    self.refreshComponentsSnapshotLocalAndTemplate(clearOnline: false)
                }
            } catch {
                try? fm.removeItem(at: tempURL)
                await MainActor.run {
                    self.logAppMessage("[Broadcast] Download failed: \(error.localizedDescription)")
                    self.showError(title: "XboxBroadcast Download Failed", message: error.localizedDescription)
                }
            }
        }
    }
}

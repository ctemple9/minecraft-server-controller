//
//  AppViewModel+WorldManagement.swift
//  MinecraftServerController
//

import Foundation

extension AppViewModel {

    // MARK: - World size

    func refreshWorldSize() {
        guard let server = selectedServer else {
            worldSizeDisplay = nil
            worldSizeMB = nil
            return
        }
        let serverDirURL = URL(fileURLWithPath: server.directory, isDirectory: true)
        let props = ServerPropertiesManager.readProperties(serverDir: server.directory)
        let levelName = (props["level-name"]?.trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 } ?? "world"
        let worldFolderNames = [levelName, "\(levelName)_nether", "\(levelName)_the_end"]

        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self else { return }
            let fm = FileManager.default
            var totalBytes: Int64 = 0
            for name in worldFolderNames {
                let url = serverDirURL.appendingPathComponent(name, isDirectory: true)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    totalBytes += AppUtilities.directorySizeInBytes(at: url)
                }
            }
            let formatted = AppUtilities.formatBytes(totalBytes)
            let mb = Double(totalBytes) / (1024.0 * 1024.0)
            DispatchQueue.main.async {
                self.worldSizeDisplay = formatted
                self.worldSizeMB = mb
            }
        }
    }

    // MARK: - Replace World

    func replaceWorld(
        for configServer: ConfigServer,
        newLevelName: String,
        worldSource: WorldSource,
        backupFirst: Bool
    ) async -> Bool {
        let trimmedLevel = newLevelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLevel.isEmpty else { return false }

        guard configServer.serverType == .java else {
            logAppMessage("[World] Replace World is currently supported for Java servers only.")
            showError(title: "World Replace Failed", message: "Replace World is currently available for Java servers only.")
            return false
        }

        if isServerRunning, configManager.config.activeServerId == configServer.id {
            logAppMessage("[World] Refusing to replace world for \(configServer.displayName) while server is running.")
            return false
        }

        switch worldSource {
        case .fresh:
            break
        case .backupZip(let zipURL):
            let archiveValid = await validateZipArchive(zipURL, logPrefix: "[World]")
            guard archiveValid else {
                showError(title: "World Replace Failed", message: "The selected backup ZIP could not be opened. No files were changed.")
                return false
            }
        case .existingFolder(let sourceURL):
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDir), isDir.boolValue else {
                logAppMessage("[World] Replace source folder is missing: \(sourceURL.path)")
                showError(title: "World Replace Failed", message: "The selected world folder could not be found. No files were changed.")
                return false
            }
        }

        if backupFirst {
            let ok = await createBackup(for: configServer, isAutomatic: false, triggerReason: "pre-replace")
            if !ok {
                logAppMessage("[World] Backup before replacement failed for \(configServer.displayName); aborting replace.")
                showError(title: "World Replace Aborted", message: "A safety backup could not be created, so no files were changed.")
                return false
            }
        }

        let serverDirURL = URL(fileURLWithPath: configServer.serverDir, isDirectory: true)
        let currentProps = ServerPropertiesManager.readProperties(serverDir: serverDirURL.path)
        let currentLevel = (currentProps["level-name"]?.trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 } ?? "world"

        let worldFolderNames = [currentLevel, "\(currentLevel)_nether", "\(currentLevel)_the_end"]
        let removed: Bool = await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            do {
                for name in worldFolderNames {
                    let url = serverDirURL.appendingPathComponent(name, isDirectory: true)
                    if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
                }
                return true
            } catch {
                return false
            }
        }.value

        guard removed else {
            logAppMessage("[World] Failed to remove existing world folders for \(configServer.displayName).")
            showError(title: "World Replace Failed", message: "Could not remove existing world folders.")
            return false
        }

        switch worldSource {
        case .fresh:
            logAppMessage("[World] Cleared world for \(configServer.displayName). A new world will generate on next start.")
        case .backupZip(let zipURL):
            let ok = await unzipWorldBackup(zipURL, into: serverDirURL, logPrefix: "[World]")
            guard ok else {
                showError(title: "World Replace Failed", message: "The selected backup ZIP could not be extracted. Restore from the safety backup if needed.")
                return false
            }
        case .existingFolder(let sourceURL):
            let ok = await copyExistingWorldFolder(from: sourceURL, toServerDir: serverDirURL, levelName: trimmedLevel, logPrefix: "[World]")
            guard ok else {
                showError(title: "World Replace Failed", message: "The selected world folder could not be copied. Restore from the safety backup if needed.")
                return false
            }
        }

        var updatedProps = ServerPropertiesManager.readProperties(serverDir: serverDirURL.path)
        updatedProps["level-name"] = trimmedLevel
        do {
            try ServerPropertiesManager.writeProperties(updatedProps, to: serverDirURL.path)
            logAppMessage("[World] Updated level-name to '\(trimmedLevel)' for \(configServer.displayName).")
        } catch {
            logAppMessage("[World] Failed to update server.properties for \(configServer.displayName): \(error.localizedDescription)")
            showError(title: "World Replace Failed", message: "Could not update server.properties: \(error.localizedDescription)")
            return false
        }

        refreshWorldSize()
        return true
    }

    // MARK: - Rename World

    func renameWorld(for configServer: ConfigServer, newLevelName: String, backupFirst: Bool) async -> Bool {
        let trimmed = newLevelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        guard configServer.serverType == .java else {
            logAppMessage("[World] Rename World is currently supported for Java servers only.")
            showError(title: "World Rename Failed", message: "Rename World is currently available for Java servers only.")
            return false
        }

        if let activeId = configManager.config.activeServerId,
           activeId == configServer.id, isServerRunning {
            logAppMessage("[World] Refusing to rename world for \(configServer.displayName) while server is running.")
            return false
        }

        let serverDirURL = URL(fileURLWithPath: configServer.serverDir, isDirectory: true)
        var props = ServerPropertiesManager.readProperties(serverDir: serverDirURL.path)
        let oldLevel = (props["level-name"]?.trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 } ?? "world"
        if trimmed == oldLevel { return true }

        if backupFirst {
            let ok = await createBackup(for: configServer, isAutomatic: false, triggerReason: "pre-rename")
            if !ok {
                logAppMessage("[World] Backup before rename failed for \(configServer.displayName); aborting rename.")
                showError(title: "World Rename Aborted", message: "A safety backup could not be created, so no files were changed.")
                return false
            }
        }

        let fm = FileManager.default
        let targetNames = [trimmed, "\(trimmed)_nether", "\(trimmed)_the_end"]
        for name in targetNames {
            let url = serverDirURL.appendingPathComponent(name, isDirectory: true)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                logAppMessage("[World] Cannot rename: folder \(name) already exists in \(configServer.displayName).")
                showError(title: "World Rename Failed", message: "A folder named \(name) already exists. No files were changed.")
                return false
            }
        }

        let mapping: [(old: String, new: String)] = [
            (oldLevel, trimmed),
            ("\(oldLevel)_nether", "\(trimmed)_nether"),
            ("\(oldLevel)_the_end", "\(trimmed)_the_end")
        ]
        var movedPairs: [(oldURL: URL, newURL: URL)] = []

        func rollbackMovedFolders() {
            for pair in movedPairs.reversed() {
                do {
                    if fm.fileExists(atPath: pair.newURL.path) {
                        try fm.moveItem(at: pair.newURL, to: pair.oldURL)
                        logAppMessage("[World] Rolled back \(pair.newURL.lastPathComponent) → \(pair.oldURL.lastPathComponent).")
                    }
                } catch {
                    logAppMessage("[World] Rollback failed for \(pair.newURL.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }

        for (oldName, newName) in mapping {
            let oldURL = serverDirURL.appendingPathComponent(oldName, isDirectory: true)
            let newURL = serverDirURL.appendingPathComponent(newName, isDirectory: true)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: oldURL.path, isDirectory: &isDir), isDir.boolValue {
                do {
                    try fm.moveItem(at: oldURL, to: newURL)
                    movedPairs.append((oldURL, newURL))
                    logAppMessage("[World] Renamed \(oldName) → \(newName) for \(configServer.displayName).")
                } catch {
                    logAppMessage("[World] Failed to rename \(oldName) for \(configServer.displayName): \(error.localizedDescription)")
                    rollbackMovedFolders()
                    showError(title: "World Rename Failed", message: "Could not rename '\(oldName)': \(error.localizedDescription)")
                    return false
                }
            }
        }

        props["level-name"] = trimmed
        do {
            try ServerPropertiesManager.writeProperties(props, to: serverDirURL.path)
            logAppMessage("[World] Updated level-name to '\(trimmed)' for \(configServer.displayName) (rename).")
        } catch {
            logAppMessage("[World] Failed to update server.properties while renaming for \(configServer.displayName): \(error.localizedDescription)")
            rollbackMovedFolders()
            showError(title: "World Rename Failed", message: "Could not update server.properties: \(error.localizedDescription)")
            return false
        }

        logAppMessage("[World] Finished renaming world \(oldLevel) → \(trimmed) for \(configServer.displayName).")
        return true
    }

    // MARK: - ZIP / folder helpers

    func validateZipArchive(_ zipURL: URL, logPrefix: String) async -> Bool {
        guard FileManager.default.fileExists(atPath: zipURL.path) else {
            logAppMessage("\(logPrefix) ZIP not found: \(zipURL.path)")
            return false
        }
        do {
            let status: Int32 = try await Task.detached(priority: .userInitiated) { () -> Int32 in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                process.arguments = ["-t", zipURL.path]
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus
            }.value
            if status == 0 { return true }
            logAppMessage("\(logPrefix) ZIP validation failed for \(zipURL.lastPathComponent) (status \(status)).")
            return false
        } catch {
            logAppMessage("\(logPrefix) Failed to validate ZIP archive \(zipURL.lastPathComponent): \(error.localizedDescription)")
            return false
        }
    }

    func unzipWorldBackup(_ zipURL: URL, into serverDir: URL, logPrefix: String) async -> Bool {
        do {
            let status: Int32 = try await Task.detached(priority: .userInitiated) { () -> Int32 in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                process.arguments = ["-o", zipURL.path, "-d", serverDir.path]
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus
            }.value
            if status == 0 {
                logAppMessage("\(logPrefix) Restored world from backup \(zipURL.lastPathComponent).")
                return true
            }
            logAppMessage("\(logPrefix) unzip failed when restoring world from backup (status \(status)).")
            return false
        } catch {
            logAppMessage("\(logPrefix) Failed to start unzip for world backup: \(error.localizedDescription)")
            return false
        }
    }

    func copyExistingWorldFolder(from srcFolder: URL, toServerDir serverDir: URL, levelName: String, logPrefix: String) async -> Bool {
        let destFolder = serverDir.appendingPathComponent(levelName, isDirectory: true)
        do {
            try await Task.detached(priority: .userInitiated) {
                let fm = FileManager.default
                if fm.fileExists(atPath: destFolder.path) { try fm.removeItem(at: destFolder) }
                try fm.copyItem(at: srcFolder, to: destFolder)
            }.value
            logAppMessage("\(logPrefix) Copied existing world folder '\(srcFolder.lastPathComponent)' into '\(destFolder.lastPathComponent)'.")
            return true
        } catch {
            logAppMessage("\(logPrefix) Failed to copy existing world folder: \(error.localizedDescription)")
            return false
        }
    }
}

//  AppViewModel+WorldRepair.swift
//  MinecraftServerController
//
//  Repairs a Bedrock world's level.dat by regenerating it with the current
//  BDS version while leaving the db (actual world data) untouched.
//  Fixes "Silverfish" / version-mismatch connection failures that appear after
//  a BDS update when the old level.dat format is no longer accepted.

import Foundation

extension AppViewModel {

    private static let repairTempLevelName = "_msc_repair_temp"

    /// Runs the full level.dat repair flow on the current selected Bedrock server.
    /// Must be called on the MainActor. Calls `logLine` on the main thread for each progress step.
    /// Returns `true` on success, `false` on any failure (server.properties is always restored).
    @MainActor
    func repairWorldLevelDat(logLine: @escaping (String) -> Void) async -> Bool {
        guard let server = selectedServer,
              let cfg = configServer(for: server),
              cfg.isBedrock else {
            logLine("No Bedrock server selected.")
            return false
        }

        isRepairingWorld = true
        defer { isRepairingWorld = false }

        let serverDir = cfg.serverDir

        // 1. Read current level-name — we need to restore it when done.
        var props = ServerPropertiesManager.readProperties(serverDir: serverDir)
        guard let originalLevelName = props["level-name"]?.trimmingCharacters(in: .whitespaces),
              !originalLevelName.isEmpty else {
            logLine("Could not read level-name from server.properties.")
            return false
        }
        logLine("World: \"\(originalLevelName)\"")

        // 2. Safety backup before touching anything.
        logLine("Creating backup of current world...")
        let backupOK = await createBackup(for: cfg, isAutomatic: false, triggerReason: "pre-repair")
        guard backupOK else {
            logLine("Backup failed — aborting repair.")
            return false
        }
        logLine("Backup created successfully.")

        // 3. Point server at a throw-away level so BDS generates a fresh level.dat.
        let tempName = Self.repairTempLevelName
        props["level-name"] = tempName
        do {
            try ServerPropertiesManager.writeProperties(props, to: serverDir)
        } catch {
            logLine("Could not update server.properties: \(error.localizedDescription)")
            return false
        }
        logLine("Starting server briefly to generate updated world format...")

        // 4. Start the server and poll until BDS reaches its ready state.
        lifecycle.serverReadyForAutoMetrics = false
        startServer()

        let startDeadline = Date().addingTimeInterval(180)
        while !lifecycle.serverReadyForAutoMetrics {
            if Date() > startDeadline {
                logLine("Timed out waiting for server to start. Aborting.")
                stopServer()
                props["level-name"] = originalLevelName
                try? ServerPropertiesManager.writeProperties(props, to: serverDir)
                return false
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        logLine("Server reached ready state — stopping...")
        stopServer()

        // Wait for the container to fully stop before touching files.
        let stopDeadline = Date().addingTimeInterval(30)
        while isServerRunning {
            if Date() > stopDeadline { break }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        // Give the backend (VM disk or Docker volume, depending on Bedrock Runtime
        // setting) a moment to fully release the world files after stopping.
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // 5. Copy the freshly generated level files into the original world folder.
        logLine("Applying updated world format files...")
        let fm = FileManager.default
        let serverDirURL = URL(fileURLWithPath: serverDir)
        let tempWorldURL = serverDirURL.appendingPathComponent("worlds/\(tempName)")
        let realWorldURL = serverDirURL.appendingPathComponent("worlds/\(originalLevelName)")

        guard fm.fileExists(atPath: realWorldURL.path) else {
            logLine("Original world folder not found at expected path — restoring server.properties.")
            props["level-name"] = originalLevelName
            try? ServerPropertiesManager.writeProperties(props, to: serverDir)
            return false
        }

        var copyFailed = false
        for file in ["level.dat", "level.dat_old", "levelname.txt"] {
            let src = tempWorldURL.appendingPathComponent(file)
            guard fm.fileExists(atPath: src.path) else { continue }
            let dst = realWorldURL.appendingPathComponent(file)
            do {
                if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
                try fm.copyItem(at: src, to: dst)
            } catch {
                logLine("Failed to copy \(file): \(error.localizedDescription)")
                copyFailed = true
            }
        }
        if copyFailed {
            props["level-name"] = originalLevelName
            try? ServerPropertiesManager.writeProperties(props, to: serverDir)
            return false
        }
        logLine("Format files updated.")

        // 6. Remove the temp world folder — it's no longer needed.
        logLine("Removing temporary files...")
        try? fm.removeItem(at: tempWorldURL)

        // 7. Restore the original level-name.
        props["level-name"] = originalLevelName
        do {
            try ServerPropertiesManager.writeProperties(props, to: serverDir)
        } catch {
            logLine("Warning: could not restore level-name in server.properties.")
        }

        return true
    }
}

// AppViewModel+WorldConversion.swift
// MinecraftServerController
//
// Owns the world conversion pipeline (Bedrock ↔ Java via Chunker CLI).
//
// Flow: unzip source slot → run Chunker → package output → create target slot
//       → backup target's active world → activate new slot → navigate to target server.
//
// All file I/O runs on a detached Task. Progress lines are emitted on an arbitrary thread;
// callers (WorldConversionWizardView) dispatch to main before updating UI.

import Foundation

// MARK: - Shared context for the conversion wizard sheet

/// Carries the source slot + server into WorldConversionWizardView.
/// Defined here so both DetailsWorldsTabView and ServerEditorWorldTab can use it.
struct WorldConversionContext: Identifiable {
    let id = UUID()
    let slot: WorldSlot
    let server: ConfigServer
}

// MARK: - Slot placement mode

enum ConversionSlotPlacement {
    case newSlot(name: String)
    case replaceExisting(slot: WorldSlot)
}

// MARK: - AppViewModel extension

extension AppViewModel {

    // MARK: - Server navigation

    /// Selects the server with the given ConfigServer on the main actor, causing the
    /// sidebar and detail pane to switch to it.
    @MainActor
    func selectServer(_ cfgServer: ConfigServer) {
        if let match = servers.first(where: { $0.id == cfgServer.id }) {
            selectedServer = match
        }
    }

    // MARK: - Preflight checks

    /// Returns true if the given ConfigServer is the currently running server.
    func isRunning(_ cfgServer: ConfigServer) -> Bool {
        isServerRunning && configManager.config.activeServerId == cfgServer.id
    }

    // MARK: - Main conversion entry point

    /// Converts a world slot from one Minecraft edition to another using Chunker CLI.
    ///
    /// - Parameters:
    ///   - sourceSlot: The WorldSlot on the source server to convert.
    ///   - sourceServer: ConfigServer the source slot belongs to.
    ///   - targetServer: ConfigServer where the converted world will be placed.
    ///   - targetFormat: Chunker format string for the desired output (e.g. "JAVA_1_21_4").
    ///   - placement: Whether to create a new slot or overwrite an existing one.
    ///   - progressHandler: Called with each status message during the conversion.
    ///                      Called from an arbitrary thread; callers must dispatch to main.
    ///
    /// Throws `ChunkerError` on failure. On success the target server is selected in the UI.
    @MainActor
    func performWorldConversion(
        sourceSlot: WorldSlot,
        sourceServer: ConfigServer,
        targetServer: ConfigServer,
        targetFormat: String,
        placement: ConversionSlotPlacement,
        progressHandler: @escaping (String) -> Void
    ) async throws {
        let chunker = ChunkerManager.shared
        let javaPath = configManager.config.javaPath

        guard let java = chunker.resolveJavaPath(appConfigJavaPath: javaPath) else {
            throw ChunkerError.javaNotFound
        }
        guard chunker.isInstalled else { throw ChunkerError.jarNotInstalled }

        // Determine target level-name (used for the zip folder structure and slot metadata)
        let targetLevelName = WorldSlotManager.currentLevelName(for: targetServer)

        // Validate placement has a non-empty name before doing any file work
        switch placement {
        case .newSlot(let name) where name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            throw ChunkerError.conversionFailed("Slot name cannot be empty.")
        default:
            break
        }

        // Source zip location
        let sourceZip = WorldSlotManager.zipURL(forSlot: sourceSlot, serverDir: sourceServer.serverDir)
        guard FileManager.default.fileExists(atPath: sourceZip.path) else {
            throw ChunkerError.conversionFailed("Source slot archive not found at \(sourceZip.path)")
        }

        // Build a temp working directory unique to this conversion run
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("msc_conversion_\(UUID().uuidString)", isDirectory: true)

        let unzipDir = tempRoot.appendingPathComponent("source", isDirectory: true)
        let chunkerOutputDir = tempRoot.appendingPathComponent("chunker_output", isDirectory: true)

        // Cleanup helper — called on both success and failure paths
        func cleanup() {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        do {
            // ── Step 1: Unzip source slot ───────────────────────────────────────
            progressHandler("Extracting source world…")
            try await unzipSlot(sourceZip: sourceZip, to: unzipDir)

            // ── Step 2: Locate the world folder inside the unzipped content ─────
            progressHandler("Locating world data…")
            guard let inputWorldDir = chunker.findInputWorldFolder(
                in: unzipDir,
                isBedrock: sourceServer.isBedrock,
                slotLevelName: sourceSlot.worldLevelName
            ) else {
                throw ChunkerError.worldFolderNotFound
            }
            progressHandler("Found world: \(inputWorldDir.lastPathComponent)")

            // ── Step 3: Run Chunker ─────────────────────────────────────────────
            progressHandler("Running Chunker conversion…")
            try await chunker.convert(
                inputDir: inputWorldDir,
                outputDir: chunkerOutputDir,
                targetFormat: targetFormat,
                javaPath: java,
                progressHandler: progressHandler
            )

            // ── Step 4: Package the Chunker output into a slot-compatible zip ───
            progressHandler("Packaging converted world…")
            let convertedZip = try await chunker.packageOutput(
                chunkerOutputDir: chunkerOutputDir,
                isBedrockTarget: targetServer.isBedrock,
                targetLevelName: targetLevelName
            )

            // ── Step 5: Place the zip into the target server's slot directory ────
            progressHandler("Placing converted world into target server…")
            let newSlot: WorldSlot
            switch placement {
            case .newSlot(let name):
                newSlot = try await createConvertedSlot(
                    name: name,
                    zipURL: convertedZip,
                    targetServer: targetServer,
                    targetLevelName: targetLevelName
                )

            case .replaceExisting(let existingSlot):
                newSlot = try await replaceSlotWithConvertedZip(
                    existingSlot: existingSlot,
                    zipURL: convertedZip,
                    targetServer: targetServer,
                    targetLevelName: targetLevelName
                )
            }

            // ── Step 6: Backup target server's current active world ──────────────
            progressHandler("Backing up target server's current world…")
            let backupOK = await createBackup(for: targetServer, isAutomatic: false, triggerReason: "pre-conversion")
            if !backupOK {
                progressHandler("Warning: pre-conversion backup failed. Proceeding with activation.")
            }

            // ── Step 7: Activate the new slot on the target server ───────────────
            progressHandler("Activating converted world on \(targetServer.displayName)…")
            let activated = await WorldSlotManager.activateSlot(
                newSlot,
                for: targetServer,
                backupCurrent: false,   // already backed up in step 6
                logLine: { msg in progressHandler(msg) },
                backupWorld: { _ in true }
            )
            guard activated else {
                throw ChunkerError.conversionFailed("Failed to activate converted world slot.")
            }

            // ── Step 8: Navigate to the target server ────────────────────────────
            await MainActor.run {
                selectServer(targetServer)
                loadWorldSlotsForSelectedServer()
                loadBackupsForSelectedServer()
            }

            progressHandler("Conversion complete.")
            cleanup()

        } catch {
            cleanup()
            throw error
        }
    }

    // MARK: - Private helpers

    private func unzipSlot(sourceZip: URL, to destination: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)

            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            p.arguments = ["-o", sourceZip.path, "-d", destination.path]
            // Use /dev/null — NOT Pipe(). A Pipe that isn't drained deadlocks
            // waitUntilExit() once its buffer fills (common with large worlds).
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try p.run()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else {
                throw ChunkerError.conversionFailed("Failed to extract source slot (unzip status \(p.terminationStatus))")
            }
        }.value
    }

    private func createConvertedSlot(
        name: String,
        zipURL: URL,
        targetServer: ConfigServer,
        targetLevelName: String
    ) async throws -> WorldSlot {
        let fm = FileManager.default
        let slotId = UUID().uuidString
        var slot = WorldSlot(
            id: slotId,
            name: name,
            createdAt: Date(),
            lastPlayedAt: nil,
            worldLevelName: targetLevelName
        )

        let slotsDir = WorldSlotManager.slotsDirectory(forServerDir: targetServer.serverDir)
        let slotDir = slotsDir.appendingPathComponent(slotId, isDirectory: true)
        let destZip = slotDir.appendingPathComponent("world.zip")

        try fm.createDirectory(at: slotDir, withIntermediateDirectories: true)
        try fm.copyItem(at: zipURL, to: destZip)

        if let attrs = try? fm.attributesOfItem(atPath: destZip.path),
           let size = attrs[.size] as? Int64 {
            slot.zipSizeBytes = size
        }

        try WorldSlotManager.saveMetadata(slot, serverDir: targetServer.serverDir)
        return slot
    }

    private func replaceSlotWithConvertedZip(
        existingSlot: WorldSlot,
        zipURL: URL,
        targetServer: ConfigServer,
        targetLevelName: String
    ) async throws -> WorldSlot {
        let fm = FileManager.default
        let destZip = WorldSlotManager.zipURL(forSlot: existingSlot, serverDir: targetServer.serverDir)
        let slotDir = WorldSlotManager.slotDirectory(slot: existingSlot, serverDir: targetServer.serverDir)

        try fm.createDirectory(at: slotDir, withIntermediateDirectories: true)
        if fm.fileExists(atPath: destZip.path) {
            try fm.removeItem(at: destZip)
        }
        try fm.copyItem(at: zipURL, to: destZip)

        var updated = existingSlot
        updated.worldLevelName = targetLevelName
        if let attrs = try? fm.attributesOfItem(atPath: destZip.path),
           let size = attrs[.size] as? Int64 {
            updated.zipSizeBytes = size
        }

        try WorldSlotManager.saveMetadata(updated, serverDir: targetServer.serverDir)
        return updated
    }
}

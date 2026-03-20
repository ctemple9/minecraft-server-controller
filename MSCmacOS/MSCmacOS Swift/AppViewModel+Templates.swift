//
//  AppViewModel+Templates.swift
//  MinecraftServerController
//

import Foundation

// Summary of what JARs a given ConfigServer is currently using.
// These strings are ready for display, e.g.:
//   "paper.jar — Dec 4, 2025 at 9:40 PM"
struct ServerJarSummary {
    let paperFilename: String?
    let geyserFilename: String?
    let floodgateFilename: String?
}

extension AppViewModel {

    // Convenience flags for the UI
    var hasPaperTemplates: Bool {
        !paperTemplateItems.isEmpty
    }

    var hasPluginTemplates: Bool {
        !pluginTemplateItems.isEmpty
    }

    // MARK: - Plugin templates (Geyser / Floodgate etc.)

    func loadPluginTemplates() {
        let dir = configManager.pluginTemplateDirURL
        let fm = FileManager.default

        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: dir.path, isDirectory: &isDir) || !isDir.boolValue {
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                logAppMessage("[Plugin] Failed to create plugin template directory: \(error.localizedDescription)")
            }
            pluginTemplateItems = []
            return
        }

        do {
            let contents = try fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )

            let jars = contents
                .filter { $0.pathExtension.lowercased() == "jar" }
                .sorted {
                    $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
                }

            pluginTemplateItems = jars.map { PluginTemplateItem(url: $0) }
        } catch {
            logAppMessage("[Plugin] Failed to list plugin templates: \(error.localizedDescription)")
        }
    }

    func addPluginTemplates(from urls: [URL]) {
        guard !urls.isEmpty else { return }

        let destDir = configManager.pluginTemplateDirURL
        let fm = FileManager.default

        do {
            try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        } catch {
            logAppMessage("[Plugin] Failed to create plugin template directory: \(error.localizedDescription)")
            return
        }

        var copiedCount = 0

        for src in urls {
            let dst = destDir.appendingPathComponent(src.lastPathComponent)

            if fm.fileExists(atPath: dst.path) {
                do {
                    try fm.removeItem(at: dst)
                } catch {
                    logAppMessage("[Plugin] Failed to remove existing template \(dst.lastPathComponent): \(error.localizedDescription)")
                }
            }

            do {
                try fm.copyItem(at: src, to: dst)
                copiedCount += 1
            } catch {
                logAppMessage("[Plugin] Failed to copy template \(src.lastPathComponent): \(error.localizedDescription)")
            }
        }

        if copiedCount > 0 {
            logAppMessage("[Plugin] Added \(copiedCount) plugin template(s).")
            loadPluginTemplates()
        }
    }

    func removePluginTemplate(_ item: PluginTemplateItem) {
        let fm = FileManager.default
        do {
            try fm.removeItem(at: item.url)
            logAppMessage("[Plugin] Removed template \(item.filename).")
            loadPluginTemplates()
        } catch {
            logAppMessage("[Templates] Failed to remove plugin template \(item.filename): \(error.localizedDescription)")
        }
    }

    /// Apply selected plugin templates to the currently active server.
    /// - Replaces existing JARs with the same prefix (e.g. "Geyser", "floodgate").
    func applyPluginTemplatesToSelectedServer(selectedTemplates: [PluginTemplateItem]) {
        guard !selectedTemplates.isEmpty else {
            logAppMessage("[Plugin] No plugin templates selected to apply.")
            return
        }
        guard let server = selectedServer else {
            logAppMessage("[Plugin] No active server selected; cannot apply templates.")
            return
        }
        guard !isServerRunning else {
            logAppMessage("[Plugin] Refusing to apply templates while server is running. Stop the server first.")
            return
        }
        guard let cfgServer = configServer(for: server) else {
            logAppMessage("[Plugin] Could not find config entry for server \(server.name).")
            return
        }

        let fm = FileManager.default
        let serverDirURL = URL(fileURLWithPath: cfgServer.serverDir, isDirectory: true)
        let pluginsDirURL = serverDirURL.appendingPathComponent("plugins", isDirectory: true)

        do {
            try fm.createDirectory(at: pluginsDirURL, withIntermediateDirectories: true)
        } catch {
            logAppMessage("[Plugin] Failed to create plugins directory: \(error.localizedDescription)")
            return
        }

        var appliedCount = 0

        do {
            let existingPlugins = try fm.contentsOfDirectory(
                at: pluginsDirURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )

            for template in selectedTemplates {
                let templateBase = template.url.deletingPathExtension().lastPathComponent
                let templatePrefix = templateBase.components(separatedBy: "-").first ?? templateBase
                let templatePrefixLower = templatePrefix.lowercased()

                // Remove any existing plugin JAR with the same prefix (case-insensitive)
                for existing in existingPlugins where existing.pathExtension.lowercased() == "jar" {
                    let existingBase = existing.deletingPathExtension().lastPathComponent
                    let existingPrefix = existingBase.components(separatedBy: "-").first ?? existingBase
                    let existingPrefixLower = existingPrefix.lowercased()

                    if existingPrefixLower == templatePrefixLower {
                        do {
                            try fm.removeItem(at: existing)
                        } catch {
                            logAppMessage("[Plugin] Failed to remove existing plugin \(existing.lastPathComponent): \(error.localizedDescription)")
                        }
                    }
                }

                let destURL = pluginsDirURL.appendingPathComponent(template.url.lastPathComponent)

                if fm.fileExists(atPath: destURL.path) {
                    do {
                        try fm.removeItem(at: destURL)
                    } catch {
                        logAppMessage("[Plugin] Failed to remove existing plugin \(destURL.lastPathComponent): \(error.localizedDescription)")
                    }
                }

                do {
                    try fm.copyItem(at: template.url, to: destURL)
                    appliedCount += 1
                    logAppMessage("[Plugin] Applied template \(template.filename) to \(server.name).")
                } catch {
                    logAppMessage("[Plugin] Failed to copy template \(template.filename) to plugins folder: \(error.localizedDescription)")
                }
            }

            
        } catch {
            logAppMessage("[Plugin] Failed to enumerate existing plugins: \(error.localizedDescription)")
            return
        }

        if appliedCount > 0 {
            logAppMessage("[Plugin] Finished applying \(appliedCount) plugin template(s) to \(server.name).")
        }

        // Components tab: refresh local/template display after applying.
        refreshComponentsSnapshotLocalAndTemplate(clearOnline: false)
    }

    // MARK: - Paper templates

    func loadPaperTemplates() {
        let dir = configManager.paperTemplateDirURL
        let fm = FileManager.default

        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: dir.path, isDirectory: &isDir) || !isDir.boolValue {
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                logAppMessage("[Paper] Failed to create Paper template directory: \(error.localizedDescription)")
            }
            paperTemplateItems = []
            return
        }

        do {
            let contents = try fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )

            let jars = contents
                .filter { $0.pathExtension.lowercased() == "jar" }
                .sorted {
                    $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
                }

            paperTemplateItems = jars.map { PaperTemplateItem(url: $0) }
        } catch {
            logAppMessage("[Paper] Failed to list Paper templates: \(error.localizedDescription)")
        }
    }

    func addPaperTemplates(from urls: [URL]) {
        guard !urls.isEmpty else { return }

        let destDir = configManager.paperTemplateDirURL
        let fm = FileManager.default

        do {
            try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        } catch {
            logAppMessage("[Paper] Failed to create Paper template directory: \(error.localizedDescription)")
            return
        }

        var copiedCount = 0

        for src in urls {
            let dst = destDir.appendingPathComponent(src.lastPathComponent)

            if fm.fileExists(atPath: dst.path) {
                do {
                    try fm.removeItem(at: dst)
                } catch {
                    logAppMessage("[Paper] Failed to remove existing template \(dst.lastPathComponent): \(error.localizedDescription)")
                }
            }

            do {
                try fm.copyItem(at: src, to: dst)
                copiedCount += 1
            } catch {
                logAppMessage("[Paper] Failed to copy template \(src.lastPathComponent): \(error.localizedDescription)")
            }
        }

        if copiedCount > 0 {
            logAppMessage("[Paper] Added \(copiedCount) Paper template(s).")
            loadPaperTemplates()
        }
    }

    func removePaperTemplate(_ item: PaperTemplateItem) {
        let fm = FileManager.default
        do {
            try fm.removeItem(at: item.url)
            logAppMessage("[Paper] Removed template \(item.filename).")
            loadPaperTemplates()
        } catch {
            logAppMessage("[Templates] Failed to remove Paper template \(item.filename): \(error.localizedDescription)")
        }
    }

    /// Apply a Paper template JAR to the active server.
    func applyPaperTemplateToSelectedServer(template: PaperTemplateItem) {
        guard let server = selectedServer else {
            logAppMessage("[Paper] No active server selected; cannot apply Paper template.")
            return
        }
        guard !isServerRunning else {
            logAppMessage("[Paper] Refusing to apply Paper template while server is running. Stop the server first.")
            return
        }
        guard let cfgServer = configServer(for: server) else {
            logAppMessage("[Paper] Could not find config entry for server \(server.name).")
            return
        }

        let fm = FileManager.default
        let expandedServerDir = (cfgServer.serverDir as NSString).expandingTildeInPath
        let serverDirURL = URL(fileURLWithPath: expandedServerDir, isDirectory: true)

        // Destination jar path: either explicit paperJarPath or serverDir/paper.jar
        let destJarURL: URL
        let trimmed = cfgServer.paperJarPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            destJarURL = serverDirURL.appendingPathComponent("paper.jar")
        } else {
            destJarURL = URL(fileURLWithPath: trimmed)
        }

        do {
            try fm.createDirectory(
                at: destJarURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            logAppMessage("[Paper] Failed to ensure destination directory for Paper JAR: \(error.localizedDescription)")
            return
        }

        if fm.fileExists(atPath: destJarURL.path) {
            do {
                try fm.removeItem(at: destJarURL)
            } catch {
                logAppMessage("[Paper] Failed to remove existing Paper JAR at \(destJarURL.path): \(error.localizedDescription)")
            }
        }

        do {
            try fm.copyItem(at: template.url, to: destJarURL)
            logAppMessage("[Paper] Applied template \(template.filename) to \(server.name) at \(destJarURL.path).")

            // Write sidecar so Components can show local build even if jar is named paper.jar.
            if let parsed = ComponentVersionParsing.parsePaperJarFilename(template.filename) {
                PaperVersionSidecarManager.write(
                    mcVersion: parsed.mcVersion,
                    build: parsed.build,
                    toServerDirectory: serverDirURL
                )
            }
        } catch {
            logAppMessage("[Paper] Failed to copy Paper template \(template.filename): \(error.localizedDescription)")
        }

        // Components tab: refresh local/template display after applying.
        refreshComponentsSnapshotLocalAndTemplate(clearOnline: false)
    }

    // MARK: - Download latest Paper into templates (global)

    func downloadLatestPaperTemplate() async {
        let destDir = configManager.paperTemplateDirURL
        let fm = FileManager.default

        do {
            try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        } catch {
            logAppMessage("[Paper] Failed to create Paper template directory: \(error.localizedDescription)")
            return
        }

        let tempURL = destDir.appendingPathComponent("paper-latest-temp.jar")

        do {
            let result = try await PaperDownloader.downloadLatestPaper(to: tempURL)

            let finalFilename = "paper-\(result.version)-build\(result.build).jar"
            let finalURL = destDir.appendingPathComponent(finalFilename)

            if fm.fileExists(atPath: finalURL.path) {
                do {
                    try fm.removeItem(at: finalURL)
                } catch {
                    logAppMessage("[Paper] Failed to remove existing template \(finalFilename): \(error.localizedDescription)")
                }
            }

            do {
                try fm.moveItem(at: tempURL, to: finalURL)
            } catch {
                logAppMessage("[Paper] Failed to move downloaded JAR into templates: \(error.localizedDescription)")
                return
            }

            logAppMessage("[Paper] Downloaded latest Paper \(result.version) build \(result.build) into templates as \(finalFilename).")
            loadPaperTemplates()

        } catch {
            if fm.fileExists(atPath: tempURL.path) {
                try? fm.removeItem(at: tempURL)
            }
            logAppMessage("[Paper] Failed to download latest Paper: \(error.localizedDescription)")
        }
    }

    // MARK: - Download latest Geyser / Floodgate into plugin templates (global)

    func downloadLatestGeyserTemplate() async {
        let fm = FileManager.default
        let destDir = configManager.pluginTemplateDirURL

        do {
            try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        } catch {
            logAppMessage("[Plugin] Failed to create plugin template directory: \(error.localizedDescription)")
            return
        }

        let tempURL = destDir.appendingPathComponent("Geyser-latest-temp.jar")
        if fm.fileExists(atPath: tempURL.path) {
            try? fm.removeItem(at: tempURL)
        }

        logAppMessage("[Plugin] Downloading latest Geyser template…")

        do {
            let result = try await PluginDownloader.downloadLatestGeyser(to: tempURL)

            // Include build number in the filename, e.g. Geyser-spigot-1004.jar
            let finalName = "Geyser-spigot-\(result.build).jar"
            let finalURL = destDir.appendingPathComponent(finalName)

            if fm.fileExists(atPath: finalURL.path) {
                try? fm.removeItem(at: finalURL)
            }

            try fm.moveItem(at: tempURL, to: finalURL)
            logAppMessage("[Plugin] Downloaded latest Geyser template: \(finalName) (build \(result.build))")
            loadPluginTemplates()
        } catch let err as PluginDownloadError {
            switch err {
            case .networkError(let message):
                logAppMessage("[Plugin] Failed to download latest Geyser: \(message)")
            case .cannotCreateFile:
                logAppMessage("[Plugin] Failed to save Geyser JAR to disk.")
            }
        } catch {
            logAppMessage("[Plugin] Failed to download latest Geyser: \(error.localizedDescription)")
        }
    }

    func downloadLatestFloodgateTemplate() async {
        let fm = FileManager.default
        let destDir = configManager.pluginTemplateDirURL

        do {
            try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        } catch {
            logAppMessage("[Plugin] Failed to create plugin template directory: \(error.localizedDescription)")
            return
        }

        let tempURL = destDir.appendingPathComponent("Floodgate-latest-temp.jar")
        if fm.fileExists(atPath: tempURL.path) {
            try? fm.removeItem(at: tempURL)
        }

        logAppMessage("[Plugin] Downloading latest Floodgate template…")

        do {
            let result = try await PluginDownloader.downloadLatestFloodgate(to: tempURL)

            // Include build number in the filename, e.g. floodgate-spigot-121.jar
            let finalName = "floodgate-spigot-\(result.build).jar"
            let finalURL = destDir.appendingPathComponent(finalName)

            if fm.fileExists(atPath: finalURL.path) {
                try? fm.removeItem(at: finalURL)
            }

            try fm.moveItem(at: tempURL, to: finalURL)
            logAppMessage("[Plugin] Downloaded latest Floodgate template: \(finalName) (build \(result.build))")
            loadPluginTemplates()
        } catch let err as PluginDownloadError {
            switch err {
            case .networkError(let message):
                logAppMessage("[Plugin] Failed to download latest Floodgate: \(message)")
            case .cannotCreateFile:
                logAppMessage("[Plugin] Failed to save Floodgate JAR to disk.")
            }
        } catch {
            logAppMessage("[Plugin] Failed to download latest Floodgate: \(error.localizedDescription)")
        }
    }

    // MARK: - Per-server JAR summary

    func jarSummary(for cfgServer: ConfigServer) -> ServerJarSummary {
        let fm = FileManager.default
        let serverDir = URL(fileURLWithPath: cfgServer.serverDir, isDirectory: true)
        let pluginsDir = serverDir.appendingPathComponent("plugins", isDirectory: true)

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        func label(forPath path: String) -> String? {
            guard fm.fileExists(atPath: path) else { return nil }
            let url = URL(fileURLWithPath: path)
            let name = url.lastPathComponent

            if let attrs = try? fm.attributesOfItem(atPath: path),
               let date = attrs[.modificationDate] as? Date {
                let dateString = formatter.string(from: date)
                return "\(name) — \(dateString)"
            } else {
                return name
            }
        }

        // PAPER
        let paperPath: String
        let trimmedPaper = cfgServer.paperJarPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPaper.isEmpty {
            paperPath = serverDir.appendingPathComponent("paper.jar").path
        } else {
            paperPath = trimmedPaper
        }
        let paperLabel = label(forPath: paperPath)

        // GEYSER / FLOODGATE – pick the *newest* JAR by modification date
        var geyserURLForSummary: URL? = nil
        var geyserDate: Date? = nil

        var floodgateURLForSummary: URL? = nil
        var floodgateDate: Date? = nil

        if let contents = try? fm.contentsOfDirectory(
            at: pluginsDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for url in contents where url.pathExtension.lowercased() == "jar" {
                let base = url.deletingPathExtension().lastPathComponent.lowercased()

                // Helper to maybe get the modification date
                let modDate: Date? = {
                    if let attrs = try? fm.attributesOfItem(atPath: url.path),
                       let d = attrs[.modificationDate] as? Date {
                        return d
                    }
                    return nil
                }()

                if base.hasPrefix("geyser") {
                    if let d = modDate {
                        if let current = geyserDate {
                            if d > current {
                                geyserDate = d
                                geyserURLForSummary = url
                            }
                        } else {
                            geyserDate = d
                            geyserURLForSummary = url
                        }
                    } else if geyserURLForSummary == nil {
                        // No date, but take the first one we see as a fallback
                        geyserURLForSummary = url
                    }
                } else if base.hasPrefix("floodgate") {
                    if let d = modDate {
                        if let current = floodgateDate {
                            if d > current {
                                floodgateDate = d
                                floodgateURLForSummary = url
                            }
                        } else {
                            floodgateDate = d
                            floodgateURLForSummary = url
                        }
                    } else if floodgateURLForSummary == nil {
                        floodgateURLForSummary = url
                    }
                }
            }
        }

        let geyserLabel = geyserURLForSummary.flatMap { label(forPath: $0.path) }
        let floodgateLabel = floodgateURLForSummary.flatMap { label(forPath: $0.path) }

        return ServerJarSummary(
            paperFilename: paperLabel,
            geyserFilename: geyserLabel,
            floodgateFilename: floodgateLabel
        )
    }

    
    // MARK: - “Update from template” helpers (per-server)

    /// Pick the latest paper-*.jar in templates and copy it into this server's Paper location.
    func updatePaperFromLatestTemplate(for cfgServer: ConfigServer) async {
        let fm = FileManager.default
        let templatesDir = configManager.paperTemplateDirURL

        guard let template = latestTemplate(in: templatesDir, prefixLowercased: "paper") else {
            logAppMessage("[Paper] No Paper templates found. Download or add one first.")
            return
        }

        let serverDir = URL(fileURLWithPath: cfgServer.serverDir, isDirectory: true)

        let destJarURL: URL
        let trimmed = cfgServer.paperJarPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            destJarURL = serverDir.appendingPathComponent("paper.jar")
        } else {
            destJarURL = URL(fileURLWithPath: trimmed)
        }

        do {
            try fm.createDirectory(at: destJarURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            logAppMessage("[Paper] Failed to create Paper destination directory: \(error.localizedDescription)")
            return
        }

        if fm.fileExists(atPath: destJarURL.path) {
            try? fm.removeItem(at: destJarURL)
        }

        do {
            try fm.copyItem(at: template, to: destJarURL)
            logAppMessage("[Paper] Updated \(cfgServer.displayName) to \(template.lastPathComponent).")

            // Write sidecar so Components can show local build even when jar is named paper.jar
            if let parsed = ComponentVersionParsing.parsePaperJarFilename(template.lastPathComponent) {
                let serverDirURL = URL(fileURLWithPath: cfgServer.serverDir, isDirectory: true)
                PaperVersionSidecarManager.write(
                    mcVersion: parsed.mcVersion,
                    build: parsed.build,
                    toServerDirectory: serverDirURL
                )
            }
        } catch {
            logAppMessage("[Paper] Failed to copy Paper template: \(error.localizedDescription)")
        }
    }

    /// Pick the latest Geyser*.jar in plugin templates and copy into this server's plugins folder.
    func updateGeyserFromTemplate(for cfgServer: ConfigServer) async {
        await updatePluginTemplate(
            for: cfgServer,
            pluginPrefix: "geyser",
            prettyName: "Geyser"
        )
    }

    /// Pick the latest Floodgate*.jar in plugin templates and copy into this server's plugins folder.
    func updateFloodgateFromTemplate(for cfgServer: ConfigServer) async {
        await updatePluginTemplate(
            for: cfgServer,
            pluginPrefix: "floodgate",
            prettyName: "Floodgate"
        )
    }

    /// Shared helper for Geyser / Floodgate update buttons.
    private func updatePluginTemplate(
        for cfgServer: ConfigServer,
        pluginPrefix: String,
        prettyName: String
    ) async {
        let fm = FileManager.default
        let templatesDir = configManager.pluginTemplateDirURL

        guard let template = latestTemplate(in: templatesDir, prefixLowercased: pluginPrefix) else {
            logAppMessage("[Plugin] No \(prettyName) templates found. Download or add one first.")
            return
        }

        let serverDir = URL(fileURLWithPath: cfgServer.serverDir, isDirectory: true)
        let pluginsDir = serverDir.appendingPathComponent("plugins", isDirectory: true)

        do {
            try fm.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
        } catch {
            logAppMessage("[Plugin] Failed to create plugins directory: \(error.localizedDescription)")
            return
        }

        // Remove old versions of this plugin
        if let contents = try? fm.contentsOfDirectory(
            at: pluginsDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for url in contents where url.pathExtension.lowercased() == "jar" {
                let base = url.deletingPathExtension().lastPathComponent.lowercased()
                if base.hasPrefix(pluginPrefix.lowercased()) {
                    try? fm.removeItem(at: url)
                }
            }
        }

        let destURL = pluginsDir.appendingPathComponent(template.lastPathComponent)

        if fm.fileExists(atPath: destURL.path) {
            try? fm.removeItem(at: destURL)
        }

        do {
            try fm.copyItem(at: template, to: destURL)
            logAppMessage("[Plugin] Updated \(prettyName) for \(cfgServer.displayName) to \(template.lastPathComponent).")
        } catch {
            logAppMessage("[Plugin] Failed to copy \(prettyName) template: \(error.localizedDescription)")
        }
    }

    /// Find the alphabetically “latest” JAR in a directory with a given prefix.
    // MARK: - Download + apply latest (single-action for Components tab)

        func downloadAndApplyLatestPaper() {
            guard let server = selectedServer, let cfg = configServer(for: server) else {
                logAppMessage("[Paper] No server selected."); return
            }
            isDownloadingAndApplyingPaper = true
            Task {
                await downloadLatestPaperTemplate()
                await updatePaperFromLatestTemplate(for: cfg)
                isDownloadingAndApplyingPaper = false
                refreshComponentsSnapshotLocalAndTemplate(clearOnline: false)
            }
        }

        func downloadAndApplyLatestGeyser() {
            guard let server = selectedServer, let cfg = configServer(for: server) else {
                logAppMessage("[Plugin] No server selected."); return
            }
            isDownloadingAndApplyingGeyser = true
            Task {
                await downloadLatestGeyserTemplate()
                await updateGeyserFromTemplate(for: cfg)
                isDownloadingAndApplyingGeyser = false
                refreshComponentsSnapshotLocalAndTemplate(clearOnline: false)
            }
        }

        func downloadAndApplyLatestFloodgate() {
            guard let server = selectedServer, let cfg = configServer(for: server) else {
                logAppMessage("[Plugin] No server selected."); return
            }
            isDownloadingAndApplyingFloodgate = true
            Task {
                await downloadLatestFloodgateTemplate()
                await updateFloodgateFromTemplate(for: cfg)
                isDownloadingAndApplyingFloodgate = false
                refreshComponentsSnapshotLocalAndTemplate(clearOnline: false)
            }
        }

        private func latestTemplate(in dir: URL, prefixLowercased: String) -> URL? {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let jars = contents.filter { url in
            guard url.pathExtension.lowercased() == "jar" else { return false }
            let base = url.deletingPathExtension().lastPathComponent.lowercased()
            return base.hasPrefix(prefixLowercased.lowercased())
        }

        return jars.sorted { $0.lastPathComponent < $1.lastPathComponent }.last
    }
}


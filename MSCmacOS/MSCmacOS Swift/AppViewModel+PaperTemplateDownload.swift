//  AppViewModel+PaperTemplateDownload.swift
//  MinecraftServerController
//
//  Download the latest Paper build into the Paper templates folder,
//  reusing the existing PaperDownloader logic.
//

import Foundation

extension AppViewModel {

    /// Download the latest Paper build into the Paper template directory.
    ///
    /// - This uses `PaperDownloader.downloadLatestPaper` (the same code path
    ///   used by the Create Server flow), then moves the JAR into the templates
    ///   folder with a friendly, versioned filename:
    ///   `paper-<version>-build<build>.jar`.
    func downloadLatestPaperTemplate() {
        let destDir = configManager.paperTemplateDirURL

        Task.detached { [weak self] in
            guard let self else { return }
            let fm = FileManager.default

            // Ensure templates directory exists
            do {
                try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
            } catch {
                await MainActor.run {
                    self.logAppMessage("[Paper] Failed to create Paper template directory: \(error.localizedDescription)")
                }
                return
            }

            // Temporary download location inside the templates folder
            let tempURL = destDir.appendingPathComponent("paper-latest-temp.jar")

            do {
                // Reuse the known-working downloader
                let result = try await PaperDownloader.downloadLatestPaper(to: tempURL)

                // Final, versioned filename in the templates folder
                let finalFilename = "paper-\(result.version)-build\(result.build).jar"
                let finalURL = destDir.appendingPathComponent(finalFilename)

                if fm.fileExists(atPath: finalURL.path) {
                    try fm.removeItem(at: finalURL)
                }

                try fm.moveItem(at: tempURL, to: finalURL)

                await MainActor.run {
                    self.logAppMessage("[Paper] Downloaded latest Paper \(result.version) build \(result.build) into templates as \(finalFilename).")
                    self.loadPaperTemplates()
                }
            } catch {
                // Cleanup temp file on failure
                try? fm.removeItem(at: tempURL)

                await MainActor.run {
                    self.logAppMessage("[Paper] Failed to download latest Paper: \(error.localizedDescription)")
                }
            }
        }
    }
}


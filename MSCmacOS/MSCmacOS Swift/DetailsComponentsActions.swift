//
//  DetailsComponentsActions.swift
//  MinecraftServerController
//

import SwiftUI
import AppKit

extension DetailsComponentsTabView {

    // MARK: - Components actions

    func replacePaperJarFromFilePicker() {
        guard let server = viewModel.selectedServer,
              let cfg = viewModel.configServer(for: server) else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["jar"]
        panel.prompt = "Replace"

        if panel.runModal() == .OK, let srcURL = panel.url {
            // Reuse the same destination logic as applying a Paper template.
            let serverDirURL = URL(fileURLWithPath: cfg.serverDir, isDirectory: true)
            let trimmed = cfg.paperJarPath.trimmingCharacters(in: .whitespacesAndNewlines)
            let destURL = trimmed.isEmpty
                ? serverDirURL.appendingPathComponent("paper.jar")
                : URL(fileURLWithPath: trimmed)

            do {
                let fm = FileManager.default
                try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: destURL.path) {
                    try fm.removeItem(at: destURL)
                }
                try fm.copyItem(at: srcURL, to: destURL)
                viewModel.logAppMessage("[Components] Replaced Paper jar with \(srcURL.lastPathComponent).")
                viewModel.refreshComponentsSnapshotLocalAndTemplate(clearOnline: false)
            } catch {
                viewModel.logAppMessage("[Components] Failed to replace Paper jar: \(error.localizedDescription)")
            }
        }
    }

    func replacePluginJarFromFilePicker(keyword: String) {
        guard let server = viewModel.selectedServer,
              let cfg = viewModel.configServer(for: server) else { return }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["jar"]
        panel.prompt = "Replace"

        if panel.runModal() == .OK, let srcURL = panel.url {
            let fm = FileManager.default
            let serverDirURL = URL(fileURLWithPath: cfg.serverDir, isDirectory: true)
            let pluginsDir = serverDirURL.appendingPathComponent("plugins", isDirectory: true)

            do {
                try fm.createDirectory(at: pluginsDir, withIntermediateDirectories: true)

                // Remove the first matching existing jar.
                let existing = try fm.contentsOfDirectory(at: pluginsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                    .first(where: { $0.pathExtension.lowercased() == "jar" && $0.lastPathComponent.lowercased().contains(keyword.lowercased()) })

                if let existing {
                    try? fm.removeItem(at: existing)
                }

                let destURL = pluginsDir.appendingPathComponent(srcURL.lastPathComponent)
                if fm.fileExists(atPath: destURL.path) {
                    try fm.removeItem(at: destURL)
                }

                try fm.copyItem(at: srcURL, to: destURL)
                viewModel.logAppMessage("[Components] Replaced \(keyword) plugin jar with \(srcURL.lastPathComponent).")
                viewModel.refreshComponentsSnapshotLocalAndTemplate(clearOnline: false)
            } catch {
                viewModel.logAppMessage("[Components] Failed to replace \(keyword) jar: \(error.localizedDescription)")
            }
        }
    }

    func replaceBroadcastJarFromFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["jar"]
        panel.prompt = "Replace"

        if panel.runModal() == .OK, let srcURL = panel.url {
            guard let path = viewModel.configManager.config.xboxBroadcastJarPath, !path.isEmpty else {
                viewModel.logAppMessage("[Components] Broadcast jar path is not configured. Use the Broadcast installer first.")
                return
            }

            let destURL = URL(fileURLWithPath: path)
            do {
                let fm = FileManager.default
                try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: destURL.path) {
                    try fm.removeItem(at: destURL)
                }
                try fm.copyItem(at: srcURL, to: destURL)

                // If user manually replaced the jar, we no longer know the version.
                // Clear stored version so the UI doesn't show stale info.
                let versionFileURL = viewModel.configManager.appDirectoryURL
                    .appendingPathComponent("MCXboxBroadcastStandalone.version.txt", isDirectory: false)
                try? fm.removeItem(at: versionFileURL)

                viewModel.logAppMessage("[Components] Replaced Broadcast jar with \(srcURL.lastPathComponent).")
                viewModel.refreshComponentsSnapshotLocalAndTemplate(clearOnline: false)
            } catch {
                viewModel.logAppMessage("[Components] Failed to replace Broadcast jar: \(error.localizedDescription)")
            }
        }
    }

    func revealPaperJarInFinder() {
        guard let server = viewModel.selectedServer,
              let cfg = viewModel.configServer(for: server) else { return }
        if let url = viewModel.effectivePaperJarURL(for: cfg) {
            viewModel.revealInFinder(url: url)
        }
    }

    func revealPluginInFinder(keyword: String) {
        guard let server = viewModel.selectedServer,
              let cfg = viewModel.configServer(for: server) else { return }
        let serverDirURL = URL(fileURLWithPath: cfg.serverDir, isDirectory: true)
        let pluginsDir = serverDirURL.appendingPathComponent("plugins", isDirectory: true)
        viewModel.revealInFinder(url: pluginsDir)
    }

    func revealBroadcastJarInFinder() {
        if let path = viewModel.configManager.config.xboxBroadcastJarPath, !path.isEmpty {
            viewModel.revealInFinder(url: URL(fileURLWithPath: path))
        }
    }

    func replaceBedrockConnectJarFromFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["jar"]
        panel.prompt = "Replace"

        if panel.runModal() == .OK, let srcURL = panel.url {
            guard let path = viewModel.configManager.config.bedrockConnectJarPath, !path.isEmpty else {
                viewModel.logAppMessage("[Components] Bedrock Connect JAR path is not configured. Use the JAR Manager first.")
                return
            }

            let destURL = URL(fileURLWithPath: path)
            do {
                let fm = FileManager.default
                try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: destURL.path) {
                    try fm.removeItem(at: destURL)
                }
                try fm.copyItem(at: srcURL, to: destURL)
                viewModel.logAppMessage("[Components] Replaced Bedrock Connect JAR with \(srcURL.lastPathComponent).")
                viewModel.refreshComponentsSnapshotLocalAndTemplate(clearOnline: false)
            } catch {
                viewModel.logAppMessage("[Components] Failed to replace Bedrock Connect JAR: \(error.localizedDescription)")
            }
        }
    }

    func revealBedrockConnectJarInFinder() {
        if let path = viewModel.configManager.config.bedrockConnectJarPath, !path.isEmpty {
            viewModel.revealInFinder(url: URL(fileURLWithPath: path))
        } else {
            viewModel.openBedrockConnectJarFolder()
        }
    }

}

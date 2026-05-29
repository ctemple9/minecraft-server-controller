//
//  DetailsComponentsActions.swift
//  MinecraftServerController
//

import SwiftUI
import AppKit

extension DetailsComponentsTabView {

    // MARK: - Finder reveal actions

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
}

// MARK: - AppViewModel helper exposed for views

extension AppViewModel {
    /// The ConfigServer for the currently selected server.
    /// Exposed as internal so view-layer helpers can access it without duplicating the lookup.
    var selectedServerConfig: ConfigServer? {
        guard let server = selectedServer else { return nil }
        return configManager.config.servers.first(where: { $0.id == server.id })
    }
}

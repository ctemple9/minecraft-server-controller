//
//  OverviewConnectionHelpers.swift
//  MinecraftServerController
//

import SwiftUI

extension OverviewConnectionCardView {

    // MARK: - Overview: Join Info Helpers

    /// Builds a clean, shareable join message from all available connection info.
    /// Respects the Local / Public toggle so "Copy All" always matches what's shown.
    func buildJoinInfoMessage() -> String {
        var lines: [String] = []

        if let server = viewModel.selectedServer {
            lines.append("🎮 Join \(server.name)")
            lines.append("")
        }

        let isBedrockServer = viewModel.selectedServer
            .flatMap { viewModel.configServer(for: $0) }?
            .isBedrock == true

        if !isBedrockServer {
            let javaAddr = resolvedJavaAddress
            let javaPort = viewModel.javaPortForDisplay
            lines.append("Java (PC/Mac): \(javaAddr):\(javaPort)")
        }

        let duckHost = viewModel.duckdnsInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !duckHost.isEmpty {
            lines.append("Hostname: \(duckHost)")
        }

        if isBedrockServer {
            let addr = resolvedBedrockAddress ?? viewModel.javaAddressForDisplay
            let ipv4Port = resolvedBedrockPort ?? 19132
            lines.append("Bedrock IPv4: \(addr):\(ipv4Port)")
            // IPv6 only meaningful on LAN
            if !showPublicIP {
                let ipv6Port = resolvedBedrockPortV6 ?? 19133
                lines.append("Bedrock IPv6: \(addr):\(ipv6Port)")
            }
        } else if let bedAddr = resolvedBedrockAddress,
                  let bedPort = viewModel.bedrockPortForDisplay {
            lines.append("Bedrock (Mobile/Console): \(bedAddr):\(bedPort)")
        }

        return lines.joined(separator: "\n")
    }
}

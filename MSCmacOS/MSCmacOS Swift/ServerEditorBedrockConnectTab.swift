import SwiftUI

extension ServerEditorView {
// MARK: - BEDROCK CONNECT TAB (Java only)

var bedrockConnectTab: some View {
    VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
        if mode == .new || editingConfigServer == nil {
            SEUnavailableCard(
                icon: "gamecontroller.fill",
                title: "Save first to configure Bedrock Connect",
                message: "Bedrock Connect settings are available after the server is created. Save, then reopen Edit Server."
            )
        } else if let cfg = editingConfigServer {
            let propsModel = viewModel.loadServerPropertiesModel(for: cfg)
            let bedrockPort = cfg.xboxBroadcastPortOverride ?? propsModel.bedrockPort
            let portDisplay = bedrockPort.map(String.init) ?? "—"

            SECallout(
                icon: "info.circle.fill",
                color: .purple,
                text: "Bedrock Connect is a global service — one instance handles all your servers. It intercepts the Mojang Featured Servers lookup and shows your own list instead, enabling PlayStation and Switch players to join."
            )

            SESection(icon: "gamecontroller.fill", title: "Bedrock Connect Service", color: .purple) {
                VStack(alignment: .leading, spacing: MSC.Spacing.md) {
                    HStack(spacing: MSC.Spacing.sm) {
                        Circle()
                            .fill(viewModel.isBedrockConnectJarInstalled ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(viewModel.isBedrockConnectJarInstalled
                             ? "Bedrock Connect JAR installed."
                             : "Bedrock Connect JAR not installed yet.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Download…") { viewModel.downloadOrUpdateBedrockConnectJar() }
                            .buttonStyle(MSCSecondaryButtonStyle())
                            .controlSize(.small)
                    }

                    Button("Open Bedrock Connect Folder…") { viewModel.openBedrockConnectFolder() }
                        .buttonStyle(MSCSecondaryButtonStyle())
                        .controlSize(.small)
                }
            }

            SESection(icon: "network", title: "DNS Setup", color: .orange) {
                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                    Text("Point your router or console's DNS to this Mac's local IP. Bedrock Connect will intercept the Mojang lookup.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    SEInlineField(label: "This Mac's Local IP", hint: nil) {
                        Text(viewModel.javaAddressForDisplay)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    SEInlineField(label: "Bedrock Connect DNS Port", hint: "The port Bedrock Connect listens on. Must not match your server's Geyser Bedrock port.") {
                                               HStack(spacing: MSC.Spacing.xs) {
                                                   TextField("19132", value: Binding(
                                                       get: { viewModel.configManager.config.bedrockConnectDNSPort ?? 19132 },
                                                       set: { viewModel.configManager.setBedrockConnectDNSPort($0 == 19132 ? nil : $0) }
                                                   ), formatter: NumberFormatter())
                                                   .textFieldStyle(.roundedBorder)
                                                   .frame(width: 80)
                                                   Text("(default 19132)")
                                                       .font(.system(size: 10))
                                                       .foregroundStyle(.secondary)
                                               }
                                           }

                    if let geyserPort = cfg.xboxBroadcastPortOverride ?? propsModel.bedrockPort {
                        let dnsPort = viewModel.configManager.config.bedrockConnectDNSPort ?? 19132
                        if dnsPort == geyserPort {
                            HStack(spacing: MSC.Spacing.xs) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("DNS port \(dnsPort) matches this server's Geyser Bedrock port \(geyserPort). Change one to avoid a conflict.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }

            SESection(icon: "list.bullet.rectangle", title: "This Server in servers.json", color: .blue) {
                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                    Text("Bedrock Connect auto-generates a servers.json from all your servers that have a Bedrock port configured.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider().opacity(0.5)

                    SEInlineField(label: "Host", hint: nil) {
                        Text(viewModel.previewBroadcastHost(for: cfg, mode: cfg.xboxBroadcastIPMode))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    SEInlineField(label: "Bedrock Port", hint: nil) {
                        Text(portDisplay)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Text("To change the host or port, update them in the Broadcast tab or Server Settings.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

// MARK: - CONSOLE ACCESS TAB (Bedrock only — renamed to Bedrock Connect per P1)

var consoleAccessTab: some View {
    VStack(alignment: .leading, spacing: MSC.Spacing.lg) {

        SECallout(
            icon: "gamecontroller.fill",
            color: .purple,
            text: "Bedrock Connect lets PlayStation, Switch, and Xbox players join your server by redirecting the console's built-in server list to yours. It runs as a single global service — one DNS listener for all your servers."
        )

        SESection(icon: "gamecontroller.fill", title: "Bedrock Connect Service", color: .purple) {
            VStack(alignment: .leading, spacing: MSC.Spacing.md) {
                HStack(spacing: MSC.Spacing.sm) {
                    Circle()
                        .fill(viewModel.isBedrockConnectJarInstalled ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Button("Open Bedrock Connect Folder…") { viewModel.openBedrockConnectFolder() }
                        .buttonStyle(MSCSecondaryButtonStyle())
                        .controlSize(.small)
                    Spacer()
                    Button("Download…") { viewModel.downloadOrUpdateBedrockConnectJar() }
                        .buttonStyle(MSCSecondaryButtonStyle())
                        .controlSize(.small)
                }

                Button("Open Bedrock Connect Folder…") { viewModel.openBedrockConnectFolder() }
                    .buttonStyle(MSCSecondaryButtonStyle())
                    .controlSize(.small)
            }
        }

        SESection(icon: "network", title: "DNS Setup", color: .orange) {
            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                Text("On each console, set the DNS server to this Mac's local IP. Bedrock Connect intercepts the Mojang server lookup and replaces it with your server list.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                SEInlineField(label: "This Mac's Local IP", hint: nil) {
                    Text(viewModel.javaAddressForDisplay)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                SEInlineField(label: "Bedrock Connect DNS Port", hint: "The port Bedrock Connect listens on. Must not match your server's Bedrock game port (default 19132).") {                                            HStack(spacing: MSC.Spacing.xs) {
                                            TextField("19132", value: Binding(
                                                get: { viewModel.configManager.config.bedrockConnectDNSPort ?? 19132 },
                                                set: { viewModel.configManager.setBedrockConnectDNSPort($0 == 19132 ? nil : $0) }
                                            ), formatter: NumberFormatter())
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 80)
                                            Text("(default 19132)")
                                                .font(.system(size: 10))
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                if let cfg = editingConfigServer,
                   let serverPort = cfg.bedrockPort {
                    let dnsPort = viewModel.configManager.config.bedrockConnectDNSPort ?? 19132
                    if dnsPort == serverPort {
                        HStack(spacing: MSC.Spacing.xs) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("DNS port \(dnsPort) matches this server's Bedrock game port \(serverPort). Change one to avoid a conflict.")
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }

        if mode != .new, let cfg = editingConfigServer {
            SESection(icon: "list.bullet.rectangle", title: "This Server in servers.json", color: .blue) {
                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                    Text("Controls whether this server appears in the list BedrockConnect shows console players.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider().opacity(0.5)

                    let bedrockPort = cfg.bedrockPort.map(String.init) ?? "—"
                    SEInlineField(label: "Bedrock Port", hint: nil) {
                        Text(bedrockPort)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    SEInlineField(label: "Host", hint: nil) {
                        Text(viewModel.previewBroadcastHost(for: cfg, mode: cfg.xboxBroadcastIPMode))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Text("To change the host or port, update them in Server Settings.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

}

import SwiftUI
import AppKit

extension ServerEditorView {
// MARK: - BROADCAST TAB (Java only)

var broadcastTab: some View {
    VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
        if mode == .new || editingConfigServer == nil {
            SEUnavailableCard(
                icon: "dot.radiowaves.left.and.right",
                title: "Save first to configure broadcast",
                message: "Xbox broadcast settings are available after this server is created. Save, then reopen Edit Server."
            )
        } else if let cfg = editingConfigServer {
            let propsModel = viewModel.loadServerPropertiesModel(for: cfg)
            let hostForDisplay = viewModel.previewBroadcastHost(for: cfg, mode: broadcastIPMode)
            let portForDisplay = (cfg.xboxBroadcastPortOverride ?? propsModel.bedrockPort).map(String.init) ?? "—"

            SESection(icon: "dot.radiowaves.left.and.right", title: "Broadcast for This Server", color: .green) {
                VStack(alignment: .leading, spacing: MSC.Spacing.md) {

                    HStack(spacing: MSC.Spacing.sm) {
                        Toggle("", isOn: $broadcastEnabled).labelsHidden()
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Enable Xbox broadcast when this server starts")
                                .font(.system(size: 12, weight: .medium))
                            Text("Starts MCXboxBroadcastStandalone so your Xbox friends can see and join via your Bedrock port.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Divider().opacity(0.5)

                    SEInlineField(label: "Host", hint: nil) {
                        Text(hostForDisplay)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    SEInlineField(label: "IP Mode", hint: ipModeCaption(for: broadcastIPMode)) {
                        Picker("", selection: $broadcastIPMode) {
                            ForEach(XboxBroadcastIPMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                        .labelsHidden()
                    }

                    SEInlineField(label: "Bedrock Port", hint: nil) {
                        Text(portForDisplay)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Divider().opacity(0.5)

                    HStack(spacing: MSC.Spacing.sm) {
                        Circle()
                            .fill(viewModel.isXboxBroadcastHelperInstalled ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(viewModel.isXboxBroadcastHelperInstalled
                             ? "Broadcast helper installed."
                             : "Broadcast helper JAR not installed yet.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Download…") { viewModel.downloadOrUpdateXboxBroadcastJar() }
                            .buttonStyle(MSCSecondaryButtonStyle())
                            .controlSize(.small)
                    }

                    Button("Open Broadcast Config Folder…") {
                        viewModel.openBroadcastConfigFolder(for: cfg)
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                    .controlSize(.small)
                }
            }

            SESection(icon: "person.fill.badge.plus", title: "Alt Account Profile (Notes Only)", color: .purple) {
                VStack(alignment: .leading, spacing: MSC.Spacing.md) {

                    SECallout(
                        icon: "info.circle.fill",
                        color: .purple,
                        text: "These fields are just for your reference — which Microsoft/Xbox account you use as the broadcast alt. Stored locally in your config; the app does not log in for you."
                    )

                    HStack(spacing: MSC.Spacing.md) {
                        ZStack {
                            if let img = broadcastAvatarImage {
                                Image(nsImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 44, height: 44)
                                    .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.15))
                                    .frame(width: 44, height: 44)
                                Text(avatarInitial(for: broadcastAltGamertag))
                                    .font(.title2.bold())
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(broadcastAltGamertag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                 ? "No gamertag set"
                                 : broadcastAltGamertag)
                                .font(.system(size: 13, weight: .semibold))
                            Button("Choose Photo…") { browseForBroadcastAvatar() }
                                .buttonStyle(MSCSecondaryButtonStyle())
                                .controlSize(.small)
                        }
                    }

                    Divider().opacity(0.5)

                    SEField(label: "Email", hint: nil) {
                        TextField("email@example.com", text: $broadcastAltEmail)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 280)
                    }
                    SEField(label: "Gamertag", hint: nil) {
                        TextField("Alt gamertag", text: $broadcastAltGamertag)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 280)
                    }
                    SEField(label: "Password", hint: "Stored in local config only") {
                        HStack(spacing: MSC.Spacing.xs) {
                            if showBroadcastAltPassword {
                                TextField("Password", text: $broadcastAltPassword)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                SecureField("Password", text: $broadcastAltPassword)
                                    .textFieldStyle(.roundedBorder)
                            }
                            Button {
                                showBroadcastAltPassword.toggle()
                            } label: {
                                Image(systemName: showBroadcastAltPassword ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.borderless)
                        }
                        .frame(maxWidth: 280)
                    }
                }
            }
        }
    }
}

}

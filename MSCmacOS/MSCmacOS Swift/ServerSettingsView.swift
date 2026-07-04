
//
//  ServerSettingsView.swift
//  MinecraftServerController
//
//  Visual update: GroupBox replaced with Components-style section cards.
//  Buttons and pickers updated to match app design system.
//  Online Mode is toggleable for Java servers.
//
//  Rules enforced here:
//    - Java server  → shows Java settings (MOTD, RAM hints, Geyser port field)
//    - Bedrock server → shows Bedrock settings (level-name, allow-cheats, IPv6 port)
//    - Shared fields shown for both but labelled appropriately.
//
//  * View distance is Java-only; BDS uses tick-distance (not surfaced here).
//

import SwiftUI

struct JavaServerSettingsDraft {
    var model: ServerPropertiesModel
    var bedrockPortText: String
    var purpurConfig: PurpurConfig?
}

struct BedrockServerSettingsDraft {
    var model: BedrockPropertiesModel
    var bedrockPortV6Text: String
}

struct SettingsValidationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct ServerSettingsView: View {
    @EnvironmentObject var viewModel: AppViewModel

    @Binding var isPresented: Bool
    let configServer: ConfigServer

    @State private var model: ServerPropertiesModel
    @State private var bedrockModel: BedrockPropertiesModel
    @State private var bedrockPortText: String
    @State private var bedrockPortV6Text: String
    @State private var purpurConfig: PurpurConfig?

    let isInline: Bool
    let sectionFill: Color
    let onJavaDraftChange: ((JavaServerSettingsDraft) -> Void)?
    let onBedrockDraftChange: ((BedrockServerSettingsDraft) -> Void)?

    init(
        isPresented: Binding<Bool>,
        configServer: ConfigServer,
        initialModel: ServerPropertiesModel,
        initialBedrockModel: BedrockPropertiesModel = BedrockPropertiesModel(),
        initialBedrockPortText: String? = nil,
        initialBedrockPortV6Text: String? = nil,
        initialPurpurConfig: PurpurConfig? = nil,
        isInline: Bool = false,
        sectionFill: Color = MSC.Colors.cardBackground,
        onJavaDraftChange: ((JavaServerSettingsDraft) -> Void)? = nil,
        onBedrockDraftChange: ((BedrockServerSettingsDraft) -> Void)? = nil
    ) {
        self._isPresented             = isPresented
        self.configServer             = configServer
        self._model                   = State(initialValue: initialModel)
        self._bedrockModel            = State(initialValue: initialBedrockModel)
        self._bedrockPortText         = State(initialValue: initialBedrockPortText ?? initialModel.bedrockPort.map(String.init) ?? "")
        self._bedrockPortV6Text       = State(initialValue: initialBedrockPortV6Text ?? String(initialBedrockModel.serverPortV6))
        self._purpurConfig            = State(initialValue: initialPurpurConfig)
        self.isInline                 = isInline
        self.sectionFill              = sectionFill
        self.onJavaDraftChange        = onJavaDraftChange
        self.onBedrockDraftChange     = onBedrockDraftChange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            if !isInline {
                HStack {
                    Text("Server Settings")
                        .font(.title2).bold()
                    Spacer()
                    Text(configServer.displayName.isEmpty ? "(no name)" : configServer.displayName)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Divider()
            }

            if configServer.isJava {
                javaSettingsForm
            } else {
                bedrockSettingsForm
            }

            Spacer()

            if !isInline {
                HStack {
                    Button("Cancel") { isPresented = false }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Save") { handleSave() }
                        .buttonStyle(MSCPrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 420)
        .alert("Invalid Settings", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            onJavaDraftChange?(javaDraft)
            onBedrockDraftChange?(bedrockDraft)
            if configServer.isBedrock { viewModel.fetchBedrockVersionsIfNeeded() }
        }
        .onChange(of: model) { _ in onJavaDraftChange?(javaDraft) }
        .onChange(of: purpurConfig) { _ in onJavaDraftChange?(javaDraft) }
        .onChange(of: bedrockPortText) { _ in
            let trimmed = bedrockPortText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { model.bedrockPort = nil }
            else if let p = Int(trimmed) { model.bedrockPort = p }
            onJavaDraftChange?(javaDraft)
        }
        .onChange(of: bedrockModel) { _ in onBedrockDraftChange?(bedrockDraft) }
        .onChange(of: bedrockPortV6Text) { _ in
            if let p = Int(bedrockPortV6Text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                bedrockModel.serverPortV6 = p
            }
            onBedrockDraftChange?(bedrockDraft)
        }
    }

    // MARK: - Java settings form

    private var javaSettingsForm: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {

            SettingsSection(title: "World Settings", icon: "globe", fill: sectionFill) {
                SettingsRow(label: "Difficulty") {
                    Picker("", selection: $model.difficulty) {
                        ForEach(ServerDifficulty.allCases) { d in Text(d.displayName).tag(d) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                }
                SettingsRow(label: "Gamemode") {
                    Picker("", selection: $model.gamemode) {
                        ForEach(ServerGamemode.allCases) { gm in Text(gm.displayName).tag(gm) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320)
                }
                SettingsRow(label: "World Type") {
                    Picker("", selection: $model.levelType) {
                        ForEach(LevelType.allCases) { t in Text(t.displayName).tag(t) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }
                SettingsRow(label: "Force Gamemode") {
                    Toggle("", isOn: $model.forceGamemode)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                SettingsRow(label: "Hardcore") {
                    Toggle("", isOn: $model.hardcore)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                SettingsRow(label: "PvP") {
                    Toggle("", isOn: $model.pvp)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                SettingsRow(label: "Spawn Monsters") {
                    Toggle("", isOn: $model.spawnMonsters)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                SettingsRow(label: "Spawn Animals") {
                    Toggle("", isOn: $model.spawnAnimals)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                SettingsRow(label: "Spawn NPCs") {
                    Toggle("", isOn: $model.spawnNpcs)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                SettingsRow(label: "Allow Nether") {
                    Toggle("", isOn: $model.allowNether)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                SettingsRow(label: "Allow Flight") {
                    Toggle("", isOn: $model.allowFlight)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                SettingsRow(label: "Spawn Protection Radius") {
                    TextField("16", value: $model.spawnProtection, formatter: integerFormatter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                Text("Blocks around the world spawn point that non-ops cannot break. Set to 0 to disable.")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, MSC.Spacing.md)
                    .padding(.top, 2)
                    .padding(.bottom, MSC.Spacing.sm)
            }
            .contextualHelpAnchor("serverEditor.settings.java.world")

            SettingsSection(title: "Server Settings", icon: "text.alignleft", fill: sectionFill) {
                SettingsRow(label: "MOTD") {
                    TextField("Server MOTD", text: $model.motd)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                }
                SettingsRow(label: "Max Players") {
                    TextField("20", value: $model.maxPlayers, formatter: integerFormatter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                SettingsRow(label: "Online Mode") {
                    Toggle("", isOn: $model.onlineMode)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                SettingsRow(label: "View Distance") {
                    TextField("10", value: $model.viewDistance, formatter: integerFormatter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                SettingsRow(label: "Simulation Distance") {
                    TextField("10", value: $model.simulationDistance, formatter: integerFormatter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                SettingsRow(label: "Whitelist") {
                    Toggle("", isOn: $model.whitelist)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                SettingsRow(label: "Enforce Whitelist") {
                    Toggle("", isOn: $model.enforceWhitelist)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                SettingsRow(label: "Player Idle Timeout (min)") {
                    TextField("0", value: $model.playerIdleTimeout, formatter: integerFormatter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                Text("Minutes before an idle player is kicked. Set to 0 to disable.")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, MSC.Spacing.md)
                    .padding(.top, 2)
                    .padding(.bottom, MSC.Spacing.sm)
                SettingsRow(label: "Op Permission Level") {
                    Picker("", selection: $model.opPermissionLevel) {
                        Text("1 — Bypass spawn protection").tag(1)
                        Text("2 — Commands & command blocks").tag(2)
                        Text("3 — Manage players").tag(3)
                        Text("4 — All permissions").tag(4)
                    }
                    .labelsHidden()
                    .frame(maxWidth: 260)
                }
            }
            .contextualHelpAnchor("serverEditor.settings.java.server")

            SettingsSection(title: "Network", icon: "network", fill: sectionFill) {
                SettingsRow(label: "Server Port (TCP)") {
                    TextField("25565", value: $model.serverPort, formatter: integerFormatter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
                SettingsRow(label: "Bedrock / Geyser Port (UDP)") {
                    TextField("e.g. 19132", text: $bedrockPortText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
                Text("Changing ports may require updating your router / port forwarding.")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, MSC.Spacing.md)
                    .padding(.top, 2)
                    .padding(.bottom, MSC.Spacing.sm)
                SettingsRow(label: "Tunnel (playit.gg)") {
                    Toggle("", isOn: Binding(
                        get: { configServer.playitEnabled },
                        set: { viewModel.setPlayitEnabled($0, for: configServer.id) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
                if configServer.playitEnabled {
                    SettingsRow(label: "Voice Chat Tunnel") {
                        Toggle("", isOn: Binding(
                            get: { configServer.playitVoiceChatEnabled },
                            set: { viewModel.setPlayitEnabled(configServer.playitEnabled, voiceChat: $0, for: configServer.id) }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                    Text("Opens a second UDP tunnel on port 24454 for Simple Voice Chat. Requires the Simple Voice Chat plugin.")
                        .font(MSC.Typography.caption)
                        .foregroundStyle(MSC.Colors.caption)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, MSC.Spacing.md)
                        .padding(.top, 2)
                        .padding(.bottom, MSC.Spacing.sm)
                }
                playitDownloadRow
            }
            .contextualHelpAnchor("serverEditor.settings.java.network")

            if configServer.javaFlavor == .purpur, let cfg = purpurConfig {
                purpurSettingsSection(config: cfg)
            }
        }
    }

    @ViewBuilder
    private func purpurSettingsSection(config: PurpurConfig) -> some View {
        SettingsSection(title: "Purpur", icon: "dial.low", fill: sectionFill) {
            SettingsRow(label: "Creeper Grief Radius") {
                TextField("3", value: Binding(
                    get: { config.creeperGriefRadius },
                    set: { purpurConfig?.creeperGriefRadius = $0; onJavaDraftChange?(javaDraft) }
                ), formatter: integerFormatter)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
            }
            Text("Explosion radius for creepers. Set to 0 to prevent block damage. -1 uses the vanilla default.")
                .font(MSC.Typography.caption)
                .foregroundStyle(MSC.Colors.caption)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, MSC.Spacing.md)
                .padding(.top, 2)
                .padding(.bottom, MSC.Spacing.sm)
            SettingsRow(label: "Disable Ice & Snow") {
                Toggle("", isOn: Binding(
                    get: { config.disableIceAndSnow },
                    set: { purpurConfig?.disableIceAndSnow = $0; onJavaDraftChange?(javaDraft) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
            SettingsRow(label: "Disable Thunder") {
                Toggle("", isOn: Binding(
                    get: { config.disableThunder },
                    set: { purpurConfig?.disableThunder = $0; onJavaDraftChange?(javaDraft) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
            SettingsRow(label: "Tick Fluids") {
                Toggle("", isOn: Binding(
                    get: { config.tickFluids },
                    set: { purpurConfig?.tickFluids = $0; onJavaDraftChange?(javaDraft) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
            Text("Disabling fluid ticking stops lava and water from spreading. Useful for creative / build servers.")
                .font(MSC.Typography.caption)
                .foregroundStyle(MSC.Colors.caption)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, MSC.Spacing.md)
                .padding(.top, 2)
                .padding(.bottom, MSC.Spacing.sm)
        }
        .contextualHelpAnchor("serverEditor.settings.java.purpur")
    }

    // MARK: - Bedrock settings form

    private var bedrockSettingsForm: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {

            SettingsSection(title: "Runtime", icon: "memorychip", fill: sectionFill) {
                /* Docker Image row — hidden; VM backend downloads BDS directly
                SettingsRow(label: "Docker Image") {
                    Text(configServer.bedrockDockerImage ?? "itzg/minecraft-bedrock-server")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                */
                SettingsRow(label: "Pinned Version") {
                    if viewModel.isFetchingBedrockVersions {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Loading versions…").foregroundStyle(.secondary)
                                .font(MSC.Typography.caption)
                        }
                    } else {
                        Picker(
                            "",
                            selection: Binding(
                                get: { configServer.bedrockVersion ?? "LATEST" },
                                set: { viewModel.setBedrockVersion($0) }
                            )
                        ) {
                            Text("Latest (auto)").tag("LATEST")
                            ForEach(viewModel.bedrockAvailableVersions, id: \.self) { entry in
                                Text(entry.version).tag(entry.version)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 220)
                    }
                }
                SettingsRow(label: "Running Version") {
                    Text(viewModel.bedrockRunningVersion ?? "—")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text("Choose a pinned BDS version, or leave on Latest (auto) to follow the newest image.")
                                    .font(MSC.Typography.caption)
                                    .foregroundStyle(MSC.Colors.caption)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, MSC.Spacing.md)
                                    .padding(.top, 2)
                                    .padding(.bottom, MSC.Spacing.sm)
            }
            .contextualHelpAnchor("serverEditor.settings.bedrock.runtime")

            SettingsSection(title: "General", icon: "text.alignleft", fill: sectionFill) {
                SettingsRow(label: "Level Name") {
                    TextField("Bedrock level", text: $bedrockModel.levelName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                }
                SettingsRow(label: "Max Players") {
                    TextField("10", value: $bedrockModel.maxPlayers, formatter: integerFormatter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                SettingsRow(label: "Online Mode") {
                    Toggle("", isOn: $bedrockModel.onlineMode)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                SettingsRow(label: "Allow Cheats") {
                    Toggle("", isOn: $bedrockModel.allowCheats)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }
            .contextualHelpAnchor("serverEditor.settings.bedrock.general")

            SettingsSection(title: "Gameplay", icon: "gamecontroller", fill: sectionFill) {
                SettingsRow(label: "Difficulty") {
                    Picker("", selection: $bedrockModel.difficulty) {
                        ForEach(ServerDifficulty.allCases) { d in Text(d.displayName).tag(d) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                }
                SettingsRow(label: "Gamemode") {
                    Picker("", selection: $bedrockModel.gamemode) {
                        ForEach(ServerGamemode.allCases) { gm in Text(gm.displayName).tag(gm) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320)
                }
            }
            .contextualHelpAnchor("serverEditor.settings.bedrock.gameplay")

            SettingsSection(title: "Network", icon: "network", fill: sectionFill) {
                SettingsRow(label: "Server Port (UDP)") {
                    TextField("19132", value: $bedrockModel.serverPort, formatter: integerFormatter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
                SettingsRow(label: "IPv6 Port (UDP)") {
                    TextField("19133", text: $bedrockPortV6Text)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
                Text("Bedrock uses UDP. Forward these ports on your router for remote play.")
                                    .font(MSC.Typography.caption)
                                    .foregroundStyle(MSC.Colors.caption)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, MSC.Spacing.md)
                                    .padding(.top, 2)
                                    .padding(.bottom, MSC.Spacing.sm)
                SettingsRow(label: "Tunnel (playit.gg)") {
                    Toggle("", isOn: Binding(
                        get: { configServer.playitEnabled },
                        set: { viewModel.setPlayitEnabled($0, for: configServer.id) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
                playitDownloadRow
            }
            .contextualHelpAnchor("serverEditor.settings.bedrock.network")
        }
    }

    // MARK: - Draft accessors

    private var javaDraft: JavaServerSettingsDraft {
        JavaServerSettingsDraft(model: model, bedrockPortText: bedrockPortText, purpurConfig: purpurConfig)
    }

    private var bedrockDraft: BedrockServerSettingsDraft {
        BedrockServerSettingsDraft(model: bedrockModel, bedrockPortV6Text: bedrockPortV6Text)
    }

    // MARK: - playit.gg download row

    @ViewBuilder
    private var playitDownloadRow: some View {
        if configServer.playitEnabled {
            // Tunnel addresses — auto-detected from playit.gg API on each server start
            if let java = viewModel.playitJavaAddress {
                SettingsRow(label: "Java Tunnel") {
                    Text(java)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            if let bedrock = viewModel.playitBedrockAddress {
                SettingsRow(label: "Bedrock Tunnel") {
                    Text(bedrock)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            if viewModel.playitJavaAddress == nil && viewModel.playitBedrockAddress == nil {
                Text("Tunnel addresses are fetched automatically when the server starts.")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, MSC.Spacing.md)
                    .padding(.top, 2)
                    .padding(.bottom, MSC.Spacing.sm)
            }

            let hasKey = viewModel.playitSecretKey != nil
            SettingsRow(label: "Secret Key") {
                if hasKey {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(MSC.Colors.success)
                            .font(.system(size: 12))
                        Text("Configured")
                            .font(MSC.Typography.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Change") {
                            viewModel.isShowingPlayitSecretSetup = true
                        }
                        .buttonStyle(MSCSecondaryButtonStyle())
                        .controlSize(.small)
                        Button("Reset…") {
                            viewModel.resetPlayitSetup()
                        }
                        .buttonStyle(MSCSecondaryButtonStyle())
                        .controlSize(.small)
                        .help("Clears the local secret key, secret file, and tunnel addresses so setup starts fresh. Does not remove the agent/tunnels from your playit.gg account.")
                    }
                } else {
                    Button("Set up Secret Key…") {
                        viewModel.isShowingPlayitSecretSetup = true
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                    .controlSize(.small)
                }
            }
            if viewModel.isPlayitRunning {
                Text("Tunnel active. Public address shown in Overview.")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.success)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, MSC.Spacing.md)
                    .padding(.top, 2)
                    .padding(.bottom, MSC.Spacing.sm)
            } else {
                Text("Tunnel starts automatically with the server via the native playit agent. Requires a playit.gg secret key (free).")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, MSC.Spacing.md)
                    .padding(.top, 2)
                    .padding(.bottom, MSC.Spacing.sm)
            }
        }
    }

    // MARK: - Validation

    static func validatedJavaModel(from draft: JavaServerSettingsDraft) -> Result<ServerPropertiesModel, SettingsValidationError> {
        var model = draft.model
        if model.maxPlayers < 1 || model.maxPlayers > 1000 {
            return .failure(SettingsValidationError(message: "Max players must be between 1 and 1000."))
        }
        if model.viewDistance < 2 || model.viewDistance > 32 {
            return .failure(SettingsValidationError(message: "View distance must be between 2 and 32."))
        }
        if model.simulationDistance < 2 || model.simulationDistance > 32 {
            return .failure(SettingsValidationError(message: "Simulation distance must be between 2 and 32."))
        }
        if model.serverPort < 1 || model.serverPort > 65535 {
            return .failure(SettingsValidationError(message: "Server port must be between 1 and 65535."))
        }
        if model.opPermissionLevel < 1 || model.opPermissionLevel > 4 {
            return .failure(SettingsValidationError(message: "Op permission level must be between 1 and 4."))
        }
        let trimmedBedrock = draft.bedrockPortText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBedrock.isEmpty {
            model.bedrockPort = nil
        } else if let p = Int(trimmedBedrock) {
            if p < 1 || p > 65535 {
                return .failure(SettingsValidationError(message: "Bedrock/Geyser port must be between 1 and 65535."))
            }
            model.bedrockPort = p
        } else {
            return .failure(SettingsValidationError(message: "Bedrock/Geyser port must be a number (or blank)."))
        }
        return .success(model)
    }

    static func validatedBedrockModel(from draft: BedrockServerSettingsDraft) -> Result<BedrockPropertiesModel, SettingsValidationError> {
        var model = draft.model
        if model.maxPlayers < 1 || model.maxPlayers > 1000 {
            return .failure(SettingsValidationError(message: "Max players must be between 1 and 1000."))
        }
        if model.serverPort < 1 || model.serverPort > 65535 {
            return .failure(SettingsValidationError(message: "Server port must be between 1 and 65535."))
        }
        let trimmedV6 = draft.bedrockPortV6Text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let p = Int(trimmedV6) {
            if p < 1 || p > 65535 {
                return .failure(SettingsValidationError(message: "IPv6 port must be between 1 and 65535."))
            }
            model.serverPortV6 = p
        } else if !trimmedV6.isEmpty {
            return .failure(SettingsValidationError(message: "IPv6 port must be a number."))
        }
        return .success(model)
    }

    // MARK: - Error state

    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""

    private var integerFormatter: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .none
        return f
    }

    // MARK: - Save (sheet mode only)

    private func handleSave() {
        if configServer.isJava { saveJava() } else { saveBedrock() }
    }

    private func saveJava() {
        switch Self.validatedJavaModel(from: javaDraft) {
        case .success(let validatedModel):
            model = validatedModel
            do {
                try viewModel.saveServerPropertiesModel(validatedModel, for: configServer)
                if let purpur = purpurConfig {
                    try? viewModel.savePurpurConfig(purpur, for: configServer)
                }
                if !isInline { isPresented = false }
            } catch {
                errorMessage = "Failed to save server.properties: \(error.localizedDescription)"
                showErrorAlert = true
            }
        case .failure(let e):
            errorMessage = e.localizedDescription
            showErrorAlert = true
        }
    }

    private func saveBedrock() {
        switch Self.validatedBedrockModel(from: bedrockDraft) {
        case .success(let validatedModel):
            bedrockModel = validatedModel
            do {
                try viewModel.saveBedrockPropertiesModel(validatedModel, for: configServer)
                if !isInline { isPresented = false }
            } catch {
                errorMessage = "Failed to save server.properties: \(error.localizedDescription)"
                showErrorAlert = true
            }
        case .failure(let e):
            errorMessage = e.localizedDescription
            showErrorAlert = true
        }
    }
}

// MARK: - SettingsSection

/// A section card matching the Components tab visual style:
/// MSCOverline header with icon, Tier C card, rows separated by spacing only.
private struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    var fill: Color = MSC.Colors.cardBackground
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Section header — matches Components tab style
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MSC.Colors.tertiary)
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MSC.Colors.tertiary)
                    .tracking(0.6)
            }
            .padding(.horizontal, MSC.Spacing.md)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill.opacity(0.5))

                        // Rows container
                        VStack(alignment: .leading, spacing: 0) {
                            content()
                        }
                        .background(fill.opacity(0.75))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                            .stroke(MSC.Colors.cardBorder, lineWidth: 1)
                    )
}
}

// MARK: - SettingsRow

/// A single settings row — left label, right value, with a subtle top divider
/// (except the first row, handled via VStack spacing=0 and the row drawing its own divider).
private struct SettingsRow<Value: View>: View {
    let label: String
    @ViewBuilder let value: () -> Value

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.4)
            HStack {
                Text(label)
                    .font(MSC.Typography.body)
                    .foregroundStyle(.primary.opacity(0.8))
                Spacer()
                value()
            }
            .padding(.horizontal, MSC.Spacing.md)
            .padding(.vertical, 9)
        }
    }
}

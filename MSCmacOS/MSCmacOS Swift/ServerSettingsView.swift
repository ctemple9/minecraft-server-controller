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

    let isInline: Bool
    let onJavaDraftChange: ((JavaServerSettingsDraft) -> Void)?
    let onBedrockDraftChange: ((BedrockServerSettingsDraft) -> Void)?

    init(
        isPresented: Binding<Bool>,
        configServer: ConfigServer,
        initialModel: ServerPropertiesModel,
        initialBedrockModel: BedrockPropertiesModel = BedrockPropertiesModel(),
        initialBedrockPortText: String? = nil,
        initialBedrockPortV6Text: String? = nil,
        isInline: Bool = false,
        onJavaDraftChange: ((JavaServerSettingsDraft) -> Void)? = nil,
        onBedrockDraftChange: ((BedrockServerSettingsDraft) -> Void)? = nil
    ) {
        self._isPresented             = isPresented
        self.configServer             = configServer
        self._model                   = State(initialValue: initialModel)
        self._bedrockModel            = State(initialValue: initialBedrockModel)
        self._bedrockPortText         = State(initialValue: initialBedrockPortText ?? initialModel.bedrockPort.map(String.init) ?? "")
        self._bedrockPortV6Text       = State(initialValue: initialBedrockPortV6Text ?? String(initialBedrockModel.serverPortV6))
        self.isInline                 = isInline
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
        .onChange(of: model.motd)         { _ in onJavaDraftChange?(javaDraft) }
        .onChange(of: model.maxPlayers)   { _ in onJavaDraftChange?(javaDraft) }
        .onChange(of: model.viewDistance) { _ in onJavaDraftChange?(javaDraft) }
        .onChange(of: model.onlineMode)   { _ in onJavaDraftChange?(javaDraft) }
        .onChange(of: model.serverPort)   { _ in onJavaDraftChange?(javaDraft) }
        .onChange(of: model.difficulty)   { _ in onJavaDraftChange?(javaDraft) }
        .onChange(of: model.gamemode)     { _ in onJavaDraftChange?(javaDraft) }
        .onChange(of: bedrockPortText) { _ in
            let trimmed = bedrockPortText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { model.bedrockPort = nil }
            else if let p = Int(trimmed) { model.bedrockPort = p }
            onJavaDraftChange?(javaDraft)
        }
        .onChange(of: bedrockModel.levelName)   { _ in onBedrockDraftChange?(bedrockDraft) }
        .onChange(of: bedrockModel.maxPlayers)  { _ in onBedrockDraftChange?(bedrockDraft) }
        .onChange(of: bedrockModel.onlineMode)  { _ in onBedrockDraftChange?(bedrockDraft) }
        .onChange(of: bedrockModel.allowCheats) { _ in onBedrockDraftChange?(bedrockDraft) }
        .onChange(of: bedrockModel.difficulty)  { _ in onBedrockDraftChange?(bedrockDraft) }
        .onChange(of: bedrockModel.gamemode)    { _ in onBedrockDraftChange?(bedrockDraft) }
        .onChange(of: bedrockModel.serverPort)  { _ in onBedrockDraftChange?(bedrockDraft) }
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

            SettingsSection(title: "General", icon: "text.alignleft") {
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
            }
            .contextualHelpAnchor("serverEditor.settings.java.general")

            SettingsSection(title: "Gameplay", icon: "gamecontroller") {
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
                SettingsRow(label: "View Distance") {
                    TextField("10", value: $model.viewDistance, formatter: integerFormatter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
            }
            .contextualHelpAnchor("serverEditor.settings.java.gameplay")

            SettingsSection(title: "Network", icon: "network") {
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
            }
            .contextualHelpAnchor("serverEditor.settings.java.network")
        }
    }

    // MARK: - Bedrock settings form

    private var bedrockSettingsForm: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {

            SettingsSection(title: "Runtime", icon: "shippingbox") {
                SettingsRow(label: "Docker Image") {
                    Text(configServer.bedrockDockerImage ?? "itzg/minecraft-bedrock-server")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
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

            SettingsSection(title: "General", icon: "text.alignleft") {
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

            SettingsSection(title: "Gameplay", icon: "gamecontroller") {
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

            SettingsSection(title: "Network", icon: "network") {
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
            }
            .contextualHelpAnchor("serverEditor.settings.bedrock.network")
        }
    }

    // MARK: - Draft accessors

    private var javaDraft: JavaServerSettingsDraft {
        JavaServerSettingsDraft(model: model, bedrockPortText: bedrockPortText)
    }

    private var bedrockDraft: BedrockServerSettingsDraft {
        BedrockServerSettingsDraft(model: bedrockModel, bedrockPortV6Text: bedrockPortV6Text)
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
        if model.serverPort < 1 || model.serverPort > 65535 {
            return .failure(SettingsValidationError(message: "Server port must be between 1 and 65535."))
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
            .background(MSC.Colors.cardBackground.opacity(0.5))

                        // Rows container
                        VStack(alignment: .leading, spacing: 0) {
                            content()
                        }
                        .background(MSC.Colors.cardBackground.opacity(0.75))
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

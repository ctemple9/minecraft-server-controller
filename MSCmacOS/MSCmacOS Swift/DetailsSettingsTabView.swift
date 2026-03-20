//
//  DetailsSettingsTabView.swift
//  MinecraftServerController
//
//  Settings tab — embeds ServerSettingsView inline (no sheet).
//  Shows Java or Bedrock settings contextually based on selected server type.
//

import SwiftUI

struct DetailsSettingsTabView: View {
    @EnvironmentObject var viewModel: AppViewModel

    @Binding var isShowingPluginTemplates: Bool
    @Binding var isShowingPaperTemplate: Bool

    @State private var javaDraft: JavaServerSettingsDraft? = nil
    @State private var bedrockDraft: BedrockServerSettingsDraft? = nil
    @State private var hasUnsavedChanges = false
    @State private var isLoadingDrafts = false

    private var cfgServer: ConfigServer? {
        guard let s = viewModel.selectedServer else { return nil }
        return viewModel.configServer(for: s)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: MSC.Spacing.md) {

                if let cfg = cfgServer,
                   let currentJavaDraft = javaDraft,
                   let currentBedrockDraft = bedrockDraft {

                    // ── Header ────────────────────────────────────────────
                    HStack(alignment: .center) {
                        HStack(spacing: 6) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text("Server Properties")
                                .font(MSC.Typography.cardTitle)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        // Unsaved badge — animates in/out
                        if hasUnsavedChanges {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(.orange)
                                    .frame(width: 5, height: 5)
                                Text("Unsaved changes")
                                    .font(MSC.Typography.caption)
                                    .foregroundStyle(.orange)
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .trailing)))
                        }
                    }
                    .animation(.easeInOut(duration: 0.15), value: hasUnsavedChanges)

                    Text("Changes in this tab stay local until you click Save Changes.")
                        .font(MSC.Typography.caption)
                        .foregroundStyle(MSC.Colors.caption)

                    // ── Form ──────────────────────────────────────────────
                    ServerSettingsView(
                        isPresented: .constant(false),
                        configServer: cfg,
                        initialModel: currentJavaDraft.model,
                        initialBedrockModel: currentBedrockDraft.model,
                        initialBedrockPortText: currentJavaDraft.bedrockPortText,
                        initialBedrockPortV6Text: currentBedrockDraft.bedrockPortV6Text,
                        isInline: true,
                        onJavaDraftChange: { updatedDraft in
                            javaDraft = updatedDraft
                            markDraftEdited()
                        },
                        onBedrockDraftChange: { updatedDraft in
                            bedrockDraft = updatedDraft
                            markDraftEdited()
                        }
                    )

                    // ── Footer ────────────────────────────────────────────
                    HStack(spacing: MSC.Spacing.sm) {
                        Button("Revert") { loadModels() }
                            .buttonStyle(MSCSecondaryButtonStyle())
                            .disabled(!hasUnsavedChanges)

                        Spacer()

                        Button("Save Changes") { saveDrafts() }
                            .buttonStyle(MSCPrimaryButtonStyle())
                    }

                } else if cfgServer == nil {
                    Text("Select a server to view its settings.")
                        .font(MSC.Typography.caption)
                        .foregroundStyle(MSC.Colors.caption)
                        .frame(maxWidth: .infinity)
                        .padding(MSC.Spacing.xxl)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(MSC.Spacing.xxl)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, MSC.Spacing.md)
        }
        .onAppear { loadModels() }
        .onChange(of: viewModel.selectedServer) { _ in loadModels() }
    }

    private func markDraftEdited() {
        guard !isLoadingDrafts else { return }
        hasUnsavedChanges = true
    }

    private func loadModels() {
        guard let cfg = cfgServer else {
            javaDraft = nil
            bedrockDraft = nil
            hasUnsavedChanges = false
            return
        }

        isLoadingDrafts = true

        if cfg.isJava {
            let loadedJava = viewModel.loadServerPropertiesModel(for: cfg)
            javaDraft = JavaServerSettingsDraft(
                model: loadedJava,
                bedrockPortText: loadedJava.bedrockPort.map(String.init) ?? ""
            )

            let loadedBedrock = viewModel.bedrockPropertiesModel(for: cfg)
            bedrockDraft = BedrockServerSettingsDraft(
                model: loadedBedrock,
                bedrockPortV6Text: String(loadedBedrock.serverPortV6)
            )
        } else {
            let placeholderJava = ServerPropertiesModel(
                motd: cfg.displayName,
                maxPlayers: 20,
                difficulty: .normal,
                gamemode: .survival,
                viewDistance: 10,
                onlineMode: true,
                serverPort: 19132
            )
            javaDraft = JavaServerSettingsDraft(model: placeholderJava, bedrockPortText: "")

            let loadedBedrock = viewModel.bedrockPropertiesModel(for: cfg)
            bedrockDraft = BedrockServerSettingsDraft(
                model: loadedBedrock,
                bedrockPortV6Text: String(loadedBedrock.serverPortV6)
            )
        }

        hasUnsavedChanges = false
        isLoadingDrafts = false
    }

    private func saveDrafts() {
        guard let cfg = cfgServer,
              let javaDraft,
              let bedrockDraft else { return }

        if cfg.isJava {
            switch ServerSettingsView.validatedJavaModel(from: javaDraft) {
            case .success(let validatedModel):
                do {
                    try viewModel.saveServerPropertiesModel(validatedModel, for: cfg)
                    self.javaDraft = JavaServerSettingsDraft(
                        model: validatedModel,
                        bedrockPortText: validatedModel.bedrockPort.map(String.init) ?? ""
                    )
                    hasUnsavedChanges = false
                } catch {
                    viewModel.showError(title: "Settings Save Failed", message: "Could not write server.properties: \(error.localizedDescription)")
                }
            case .failure(let message):
                viewModel.showError(title: "Invalid Settings", message: message.localizedDescription)
            }
        } else {
            switch ServerSettingsView.validatedBedrockModel(from: bedrockDraft) {
            case .success(let validatedModel):
                do {
                    try viewModel.saveBedrockPropertiesModel(validatedModel, for: cfg)
                    self.bedrockDraft = BedrockServerSettingsDraft(
                        model: validatedModel,
                        bedrockPortV6Text: String(validatedModel.serverPortV6)
                    )
                    hasUnsavedChanges = false
                } catch {
                    viewModel.showError(title: "Settings Save Failed", message: "Could not write server.properties: \(error.localizedDescription)")
                }
            case .failure(let message):
                viewModel.showError(title: "Invalid Settings", message: message.localizedDescription)
            }
        }
    }
}

import SwiftUI

extension ServerEditorView {
// MARK: - SETTINGS TAB

var settingsTab: some View {
    VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
        if mode == .new || editingConfigServer == nil {
            SEUnavailableCard(
                icon: "slider.horizontal.3",
                title: "Save first to edit gameplay settings",
                message: "MOTD, max players, difficulty, online mode, and more are available after the server is created. Save, then reopen Edit Server."
            )
        } else if let cfg = editingConfigServer {
            // ── Server Properties ──────────────────────────────────────
            // ServerSettingsView renders its own section headers internally;
            // we drop the SESection wrapper and let it fill the content area directly.
            ServerSettingsView(
                isPresented: .constant(false),
                configServer: cfg,
                initialModel: javaSettingsDraft?.model ?? viewModel.loadServerPropertiesModel(for: cfg),
                initialBedrockModel: bedrockSettingsDraft?.model ?? viewModel.bedrockPropertiesModel(for: cfg),
                initialBedrockPortText: javaSettingsDraft?.bedrockPortText,
                initialBedrockPortV6Text: bedrockSettingsDraft?.bedrockPortV6Text,
                isInline: true,
                onJavaDraftChange: { updatedDraft in
                    javaSettingsDraft = updatedDraft
                },
                onBedrockDraftChange: { updatedDraft in
                    bedrockSettingsDraft = updatedDraft
                }
            )
            .contextualHelpAnchor(settingsGeneralAnchorID)

            // ── Notifications ──────────────────────────────────────────
            SEBlockHeader(title: "Notifications")
            SEBlock {
                SERow(label: "Server started") {
                    Toggle("", isOn: $notifOnStart)
                        .labelsHidden()
                        .onChange(of: notifOnStart) { _, _ in saveNotifPrefs(for: cfg) }
                }
                Divider().padding(.leading, MSC.Spacing.md - 1)
                SERow(label: "Server stopped") {
                    Toggle("", isOn: $notifOnStop)
                        .labelsHidden()
                        .onChange(of: notifOnStop) { _, _ in saveNotifPrefs(for: cfg) }
                }
                Divider().padding(.leading, MSC.Spacing.md - 1)
                SERow(label: "Player joined") {
                    Toggle("", isOn: $notifOnJoin)
                        .labelsHidden()
                        .onChange(of: notifOnJoin) { _, _ in saveNotifPrefs(for: cfg) }
                }
                Divider().padding(.leading, MSC.Spacing.md - 1)
                SERow(label: "Player left") {
                    Toggle("", isOn: $notifOnLeave)
                        .labelsHidden()
                        .onChange(of: notifOnLeave) { _, _ in saveNotifPrefs(for: cfg) }
                }
            }
            .contextualHelpAnchor(settingsNotificationsAnchorID)
        }
    }
}

}

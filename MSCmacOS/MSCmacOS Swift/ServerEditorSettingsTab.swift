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
            SESection(icon: "gearshape.fill", title: "Server Properties", color: .blue) {
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
            }

            SESection(icon: "bell.badge.fill", title: "Notifications", color: .orange) {
                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                    Text("Choose which events deliver a macOS notification for this server.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    notifToggleRow(label: "Server started", isOn: $notifOnStart) { _ in saveNotifPrefs(for: cfg) }
                    notifToggleRow(label: "Server stopped", isOn: $notifOnStop)  { _ in saveNotifPrefs(for: cfg) }
                    notifToggleRow(label: "Player joined",  isOn: $notifOnJoin)  { _ in saveNotifPrefs(for: cfg) }
                    notifToggleRow(label: "Player left",    isOn: $notifOnLeave) { _ in saveNotifPrefs(for: cfg) }
                }
            }
            .contextualHelpAnchor(settingsNotificationsAnchorID)
        }
    }
}

}

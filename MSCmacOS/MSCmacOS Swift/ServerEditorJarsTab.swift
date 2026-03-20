import SwiftUI

extension ServerEditorView {
// MARK: - JARS TAB (Java only)

var jarsTab: some View {
    VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
        if mode == .new || editingConfigServer == nil {
            SEUnavailableCard(
                icon: "shippingbox.fill",
                title: "Save first to manage JARs",
                message: "Configure Paper, Geyser, and Floodgate after this server has been created. Save, then reopen Edit Server."
            )
        } else if let cfg = editingConfigServer {
            let summary = viewModel.jarSummary(for: cfg)

            SESection(icon: "shippingbox.fill", title: "Paper & Cross-play JARs", color: .blue) {
                VStack(spacing: MSC.Spacing.md) {
                    SEJarRow(
                        icon: "server.rack",
                        color: .blue,
                        title: "Paper JAR",
                        filename: summary.paperFilename ?? "Not found",
                        isFound: summary.paperFilename != nil
                    ) {
                        Button("Update from Template") {
                            Task { await viewModel.updatePaperFromLatestTemplate(for: cfg) }
                        }
                        .buttonStyle(MSCSecondaryButtonStyle())
                        .disabled(!viewModel.hasPaperTemplates)
                    }

                    Divider().opacity(0.5)

                    SEJarRow(
                        icon: "puzzlepiece.fill",
                        color: .purple,
                        title: "Geyser Plugin",
                        filename: summary.geyserFilename ?? "Not found",
                        isFound: summary.geyserFilename != nil
                    ) {
                        Button("Update from Template") {
                            Task { await viewModel.updateGeyserFromTemplate(for: cfg) }
                        }
                        .buttonStyle(MSCSecondaryButtonStyle())
                        .disabled(!viewModel.hasPluginTemplates)
                    }

                    Divider().opacity(0.5)

                    SEJarRow(
                        icon: "person.badge.key.fill",
                        color: .orange,
                        title: "Floodgate Plugin",
                        filename: summary.floodgateFilename ?? "Not found",
                        isFound: summary.floodgateFilename != nil
                    ) {
                        Button("Update from Template") {
                            Task { await viewModel.updateFloodgateFromTemplate(for: cfg) }
                        }
                        .buttonStyle(MSCSecondaryButtonStyle())
                        .disabled(!viewModel.hasPluginTemplates)
                    }
                }
            }

            SECallout(
                icon: "info.circle.fill",
                color: .blue,
                text: "Update actions copy the latest template into this server's plugins/ folder, replacing older versions. Download templates in Preferences → JAR Library."
            )
        }
    }
}

}

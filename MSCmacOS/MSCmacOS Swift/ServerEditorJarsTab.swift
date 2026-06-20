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

            SECallout(
                icon: "info.circle.fill",
                color: .blue,
                text: "Update actions copy the latest template into this server's plugins/ folder, replacing older versions. Download templates in Preferences → JAR Library."
            )

            SEBlockHeader(title: "Installed JARs")
            SEBlock {
                SEJarRow(
                    icon: "server.rack",
                    color: .blue,
                    title: "Paper Server JAR",
                    filename: summary.paperFilename ?? "Not found",
                    isFound: summary.paperFilename != nil
                ) {
                    Button("Update") {
                        Task { await viewModel.updatePaperFromLatestTemplate(for: cfg) }
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                    .disabled(!viewModel.hasPaperTemplates)
                }
                .padding(.horizontal, MSC.Spacing.sm)
                .padding(.vertical, MSC.Spacing.xs)

                Divider().padding(.leading, MSC.Spacing.md)

                SEJarRow(
                    icon: "puzzlepiece.fill",
                    color: .purple,
                    title: "Geyser Plugin",
                    filename: summary.geyserFilename ?? "Not found",
                    isFound: summary.geyserFilename != nil
                ) {
                    Button("Update") {
                        Task { await viewModel.updateGeyserFromTemplate(for: cfg) }
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                    .disabled(!viewModel.hasPluginTemplates)
                }
                .padding(.horizontal, MSC.Spacing.sm)
                .padding(.vertical, MSC.Spacing.xs)

                Divider().padding(.leading, MSC.Spacing.md)

                SEJarRow(
                    icon: "person.badge.key.fill",
                    color: .orange,
                    title: "Floodgate Plugin",
                    filename: summary.floodgateFilename ?? "Not found",
                    isFound: summary.floodgateFilename != nil
                ) {
                    Button("Update") {
                        Task { await viewModel.updateFloodgateFromTemplate(for: cfg) }
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                    .disabled(!viewModel.hasPluginTemplates)
                }
                .padding(.horizontal, MSC.Spacing.sm)
                .padding(.vertical, MSC.Spacing.xs)
            }
        }
    }
}

}

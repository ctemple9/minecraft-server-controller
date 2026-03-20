import SwiftUI

extension ServerEditorView {
// MARK: - DOCKER TAB (Bedrock only)

var dockerTab: some View {
    VStack(alignment: .leading, spacing: MSC.Spacing.lg) {

        SECallout(
            icon: "shippingbox.fill",
            color: .blue,
            text: "This server runs via Docker. Container lifecycle (start, stop, logs) is managed from the main server detail view."
        )

        SESection(icon: "shippingbox.fill", title: "Docker Image", color: .blue) {
            VStack(alignment: .leading, spacing: MSC.Spacing.md) {
                if let cfg = editingConfigServer {
                    let imageTag = cfg.bedrockDockerImage ?? "itzg/minecraft-bedrock-server"
                    let version  = cfg.bedrockVersion ?? "LATEST"

                    SEInlineField(label: "Image", hint: nil) {
                        Text(imageTag)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    SEInlineField(label: "Version pin", hint: nil) {
                        Text(version)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Image details available after the server is saved.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                SECallout(
                    icon: "info.circle.fill",
                    color: .blue,
                    text: "To update the BDS version or pull a new image, use the Components tab in the main server detail view."
                )
            }
        }
    }
}

}

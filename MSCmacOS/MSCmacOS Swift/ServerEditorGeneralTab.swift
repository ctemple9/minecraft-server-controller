import SwiftUI

extension ServerEditorView {
// MARK: - GENERAL TAB

var generalTab: some View {
    VStack(alignment: .leading, spacing: MSC.Spacing.lg) {

        SESection(icon: "info.circle.fill", title: "Basics", color: .blue) {
            VStack(alignment: .leading, spacing: MSC.Spacing.md) {
                SEField(label: "Display Name", hint: "e.g. Friends SMP") {
                    TextField("Display Name", text: $data.displayName)
                        .textFieldStyle(.roundedBorder)
                }

                SEField(label: "Server Directory", hint: "Folder where server files are stored") {
                    HStack(spacing: MSC.Spacing.sm) {
                        TextField("Server directory path", text: $data.serverDir)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse…") { browseForServerDirectory() }
                            .buttonStyle(MSCSecondaryButtonStyle())
                    }
                }

                if data.serverType == .java, let cfg = editingConfigServer {
                    SEField(label: "Paper & Cross-play", hint: "Current status — manage in the JARs tab") {
                        let summary = viewModel.jarSummary(for: cfg)
                        HStack(spacing: MSC.Spacing.lg) {
                            SEStatusChip(
                                icon: "shippingbox.fill",
                                label: summary.paperFilename ?? "Not found",
                                color: summary.paperFilename != nil ? .blue : .red
                            )
                            SEStatusChip(
                                icon: "puzzlepiece.fill",
                                label: crossPlayLabel(for: cfg),
                                color: crossPlayLabelColor(for: cfg)
                            )
                        }
                    }
                }
            }
        }

        if data.serverType == .java {
            SESection(icon: "checkmark.seal.fill", title: "EULA", color: .orange) {
                ServerEditorEULASection(serverDir: data.serverDir)
            }

            SESection(icon: "memorychip.fill", title: "Memory", color: .green) {
                VStack(alignment: .leading, spacing: MSC.Spacing.md) {
                    SEInlineField(label: "Min RAM (GB)", hint: "-Xms") {
                        TextField("2", text: $data.minRamGB)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                    SEInlineField(label: "Max RAM (GB)", hint: "-Xmx") {
                        TextField("4", text: $data.maxRamGB)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                    SECallout(
                        icon: "lightbulb.fill",
                        color: .blue,
                        text: "2 GB min / 4 GB max is a solid starting point for a small friend server. Don't exceed ~60% of your Mac's total RAM."
                    )
                }
            }
        } else {
            SECallout(
                icon: "shippingbox.fill",
                color: .blue,
                text: "Memory is managed by Docker. Configure container resource limits in Docker Desktop if needed."
            )
        }

        SESection(icon: "note.text", title: "Notes", color: .secondary) {
            TextEditor(text: $data.notes)
                .frame(minHeight: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
                .font(.system(size: 12))
        }

        if mode == .edit, let _ = editingConfigServer {
            SESection(icon: "exclamationmark.octagon.fill", title: "Danger Zone", color: .red) {
                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                    Text("Permanently delete this server's folder from disk and remove it from the controller. This cannot be undone.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(role: .destructive) {
                        showDeleteServerConfirm = true
                    } label: {
                        HStack(spacing: MSC.Spacing.sm) {
                            Image(systemName: "trash.fill")
                            Text("Delete Server Folder from Disk…")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MSCDestructiveButtonStyle())
                }
            }
        }
    }
}

}

private struct ServerEditorEULASection: View {
    let serverDir: String

    @State private var eulaState: Bool?
    @State private var feedbackMessage: String?

    private var trimmedServerDir: String {
        serverDir.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {
            HStack(spacing: MSC.Spacing.lg) {
                SEStatusChip(
                    icon: eulaState == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    label: statusLabel,
                    color: eulaState == true ? .green : .orange
                )

                Spacer(minLength: 0)

                if eulaState == true {
                    Button("Accepted") {}
                        .buttonStyle(MSCSecondaryButtonStyle())
                        .disabled(true)
                } else {
                    Button("Accept EULA") {
                        acceptEULA()
                    }
                    .buttonStyle(MSCPrimaryButtonStyle())
                    .disabled(trimmedServerDir.isEmpty)
                }
            }

            Text(statusDescription)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let feedbackMessage {
                Text(feedbackMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: refreshEULAState)
        .onChange(of: serverDir) { _, _ in
            refreshEULAState()
        }
    }

    private var statusLabel: String {
        if trimmedServerDir.isEmpty {
            return "Set server directory first"
        }
        if eulaState == true {
            return "Accepted"
        }
        return "Needs acceptance"
    }

    private var statusDescription: String {
        if trimmedServerDir.isEmpty {
            return "Choose the server folder first so the controller knows where to read or write eula.txt."
        }
        if eulaState == true {
            return "This server already has eula=true in eula.txt. Overview still keeps its existing acceptance flow."
        }
        return "Use this to write eula=true into the selected server folder before first launch or after a fresh setup."
    }

    private func refreshEULAState() {
        feedbackMessage = nil
        guard !trimmedServerDir.isEmpty else {
            eulaState = nil
            return
        }
        eulaState = EULAManager.readEULA(in: trimmedServerDir)
    }

    private func acceptEULA() {
        feedbackMessage = nil
        guard !trimmedServerDir.isEmpty else { return }

        do {
            try EULAManager.writeAcceptedEULA(in: trimmedServerDir)
            eulaState = true
            feedbackMessage = "eula.txt updated successfully."
        } catch {
            feedbackMessage = "Could not update eula.txt: \(error.localizedDescription)"
            refreshEULAState()
        }
    }
}

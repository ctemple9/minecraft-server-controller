import SwiftUI

extension ServerEditorView {
// MARK: - GENERAL TAB

var generalTab: some View {
    VStack(alignment: .leading, spacing: MSC.Spacing.lg) {

        // ── Identity ──────────────────────────────────────────────────
        SEBlockHeader(title: "Identity")
        SEBlock {
            SERow(label: "Display Name", hint: "e.g. Friends SMP") {
                TextField("Display Name", text: $data.displayName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
            }
            Divider().padding(.leading, MSC.Spacing.md - 1)
            SERow(label: "Server Directory", hint: "Folder where server files live") {
                HStack(spacing: MSC.Spacing.sm) {
                    TextField("Server directory path", text: $data.serverDir)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                    Button("Browse…") { browseForServerDirectory() }
                        .buttonStyle(MSCSecondaryButtonStyle())
                }
            }
            if data.serverType == .java, let cfg = editingConfigServer {
                Divider().padding(.leading, MSC.Spacing.md - 1)
                SERow(label: "Paper & Cross-play", hint: "Manage in JARs tab") {
                    let summary = viewModel.jarSummary(for: cfg)
                    HStack(spacing: MSC.Spacing.sm) {
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

        // ── Memory ────────────────────────────────────────────────────
        SEBlockHeader(title: data.serverType == .java ? "Memory" : "Memory Limit")
        if data.serverType == .java {
            SEBlock {
                SERow(label: "Minimum RAM", hint: "-Xms Java flag") {
                    HStack(spacing: 4) {
                        TextField("2", text: $data.minRamGB)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 64)
                        Text("GB").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Divider().padding(.leading, MSC.Spacing.md - 1)
                SERow(label: "Maximum RAM", hint: "-Xmx Java flag") {
                    HStack(spacing: 4) {
                        TextField("4", text: $data.maxRamGB)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 64)
                        Text("GB").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            SEBlock {
                SERow(label: "Memory Limit", hint: "Docker --memory · 0 = no limit") {
                    HStack(spacing: 4) {
                        TextField("0", text: $data.maxRamGB)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 64)
                        Text("GB").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        SECallout(
            icon: "lightbulb.fill",
            color: .blue,
            text: data.serverType == .java
                ? "2 GB min / 4 GB max is a solid starting point for a small friend server. Don't exceed ~60% of your Mac's total RAM."
                : "Sets the Docker container memory limit. 0 = no limit (Docker default). 4–6 GB is typical for a Bedrock server."
        )

        // ── EULA (Java only) ─────────────────────────────────────────
        if data.serverType == .java {
            SEBlockHeader(title: "EULA")
            SEBlock {
                SERow(label: "Agreement", hint: "Minecraft End User License Agreement") {
                    ServerEditorEULASectionRow(serverDir: data.serverDir)
                }
            }
        }

        // ── Notes ─────────────────────────────────────────────────────
        SEBlockHeader(title: "Notes")
        SEBlock {
            TextEditor(text: $data.notes)
                .frame(minHeight: 72)
                .font(.system(size: 12))
                .padding(.horizontal, MSC.Spacing.md - 1)
                .padding(.vertical, MSC.Spacing.sm)
        }

        // ── Tools ─────────────────────────────────────────────────────
        SEBlockHeader(title: "Tools")
        SEBlock {
            SERow(label: "Headless Shell Script", hint: "Run server from Terminal without the app") {
                Button {
                    showHeadlessScriptSheet = true
                } label: {
                    Label("Generate…", systemImage: "doc.badge.gearshape")
                }
                .buttonStyle(MSCSecondaryButtonStyle())
                .disabled(data.serverDir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .sheet(isPresented: $showHeadlessScriptSheet) {
            if let cfg = editingConfigServer {
                HeadlessScriptSheet(config: cfg, isPresented: $showHeadlessScriptSheet)
                    .environmentObject(viewModel)
            }
        }

        // ── Danger Zone ───────────────────────────────────────────────
        if mode == .edit, let _ = editingConfigServer {
            HStack(spacing: MSC.Spacing.md) {
                Text("Permanently delete this server's folder from disk and remove it from the controller.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(role: .destructive) {
                    showDeleteServerConfirm = true
                } label: {
                    Label("Delete Server…", systemImage: "trash.fill")
                }
                .buttonStyle(MSCDestructiveButtonStyle())
            }
            .padding(.top, MSC.Spacing.xs)
        }
    }
}

}

// MARK: - Inline EULA row

private struct ServerEditorEULASectionRow: View {
    let serverDir: String

    @State private var eulaState: Bool?
    @State private var feedbackMessage: String?

    private var trimmed: String { serverDir.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        HStack(spacing: MSC.Spacing.sm) {
            SEStatusChip(
                icon: eulaState == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                label: chipLabel,
                color: eulaState == true ? .green : .orange
            )
            Spacer(minLength: 0)
            if eulaState == true {
                Button("Accepted") {}
                    .buttonStyle(MSCSecondaryButtonStyle())
                    .disabled(true)
            } else {
                Button("Accept EULA") { acceptEULA() }
                    .buttonStyle(MSCPrimaryButtonStyle())
                    .disabled(trimmed.isEmpty)
            }
        }
        .onAppear { refreshEULAState() }
        .onChange(of: serverDir) { _, _ in refreshEULAState() }
    }

    private var chipLabel: String {
        if trimmed.isEmpty { return "Set directory first" }
        return eulaState == true ? "Accepted" : "Needs acceptance"
    }

    private func refreshEULAState() {
        feedbackMessage = nil
        guard !trimmed.isEmpty else { eulaState = nil; return }
        eulaState = EULAManager.readEULA(in: trimmed)
    }

    private func acceptEULA() {
        guard !trimmed.isEmpty else { return }
        do {
            try EULAManager.writeAcceptedEULA(in: trimmed)
            eulaState = true
        } catch {
            eulaState = false
        }
    }
}

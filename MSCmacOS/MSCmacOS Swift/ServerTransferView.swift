//
//  ServerTransferView.swift
//  MinecraftServerController
//
//  Export sheet: description + Export… button.
//  Import sheet: choose file → review with editable ports + merge/replace → apply.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Panel helpers

private enum TransferPanels {
    static var packageContentType: UTType {
        UTType(filenameExtension: ServerTransfer.fileExtension) ?? .data
    }

    @MainActor
    static func savePanel(defaultName: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = [packageContentType]
        panel.allowsOtherFileTypes = true
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    static func openPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [packageContentType, .zip]
        panel.allowsOtherFileTypes = true
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func defaultExportName() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "MinecraftServers-\(f.string(from: Date())).\(ServerTransfer.fileExtension)"
    }
}

// MARK: - Export sheet

struct ServerTransferExportSheet: View {
    @ObservedObject var viewModel: AppViewModel
    let onClose: () -> Void

    @State private var isWorking = false
    @State private var resultMessage: String?
    @State private var resultIsError = false

    private var serverCount: Int { viewModel.configServers.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Export Servers to a Transfer File", systemImage: "square.and.arrow.up.on.square")
                .font(.title3).bold()

            Text("Bundles all \(serverCount) server\(serverCount == 1 ? "" : "s") — settings, all world slots, backups, plugins, resource packs, and config files — into a single file you can copy to another Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("App-level settings (Java path, Remote API, Xbox broadcast account) are not included — those stay per-Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let resultMessage {
                Text(resultMessage)
                    .font(.callout)
                    .foregroundStyle(resultIsError ? .red : .green)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if isWorking { ProgressView().scaleEffect(0.7) }
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button("Export\u{2026}") {
                    Task { await runExport() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isWorking || serverCount == 0)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func runExport() async {
        guard let dest = TransferPanels.savePanel(defaultName: TransferPanels.defaultExportName()) else { return }
        isWorking = true
        resultMessage = nil
        let result = await viewModel.exportServerTransfer(to: dest)
        isWorking = false
        switch result {
        case .success(let summary):
            resultIsError = false
            resultMessage = "Exported \(summary.serverCount) server\(summary.serverCount == 1 ? "" : "s") to \(summary.destination.lastPathComponent)."
        case .failure(let msg):
            resultIsError = true
            resultMessage = msg
        }
    }
}

// MARK: - Import sheet

struct ServerTransferImportSheet: View {
    @ObservedObject var viewModel: AppViewModel
    let onClose: () -> Void

    @State private var plan: TransferImportPlan?
    @State private var mode: TransferImportMode = .merge
    /// Editable port for each server, keyed by source server id.
    @State private var portEdits: [String: String] = [:]
    @State private var isWorking = false
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var showReplaceConfirm = false

    private var existingCount: Int { viewModel.configServers.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Import a Transfer File", systemImage: "square.and.arrow.down.on.square")
                .font(.title3).bold()

            if plan == nil {
                chooseFileView
            } else {
                reviewView
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.callout)
                    .foregroundStyle(statusIsError ? .red : .green)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 540)
        .confirmationDialog(
            "Replace all current servers?",
            isPresented: $showReplaceConfirm,
            titleVisibility: .visible
        ) {
            Button("Save Backup & Replace\u{2026}", role: .destructive) {
                Task { await runReplaceWithBackup() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the \(existingCount) server\(existingCount == 1 ? "" : "s") currently in MSC and imports the ones from the file. You'll first choose where to save a backup transfer file of your current servers so you can restore them later.")
        }
        .onDisappear { cleanupStaging() }
    }

    // MARK: Step 1 — choose file

    private var chooseFileView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a .\(ServerTransfer.fileExtension) file exported from another Mac.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                if isWorking { ProgressView().scaleEffect(0.7) }
                Spacer()
                Button("Close", action: onClose).keyboardShortcut(.cancelAction)
                Button("Choose File\u{2026}") { Task { await chooseAndInspect() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isWorking)
            }
        }
    }

    // MARK: Step 2 — review + port editing

    @ViewBuilder
    private var reviewView: some View {
        if let plan {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: "desktopcomputer")
                    Text("From \u{201C}\(plan.manifest.sourceMachineName)\u{201D}")
                    Spacer()
                    Text(formattedDate(plan.manifest.createdAt))
                        .foregroundStyle(.secondary)
                }
                .font(.caption)

                GroupBox("Servers in this file (\(plan.servers.count))") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(plan.servers) { row in
                                serverPortRow(row)
                                if row.id != plan.servers.last?.id {
                                    Divider().padding(.leading, 24)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 240)
                }

                Picker("Import mode", selection: $mode) {
                    Text("Merge — add to my servers").tag(TransferImportMode.merge)
                    Text("Replace — match the other Mac").tag(TransferImportMode.replaceAll)
                }
                .pickerStyle(.radioGroup)

                if mode == .replaceAll {
                    Label(
                        "Your current \(existingCount) server\(existingCount == 1 ? "" : "s") will be removed (a backup is saved first).",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption).foregroundStyle(.orange)
                }

                HStack {
                    if isWorking { ProgressView().scaleEffect(0.7) }
                    Spacer()
                    Button("Close", action: onClose).keyboardShortcut(.cancelAction)
                    Button("Import") { startImport() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isWorking)
                }
            }
        }
    }

    // MARK: Server row with editable port

    @ViewBuilder
    private func serverPortRow(_ row: TransferImportPlan.Row) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: row.entry.server.isJava ? "cup.and.saucer" : "cube")
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.displayName).font(.callout)
                if row.portConflict, let detail = row.conflictDetail {
                    Text(detail).font(.caption2).foregroundStyle(.orange)
                } else {
                    Text(row.serverTypeLabel)
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(row.entry.server.isJava ? "Java Port" : "Bedrock Port")
                    .font(.caption2).foregroundStyle(.secondary)
                TextField("Port", text: portBinding(for: row))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 72)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
    }

    private func portBinding(for row: TransferImportPlan.Row) -> Binding<String> {
        Binding(
            get: { portEdits[row.entry.server.id] ?? defaultPortString(for: row.entry) },
            set: { portEdits[row.entry.server.id] = $0 }
        )
    }

    private func defaultPortString(for entry: TransferServerEntry) -> String {
        if entry.server.isJava {
            return entry.javaPort.map { String($0) } ?? "25565"
        } else {
            return entry.server.bedrockPort.map { String($0) } ?? "19132"
        }
    }

    // MARK: Actions

    private func chooseAndInspect() async {
        guard let url = TransferPanels.openPanel() else { return }
        isWorking = true
        statusMessage = nil
        let result = await viewModel.inspectTransferPackage(at: url)
        isWorking = false
        switch result {
        case .success(let p):
            var edits: [String: String] = [:]
            for row in p.servers {
                edits[row.entry.server.id] = defaultPortString(for: row.entry)
            }
            portEdits = edits
            plan = p
        case .failure(let msg):
            statusIsError = true
            statusMessage = msg
        }
    }

    private func startImport() {
        if mode == .replaceAll {
            showReplaceConfirm = true
        } else {
            Task { await applyImport() }
        }
    }

    private func runReplaceWithBackup() async {
        guard let backupURL = TransferPanels.savePanel(
            defaultName: "MSC-Backup-Before-Replace-\(TransferPanels.defaultExportName())"
        ) else { return }
        isWorking = true
        statusMessage = nil
        let backup = await viewModel.exportServerTransfer(to: backupURL)
        if case .failure(let msg) = backup {
            isWorking = false
            statusIsError = true
            statusMessage = "Backup failed, nothing was changed: \(msg)"
            return
        }
        isWorking = false
        await applyImport()
    }

    private func applyImport() async {
        guard let p = plan else { return }
        isWorking = true
        statusMessage = nil

        // Only pass overrides that differ from the manifest value
        var javaPortOverrides: [String: Int] = [:]
        var bedrockPortOverrides: [String: Int] = [:]
        for row in p.servers {
            let id = row.entry.server.id
            guard let str = portEdits[id], let port = Int(str), port > 0, port <= 65535 else { continue }
            if row.entry.server.isJava {
                if port != row.entry.javaPort { javaPortOverrides[id] = port }
            } else {
                if port != row.entry.server.bedrockPort { bedrockPortOverrides[id] = port }
            }
        }

        let result = await viewModel.applyTransferImport(
            plan: p,
            mode: mode,
            javaPortOverrides: javaPortOverrides,
            bedrockPortOverrides: bedrockPortOverrides
        )
        isWorking = false
        switch result {
        case .success(let summary):
            statusIsError = false
            let skippedNote = summary.skipped > 0 ? ", \(summary.skipped) skipped" : ""
            let replacedNote = summary.replaced ? " (replaced existing set)" : ""
            statusMessage = "Imported \(summary.imported) server\(summary.imported == 1 ? "" : "s")\(skippedNote)\(replacedNote)."
            plan = nil
        case .failure(let msg):
            statusIsError = true
            statusMessage = msg
        }
    }

    private func cleanupStaging() {
        if let dir = plan?.stagingDir {
            try? FileManager.default.removeItem(at: dir)
            plan = nil
        }
    }

    private func formattedDate(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return "" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}

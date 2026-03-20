//
//  RenameWorldView.swift
//  MinecraftServerController
//

import SwiftUI
import Foundation

struct RenameWorldView: View {
    @EnvironmentObject var viewModel: AppViewModel

    @Binding var isPresented: Bool
    let configServer: ConfigServer

    @State private var currentLevelName: String = "world"
    @State private var currentWorldExists: Bool = false

    @State private var newLevelName: String = ""
    @State private var backupBeforeRename: Bool = true

    @State private var isRenaming: Bool = false
    @State private var statusMessage: String = ""

    private var isActiveAndRunning: Bool {
        viewModel.isServerRunning &&
        viewModel.configManager.config.activeServerId == configServer.id
    }

    private var canRename: Bool {
        let trimmed = newLevelName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !isRenaming &&
               !isActiveAndRunning &&
               !trimmed.isEmpty &&
               trimmed != currentLevelName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // HEADER
            HStack {
                Text("Rename World for \(configServer.displayName)")
                    .font(.title2)
                    .bold()
                Spacer()
                Button("Close") {
                    isPresented = false
                }
            }

            Divider()

            // CURRENT WORLD INFO
            VStack(alignment: .leading, spacing: 6) {
                Text("Current World")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 4) {
                    Text("level-name: \(currentLevelName)")
                        .font(.subheadline)

                    let status = currentWorldExists ? "found" : "missing"
                    Text("World folder: \(currentLevelName) (\(status))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .windowBackgroundColor))
                )
            }

            // NEW WORLD NAME
            VStack(alignment: .leading, spacing: 6) {
                Text("New World Name")
                    .font(.headline)

                TextField("New level-name (folder prefix)", text: $newLevelName)
                    .textFieldStyle(.roundedBorder)

                Text("This becomes `level-name` in server.properties and the base folder name for overworld/nether/end.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // BACKUP OPTION
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $backupBeforeRename) {
                    Text("Back up current world before renaming")
                }

                Text("Backup is stored under this server’s backups folder using the current level-name.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // STATUS / WARNINGS
            if isActiveAndRunning {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("Stop this server before renaming its world.")
                }
                .font(.caption)
                .foregroundStyle(.yellow)
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isRenaming {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Renaming world…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // FOOTER BUTTONS
            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                Button("Rename World") {
                    performRename()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canRename)
            }
        }
        .padding(18)
        .frame(minWidth: 520, minHeight: 380)
        .onAppear {
            loadCurrentWorldInfo()
        }
    }

    // MARK: - Load info

    private func loadCurrentWorldInfo() {
        let props = ServerPropertiesManager.readProperties(serverDir: configServer.serverDir)

        let level = (props["level-name"]?
            .trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 } ?? "world"

        currentLevelName = level

        if newLevelName.isEmpty {
            newLevelName = level
        }

        let fm = FileManager.default
        let serverDirURL = URL(fileURLWithPath: configServer.serverDir, isDirectory: true)
        let worldURL = serverDirURL.appendingPathComponent(level, isDirectory: true)

        var isDir: ObjCBool = false
        currentWorldExists = fm.fileExists(atPath: worldURL.path, isDirectory: &isDir) && isDir.boolValue
    }

    // MARK: - Actions

    private func performRename() {
        guard canRename else { return }

        let targetName = newLevelName.trimmingCharacters(in: .whitespacesAndNewlines)
        statusMessage = ""
        isRenaming = true

        Task {
            let success = await viewModel.renameWorld(
                for: configServer,
                newLevelName: targetName,
                backupFirst: backupBeforeRename
            )

            await MainActor.run {
                isRenaming = false
                if success {
                    isPresented = false
                } else {
                    statusMessage = "Failed to rename world. Check the console for details."
                }
            }
        }
    }
}


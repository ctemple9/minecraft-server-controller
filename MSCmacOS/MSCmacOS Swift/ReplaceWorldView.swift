//
//  ReplaceWorldView.swift
//  MinecraftServerController
//

import SwiftUI
import AppKit

struct ReplaceWorldView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Binding var isPresented: Bool

    let configServer: ConfigServer

    // Current world info
    @State private var currentLevelName: String = "world"
    @State private var worldFolderExists: Bool = false

    // New settings
    @State private var levelName: String = "world"
    @State private var worldSourceMode: WorldSourceMode = .fresh
    @State private var selectedBackupURL: URL?
    @State private var selectedWorldFolderURL: URL?
    @State private var backupFirst: Bool = true

    // Progress / state
    @State private var isWorking: Bool = false
    @State private var statusMessage: String = ""

    enum WorldSourceMode: String, CaseIterable, Identifiable {
        case fresh = "New world"
        case backupZip = "From backup (.zip)"
        case folder = "From existing world folder"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // HEADER
            HStack {
                Text("Replace World for \(configServer.displayName)")
                    .font(.title2).bold()
                Spacer()
                Button("Close") {
                    if !isWorking {
                        isPresented = false
                    }
                }
            }

            Divider()

            // SECTION 1 – Current world info
            VStack(alignment: .leading, spacing: 6) {
                Text("Current World")
                    .font(.headline)

                Text("level-name: \(currentLevelName)")
                    .font(.subheadline)

                if worldFolderExists {
                    Text("World folder: \(currentLevelName) (found)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("World folder: \(currentLevelName) (missing)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if viewModel.isServerRunning,
                   viewModel.configManager.config.activeServerId == configServer.id {
                    Text("Stop this server before replacing the world.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            // SECTION 2 – New world settings
            VStack(alignment: .leading, spacing: 6) {
                Text("New World Settings")
                    .font(.headline)

                TextField("level-name", text: $levelName)
                    .textFieldStyle(.roundedBorder)

                Text("This value becomes `level-name` in server.properties and the folder name for the overworld.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // SECTION 3 – World Source
            VStack(alignment: .leading, spacing: 6) {
                Text("World Source")
                    .font(.headline)

                Picker("World Source", selection: $worldSourceMode) {
                    ForEach(WorldSourceMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                switch worldSourceMode {
                case .fresh:
                    Text("Existing world folders will be removed. A new world will be generated on next server start.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                case .backupZip:
                    VStack(alignment: .leading, spacing: 4) {
                        Button("Choose backup zip…") {
                            chooseBackupZip()
                        }
                        if let url = selectedBackupURL {
                            Text("Selected: \(url.lastPathComponent)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text("No backup zip selected.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                case .folder:
                    VStack(alignment: .leading, spacing: 4) {
                        Button("Choose world folder…") {
                            chooseWorldFolder()
                        }
                        if let url = selectedWorldFolderURL {
                            Text("Selected: \(url.lastPathComponent)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text("No world folder selected.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // SECTION 4 – Optional backup
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $backupFirst) {
                    Text("Back up current world before replacing")
                }

                Text("Backup is stored under this server's backups folder, using the current level-name.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // STATUS
            if isWorking {
                HStack {
                    ProgressView()
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // FOOTER
            HStack {
                Spacer()
                Button("Cancel") {
                    if !isWorking {
                        isPresented = false
                    }
                }
                Button("Replace World") {
                    beginReplaceWorld()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canReplace)
            }
        }
        .padding(18)
        .frame(minWidth: 520, minHeight: 520)
        .onAppear {
            loadCurrentWorldInfo()
        }
    }

    // MARK: - Derived state

    private var canReplace: Bool {
        let trimmed = levelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        switch worldSourceMode {
        case .fresh:
            return true
        case .backupZip:
            return selectedBackupURL != nil
        case .folder:
            return selectedWorldFolderURL != nil
        }
    }

    // MARK: - Load current world info

    private func loadCurrentWorldInfo() {
        let serverDirURL = URL(fileURLWithPath: configServer.serverDir, isDirectory: true)
        let props = ServerPropertiesManager.readProperties(serverDir: serverDirURL.path)

        let level = (props["level-name"]?
            .trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 } ?? "world"

        currentLevelName = level
        levelName = level

        let fm = FileManager.default
        let worldDir = serverDirURL.appendingPathComponent(level, isDirectory: true)
        var isDir: ObjCBool = false
        worldFolderExists = fm.fileExists(atPath: worldDir.path, isDirectory: &isDir) && isDir.boolValue
    }

    // MARK: - Actions

    private func beginReplaceWorld() {
        guard canReplace else { return }
        guard !isWorking else { return }

        isWorking = true
        statusMessage = "Replacing world…"

        let trimmedLevel = levelName.trimmingCharacters(in: .whitespacesAndNewlines)

        // Build the world source enum for the view model.
        let worldSource: AppViewModel.WorldSource
        switch worldSourceMode {
        case .fresh:
            worldSource = .fresh

        case .backupZip:
            guard let url = selectedBackupURL else {
                isWorking = false
                statusMessage = "No backup selected."
                return
            }
            worldSource = .backupZip(url)

        case .folder:
            guard let url = selectedWorldFolderURL else {
                isWorking = false
                statusMessage = "No world folder selected."
                return
            }
            worldSource = .existingFolder(url)
        }

        Task {
            let success = await viewModel.replaceWorld(
                for: configServer,
                newLevelName: trimmedLevel,
                worldSource: worldSource,
                backupFirst: backupFirst
            )

            await MainActor.run {
                isWorking = false
                if success {
                    statusMessage = "World replaced."
                    isPresented = false
                } else {
                    statusMessage = "Failed to replace world. See console for details."
                }
            }
        }
    }

    // MARK: - NSOpenPanel helpers

    private func chooseBackupZip() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["zip"]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Choose Backup ZIP"

        if panel.runModal() == .OK {
            selectedBackupURL = panel.url
        }
    }

    private func chooseWorldFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.title = "Choose World Folder"

        if panel.runModal() == .OK {
            selectedWorldFolderURL = panel.url
        }
    }
}


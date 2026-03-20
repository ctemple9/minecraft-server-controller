//
//  CreateServerView.swift
//  MinecraftServerController
//
//  Server type is the first choice, with equal visual weight.
//  All subsequent fields are conditional on the selected type.
//

import SwiftUI
import AppKit

struct CreateServerView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Binding var isPresented: Bool

    // MARK: - Shared state

    @State private var serverName: String = ""
    @State private var serverType: ServerType = .java

    // World source (shared by both types)
    @State private var worldSourceMode: WorldSourceMode = .fresh
    @State private var selectedBackupURL: URL?
    @State private var selectedWorldFolderURL: URL?
    @State private var initialWorldName: String = ""
    @State private var initialWorldSeed: String = ""
    @State private var initialWorldDifficulty: ServerDifficulty = .normal
    @State private var initialWorldGamemode: ServerGamemode = .survival

    // Progress
    @State private var isCreating = false
    @State private var statusMessage = ""

    // MARK: - Java-specific state

    @State private var sourceMode: JarSourceMode = .downloadLatest
    @State private var selectedTemplateId: String?
    @State private var javaPort: String = "25565"
    @State private var enableCrossPlay: Bool = false
    @State private var crossPlayBedrockPort: String = "19132"
    @State private var isDownloadingCrossPlayJars = false
    @State private var crossPlayDownloadStatus: String? = nil

    // MARK: - Bedrock-specific state

    @State private var bedrockDockerImage: String = "itzg/minecraft-bedrock-server"
    @State private var bedrockVersion: String = "LATEST"
    @State private var bedrockPort: String = "19132"
    @State private var bedrockMaxPlayers: String = "10"

    // MARK: - Enums

    enum JarSourceMode: String, CaseIterable, Identifiable {
        case downloadLatest = "Download Latest Paper"
        case template = "Use Existing Template"
        var id: String { rawValue }
    }

    enum WorldSourceMode: String, CaseIterable, Identifiable {
        case fresh = "New world"
        case backupZip = "From backup (.zip)"
        case folder = "From existing world folder"
        var id: String { rawValue }
    }

    // MARK: - Helpers

    private var selectedTemplate: PaperTemplateItem? {
        guard let id = selectedTemplateId else { return nil }
        return viewModel.paperTemplateItems.first { $0.id == id }
    }

    private var initialWorldSlotName: String {
        let worldTrimmed = initialWorldName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !worldTrimmed.isEmpty { return worldTrimmed }

        let serverTrimmed = serverName.trimmingCharacters(in: .whitespacesAndNewlines)
        return serverTrimmed.isEmpty ? "World 1" : serverTrimmed
    }

    private var normalizedInitialWorldName: String? {
        guard worldSourceMode == .fresh else { return nil }
        let trimmed = initialWorldName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var normalizedInitialWorldSeed: String? {
        guard worldSourceMode == .fresh else { return nil }
        let trimmed = initialWorldSeed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
            MSCSheetHeader("Create New Server") {
                isPresented = false
            }

            ScrollView {
                VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
                    serverTypeSection

                    Divider()

                    serverNameSection

                    Divider()

                    VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
                        if serverType == .java {
                            javaSection
                        } else {
                            bedrockSection
                        }
                    }
                    .onboardingAnchor(.serverSettingsArea)

                    Divider()

                    worldSourceSection
                        .onboardingAnchor(.worldCreationArea)

                    Divider()

                    if isCreating {
                        HStack {
                            ProgressView()
                            Text(statusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(.bottom, MSC.Spacing.lg)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()

                Button("Create Server") {
                    beginCreateServer()
                }
                .buttonStyle(MSCPrimaryButtonStyle())
                .disabled(!canCreate || isCreating)
                .onboardingAnchor(.createSaveButton)
            }
        }
        .padding(MSC.Spacing.xl)
        .frame(minWidth: 480, minHeight: 660)
        .overlay {
            OnboardingOverlayView(
                ownedSteps: [.serverName, .serverType, .serverSettings, .firstWorld, .createButton]
            )
        }
        .onAppear {
            if OnboardingManager.shared.isActive,
               OnboardingManager.shared.currentStep == .createServer {
                OnboardingManager.shared.jumpTo(.serverName)
            }
        }
    }

    // MARK: - Section views

    private var serverTypeSection: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
            Text("Server Type")
                .font(MSC.Typography.sectionHeader)

            HStack(spacing: MSC.Spacing.md) {
                ServerTypeCard(
                    title: "Java",
                    subtitle: "PC · Cross-play",
                    systemImage: "cup.and.saucer.fill",
                    isSelected: serverType == .java
                ) {
                    serverType = .java
                    OnboardingManager.shared.tourServerType = .java
                }

                ServerTypeCard(
                    title: "Bedrock",
                    subtitle: "PC · Console · Mobile",
                    systemImage: "square.grid.3x3.fill",
                    isSelected: serverType == .bedrock
                ) {
                    serverType = .bedrock
                    OnboardingManager.shared.tourServerType = .bedrock
                }
            }
            .onboardingAnchor(.serverTypeSelector)
        }
    }

    private var serverNameSection: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
            Text("Server Name")
                .font(MSC.Typography.sectionHeader)

            TextField("Enter server name", text: $serverName)
                .textFieldStyle(.roundedBorder)
                .onboardingAnchor(.serverNameField)
        }
    }

    // MARK: - Java section

    private var javaSection: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                Text("Paper Source")
                    .font(MSC.Typography.sectionHeader)

                Picker("Paper Source", selection: $sourceMode) {
                    ForEach(JarSourceMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            if sourceMode == .template {
                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                    Text("Choose Template")
                        .font(.subheadline)

                    List(selection: $selectedTemplateId) {
                        if viewModel.paperTemplateItems.isEmpty {
                            Text("No templates found. Add some in the Templates menu.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(viewModel.paperTemplateItems) { item in
                                Text(item.filename).tag(item.id)
                            }
                        }
                    }
                    .frame(height: 140)
                    .onAppear { viewModel.loadPaperTemplates() }
                }
            }

            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                Text("Server Port")
                    .font(MSC.Typography.sectionHeader)

                TextField("25565", text: $javaPort)
                    .textFieldStyle(.roundedBorder)

                Text("Java uses TCP port 25565 by default. Change it here if you want this server to start on a different port.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                Toggle(isOn: $enableCrossPlay) {
                    Text("Enable Bedrock cross-play (Geyser + Floodgate)")
                }
                .toggleStyle(.switch)
                .onChange(of: enableCrossPlay) { _, enabled in
                    guard enabled else { crossPlayDownloadStatus = nil; return }
                    if !crossPlayJarsPresent() {
                        Task { await downloadCrossPlayJarsIfNeeded() }
                    }
                }

                if isDownloadingCrossPlayJars {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Downloading Geyser & Floodgate…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let status = crossPlayDownloadStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(status.contains("Failed") ? .red : .green)
                } else {
                    Text(crossPlayJarsPresent()
                         ? "Geyser & Floodgate found in your plugin templates folder."
                         : "Uses Geyser & Floodgate jars from your plugin templates folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if enableCrossPlay {
                    VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                        Text("Bedrock Port (Geyser)")
                            .font(MSC.Typography.sectionHeader)

                        TextField("19132", text: $crossPlayBedrockPort)
                            .textFieldStyle(.roundedBorder)

                        Text("The UDP port Bedrock clients will connect on. Must be forwarded on your router for external access.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, MSC.Spacing.sm)
                }
            }
        }
    }

    // MARK: - Bedrock section

    private var bedrockSection: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                Text("Docker Image")
                    .font(MSC.Typography.sectionHeader)

                TextField("Docker image", text: $bedrockDockerImage)
                    .textFieldStyle(.roundedBorder)

                Text("Default: itzg/minecraft-bedrock-server. Change only if you use a custom image.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                Text("Bedrock Version")
                    .font(MSC.Typography.sectionHeader)

                TextField("e.g. LATEST or 1.21.0.3", text: $bedrockVersion)
                    .textFieldStyle(.roundedBorder)

                Text("Use LATEST to always pull the newest stable release.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                Text("Server Port")
                    .font(MSC.Typography.sectionHeader)

                TextField("19132", text: $bedrockPort)
                    .textFieldStyle(.roundedBorder)

                Text("Bedrock uses UDP port 19132 (not TCP). Set your router to forward UDP when enabling external access.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                Text("Max Players")
                    .font(MSC.Typography.sectionHeader)
                TextField("10", text: $bedrockMaxPlayers)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 160)
            }
        }
    }

    // MARK: - World source section

    private var worldSourceSection: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {
            Text("World Source")
                .font(MSC.Typography.sectionHeader)

            Picker("World Source", selection: $worldSourceMode) {
                ForEach(WorldSourceMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            switch worldSourceMode {
            case .fresh:
                Text("A brand-new world will be generated on first start, and the first persistent world slot will be created immediately for this server.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .backupZip:
                VStack(alignment: .leading, spacing: 4) {
                    Button("Choose backup zip…") { chooseBackupZip() }

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
                    Button("Choose world folder…") { chooseWorldFolder() }

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

            if worldSourceMode == .fresh {
                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                    Text("Initial World Settings")
                        .font(MSC.Typography.sectionHeader)

                    VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                        Text("World Name")
                            .font(.subheadline)
                        TextField("Defaults to server name", text: $initialWorldName)
                            .textFieldStyle(.roundedBorder)
                        Text("This names the first world slot and world identity. The server name stays separate, and you can add more worlds later in the Worlds tab.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(alignment: .top, spacing: MSC.Spacing.lg) {
                        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                            Text("Difficulty")
                                .font(.subheadline)
                            Picker("Difficulty", selection: $initialWorldDifficulty) {
                                ForEach(ServerDifficulty.allCases) { difficulty in
                                    Text(difficulty.displayName).tag(difficulty)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                            Text("Game Mode")
                                .font(.subheadline)
                            Picker("Game Mode", selection: $initialWorldGamemode) {
                                ForEach(ServerGamemode.allCases.filter { $0 != .spectator }) { gamemode in
                                    Text(gamemode.displayName).tag(gamemode)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                        Text("Seed")
                            .font(.subheadline)
                        TextField("Optional seed", text: $initialWorldSeed)
                            .textFieldStyle(.roundedBorder)
                        Text("The seed is only used when generating a fresh world for the first time. Imported worlds keep their existing terrain.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("The first persistent world slot will be created automatically as: \(initialWorldSlotName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onboardingAnchor(.worldSourceArea)
    }

    // MARK: - Validation

    private var canCreate: Bool {
        guard !serverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        if serverType == .java {
            if sourceMode == .template && selectedTemplate == nil { return false }
            if Int(javaPort) == nil { return false }
        } else {
            if bedrockDockerImage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
            if Int(bedrockPort) == nil { return false }
        }

        switch worldSourceMode {
        case .fresh:
            break
        case .backupZip:
            if selectedBackupURL == nil { return false }
        case .folder:
            if selectedWorldFolderURL == nil { return false }
        }

        return true
    }

    // MARK: - Create action

    private func beginCreateServer() {
        guard canCreate else { return }
        isCreating = true

        let name = serverName.trimmingCharacters(in: .whitespacesAndNewlines)

        let worldSource: AppViewModel.WorldSource
        switch worldSourceMode {
        case .fresh:
            worldSource = .fresh
        case .backupZip:
            guard let url = selectedBackupURL else {
                isCreating = false
                statusMessage = "No backup selected."
                return
            }
            worldSource = .backupZip(url)
        case .folder:
            guard let url = selectedWorldFolderURL else {
                isCreating = false
                statusMessage = "No world folder selected."
                return
            }
            worldSource = .existingFolder(url)
        }

        if serverType == .java {
            statusMessage = sourceMode == .downloadLatest
                ? "Downloading latest Paper and creating server…"
                : "Creating server…"

            let jarSource: CreateServerJarSource
            if sourceMode == .template, let item = selectedTemplate {
                jarSource = .template(item.url)
            } else {
                jarSource = .downloadLatest
            }

            let port = Int(javaPort) ?? 25565

            Task {
                let success = await viewModel.createNewServer(
                    name: name,
                    initialWorldName: normalizedInitialWorldName,
                    jarSource: jarSource,
                    port: port,
                    enableCrossPlay: enableCrossPlay,
                    crossPlayBedrockPort: enableCrossPlay ? (Int(crossPlayBedrockPort) ?? 19132) : nil,
                    difficulty: initialWorldDifficulty.rawValue,
                    gamemode: initialWorldGamemode.rawValue,
                    worldSeed: normalizedInitialWorldSeed,
                    worldSource: worldSource
                )
                await MainActor.run {
                    finishCreation(success)
                }
            }
        } else {
            statusMessage = "Creating Bedrock server…"

            let image = bedrockDockerImage.trimmingCharacters(in: .whitespacesAndNewlines)
            let version = bedrockVersion.trimmingCharacters(in: .whitespacesAndNewlines)
            let port = Int(bedrockPort) ?? 19132
            let maxPlayers = Int(bedrockMaxPlayers) ?? 10

            Task {
                let success = await viewModel.createNewBedrockServer(
                    name: name,
                    initialWorldName: normalizedInitialWorldName,
                    dockerImage: image,
                    bedrockVersion: version.isEmpty ? "LATEST" : version,
                    port: port,
                    maxPlayers: maxPlayers,
                    difficulty: initialWorldDifficulty.rawValue,
                    gamemode: initialWorldGamemode.rawValue,
                    worldSeed: normalizedInitialWorldSeed,
                    worldSource: worldSource
                )
                await MainActor.run {
                    finishCreation(success)
                }
            }
        }
    }

    // MARK: - Cross-play jar helpers

    private func crossPlayJarsPresent() -> Bool {
        let fm = FileManager.default
        let dir = viewModel.configManager.pluginTemplateDirURL
        guard let files = try? fm.contentsOfDirectory(atPath: dir.path) else { return false }
        let jars = files.filter { $0.lowercased().hasSuffix(".jar") }
        let hasGeyser = jars.contains { $0.lowercased().contains("geyser") }
        let hasFloodgate = jars.contains { $0.lowercased().contains("floodgate") }
        return hasGeyser && hasFloodgate
    }

    @MainActor
    private func downloadCrossPlayJarsIfNeeded() async {
        guard !crossPlayJarsPresent() else { return }
        isDownloadingCrossPlayJars = true
        crossPlayDownloadStatus = nil
        await viewModel.downloadLatestGeyserTemplate()
        await viewModel.downloadLatestFloodgateTemplate()
        isDownloadingCrossPlayJars = false
        if crossPlayJarsPresent() {
            crossPlayDownloadStatus = "✓ Geyser & Floodgate downloaded successfully."
        } else {
            crossPlayDownloadStatus = "Failed to download — check your internet connection."
        }
    }

    private func finishCreation(_ success: Bool) {
        isCreating = false
        if success {
            statusMessage = "Server created."
            isPresented = false
        } else {
            statusMessage = "Failed to create server."
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

// MARK: - ServerTypeCard

private struct ServerTypeCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: MSC.Spacing.sm) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(isSelected ? MSC.Colors.accent : .secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(MSC.Typography.sectionHeader)
                        .foregroundStyle(isSelected ? MSC.Colors.accent : .primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(MSC.Colors.accent)
                }
            }
            .padding(MSC.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.md)
                    .fill(
                        isSelected
                        ? MSC.Colors.accent.opacity(0.08)
                        : Color(NSColor.controlBackgroundColor)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: MSC.Radius.md)
                    .stroke(
                        isSelected ? MSC.Colors.accent : Color(NSColor.separatorColor),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

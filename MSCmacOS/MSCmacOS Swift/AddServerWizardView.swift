//
//  AddServerWizardView.swift
//  MinecraftServerController
//
//  Four-step wizard unifying "Import Existing" and "Start Fresh" into a single
//  entry point. Opened from the single "Add Server…" button in ManageServersView.
//
//  Import path:  Step 1 (choose) → Step 2 (drop/browse) → Step 3 (review + world) → Step 4 (name + confirm)
//  Fresh path:   Step 1 (choose) → Step 2 (type + config) → Step 3 (world source) → Step 4 (name + confirm)
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers
// MARK: - Wizard path

enum AddServerWizardPath {
    case importExisting
    case fresh
}

// MARK: - Main view

struct AddServerWizardView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Binding var isPresented: Bool

    // MARK: Navigation
    @State private var currentStep: Int = 1
    @State private var wizardPath: AddServerWizardPath = .importExisting

    // MARK: Import path
        @State private var sourceURL: URL?           = nil
        @State private var isSourceZip: Bool         = false
        @State private var scannedInfo: ScannedServerInfo? = nil
        @State private var isScanning: Bool          = false
        @State private var scanError: String?        = nil
        @State private var selectedWorldName: String? = nil

        // Editable overrides for the review step (pre-populated from scan)
        @State private var importPort: String        = ""
        @State private var importMaxPlayers: String  = ""
        @State private var importEulaAccepted: Bool  = false

    // MARK: Fresh path — shared
    @State private var serverName: String        = ""
    @State private var serverType: ServerType    = .java

    // Fresh — Java
    @State private var javaPort: String          = "25565"
    @State private var enableCrossPlay: Bool     = false
    @State private var crossPlayBedrockPort: String = "19132"
    @State private var isDownloadingCrossPlay: Bool = false
    @State private var crossPlayDownloadStatus: String? = nil
    @State private var jarSourceMode: FreshJarSourceMode = .downloadLatest
    @State private var selectedTemplateId: String? = nil

    // Fresh — Bedrock
    @State private var bedrockDockerImage: String = "itzg/minecraft-bedrock-server"
    @State private var bedrockVersion: String    = "LATEST"
    @State private var bedrockPort: String       = "19132"
    @State private var bedrockMaxPlayers: String = "10"

    // Fresh — world
    @State private var worldSourceMode: FreshWorldSourceMode = .fresh
    @State private var selectedBackupURL: URL?   = nil
    @State private var selectedWorldFolderURL: URL? = nil
    @State private var initialWorldName: String  = ""
    @State private var initialWorldSeed: String  = ""
    @State private var initialWorldDifficulty: ServerDifficulty = .normal
    @State private var initialWorldGamemode: ServerGamemode = .survival

    // MARK: Shared / creation
    @State private var displayName: String       = ""
    @State private var isCreating: Bool          = false
    @State private var statusMessage: String     = ""

    // MARK: Enums

    enum FreshJarSourceMode: String, CaseIterable, Identifiable {
        case downloadLatest = "Download Latest Paper"
        case template       = "Use Existing Template"
        var id: String { rawValue }
    }

    enum FreshWorldSourceMode: String, CaseIterable, Identifiable {
        case fresh      = "New world"
        case backupZip  = "From backup (.zip)"
        case folder     = "From existing world folder"
        var id: String { rawValue }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {

            MSCSheetHeader("Add Server") { isPresented = false }
                .padding(.horizontal, MSC.Spacing.xl)
                .padding(.top, MSC.Spacing.xl)

            stepIndicator
                .padding(.horizontal, MSC.Spacing.xl)
                .padding(.vertical, MSC.Spacing.lg)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    stepContent
                        .padding(MSC.Spacing.xl)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            footerBar
        }
        .frame(minWidth: 640, minHeight: 520)
    }

    // MARK: - Step indicator

    private var stepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(1...4, id: \.self) { step in
                stepItemView(step: step)
                if step < 4 {
                    Rectangle()
                        .fill(step < currentStep
                              ? Color.green.opacity(0.5)
                              : Color.secondary.opacity(0.18))
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 8)
                }
            }
        }
    }

    private func stepItemView(step: Int) -> some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(stepDotFill(step))
                    .frame(width: 22, height: 22)
                if step < currentStep {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.green)
                } else {
                    Text("\(step)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(step == currentStep ? .primary : MSC.Colors.caption)
                }
            }
            Text(stepLabel(step))
                .font(.system(size: 11, weight: step == currentStep ? .semibold : .regular))
                .foregroundStyle(step <= currentStep ? .primary : MSC.Colors.caption)
                .fixedSize()
        }
    }

    private func stepDotFill(_ step: Int) -> Color {
        if step < currentStep  { return Color.green.opacity(0.15) }
        if step == currentStep { return Color.accentColor.opacity(0.15) }
        return Color.secondary.opacity(0.08)
    }

    private func stepLabel(_ step: Int) -> String {
        if wizardPath == .fresh && currentStep > 1 {
            switch step {
            case 1: return "Choose path"
            case 2: return "Configure"
            case 3: return "World"
            case 4: return "Confirm"
            default: return ""
            }
        }
        switch step {
        case 1: return "Choose path"
        case 2: return "Upload"
        case 3: return "Review"
        case 4: return "Confirm"
        default: return ""
        }
    }

    // MARK: - Step content router

    @ViewBuilder
    private var stepContent: some View {
        if currentStep == 1 {
            step1PathPicker
        } else if currentStep == 2 && wizardPath == .importExisting {
            step2ImportUpload
        } else if currentStep == 2 && wizardPath == .fresh {
            step2FreshConfigure
        } else if currentStep == 3 && wizardPath == .importExisting {
            step3ImportReview
        } else if currentStep == 3 && wizardPath == .fresh {
            step3FreshWorld
        } else {
            step4Confirm
        }
    }

    // MARK: - Step 1: Path picker

    private var step1PathPicker: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.xl) {
            VStack(alignment: .leading, spacing: 4) {
                Text("How do you want to add this server?")
                    .font(MSC.Typography.pageTitle)
                Text("Import a server you already have, or start a brand new one from scratch.")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.caption)
            }

            HStack(spacing: MSC.Spacing.md) {
                WizardPathCard(
                    title: "Import Existing",
                    subtitle: "Drop a folder or .zip — MSC reads and configures it for you.",
                    systemImage: "arrow.down.to.line.compact",
                    isSelected: wizardPath == .importExisting
                ) { wizardPath = .importExisting }

                WizardPathCard(
                    title: "Start Fresh",
                    subtitle: "MSC downloads and sets up a brand new server from scratch.",
                    systemImage: "sparkles",
                    isSelected: wizardPath == .fresh
                ) { wizardPath = .fresh }
            }
        }
    }

    // MARK: - Step 2 (Import): Drop zone

    private var step2ImportUpload: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Drop your server folder or archive")
                    .font(MSC.Typography.pageTitle)
                Text("MSC will scan it and read what it can find — nothing is copied until you confirm on the last step.")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.caption)
            }

            if isScanning {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Scanning server folder…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)

            } else if let error = scanError {
                VStack(spacing: MSC.Spacing.md) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try Again") {
                        sourceURL = nil
                        scanError = nil
                        scannedInfo = nil
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)

            } else {
                dropZone
            }
        }
    }

    @State private var dropTargeted: Bool = false

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: MSC.Radius.lg, style: .continuous)
                .fill(dropTargeted
                      ? Color.accentColor.opacity(0.06)
                      : Color.secondary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: MSC.Radius.lg, style: .continuous)
                        .stroke(
                            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                        )
                        .foregroundStyle(
                            dropTargeted
                            ? Color.accentColor.opacity(0.6)
                            : Color.secondary.opacity(0.25)
                        )
                )

            VStack(spacing: MSC.Spacing.md) {
                Image(systemName: "arrow.up.to.line.compact")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(dropTargeted ? Color.accentColor : .secondary)

                VStack(spacing: 6) {
                    Text("Drop server folder or archive here")
                        .font(.system(size: 14, weight: .medium))
                    Text("or")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Browse…") { browseForServerFolder() }
                        .buttonStyle(MSCSecondaryButtonStyle())
                }

                HStack(spacing: 8) {
                    ForEach(["Folder", ".zip", ".tar.gz"], id: \.self) { label in
                        Text(label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(MSC.Colors.caption)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.secondary.opacity(0.1))
                            )
                    }
                }
            }
            .padding(.vertical, 56)
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard let provider = providers.first else { return false }
            provider.loadDataRepresentation(forTypeIdentifier: "public.file-url") { data, _ in
                guard let data = data,
                      let path = String(data: data, encoding: .utf8),
                      let url  = URL(string: path)
                else { return }
                let cleaned = url.standardizedFileURL
                let zip     = cleaned.pathExtension.lowercased() == "zip"
                Task { @MainActor in
                    sourceURL   = cleaned
                    isSourceZip = zip
                    await performScan(cleaned, isZip: zip)
                }
            }
            return true
        }
    }

    // MARK: - Step 3 (Import): Review + world selection

        @ViewBuilder
        private var step3ImportReview: some View {
            if let info = scannedInfo {
                VStack(alignment: .leading, spacing: MSC.Spacing.xl) {

                    // Editable server settings
                    VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                        Text("SERVER SETTINGS")
                            .font(MSC.Typography.sectionHeader)

                        VStack(spacing: 0) {
                            // Server type — read only, cannot change after detection
                            editInfoRow(key: "Server type") {
                                Text(info.serverType.displayName)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }

                            editInfoRow(key: "Port") {
                                TextField("25565", text: $importPort)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 90)
                                    .font(.system(size: 12))
                            }

                            editInfoRow(key: "Max players") {
                                TextField("20", text: $importMaxPlayers)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 90)
                                    .font(.system(size: 12))
                            }

                            editInfoRow(key: "Accept EULA") {
                                Toggle("", isOn: $importEulaAccepted)
                                    .toggleStyle(.switch)
                                    .labelsHidden()
                            }
                        }
                        .pscCard(padding: MSC.Spacing.sm)

                        if !importEulaAccepted {
                            Text("The EULA must be accepted before the server can start. You can accept it now or do it later in the server editor.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }

                    // World picker
                    VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                        Text("SELECT ACTIVE WORLD")
                            .font(MSC.Typography.sectionHeader)

                        if info.worlds.isEmpty {
                            Text("No worlds were detected in this server folder. A world will be generated on first start.")
                                .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(info.worlds) { world in
                                worldRow(world)
                            }
                        }
                    }
                }
            }
        } else {
            EmptyView()
        }
    }

    private func worldRow(_ world: DetectedWorld) -> some View {
        let isSelected = selectedWorldName == world.name
        return Button {
            selectedWorldName = world.name
        } label: {
            HStack(spacing: MSC.Spacing.md) {
                // Radio button
                ZStack {
                    Circle()
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.secondary.opacity(0.4),
                            lineWidth: 1.5
                        )
                        .frame(width: 16, height: 16)
                    if isSelected {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 8, height: 8)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(world.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(world.dimensionsLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(world.formattedSize)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(MSC.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                    .fill(isSelected
                          ? Color.accentColor.opacity(0.08)
                          : Color.secondary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.45) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 2 (Fresh): Configure

    private var step2FreshConfigure: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.lg) {

            // Server type
            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                Text("Server Type")
                    .font(MSC.Typography.sectionHeader)
                HStack(spacing: MSC.Spacing.md) {
                    WizardServerTypeCard(
                        title: "Java",
                        subtitle: "PC · Cross-play optional",
                        systemImage: "cup.and.saucer.fill",
                        isSelected: serverType == .java
                    ) { serverType = .java }

                    WizardServerTypeCard(
                        title: "Bedrock",
                        subtitle: "PC · Console · Mobile",
                        systemImage: "square.grid.3x3.fill",
                        isSelected: serverType == .bedrock
                    ) { serverType = .bedrock }
                }
            }

            Divider()

            // Server name
            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                Text("Server Name")
                    .font(MSC.Typography.sectionHeader)
                TextField("Enter server name", text: $serverName)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            if serverType == .java {
                javaFreshSection
            } else {
                bedrockFreshSection
            }
        }
    }

    private var javaFreshSection: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                Text("Paper Source")
                    .font(MSC.Typography.sectionHeader)
                Picker("Paper Source", selection: $jarSourceMode) {
                    ForEach(FreshJarSourceMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
            }

            if jarSourceMode == .template {
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
                    .frame(height: 110)
                    .onAppear { viewModel.loadPaperTemplates() }
                }
            }

            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                Text("Server Port")
                    .font(MSC.Typography.sectionHeader)
                TextField("25565", text: $javaPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 120)
            }

            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                Toggle("Enable Bedrock cross-play (Geyser + Floodgate)", isOn: $enableCrossPlay)
                    .toggleStyle(.switch)
                    .onChange(of: enableCrossPlay) { _, enabled in
                        if enabled && !crossPlayJarsPresent() {
                            Task { await downloadCrossPlayIfNeeded() }
                        } else if !enabled {
                            crossPlayDownloadStatus = nil
                        }
                    }

                if isDownloadingCrossPlay {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Downloading Geyser & Floodgate…")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else if let status = crossPlayDownloadStatus {
                    Text(status).font(.caption)
                        .foregroundStyle(status.contains("Failed") ? .red : .green)
                }

                if enableCrossPlay {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Bedrock Port (Geyser)")
                                .font(MSC.Typography.sectionHeader)
                            TextField("19132", text: $crossPlayBedrockPort)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 120)
                        }
                    }
                    .padding(.top, MSC.Spacing.xs)
                }
            }
        }
    }

    private var bedrockFreshSection: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                Text("Docker Image")
                    .font(MSC.Typography.sectionHeader)
                TextField("itzg/minecraft-bedrock-server", text: $bedrockDockerImage)
                    .textFieldStyle(.roundedBorder)
                Text("Change only if you use a custom Bedrock image.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                Text("Bedrock Version")
                    .font(MSC.Typography.sectionHeader)
                TextField("LATEST", text: $bedrockVersion)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
            }

            HStack(spacing: MSC.Spacing.xl) {
                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                    Text("Port")
                        .font(MSC.Typography.sectionHeader)
                    TextField("19132", text: $bedrockPort)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 120)
                }
                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                    Text("Max Players")
                        .font(MSC.Typography.sectionHeader)
                    TextField("10", text: $bedrockMaxPlayers)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 120)
                }
            }
        }
    }

    // MARK: - Step 3 (Fresh): World source

    private var step3FreshWorld: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
            Text("World Source")
                .font(MSC.Typography.sectionHeader)

            Picker("World Source", selection: $worldSourceMode) {
                ForEach(FreshWorldSourceMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            switch worldSourceMode {
            case .fresh:
                freshWorldSettings

            case .backupZip:
                VStack(alignment: .leading, spacing: 6) {
                    Button("Choose backup .zip…") { chooseBackupZip() }
                        .buttonStyle(MSCSecondaryButtonStyle())
                    if let url = selectedBackupURL {
                        Text(url.lastPathComponent)
                            .font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    } else {
                        Text("No file selected.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }

            case .folder:
                VStack(alignment: .leading, spacing: 6) {
                    Button("Choose world folder…") { chooseWorldFolder() }
                        .buttonStyle(MSCSecondaryButtonStyle())
                    if let url = selectedWorldFolderURL {
                        Text(url.lastPathComponent)
                            .font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    } else {
                        Text("No folder selected.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var freshWorldSettings: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {
            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                Text("World Name")
                    .font(MSC.Typography.sectionHeader)
                TextField("Defaults to server name", text: $initialWorldName)
                    .textFieldStyle(.roundedBorder)
                Text("This names the first world slot. You can add more worlds later in the Worlds tab.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: MSC.Spacing.xl) {
                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                    Text("Difficulty")
                        .font(MSC.Typography.sectionHeader)
                    Picker("Difficulty", selection: $initialWorldDifficulty) {
                        ForEach(ServerDifficulty.allCases) { d in Text(d.displayName).tag(d) }
                    }
                    .pickerStyle(.menu).labelsHidden()
                }
                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                    Text("Game Mode")
                        .font(MSC.Typography.sectionHeader)
                    Picker("Game Mode", selection: $initialWorldGamemode) {
                        ForEach(ServerGamemode.allCases.filter { $0 != .spectator }) { g in
                            Text(g.displayName).tag(g)
                        }
                    }
                    .pickerStyle(.menu).labelsHidden()
                }
            }

            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                Text("Seed")
                    .font(MSC.Typography.sectionHeader)
                TextField("Optional", text: $initialWorldSeed)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
            }
        }
    }

    // MARK: - Step 4: Confirm

    private var step4Confirm: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Name and confirm")
                    .font(MSC.Typography.pageTitle)
                Text("Review the summary below, then give your server a display name.")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.caption)
            }

            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                Text("Display Name")
                    .font(MSC.Typography.sectionHeader)
                TextField("Server display name", text: $displayName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                Text("SUMMARY")
                    .font(MSC.Typography.sectionHeader)
                VStack(spacing: 0) {
                    if wizardPath == .importExisting, let info = scannedInfo {
                        infoRow(key: "Method",       value: "Import existing")
                        infoRow(key: "Server type",  value: info.serverType.displayName)
                        infoRow(key: "Port",         value: importPort.isEmpty ? "\(info.port)" : importPort)
                                                infoRow(key: "Max players",  value: importMaxPlayers.isEmpty ? "\(info.maxPlayers)" : importMaxPlayers)
                        infoRow(key: "Active world",
                                value: selectedWorldName ?? info.defaultWorldName ?? "—")
                        if !info.worlds.isEmpty && info.worlds.count > 1 {
                            let others = info.worlds
                                .filter { $0.name != (selectedWorldName ?? info.defaultWorldName) }
                                .map(\.name)
                                .joined(separator: ", ")
                            if !others.isEmpty {
                                infoRow(key: "Other worlds", value: others)
                            }
                        }
                        if !info.eulaAccepted {
                            infoRow(key: "EULA", value: "Not yet accepted — accept before starting",
                                    valueColor: .orange)
                        }
                    } else {
                        infoRow(key: "Method",       value: "Start fresh")
                        infoRow(key: "Server type",  value: serverType.displayName)
                        infoRow(key: "Port",
                                value: serverType == .java ? javaPort : bedrockPort)
                        infoRow(key: "World source",  value: worldSourceMode.rawValue)
                        if worldSourceMode == .fresh {
                            let wName = initialWorldName.trimmingCharacters(in: .whitespacesAndNewlines)
                            let displayedName = wName.isEmpty ? serverName : wName
                            infoRow(key: "World name", value: displayedName)
                        }
                    }
                }
                .pscCard(padding: MSC.Spacing.sm)
            }

            if isCreating {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(statusMessage.isEmpty ? "Working…" : statusMessage)
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(
                        statusMessage.lowercased().contains("fail") ||
                        statusMessage.lowercased().contains("error")
                        ? Color.red : Color.secondary
                    )
            }
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: MSC.Spacing.sm) {
                if currentStep > 1 {
                    Button("Back") {
                        withAnimation(.easeInOut(duration: 0.18)) { currentStep -= 1 }
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                    .disabled(isCreating || isScanning)
                }

                Spacer()

                if currentStep == 4 {
                    Button("Create Server") { beginCreate() }
                        .buttonStyle(MSCPrimaryButtonStyle())
                        .disabled(!canCreate || isCreating)
                } else {
                    Button("Continue") { advanceStep() }
                        .buttonStyle(MSCPrimaryButtonStyle())
                        .disabled(!canAdvance || isScanning)
                }
            }
            .padding(.horizontal, MSC.Spacing.xl)
            .padding(.vertical, MSC.Spacing.lg)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Navigation

    private var canAdvance: Bool {
        switch currentStep {
        case 1:
            return true
        case 2:
            if wizardPath == .importExisting {
                return scannedInfo != nil && !isScanning && scanError == nil
            } else {
                let nameOk = !serverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if serverType == .java {
                    return nameOk
                        && Int(javaPort) != nil
                        && (jarSourceMode != .template || selectedTemplateId != nil)
                } else {
                    return nameOk
                        && !bedrockDockerImage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && Int(bedrockPort) != nil
                }
            }
        case 3:
            if wizardPath == .importExisting { return true }
            switch worldSourceMode {
            case .fresh:     return true
            case .backupZip: return selectedBackupURL != nil
            case .folder:    return selectedWorldFolderURL != nil
            }
        default:
            return false
        }
    }

    private var canCreate: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isCreating
    }

    private func advanceStep() {
        // Pre-fill display name before reaching step 4
        if currentStep == 2 && wizardPath == .importExisting {
            if displayName.isEmpty, let url = sourceURL {
                displayName = url.deletingPathExtension().lastPathComponent
                    .replacingOccurrences(of: "_", with: " ")
            }
            if selectedWorldName == nil {
                selectedWorldName = scannedInfo?.defaultWorldName
            }
        }
        if currentStep == 3 && wizardPath == .fresh && displayName.isEmpty {
            displayName = serverName
        }
        withAnimation(.easeInOut(duration: 0.18)) { currentStep += 1 }
    }

    // MARK: - Create

    private func beginCreate() {
        guard canCreate else { return }
        isCreating = true
        statusMessage = ""

        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        if wizardPath == .importExisting {
            guard let url = sourceURL, let info = scannedInfo else {
                statusMessage = "Missing source file."; isCreating = false; return
            }
            Task {
                let result = await viewModel.importExistingServer(
                                    sourceURL: url,
                                    isZip: isSourceZip,
                                    displayName: name,
                                    serverType: info.serverType,
                                    activeWorldName: selectedWorldName ?? info.defaultWorldName,
                                    portOverride: Int(importPort) ?? info.port,
                                    maxPlayersOverride: Int(importMaxPlayers) ?? info.maxPlayers,
                                    eulaOverride: importEulaAccepted
                                )
                await MainActor.run {
                    isCreating = false
                    switch result {
                    case .success:     isPresented = false
                    case .failure(let msg): statusMessage = "Error: \(msg)"
                    }
                }
            }

        } else {
            // Fresh server — pass to existing VM functions
            let worldSource: AppViewModel.WorldSource
            switch worldSourceMode {
            case .fresh:
                worldSource = .fresh
            case .backupZip:
                guard let url = selectedBackupURL else {
                    statusMessage = "No backup file selected."; isCreating = false; return
                }
                worldSource = .backupZip(url)
            case .folder:
                guard let url = selectedWorldFolderURL else {
                    statusMessage = "No world folder selected."; isCreating = false; return
                }
                worldSource = .existingFolder(url)
            }

            let worldName = initialWorldName.trimmingCharacters(in: .whitespacesAndNewlines)
            let worldNameOpt = worldName.isEmpty ? nil : worldName
            let seedRaw = initialWorldSeed.trimmingCharacters(in: .whitespacesAndNewlines)
            let seedOpt = seedRaw.isEmpty ? nil : seedRaw

            if serverType == .java {
                statusMessage = jarSourceMode == .downloadLatest
                    ? "Downloading latest Paper and creating server…"
                    : "Creating server…"

                let jarSource: CreateServerJarSource
                if jarSourceMode == .template,
                   let id = selectedTemplateId,
                   let item = viewModel.paperTemplateItems.first(where: { $0.id == id }) {
                    jarSource = .template(item.url)
                } else {
                    jarSource = .downloadLatest
                }

                let port        = Int(javaPort) ?? 25565
                let crossPort   = enableCrossPlay ? (Int(crossPlayBedrockPort) ?? 19132) : nil

                Task {
                    let ok = await viewModel.createNewServer(
                        name: name,
                        initialWorldName: worldNameOpt,
                        jarSource: jarSource,
                        port: port,
                        enableCrossPlay: enableCrossPlay,
                        crossPlayBedrockPort: crossPort,
                        difficulty: initialWorldDifficulty.rawValue,
                        gamemode: initialWorldGamemode.rawValue,
                        worldSeed: seedOpt,
                        worldSource: worldSource
                    )
                    await MainActor.run {
                        isCreating = false
                        if ok { isPresented = false }
                        else  { statusMessage = "Failed to create server." }
                    }
                }

            } else {
                statusMessage = "Creating Bedrock server…"
                let image   = bedrockDockerImage.trimmingCharacters(in: .whitespacesAndNewlines)
                let version = bedrockVersion.trimmingCharacters(in: .whitespacesAndNewlines)
                let port    = Int(bedrockPort) ?? 19132
                let maxP    = Int(bedrockMaxPlayers) ?? 10

                Task {
                    let ok = await viewModel.createNewBedrockServer(
                        name: name,
                        initialWorldName: worldNameOpt,
                        dockerImage: image,
                        bedrockVersion: version.isEmpty ? "LATEST" : version,
                        port: port,
                        maxPlayers: maxP,
                        difficulty: initialWorldDifficulty.rawValue,
                        gamemode: initialWorldGamemode.rawValue,
                        worldSeed: seedOpt,
                        worldSource: worldSource
                    )
                    await MainActor.run {
                        isCreating = false
                        if ok { isPresented = false }
                        else  { statusMessage = "Failed to create Bedrock server." }
                    }
                }
            }
        }
    }

    // MARK: - Scanning

    private func performScan(_ url: URL, isZip: Bool) async {
        await MainActor.run {
            isScanning  = true
            scanError   = nil
            scannedInfo = nil
        }

        var scanDir = url
        var tempDir: URL? = nil

        if isZip {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("msc_wizardscan_\(UUID().uuidString)", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            } catch {
                await MainActor.run {
                    isScanning = false
                    scanError  = "Could not create temp directory: \(error.localizedDescription)"
                }
                return
            }

            let exitCode: Int32 = await Task.detached(priority: .userInitiated) {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                p.arguments = ["-q", url.path, "-d", tmp.path]
                do { try p.run(); p.waitUntilExit() } catch { return -1 }
                return p.terminationStatus
            }.value

            guard exitCode == 0 else {
                try? FileManager.default.removeItem(at: tmp)
                await MainActor.run {
                    isScanning = false
                    scanError  = "Could not read archive (exit \(exitCode)). Make sure it is a valid .zip file."
                }
                return
            }

            tempDir = tmp
            scanDir = tmp
        }

        // Unwrap single-root zip
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: scanDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) {
            let subdirs = contents.filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            }
            let files = contents.filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == false
            }
            if subdirs.count == 1 && files.isEmpty {
                scanDir = subdirs[0]
            }
        }

        let info = viewModel.scanServerDirectory(scanDir)

        // Clean up temp dir — we have all info we need
        if let tmp = tempDir { try? FileManager.default.removeItem(at: tmp) }

        await MainActor.run {
                    isScanning           = false
                    scannedInfo          = info
                    selectedWorldName    = info.defaultWorldName
                    importPort           = "\(info.port)"
                    importMaxPlayers     = "\(info.maxPlayers)"
                    importEulaAccepted   = info.eulaAccepted
                    // Auto-advance to review step
                    withAnimation(.easeInOut(duration: 0.18)) { currentStep = 3 }
                }
    }

    // MARK: - NSOpenPanel helpers

    private func browseForServerFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles       = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes     = ["zip", ""]
        panel.title                = "Choose Server Folder or .zip Archive"
        panel.message              = "Select a server folder or .zip archive to import into MSC."
        if panel.runModal() == .OK, let url = panel.url {
            let zip = url.pathExtension.lowercased() == "zip"
            sourceURL   = url
            isSourceZip = zip
            Task { await performScan(url, isZip: zip) }
        }
    }

    private func chooseBackupZip() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["zip"]
        panel.canChooseFiles   = true
        panel.canChooseDirectories = false
        panel.title = "Choose Backup ZIP"
        if panel.runModal() == .OK { selectedBackupURL = panel.url }
    }

    private func chooseWorldFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles       = false
        panel.title = "Choose World Folder"
        if panel.runModal() == .OK { selectedWorldFolderURL = panel.url }
    }

    // MARK: - Cross-play helpers

    private func crossPlayJarsPresent() -> Bool {
        let dir = viewModel.configManager.pluginTemplateDirURL
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return false }
        let jars = files.filter { $0.lowercased().hasSuffix(".jar") }
        return jars.contains { $0.lowercased().contains("geyser") }
            && jars.contains { $0.lowercased().contains("floodgate") }
    }

    @MainActor
    private func downloadCrossPlayIfNeeded() async {
        guard !crossPlayJarsPresent() else { return }
        isDownloadingCrossPlay     = true
        crossPlayDownloadStatus    = nil
        await viewModel.downloadLatestGeyserTemplate()
        await viewModel.downloadLatestFloodgateTemplate()
        isDownloadingCrossPlay     = false
        crossPlayDownloadStatus    = crossPlayJarsPresent()
            ? "✓ Geyser & Floodgate downloaded successfully."
            : "Failed to download — check your internet connection."
    }

    // MARK: - Shared info row

    @ViewBuilder
        private func editInfoRow<Content: View>(key: String, @ViewBuilder content: () -> Content) -> some View {
            HStack {
                Text(key)
                    .font(.system(size: 12))
                    .foregroundStyle(MSC.Colors.caption)
                Spacer()
                content()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, MSC.Spacing.sm)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.07))
                    .frame(height: 0.5)
            }
        }

        private func infoRow(key: String, value: String, valueColor: Color? = nil) -> some View {
        HStack {
            Text(key)
                .font(.system(size: 12))
                .foregroundStyle(MSC.Colors.caption)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(valueColor ?? .primary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, MSC.Spacing.sm)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.secondary.opacity(0.07))
                .frame(height: 0.5)
        }
    }
}

// MARK: - WizardPathCard

private struct WizardPathCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(MSC.Typography.sectionHeader)
                        .foregroundStyle(isSelected ? Color.accentColor : .primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(MSC.Spacing.lg)
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                    .fill(isSelected
                          ? Color.accentColor.opacity(0.08)
                          : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor : Color(NSColor.separatorColor),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - WizardServerTypeCard

private struct WizardServerTypeCard: View {
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
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(MSC.Typography.sectionHeader)
                        .foregroundStyle(isSelected ? Color.accentColor : .primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(MSC.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                    .fill(isSelected
                          ? Color.accentColor.opacity(0.08)
                          : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor : Color(NSColor.separatorColor),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

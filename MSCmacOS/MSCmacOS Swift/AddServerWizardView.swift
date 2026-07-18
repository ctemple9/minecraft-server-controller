//
//  AddServerWizardView.swift
//  MinecraftServerController
//
//  Five-step wizard unifying "Import Existing" and "Start Fresh" into a single
//  entry point. Opened from the single "Add Server…" button in ManageServersView.
//
//  Import path:  Step 1 (choose) → Step 2 (drop/browse) → Step 3 (review) → Step 4 (network) → Step 5 (confirm)
//  Fresh path:   Step 1 (choose) → Step 2 (type + config) → Step 3 (network) → Step 4 (world) → Step 5 (confirm)
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Staged add-on types

enum WizardStagedSource {
    case modrinthDownload(hit: ModrinthSearchHit, version: ModrinthVersionInfo)
    case localJar(url: URL)
    case remoteJar(url: URL, filename: String)
    case mrpackFile(url: URL)
    case curseForgeFile(url: URL)
    case zipFolder(url: URL)
}

struct WizardStagedAddOn: Identifiable {
    let id = UUID()
    let name: String
    let filename: String
    let source: WizardStagedSource
}

// MARK: - Wizard path

enum AddServerWizardPath {
    case importExisting
    case fresh
}

// MARK: - Import kind

enum ImportKind {
    case undetermined, existingServer, modpack
}

// MARK: - Main view

struct AddServerWizardView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Binding var isPresented: Bool

    // MARK: Navigation
    @State private var currentStep: Int = 1
    @State private var wizardPath: AddServerWizardPath = .importExisting
    @State private var importKind: ImportKind = .undetermined

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
    @State private var enableXboxBroadcast: Bool = false
    @State private var xboxBroadcastDownloadStatus: String? = nil
    @State private var jarSourceMode: FreshJarSourceMode = .downloadLatest
    @State private var selectedTemplateId: String? = nil

    // Version picker
    @State private var selectedVersionEntry: ServerVersionEntry? = nil
    @State private var isShowingVersionPicker = false
    @State private var availableVersions: [ServerVersionEntry] = []
    @State private var isLoadingVersions = false
    /// One-shot: when a staged .mrpack sets the flavor from pack metadata, the
    /// `selectedFlavor` onChange would normally clear the pinned version. This flag
    /// lets that single programmatic flavor change through without wiping the pin.
    @State private var preserveVersionOnNextFlavorChange = false

    // Staged add-ons
    @State private var stagedAddOns: [WizardStagedAddOn] = []
    @State private var isShowingAddOnBrowser = false

    // Fresh — Java server software (M1: category + flavor selection)
    @State private var selectedCategory: JavaServerCategory = .standard
    @State private var selectedFlavor: JavaServerFlavor = .paper

    /// Flavors whose provisioning is implemented today. Grows as M2–M4 land
    /// (M2: Standard forks · M3: Fabric · M4: NeoForge). Others show "Soon".
    private let implementedFlavors: Set<JavaServerFlavor> = [.paper, .purpur, .vanilla, .fabric, .neoforge, .forge]

    /// Cross-play is unavailable for Modded (Bedrock can't load Java mods) and
    /// for Vanilla (no plugin API to host Geyser).
    private var crossPlayUnavailable: Bool {
        selectedCategory == .modded || selectedFlavor == .vanilla
    }

    // True when the wizard should insert an Add-ons step between World and Confirm.
    private var hasAddOnsStep: Bool {
        wizardPath == .fresh && serverType == .java && selectedFlavor.addOnKind != nil
    }
    private var totalSteps: Int    { hasAddOnsStep ? 6 : 5 }
    private var confirmStepNum: Int { hasAddOnsStep ? 6 : 5 }
    private var addOnsNoun: String  { selectedFlavor.addOnKind?.displayName ?? "Add-ons" }

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

    // MARK: Network step
    @State private var enablePlayit: Bool        = false
    // @State private var isShowingPlayitGuide: Bool = false  // hidden — app handles playit setup in-flow
    @State private var isShowingPortForwardGuide: Bool = false

    // MARK: Shared / creation
    @State private var displayName: String       = ""
    @State private var isCreating: Bool          = false
    @State private var statusMessage: String     = ""
    @State private var createSucceeded: Bool     = false

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

            // Wrap scroll content + footer together so firstWorld/createButton
            // spotlight covers the full page including the action button.
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        stepContent
                            .padding(MSC.Spacing.xl)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                footerBar
            }
            .onboardingAnchor(.wizardBodyArea)
        }
        .frame(minWidth: 640, minHeight: 520)
        .onboardingAnchor(.wizardSheetArea)
        .overlay {
            OnboardingOverlayView(
                ownedSteps: [.wizardChoosePath, .serverName, .serverType,
                             .serverCategory, .serverFlavor, .serverVersion, .serverCrossplay,
                             .serverXboxBroadcast,
                             .serverSettings, .serverConnectivity, .serverConnectivityPorts,
                             .serverNetworkContinue, .firstWorld,
                             .serverAddOns, .createButton]
            )
        }
        .onAppear {
            if OnboardingManager.shared.isActive {
                wizardPath = .fresh
            }
        }
        // .sheet(isPresented: $isShowingPlayitGuide) {  // hidden — app handles playit setup in-flow
        //     PlayitSetupGuideSheet(
        //         localPort: currentNetworkLocalPort,
        //         bedrockPort: currentNetworkBedrockPort
        //     )
        // }
        .sheet(isPresented: $isShowingPortForwardGuide) {
            RouterPortForwardGuideSheet(
                runtimeContext: networkStepPortForwardContext
            )
        }
        .sheet(isPresented: $isShowingVersionPicker) {
            VersionPickerSheet(
                versions: availableVersions,
                selectedEntry: $selectedVersionEntry,
                isPresented: $isShowingVersionPicker
            )
        }
        .sheet(isPresented: $isShowingAddOnBrowser) {
            ModrinthBrowserView(
                serverConfig: wizardStagingConfig,
                onAddToStaging: { hit, version in
                    let entry = WizardStagedAddOn(
                        name: hit.title,
                        filename: version.primaryFile?.filename ?? "\(hit.slug).jar",
                        source: .modrinthDownload(hit: hit, version: version)
                    )
                    stagedAddOns.append(entry)
                },
                stagingGameVersion: resolvedStagingMCVersion
            )
            .environmentObject(viewModel)
        }
    }

    /// The Minecraft version add-ons should be matched against. When the user picked a
    /// specific version, that's it. When "Latest (recommended)" is selected
    /// (`selectedVersionEntry == nil`), fall back to the newest stable version we loaded,
    /// so compatibility checks aren't comparing against an unknown (nil) version.
    private var resolvedStagingMCVersion: String? {
        if let v = selectedVersionEntry?.mcVersion, !v.isEmpty { return v }
        return availableVersions.first(where: { $0.isStable })?.mcVersion
            ?? availableVersions.first?.mcVersion
    }

    /// "1.20.1 · Forge 47.4.1" when a loader build is pinned, else just the MC version.
    private func versionSummary(_ entry: ServerVersionEntry) -> String {
        if let buildLabel = entry.buildLabel, !buildLabel.isEmpty {
            return "\(entry.displayLabel) · \(buildLabel)"
        }
        return entry.displayLabel
    }

    /// A minimal ConfigServer populated with the wizard's current flavor selection,
    /// used only as a config carrier for ModrinthBrowserView during staging.
    private var wizardStagingConfig: ConfigServer {
        var cfg = ConfigServer(
            id: "wizard-staging",
            displayName: serverName,
            serverDir: "",
            paperJarPath: "",
            minRamGB: 2,
            maxRamGB: 4
        )
        cfg.javaFlavor = selectedFlavor
        cfg.minecraftVersion = resolvedStagingMCVersion
        return cfg
    }

    // MARK: - Step indicator

    private var stepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(1...totalSteps, id: \.self) { step in
                stepItemView(step: step)
                if step < totalSteps {
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
        if importKind == .modpack {
            switch step {
            case 1: return "Choose path"
            case 2: return "Upload"
            case 3: return "Network"
            case 4: return "World"
            case 5: return "Confirm"
            default: return ""
            }
        }
        if wizardPath == .fresh && currentStep > 1 {
            if hasAddOnsStep {
                switch step {
                case 1: return "Choose path"
                case 2: return "Configure"
                case 3: return "Network"
                case 4: return "World"
                case 5: return addOnsNoun
                case 6: return "Confirm"
                default: return ""
                }
            } else {
                switch step {
                case 1: return "Choose path"
                case 2: return "Configure"
                case 3: return "Network"
                case 4: return "World"
                case 5: return "Confirm"
                default: return ""
                }
            }
        }
        switch step {
        case 1: return "Choose path"
        case 2: return "Upload"
        case 3: return "Review"
        case 4: return "Network"
        case 5: return "Confirm"
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
            if importKind == .modpack { step3Network } else { step3ImportReview }
        } else if currentStep == 3 && wizardPath == .fresh {
            step3Network
        } else if currentStep == 4 && wizardPath == .importExisting {
            if importKind == .modpack { step4FreshWorld } else { step3Network }
        } else if currentStep == 4 && wizardPath == .fresh {
            step4FreshWorld
        } else if currentStep == 5 && hasAddOnsStep {
            step5AddOns
        } else {
            step5Confirm
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
                .onboardingAnchor(.wizardStartFreshCard)
            }
            .onboardingAnchor(.wizardPathPicker)
        }
    }

    // MARK: - Step 2 (Import): Drop zone / Modpack details

    private var step2ImportUpload: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
            if importKind == .modpack {
                step2ModpackDetails
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Drop your server folder, archive, or modpack")
                        .font(MSC.Typography.pageTitle)
                    Text("Drop a server folder or .zip to import an existing server, or drop a .mrpack / CurseForge .zip to start from a modpack.")
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
    }

    // Shown on step 2 when a modpack is detected — merged upload+details page.
    private var step2ModpackDetails: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Modpack detected")
                    .font(MSC.Typography.pageTitle)
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(MSC.Typography.caption)
                        .foregroundStyle(MSC.Colors.caption)
                }
            }

            // Pack info — locked from metadata
            VStack(spacing: 0) {
                infoRow(key: "Pack", value: serverName.isEmpty ? "Unknown" : serverName)
                if let entry = selectedVersionEntry {
                    infoRow(key: "Version", value: versionSummary(entry))
                }
                infoRow(key: "Software", value: "\(selectedFlavor.displayName) · \(selectedCategory.displayName)")
            }
            .pscCard(padding: MSC.Spacing.sm)

            // Server display name
            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                Text("Server Name")
                    .font(MSC.Typography.sectionHeader)
                TextField("Enter server name", text: $displayName)
                    .textFieldStyle(.roundedBorder)
            }

            // Override escape hatch — collapsed by default
            DisclosureGroup("Change loader/version…") {
                VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
                    VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                        Text("Server Software")
                            .font(MSC.Typography.sectionHeader)
                        ForEach(JavaServerFlavor.createFlowChoices(in: selectedCategory), id: \.self) { flavor in
                            WizardFlavorCard(
                                flavor: flavor,
                                isSelected: selectedFlavor == flavor,
                                isAvailable: implementedFlavors.contains(flavor)
                            ) {
                                if implementedFlavors.contains(flavor) {
                                    selectedFlavor = flavor
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                        Text("Version")
                            .font(MSC.Typography.sectionHeader)
                        Button {
                            if availableVersions.isEmpty && !isLoadingVersions {
                                isLoadingVersions = true
                                Task {
                                    let versions = (try? await ServerJarProvider.listVersions(for: selectedFlavor)) ?? []
                                    await MainActor.run {
                                        availableVersions = versions
                                        isLoadingVersions = false
                                        isShowingVersionPicker = true
                                    }
                                }
                            } else {
                                isShowingVersionPicker = true
                            }
                        } label: {
                            HStack(spacing: 6) {
                                if isLoadingVersions { ProgressView().controlSize(.mini) }
                                Text(selectedVersionEntry.map { versionSummary($0) } ?? "Choose version\u{2026}")
                                    .font(.subheadline)
                                    .foregroundStyle(selectedVersionEntry != nil ? Color.accentColor : .primary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, MSC.Spacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                                    .fill(selectedVersionEntry != nil ? Color.accentColor.opacity(0.08) : Color(NSColor.controlBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                                    .stroke(selectedVersionEntry != nil ? Color.accentColor : Color(NSColor.separatorColor),
                                            lineWidth: selectedVersionEntry != nil ? 1.5 : 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                        if let sv = selectedVersionEntry {
                            Text("Pinned: \(versionSummary(sv))")
                                .font(.caption).foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .padding(.top, MSC.Spacing.sm)
            }

            Button("Choose a different file") {
                importKind = .undetermined
                sourceURL = nil
                stagedAddOns.removeAll()
                serverName = ""
                selectedVersionEntry = nil
                displayName = ""
                statusMessage = ""
            }
            .buttonStyle(MSCSecondaryButtonStyle())
            .controlSize(.small)
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
                    Text("Drop server folder, archive, or modpack here")
                        .font(.system(size: 14, weight: .medium))
                    Text("or")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Browse…") { browseForServerFolder() }
                        .buttonStyle(MSCSecondaryButtonStyle())
                }

                HStack(spacing: 8) {
                    ForEach(["Folder", ".zip", ".mrpack", ".tar.gz"], id: \.self) { label in
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
                Task { @MainActor in
                    await handleImportDrop(url.standardizedFileURL)
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
                    ) {
                        serverType = .java
                        OnboardingManager.shared.tourServerType = .java
                    }

                    WizardServerTypeCard(
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

            Divider()

            // Server name
            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                Text("Server Name")
                    .font(MSC.Typography.sectionHeader)
                TextField("Enter server name", text: $serverName)
                    .textFieldStyle(.roundedBorder)
                    .onboardingAnchor(.serverNameField)
            }

            Divider()

            Group {
                if serverType == .java {
                    javaFreshSection
                } else {
                    bedrockFreshSection
                }
            }
            .onboardingAnchor(.serverSettingsArea)
        }
    }

    private var javaFreshSection: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.lg) {

            // Server Software — Level 1: category (Standard vs Modded)
            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                Text("Server Software")
                    .font(MSC.Typography.sectionHeader)
                HStack(spacing: MSC.Spacing.md) {
                    ForEach(JavaServerCategory.allCases, id: \.self) { cat in
                        WizardServerTypeCard(
                            title: cat.displayName,
                            subtitle: cat.subtitle,
                            systemImage: cat == .standard ? "bolt.fill" : "cube.fill",
                            isSelected: selectedCategory == cat
                        ) {
                            selectCategory(cat)
                        }
                    }
                }
            }
            .onboardingAnchor(.serverCategoryArea)

            // Server Software — Level 2: specific flavor
            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                ForEach(JavaServerFlavor.createFlowChoices(in: selectedCategory), id: \.self) { flavor in
                    WizardFlavorCard(
                        flavor: flavor,
                        isSelected: selectedFlavor == flavor,
                        isAvailable: implementedFlavors.contains(flavor)
                    ) {
                        if implementedFlavors.contains(flavor) {
                            selectedFlavor = flavor
                            OnboardingManager.shared.tourFlavor = flavor
                            if flavor == .vanilla { enableCrossPlay = false }
                        }
                    }
                }
            }
            .onboardingAnchor(.serverFlavorArea)

            // Source
            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                Text("Source")
                    .font(MSC.Typography.sectionHeader)
                HStack(spacing: MSC.Spacing.md) {
                    sourceChip(title: "Download latest", isSelected: selectedVersionEntry == nil, isAvailable: true) {
                        selectedVersionEntry = nil
                    }
                    Button {
                        if availableVersions.isEmpty && !isLoadingVersions {
                            isLoadingVersions = true
                            Task {
                                let versions = (try? await ServerJarProvider.listVersions(for: selectedFlavor)) ?? []
                                await MainActor.run {
                                    availableVersions = versions
                                    isLoadingVersions = false
                                    isShowingVersionPicker = true
                                }
                            }
                        } else {
                            isShowingVersionPicker = true
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isLoadingVersions {
                                ProgressView().controlSize(.mini)
                            }
                            Text(selectedVersionEntry.map { versionSummary($0) } ?? "Choose version\u{2026}")
                                .font(.subheadline)
                                .foregroundStyle(selectedVersionEntry != nil ? Color.accentColor : .primary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MSC.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                                .fill(selectedVersionEntry != nil ? Color.accentColor.opacity(0.08) : Color(NSColor.controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                                .stroke(selectedVersionEntry != nil ? Color.accentColor : Color(NSColor.separatorColor),
                                        lineWidth: selectedVersionEntry != nil ? 1.5 : 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
                if let sv = selectedVersionEntry {
                    Text("Pinned: \(versionSummary(sv))")
                        .font(.caption).foregroundStyle(Color.accentColor)
                }
            }
            .onboardingAnchor(.serverSourceArea)
            .onChange(of: selectedFlavor) { _, _ in
                // A staged .mrpack programmatically sets the flavor from pack metadata;
                // in that one case keep the manifest-pinned version instead of clearing.
                if preserveVersionOnNextFlavorChange {
                    preserveVersionOnNextFlavorChange = false
                } else {
                    selectedVersionEntry = nil
                    availableVersions = []
                }
            }

            crossPlaySection
                .onboardingAnchor(.serverCrossplayArea)

            if enableCrossPlay && !crossPlayUnavailable {
                xboxBroadcastSection
            }
        }
    }

    private var crossPlaySection: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
            Text("Crossplay")
                .font(MSC.Typography.sectionHeader)

            HStack(alignment: .top, spacing: MSC.Spacing.md) {
                Image(systemName: "cube.fill")
                    .font(.title3)
                    .foregroundStyle(enableCrossPlay && !crossPlayUnavailable ? Color.accentColor : .secondary)
                    .frame(width: 26)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable Bedrock Cross-play")
                        .font(MSC.Typography.sectionHeader)
                        .foregroundStyle(crossPlayUnavailable ? .secondary : .primary)
                    Text("Geyser and Floodgate are plugins that let Bedrock players (console, mobile, Windows) join your Java server. Enable here rather than adding them through the plugin browser.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Toggle("", isOn: $enableCrossPlay)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(crossPlayUnavailable)
                    .onChange(of: enableCrossPlay) { _, enabled in
                        if enabled && !crossPlayJarsPresent() {
                            Task { await downloadCrossPlayIfNeeded() }
                        } else if !enabled {
                            crossPlayDownloadStatus = nil
                            enableXboxBroadcast = false
                            xboxBroadcastDownloadStatus = nil
                        }
                        OnboardingManager.shared.tourCrossplayEnabled = enabled
                    }
            }
            .padding(MSC.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                    .fill(enableCrossPlay && !crossPlayUnavailable
                          ? Color.accentColor.opacity(0.08)
                          : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                    .stroke(enableCrossPlay && !crossPlayUnavailable
                            ? Color.accentColor : Color(NSColor.separatorColor),
                            lineWidth: enableCrossPlay && !crossPlayUnavailable ? 1.5 : 0.5)
            )
            .opacity(crossPlayUnavailable ? 0.55 : 1.0)

            if selectedCategory == .modded {
                Text("Bedrock players can't join modded Java servers — cross-play is unavailable.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if selectedFlavor == .vanilla {
                Text("Vanilla servers have no plugin API, so Geyser can't run — cross-play is unavailable.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if isDownloadingCrossPlay {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Downloading Geyser & Floodgate…")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if let status = crossPlayDownloadStatus {
                Text(status).font(.caption)
                    .foregroundStyle(status.contains("Failed") ? .red : .green)
            }
        }
    }

    private var xboxBroadcastSection: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
            Text("Xbox Broadcast")
                .font(MSC.Typography.sectionHeader)

            HStack(alignment: .top, spacing: MSC.Spacing.md) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.title3)
                    .foregroundStyle(enableXboxBroadcast ? Color.accentColor : .secondary)
                    .frame(width: 26)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable Xbox Broadcast")
                        .font(MSC.Typography.sectionHeader)
                    Text("Let console, mobile, and PC players see your server in the Xbox Friends tab. MSC downloads the broadcast tool automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Toggle("", isOn: $enableXboxBroadcast)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .onChange(of: enableXboxBroadcast) { _, enabled in
                        if enabled {
                            downloadXboxBroadcastIfNeeded()
                        } else {
                            xboxBroadcastDownloadStatus = nil
                        }
                    }
            }
            .padding(MSC.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                    .fill(enableXboxBroadcast
                          ? Color.accentColor.opacity(0.08)
                          : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                    .stroke(enableXboxBroadcast
                            ? Color.accentColor : Color(NSColor.separatorColor),
                            lineWidth: enableXboxBroadcast ? 1.5 : 0.5)
            )

            if let status = xboxBroadcastDownloadStatus {
                Text(status).font(.caption)
                    .foregroundStyle(status.contains("Failed") || status.contains("failed") ? .red : .green)
            }
        }
        .onboardingAnchor(.serverXboxBroadcastArea)
    }

    private func downloadXboxBroadcastIfNeeded() {
        guard !viewModel.isXboxBroadcastHelperInstalled else {
            xboxBroadcastDownloadStatus = "✓ Xbox Broadcast ready."
            return
        }
        xboxBroadcastDownloadStatus = "Downloading Xbox Broadcast…"
        viewModel.downloadOrUpdateXboxBroadcastJar()
    }

    /// Selecting a category defaults the flavor to that category's recommended
    /// (preferring an implemented one) and clears cross-play for Modded.
    private func selectCategory(_ cat: JavaServerCategory) {
        selectedCategory = cat
        let choices = JavaServerFlavor.createFlowChoices(in: cat)
        selectedFlavor = choices.first(where: { implementedFlavors.contains($0) }) ?? choices.first ?? .paper
        if cat == .modded { enableCrossPlay = false }
        OnboardingManager.shared.tourServerType = .java
        OnboardingManager.shared.tourFlavor = selectedFlavor
    }

    /// A small bordered chip for the Source row. Mirrors WizardServerTypeCard styling.
    @ViewBuilder
    private func sourceChip(title: String, isSelected: Bool, isAvailable: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { if isAvailable { action() } }) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? Color.accentColor : (isAvailable ? .primary : .secondary))
                if !isAvailable {
                    Text("SOON")
                        .font(.system(size: 8.5, weight: .semibold)).tracking(0.5)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, MSC.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color(NSColor.separatorColor),
                            lineWidth: isSelected ? 1.5 : 0.5)
            )
            .opacity(isAvailable ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
    }

    private var bedrockFreshSection: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
            /* Docker Image field — hidden; VM backend downloads BDS directly
            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                Text("Docker Image")
                    .font(MSC.Typography.sectionHeader)
                TextField("itzg/minecraft-bedrock-server", text: $bedrockDockerImage)
                    .textFieldStyle(.roundedBorder)
                Text("Change only if you use a custom Bedrock image.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            */

            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                Text("Bedrock Version")
                    .font(MSC.Typography.sectionHeader)
                TextField("LATEST", text: $bedrockVersion)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
            }

            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                Text("Max Players")
                    .font(MSC.Typography.sectionHeader)
                TextField("10", text: $bedrockMaxPlayers)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 120)
                Text("Port and connectivity options are on the next step.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            xboxBroadcastSection
        }
    }

    // MARK: - Step 3/4: Network (shared by both paths)

    private var step3Network: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
            VStack(alignment: .leading, spacing: 4) {
                Text("How will friends connect?")
                    .font(MSC.Typography.pageTitle)
                Text("Choose how players outside your local network will join your server.")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.caption)
            }

            HStack(spacing: MSC.Spacing.md) {
                WizardPathCard(
                    title: "Port Forwarding",
                    subtitle: "Open a port on your router. Full control, no relay, best latency.",
                    systemImage: "network",
                    isSelected: !enablePlayit
                ) {
                    enablePlayit = false
                    // Tour advances only via the coach mark's Next button, so the user can
                    // toggle between connectivity options freely.
                }

                WizardPathCard(
                    title: "Tunnel (playit.gg)",
                    subtitle: "No router access needed. Free relay service. Adds ~10–50 ms.",
                    systemImage: "arrow.triangle.2.circlepath",
                    isSelected: enablePlayit
                ) {
                    enablePlayit = true
                    // Tour advances only via the coach mark's Next button.
                }
            }
            .onboardingAnchor(.serverConnectivityArea)

            Divider()

            Group {
                if enablePlayit {
                    playitPortSection
                } else {
                    portForwardingSection
                }
            }
            .onboardingAnchor(.serverConnectivityPortsArea)
        }
    }

    // Port fields + guide for Port Forwarding
    private var portForwardingSection: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {
            if (wizardPath == .fresh || importKind == .modpack) && serverType == .java {
                HStack(spacing: MSC.Spacing.xl) {
                    VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                        Text("Java Port (TCP)")
                            .font(MSC.Typography.sectionHeader)
                        TextField("25565", text: $javaPort)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 120)
                    }
                    if enableCrossPlay {
                        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                            Text("Bedrock / Geyser Port (UDP)")
                                .font(MSC.Typography.sectionHeader)
                            TextField("19132", text: $crossPlayBedrockPort)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 120)
                        }
                    }
                }
                Text("Forward these ports on your router so players outside your network can connect.")
                    .font(.caption).foregroundStyle(.secondary)

            } else if wizardPath == .fresh && serverType == .bedrock {
                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                    Text("Server Port (UDP)")
                        .font(MSC.Typography.sectionHeader)
                    TextField("19132", text: $bedrockPort)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 120)
                }
                Text("Bedrock uses UDP. Forward this port on your router for external access.")
                    .font(.caption).foregroundStyle(.secondary)

            } else {
                // Existing-server import — port from scan
                HStack(spacing: MSC.Spacing.xl) {
                    VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                        Text("Server Port")
                            .font(MSC.Typography.sectionHeader)
                        TextField("25565", text: $importPort)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 120)
                    }
                }
                Text("Port was read from your server folder. Change it here if needed, then forward it on your router.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Button {
                isShowingPortForwardGuide = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.circle")
                        .font(.system(size: 12))
                    Text("Port Forwarding Guide")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .buttonStyle(MSCSecondaryButtonStyle())
            .controlSize(.small)
        }
    }

    // Port fields + guide for playit.gg
    private var playitPortSection: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {
            if (wizardPath == .fresh || importKind == .modpack) && serverType == .java {
                HStack(spacing: MSC.Spacing.xl) {
                    VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                        Text("Local Port (TCP)")
                            .font(MSC.Typography.sectionHeader)
                        TextField("25565", text: $javaPort)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 120)
                    }
                    if enableCrossPlay {
                        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                            Text("Bedrock / Geyser Port (UDP)")
                                .font(MSC.Typography.sectionHeader)
                            TextField("19132", text: $crossPlayBedrockPort)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 120)
                        }
                    }
                }
            } else if wizardPath == .fresh && serverType == .bedrock {
                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                    Text("Local Port (UDP)")
                        .font(MSC.Typography.sectionHeader)
                    TextField("19132", text: $bedrockPort)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 120)
                }
            } else {
                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                    Text("Local Port")
                        .font(MSC.Typography.sectionHeader)
                    TextField("25565", text: $importPort)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 120)
                }
            }

            Text("playit.gg will assign a public address (e.g. abc.joinmc.link:25565) the first time you start your server. Your local port is what the server listens on — no router config needed.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Button {  // hidden — app handles playit setup in-flow
            //     isShowingPlayitGuide = true
            // } label: {
            //     HStack(spacing: 6) {
            //         Image(systemName: "questionmark.circle")
            //             .font(.system(size: 12))
            //         Text("How does this work?")
            //             .font(.system(size: 12, weight: .medium))
            //     }
            // }
            // .buttonStyle(MSCSecondaryButtonStyle())
            // .controlSize(.small)
        }
    }

    // Computed helpers for sheet context
    private var currentNetworkLocalPort: Int {
        if serverType == .java || wizardPath == .importExisting {
            let portStr = (wizardPath == .importExisting && importKind != .modpack) ? importPort : javaPort
            return Int(portStr) ?? 25565
        }
        return Int(bedrockPort) ?? 19132
    }

    private var currentNetworkBedrockPort: Int? {
        guard enableCrossPlay, serverType == .java else { return nil }
        return Int(crossPlayBedrockPort) ?? 19132
    }

    private var networkStepPortForwardContext: RouterPortForwardGuideRuntimeContext {
        RouterPortForwardGuideRuntimeContext(
            selectedServerID: nil,
            selectedServerName: displayName.isEmpty ? serverName : displayName,
            detectedLocalIPAddress: AppUtilities.localIPAddress(),
            detectedGatewayIPAddress: nil,
            javaPort: serverType == .java ? (Int(javaPort) ?? 25565) : nil,
            bedrockPort: enableCrossPlay ? (Int(crossPlayBedrockPort) ?? 19132) : (serverType == .bedrock ? (Int(bedrockPort) ?? 19132) : nil),
            recommendedProtocol: serverType == .java ? "TCP" : "UDP",
            bedrockEnabled: enableCrossPlay || serverType == .bedrock
        )
    }

    // MARK: - Step 4 (Fresh): World source

    private var step4FreshWorld: some View {
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
        .onboardingAnchor(.worldCreationArea)
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

    // MARK: - Step 5: Add-ons (only when hasAddOnsStep)

    private var step5AddOns: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
            HStack(alignment: .top, spacing: MSC.Spacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(stagedAddOns.isEmpty ? "Add \(addOnsNoun)" : "\(addOnsNoun) (\(stagedAddOns.count))")
                        .font(MSC.Typography.pageTitle)
                    Text(stagedAddOns.isEmpty
                         ? "Browse Modrinth or import from a file. You can also skip this and add \(addOnsNoun.lowercased()) after the server is created."
                         : "These will be installed after the server folder is created. You can add more or remove any below.")
                        .font(MSC.Typography.caption)
                        .foregroundStyle(MSC.Colors.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                // Add/import controls live beside the title once items are staged,
                // so we don't repeat the section name in a second header below.
                if !stagedAddOns.isEmpty {
                    HStack(spacing: MSC.Spacing.sm) {
                        Button { importModpack() } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(MSCSecondaryButtonStyle())
                        .controlSize(.small)
                        .help("Import \(addOnsNoun.lowercased()) from a file")

                        Button { isShowingAddOnBrowser = true } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                Text("Add")
                            }
                        }
                        .buttonStyle(MSCSecondaryButtonStyle())
                        .controlSize(.small)
                        .help("Search Modrinth")
                    }
                    .padding(.top, 2)
                }
            }

            if stagedAddOns.isEmpty {
                // Two action tiles
                HStack(spacing: MSC.Spacing.md) {
                    WizardPathCard(
                        title: "Browse Modrinth",
                        subtitle: "Search and add \(addOnsNoun.lowercased()) by name or keyword.",
                        systemImage: "magnifyingglass",
                        isSelected: false
                    ) { isShowingAddOnBrowser = true }

                    WizardPathCard(
                        title: selectedFlavor.addOnKind == .mod ? "Import Modpack" : "Import \(addOnsNoun)",
                        subtitle: selectedFlavor.addOnKind == .mod
                            ? "Import a .mrpack, .zip, or folder of .jar files."
                            : "Import a .zip or folder of .jar plugin files.",
                        systemImage: "folder",
                        isSelected: false
                    ) { importModpack() }
                }
            } else {
                // Staged list — add/import controls sit next to the page title above.
                VStack(spacing: 0) {
                    ForEach(stagedAddOns) { addOn in
                        addOnRow(addOn)
                        if addOn.id != stagedAddOns.last?.id {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .pscCard(padding: 0)
            }
        }
        .task {
            // Ensure we know the latest MC version so add-on compatibility checks work even
            // if the user never opened the version picker (i.e. left "Latest" selected).
            if availableVersions.isEmpty && !isLoadingVersions {
                isLoadingVersions = true
                let versions = (try? await ServerJarProvider.listVersions(for: selectedFlavor)) ?? []
                await MainActor.run {
                    availableVersions = versions
                    isLoadingVersions = false
                }
            }
        }
    }

    @ViewBuilder
    private func addOnRow(_ addOn: WizardStagedAddOn) -> some View {
        HStack(spacing: MSC.Spacing.sm) {
            // Icon: async from Modrinth if available, else generic
            Group {
                if case .modrinthDownload(let hit, _) = addOn.source, let iconStr = hit.iconUrl, let iconURL = URL(string: iconStr) {
                    AsyncImage(url: iconURL) { img in
                        img.resizable().scaledToFit()
                    } placeholder: {
                        Image(systemName: selectedFlavor.addOnKind == .plugin ? "puzzlepiece.fill" : "shippingbox.fill")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Image(systemName: selectedFlavor.addOnKind == .plugin ? "puzzlepiece.fill" : "shippingbox.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(addOn.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if case .modrinthDownload(let hit, _) = addOn.source {
                    Text(hit.description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text(addOn.filename)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                stagedAddOns.removeAll { $0.id == addOn.id }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, MSC.Spacing.sm)
        .padding(.horizontal, MSC.Spacing.md)
    }

    // MARK: - Step 5/6: Confirm

    private var step5Confirm: some View {
        Group {
            if createSucceeded {
                createSuccessView
            } else {
                confirmFormView
            }
        }
    }

    private var createSuccessView: some View {
        VStack(spacing: MSC.Spacing.lg) {
            Spacer()
            VStack(spacing: MSC.Spacing.md) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(MSC.Colors.success)
                Text("\(displayName) created!")
                    .font(.system(size: 20, weight: .semibold))
                Text(postCreateHint)
                    .font(.system(size: 13))
                    .foregroundStyle(MSC.Colors.caption)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var installerLogView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Installing \(selectedFlavor.displayName) — this can take several minutes…")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(viewModel.creationLogLines.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(MSC.Colors.caption)
                                .textSelection(.enabled)
                                .id(idx)
                        }
                    }
                    .padding(6)
                }
                .frame(height: 100)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.08)))
                .onChange(of: viewModel.creationLogLines.count) { _ in
                    if let last = viewModel.creationLogLines.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var postCreateHint: String {
        if wizardPath == .importExisting && importKind == .modpack {
            return "Your modpack's mods are installed. Start the server when you're ready to play."
        }
        if selectedFlavor.category == .modded {
            return "Add mods in the Components tab before starting — world-gen mods must be present on first boot."
        }
        if selectedFlavor == .vanilla {
            return "Open Server Settings to review defaults, then press Start when you're ready."
        }
        return "Open Server Settings to review defaults. Install plugins from the Components tab any time."
    }

    private var confirmFormView: some View {
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
                    if wizardPath == .importExisting && importKind == .modpack {
                        infoRow(key: "Method",       value: "Import modpack")
                        infoRow(key: "Pack",         value: serverName.isEmpty ? "Unknown" : serverName)
                        infoRow(key: "Software",     value: "\(selectedFlavor.displayName) · \(selectedCategory.displayName)")
                        infoRow(key: "Version",      value: selectedVersionEntry.map { versionSummary($0) } ?? "Latest")
                        infoRow(key: "Java Port",    value: javaPort)
                        infoRow(key: "Connectivity", value: enablePlayit ? "Tunnel (playit.gg)" : "Port Forwarding")
                        infoRow(key: "World source", value: worldSourceMode.rawValue)
                        if worldSourceMode == .fresh {
                            let wName = initialWorldName.trimmingCharacters(in: .whitespacesAndNewlines)
                            infoRow(key: "World name", value: wName.isEmpty ? serverName : wName)
                        }
                        if !stagedAddOns.isEmpty {
                            infoRow(key: "Mods", value: "\(stagedAddOns.count) from pack")
                        }
                    } else if wizardPath == .importExisting, let info = scannedInfo {
                        infoRow(key: "Method",       value: "Import existing")
                        infoRow(key: "Server type",  value: info.serverType.displayName)
                        infoRow(key: "Port",         value: importPort.isEmpty ? "\(info.port)" : importPort)
                        infoRow(key: "Connectivity", value: enablePlayit ? "Tunnel (playit.gg)" : "Port Forwarding")
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
                        if serverType == .java {
                            infoRow(key: "Software", value: "\(selectedFlavor.displayName) · \(selectedCategory.displayName)")
                            infoRow(key: "Version",  value: selectedVersionEntry.map { versionSummary($0) } ?? "Latest \(selectedFlavor.displayName)")
                        }
                        if serverType == .java {
                            infoRow(key: "Java Port", value: javaPort)
                            if enableCrossPlay {
                                infoRow(key: "Bedrock Port", value: crossPlayBedrockPort)
                            }
                        } else {
                            infoRow(key: "Port", value: bedrockPort)
                        }
                        infoRow(key: "Connectivity", value: enablePlayit ? "Tunnel (playit.gg)" : "Port Forwarding")
                        infoRow(key: "World source",  value: worldSourceMode.rawValue)
                        if worldSourceMode == .fresh {
                            let wName = initialWorldName.trimmingCharacters(in: .whitespacesAndNewlines)
                            let displayedName = wName.isEmpty ? serverName : wName
                            infoRow(key: "World name", value: displayedName)
                        }
                    }
                }
                .pscCard(padding: MSC.Spacing.sm)

                if wizardPath == .fresh && serverType == .java && selectedCategory == .modded {
                    Label {
                        Text("To join, every player needs the \(selectedFlavor.displayName) loader for this Minecraft version, plus the same mods installed.")
                    } icon: {
                        Image(systemName: "person.2.fill")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            if isCreating {
                if selectedFlavor.provisioningKind == .installStep && !viewModel.creationLogLines.isEmpty {
                    installerLogView
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(statusMessage.isEmpty ? "Working…" : statusMessage)
                            .font(.caption).foregroundStyle(.secondary)
                    }
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
        .onboardingAnchor(.confirmPageArea)
    }  // end confirmFormView

    // MARK: - Footer

    private var footerBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: MSC.Spacing.sm) {
                if !createSucceeded && currentStep > 1 {
                    Button("Back") {
                        withAnimation(.easeInOut(duration: 0.18)) { currentStep -= 1 }
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                    .disabled(isCreating || isScanning)
                }

                Spacer()

                if createSucceeded {
                    Button("Done") { isPresented = false }
                        .buttonStyle(MSCPrimaryButtonStyle())
                } else if currentStep == confirmStepNum {
                    Button("Create Server") { beginCreate() }
                        .buttonStyle(MSCPrimaryButtonStyle())
                        .disabled(!canCreate || isCreating)
                        .onboardingAnchor(.createSaveButton)
                } else {
                    Button("Continue") { advanceStep() }
                        .buttonStyle(MSCPrimaryButtonStyle())
                        .disabled(!canAdvance || isScanning)
                        .onboardingAnchor(.wizardContinueButton)
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
                if importKind == .modpack {
                    return selectedVersionEntry != nil
                        && !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                return scannedInfo != nil && !isScanning && scanError == nil
            } else {
                let nameOk = !serverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if serverType == .java {
                    return nameOk && implementedFlavors.contains(selectedFlavor)
                } else {
                    return nameOk
                        // Docker image validation removed — VM backend ignores this field
                }
            }
        case 3:
            // Network step (Fresh or Modpack) or Review step (existing Import)
            if wizardPath == .importExisting {
                if importKind == .modpack { return Int(javaPort) != nil }
                return true
            }
            if serverType == .java { return Int(javaPort) != nil }
            return Int(bedrockPort) != nil
        case 4:
            // World step (Modpack or Fresh) or Network step (existing Import)
            if wizardPath == .importExisting {
                if importKind == .modpack {
                    switch worldSourceMode {
                    case .fresh:     return true
                    case .backupZip: return selectedBackupURL != nil
                    case .folder:    return selectedWorldFolderURL != nil
                    }
                }
                return Int(importPort) != nil
            }
            switch worldSourceMode {
            case .fresh:     return true
            case .backupZip: return selectedBackupURL != nil
            case .folder:    return selectedWorldFolderURL != nil
            }
        case 5:
            // Add-ons step — always skippable
            return hasAddOnsStep
        default:
            return false
        }
    }

    private var canCreate: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isCreating
    }

    private func advanceStep() {
        // Pre-fill display name before reaching the confirm step
        if currentStep == 3 && wizardPath == .importExisting && importKind != .modpack {
            if displayName.isEmpty, let url = sourceURL {
                displayName = url.deletingPathExtension().lastPathComponent
                    .replacingOccurrences(of: "_", with: " ")
            }
            if selectedWorldName == nil {
                selectedWorldName = scannedInfo?.defaultWorldName
            }
        }
        if currentStep == 4 && wizardPath == .fresh && displayName.isEmpty {
            displayName = serverName
        }
        // Modpack: displayName is entered on step 2; fallback in case it was left empty
        if currentStep == 4 && wizardPath == .importExisting && importKind == .modpack && displayName.isEmpty {
            displayName = serverName
        }
        withAnimation(.easeInOut(duration: 0.18)) { currentStep += 1 }

        // Sync tour to match the wizard page we just entered
        guard OnboardingManager.shared.isActive else { return }
        let tourStep = OnboardingManager.shared.currentStep
        switch currentStep {
        case 2 where wizardPath == .fresh:
            if tourStep == .wizardChoosePath {
                OnboardingManager.shared.advance()    // → .serverType (first Configure step)
            } else if tourStep.rawValue < OnboardingStep.serverType.rawValue {
                OnboardingManager.shared.jumpTo(.serverType)
            }
        case 3 where wizardPath == .fresh:
            // Entered Network page — advance from serverSettings to serverConnectivity
            if tourStep == .serverSettings {
                OnboardingManager.shared.advance()    // → .serverConnectivity
            } else if tourStep.rawValue < OnboardingStep.serverConnectivity.rawValue {
                OnboardingManager.shared.jumpTo(.serverConnectivity)
            }
        case 4 where wizardPath == .fresh:
            // Entered World page — advance from serverNetworkContinue to firstWorld
            if tourStep == .serverNetworkContinue {
                OnboardingManager.shared.advance()    // → .firstWorld
            } else if tourStep.rawValue < OnboardingStep.firstWorld.rawValue {
                OnboardingManager.shared.jumpTo(.firstWorld)
            }
        case 5 where hasAddOnsStep:
            // Entered the Add-ons (Plugins/Mods) page — advance from the world step.
            if tourStep == .firstWorld {
                OnboardingManager.shared.advance()    // → .serverAddOns
            } else if tourStep.rawValue < OnboardingStep.serverAddOns.rawValue {
                OnboardingManager.shared.jumpTo(.serverAddOns)
            }
        case 5, 6:
            // Entered the Confirm page (page 5 when there's no add-ons step, page 6 with it).
            // advance() is skip-aware, so from .firstWorld it hops over the inapplicable
            // .serverAddOns step straight to .createButton when no add-ons step exists.
            if tourStep == .firstWorld || tourStep == .serverAddOns {
                OnboardingManager.shared.advance()    // → .createButton
            } else if tourStep.rawValue < OnboardingStep.createButton.rawValue {
                OnboardingManager.shared.jumpTo(.createButton)
            }
        default:
            break
        }
    }

    // MARK: - Create

    private func beginCreate() {
        guard canCreate else { return }
        isCreating = true
        statusMessage = ""

        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        if wizardPath == .importExisting && importKind == .modpack {
            // Modpack import: provision via createNewServer (same as Start Fresh Java)
            let worldSource: AppViewModel.WorldSource
            switch worldSourceMode {
            case .fresh: worldSource = .fresh
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
            let seedRaw   = initialWorldSeed.trimmingCharacters(in: .whitespacesAndNewlines)
            let port      = Int(javaPort) ?? 25565
            statusMessage = "Downloading \(selectedFlavor.displayName) and installing modpack…"
            Task {
                let ok = await viewModel.createNewServer(
                    name: name,
                    initialWorldName: worldName.isEmpty ? nil : worldName,
                    jarSource: .downloadLatest,
                    flavor: selectedFlavor,
                    specificVersion: selectedVersionEntry,
                    stagedAddOns: stagedAddOns,
                    port: port,
                    enableCrossPlay: false,
                    crossPlayBedrockPort: nil,
                    enablePlayit: enablePlayit,
                    enableXboxBroadcast: false,
                    difficulty: initialWorldDifficulty.rawValue,
                    gamemode: initialWorldGamemode.rawValue,
                    worldSeed: seedRaw.isEmpty ? nil : seedRaw,
                    worldSource: worldSource
                )
                await MainActor.run {
                    isCreating = false
                    if ok { createSucceeded = true }
                    else {
                        statusMessage = viewModel.lastServerCreateError.map { "Failed to create server: \($0)" }
                            ?? "Failed to create server."
                    }
                }
            }

        } else if wizardPath == .importExisting {
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
                                    eulaOverride: importEulaAccepted,
                                    enablePlayit: enablePlayit
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
                    ? "Downloading latest \(selectedFlavor.displayName) and creating server…"
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
                        flavor: selectedFlavor,
                        specificVersion: selectedVersionEntry,
                        stagedAddOns: stagedAddOns,
                        port: port,
                        enableCrossPlay: enableCrossPlay,
                        crossPlayBedrockPort: crossPort,
                        enablePlayit: enablePlayit,
                        enableXboxBroadcast: enableXboxBroadcast,
                        difficulty: initialWorldDifficulty.rawValue,
                        gamemode: initialWorldGamemode.rawValue,
                        worldSeed: seedOpt,
                        worldSource: worldSource
                    )
                    await MainActor.run {
                        isCreating = false
                        if ok { createSucceeded = true }
                        else {
                            statusMessage = viewModel.lastServerCreateError.map { "Failed to create server: \($0)" }
                                ?? "Failed to create server."
                        }
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
                        enablePlayit: enablePlayit,
                        enableXboxBroadcast: enableXboxBroadcast,
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

            // Use ditto to avoid /usr/bin/unzip's mode-000 quirk on user-selected archives.
            let exitCode: Int32 = await Task.detached(priority: .userInitiated) {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                p.arguments = ["-x", "-k", url.path, tmp.path]
                p.standardOutput = FileHandle.nullDevice
                p.standardError  = FileHandle.nullDevice
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
        panel.canChooseFiles          = true
        panel.canChooseDirectories    = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes     = [.folder, .zip,
                                          UTType(filenameExtension: "mrpack") ?? .zip]
        panel.title                   = "Choose Server Folder, .zip, or Modpack"
        panel.message                 = "Select a server folder, .zip archive, or modpack (.mrpack / CurseForge .zip) to import."
        if panel.runModal() == .OK, let url = panel.url {
            Task { await handleImportDrop(url) }
        }
    }

    @MainActor
    private func handleImportDrop(_ url: URL) async {
        let ext = url.pathExtension.lowercased()
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

        if ext == "mrpack" || (!isDir.boolValue && ext == "zip" && (try? AppViewModel.readCurseForgeMetadata(from: url)) != nil) {
            importKind = .modpack
            sourceURL = url
            stagedAddOns.removeAll()
            await processModpackURL(url)
            if displayName.isEmpty { displayName = serverName }
        } else {
            importKind = .existingServer
            let zip = ext == "zip"
            sourceURL   = url
            isSourceZip = zip
            await performScan(url, isZip: zip)
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

    // MARK: - Modpack import

    private func importModpack() {
        let panel = NSOpenPanel()
        panel.title = "Import Modpack"
        panel.prompt = "Import"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType(filenameExtension: "mrpack") ?? .zip,
            .zip,
        ]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { await processModpackURL(url) }
        }
    }

    @MainActor
    private func processModpackURL(_ url: URL) async {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        fm.fileExists(atPath: url.path, isDirectory: &isDir)

        let ext = url.pathExtension.lowercased()
        if ext == "mrpack" {
            // Pre-parse the manifest so we can pin the flavor + exact MC/loader version the
            // pack expects, instead of importing blind and downloading "latest".
            let stagedName: String
            do {
                let metadata = try AppViewModel.readMrpackMetadata(from: url)
                let manifest = metadata.manifest
                stagedName = "Modpack: \(manifest.name) v\(manifest.versionId)"

                if serverType != .java { serverType = .java }
                if let flavor = metadata.loaderFlavor {
                    selectedCategory = flavor.category
                    if selectedFlavor != flavor {
                        // Let this single programmatic flavor change keep the pinned version.
                        preserveVersionOnNextFlavorChange = true
                        selectedFlavor = flavor
                    }
                    // A staged pack always installs a downloaded jar, never a template.
                    jarSourceMode = .downloadLatest
                }
                if let entry = metadata.versionEntry {
                    selectedVersionEntry = entry
                    availableVersions.removeAll { $0.id == entry.id }
                    availableVersions.insert(entry, at: 0)
                }
                if serverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    serverName = manifest.name
                }

                let detectedParts = [
                    metadata.minecraftVersion.map { "Minecraft \($0)" },
                    metadata.loaderFlavor.map { flavor in
                        if let loaderVersion = metadata.loaderVersion {
                            return "\(flavor.displayName) \(loaderVersion)"
                        }
                        return flavor.displayName
                    }
                ].compactMap { $0 }
                if !detectedParts.isEmpty {
                    statusMessage = "Detected \(manifest.name): \(detectedParts.joined(separator: " · "))."
                }
            } catch {
                stagedName = "Modpack: \(url.deletingPathExtension().lastPathComponent)"
                statusMessage = "Could not read modpack metadata yet: \(error.localizedDescription)"
            }

            // Stage the whole .mrpack file; it will be imported via importModpack at creation time.
            stagedAddOns.append(WizardStagedAddOn(
                name: stagedName,
                filename: url.lastPathComponent,
                source: .mrpackFile(url: url)
            ))
        } else if isDir.boolValue {
            // Folder: scan for .jar files directly.
            if let items = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                for item in items where item.pathExtension.lowercased() == "jar" {
                    stagedAddOns.append(WizardStagedAddOn(
                        name: item.deletingPathExtension().lastPathComponent,
                        filename: item.lastPathComponent,
                        source: .localJar(url: item)
                    ))
                }
            }
        } else if ext == "zip" {
            // A .zip may be a CurseForge modpack (manifest.json) or a plain jars folder.
            // Sniff for CurseForge first so we can pin its loader + MC version like .mrpack.
            if let metadata = try? AppViewModel.readCurseForgeMetadata(from: url) {
                let manifest = metadata.manifest

                if serverType != .java { serverType = .java }
                if let flavor = metadata.loaderFlavor {
                    selectedCategory = flavor.category
                    if selectedFlavor != flavor {
                        preserveVersionOnNextFlavorChange = true
                        selectedFlavor = flavor
                    }
                    jarSourceMode = .downloadLatest
                }
                if let entry = metadata.versionEntry {
                    selectedVersionEntry = entry
                    availableVersions.removeAll { $0.id == entry.id }
                    availableVersions.insert(entry, at: 0)
                }
                if serverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    serverName = metadata.name
                }

                let detectedParts = [
                    metadata.minecraftVersion.map { "Minecraft \($0)" },
                    metadata.loaderFlavor.map { flavor in
                        if let loaderVersion = metadata.loaderVersion {
                            return "\(flavor.displayName) \(loaderVersion)"
                        }
                        return flavor.displayName
                    }
                ].compactMap { $0 }
                if !detectedParts.isEmpty {
                    statusMessage = "Detected CurseForge pack \(metadata.name): \(detectedParts.joined(separator: " · "))."
                }

                let stagedName = metadata.versionId.isEmpty
                    ? "CurseForge: \(manifest.name ?? metadata.name)"
                    : "CurseForge: \(metadata.name) v\(metadata.versionId)"
                stagedAddOns.append(WizardStagedAddOn(
                    name: stagedName,
                    filename: url.lastPathComponent,
                    source: .curseForgeFile(url: url)
                ))
            } else {
                // Plain zip with JARs — staged for extraction at creation time.
                stagedAddOns.append(WizardStagedAddOn(
                    name: "Zip: \(url.deletingPathExtension().lastPathComponent)",
                    filename: url.lastPathComponent,
                    source: .zipFolder(url: url)
                ))
            }
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

/// Level-2 selection card for a specific Java server flavor (Paper, Purpur, …).
/// Shows a "Recommended" badge for the category default and a "Soon" badge plus
/// a disabled/dimmed state for flavors whose provisioning isn't built yet.
private struct WizardFlavorCard: View {
    let flavor: JavaServerFlavor
    let isSelected: Bool
    let isAvailable: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: MSC.Spacing.sm) {
                Image(systemName: flavor.iconName)
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(flavor.displayName)
                            .font(MSC.Typography.sectionHeader)
                            .foregroundStyle(isSelected ? Color.accentColor : (isAvailable ? .primary : .secondary))
                        if flavor.isRecommended { badge("Recommended", color: .accentColor) }
                        if !isAvailable { badge("Soon", color: .secondary) }
                    }
                    Text(flavor.shortDescription)
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
                    .stroke(isSelected ? Color.accentColor : Color(NSColor.separatorColor),
                            lineWidth: isSelected ? 1.5 : 0.5)
            )
            .opacity(isAvailable ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .disabled(!isAvailable)
    }

    @ViewBuilder
    private func badge(_ text: String, color: Color) -> some View {
        Text(text.uppercased())
            .font(.system(size: 8.5, weight: .semibold))
            .tracking(0.5)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }
}

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

// MARK: - VersionPickerSheet

struct VersionPickerSheet: View {
    let versions: [ServerVersionEntry]
    @Binding var selectedEntry: ServerVersionEntry?
    @Binding var isPresented: Bool

    @State private var tab: VersionTab = .stable

    enum VersionTab: String, CaseIterable, Identifiable {
        case stable = "Stable"
        case experimental = "Experimental"
        var id: String { rawValue }
    }

    private var hasExperimental: Bool { versions.contains(where: { !$0.isStable }) }
    private var visibleVersions: [ServerVersionEntry] {
        switch tab {
        case .stable:       return versions.filter { $0.isStable }
        case .experimental: return versions.filter { !$0.isStable }
        }
    }

    // "Latest (recommended)" row with actual version+build info from the first stable entry.
    private var latestEntry: ServerVersionEntry {
        let first = versions.first(where: { $0.isStable }) ?? versions.first
        guard let first else { return ServerVersionEntry.latest }
        var label = first.mcVersion
        if let bl = first.buildLabel { label += " · \(bl)" }
        return ServerVersionEntry(id: "__latest__", displayLabel: "Latest (recommended)",
                                  mcVersion: first.mcVersion, loaderVersion: first.loaderVersion,
                                  buildLabel: label, isStable: true)
    }

    var body: some View {
        VStack(spacing: 0) {
            MSCSheetHeader("Choose Version") { isPresented = false }
                .padding(.horizontal, MSC.Spacing.xl)
                .padding(.top, MSC.Spacing.xl)

            if hasExperimental {
                Picker("", selection: $tab) {
                    ForEach(VersionTab.allCases) { t in Text(t.rawValue).tag(t) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, MSC.Spacing.xl)
                .padding(.vertical, MSC.Spacing.sm)
            }

            Divider()

            if versions.isEmpty {
                VStack(spacing: MSC.Spacing.md) {
                    ProgressView()
                    Text("Loading versions…")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if tab == .stable {
                            versionRow(latestEntry)
                            Divider()
                        }
                        ForEach(visibleVersions) { entry in
                            versionRow(entry)
                            if entry.id != visibleVersions.last?.id {
                                Divider().padding(.leading, MSC.Spacing.xl)
                            }
                        }
                    }
                    .padding(.vertical, MSC.Spacing.sm)
                }
            }

            Divider()
            HStack {
                Spacer()
                Button("Done") { isPresented = false }
                    .buttonStyle(MSCPrimaryButtonStyle())
            }
            .padding(.horizontal, MSC.Spacing.xl)
            .padding(.vertical, MSC.Spacing.lg)
        }
        .frame(width: 420, height: 520)
    }

    @ViewBuilder
    private func versionRow(_ entry: ServerVersionEntry) -> some View {
        let isSelected = entry == selectedEntry || (entry.isLatest && selectedEntry == nil)
        Button {
            selectedEntry = entry.isLatest ? nil : entry
            isPresented = false
        } label: {
            HStack(spacing: MSC.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.displayLabel)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Color.accentColor : .primary)
                        if entry.isLatest {
                            Text("RECOMMENDED")
                                .font(.system(size: 8.5, weight: .semibold)).tracking(0.5)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Capsule().fill(Color.green.opacity(0.15)))
                                .foregroundStyle(.green)
                        }
                    }
                    if let bl = entry.buildLabel {
                        Text(bl)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, MSC.Spacing.sm)
            .padding(.horizontal, MSC.Spacing.xl)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.06) : Color.clear)
    }
}

//
//  ServerEditorView.swift
//  MinecraftServerController
//
//  Server editor for general settings, components, backups, worlds, and
//  platform-specific server options.
//

import SwiftUI
import AppKit

struct ServerEditorView: View {
    // MARK: - Tabs

    enum EditorTab: Hashable {
        case general
        case jars
        case backups
        case world
        case settings
        case broadcast
        case bedrockConnect
        case docker
    }

    // MARK: - Environment / Inputs

    @EnvironmentObject var viewModel: AppViewModel

    let mode: ServerEditorMode
    @Binding var data: ServerEditorData

    let onSave: (ServerEditorData) -> Void
    let onCancel: () -> Void

    let initialTab: EditorTab

    // MARK: - Local State

    @State var selectedTab: EditorTab

    // Backups
    @State var selectedBackupId: String?
    @State var showRestoreConfirm = false
    @State var showDuplicateSheet = false      // server-duplicate (existing)
    @State var newServerName: String = ""
    @State var autoBackupEnabledLocal: Bool = false

    // Per-server notification preferences used by the editor
    @State var notifOnStart: Bool = false
    @State var notifOnStop: Bool = false
    @State var notifOnJoin: Bool = false
    @State var notifOnLeave: Bool = false

    var selectedBackup: BackupItem? {
        guard let id = selectedBackupId else { return nil }
        return viewModel.backupItems.first(where: { $0.id == id })
    }

    // World tab — existing
    @State var replaceSourcePath: String = ""
    @State var renameWorldName: String = ""

    // World tab — P6 slot admin
    @State var selectedSlotForEditor: WorldSlot? = nil
        @State var showDuplicateSlotSheet: Bool = false
        @State var showSaveSlotSheet: Bool = false
        @State var duplicateSlotName: String = ""
        @State var importZIPPath: String = ""
        @State var importSlotName: String = ""
    @State var createWorldName: String = ""
    @State var createWorldSeed: String = ""
    @State var showCreateWorldSlotSheet: Bool = false
        @State var showSlotRenameId: String? = nil
        @State var slotRenameText: String = ""
        @State var showSlotDeleteConfirm: Bool = false
        @State var slotToDelete: WorldSlot? = nil

    // Settings tab
    @State var javaSettingsDraft: JavaServerSettingsDraft?
    @State var bedrockSettingsDraft: BedrockServerSettingsDraft?

    // Broadcast tab
    @State var broadcastEnabled: Bool = false
    @State var broadcastIPMode: XboxBroadcastIPMode = .auto
    @State var broadcastAltEmail: String = ""
    @State var broadcastAltGamertag: String = ""
    @State var broadcastAltPassword: String = ""
    @State var showBroadcastAltPassword: Bool = false
    @State var broadcastAvatarPath: String = ""
    @State var broadcastAvatarImage: NSImage?

    // HUD
    @State var showSaveHUD: Bool = false

    // Danger zone
    @State var showDeleteServerConfirm = false

    // MARK: - Custom inits

    init(
        mode: ServerEditorMode,
        data: Binding<ServerEditorData>,
        initialTab: EditorTab = .general,
        onSave: @escaping (ServerEditorData) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self._data = data
        self.initialTab = initialTab
        self.onSave = onSave
        self.onCancel = onCancel
        _selectedTab = State(initialValue: initialTab)
    }

    init(
        mode: ServerEditorMode,
        data: Binding<ServerEditorData>,
        onSave: @escaping (ServerEditorData) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.init(mode: mode, data: data, initialTab: .general, onSave: onSave, onCancel: onCancel)
    }

    // MARK: - Derived Helpers

    var editingConfigServer: ConfigServer? {
        viewModel.configServers.first(where: { $0.id == data.id })
    }

    var isSaveDisabled: Bool {
        let nameEmpty = data.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let dirEmpty  = data.serverDir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if nameEmpty || dirEmpty { return true }
        if data.serverType == .java {
            if Int(data.minRamGB) ?? 0 <= 0 { return true }
            if Int(data.maxRamGB) ?? 0 <= 0 { return true }
        }
        return false
    }

    var closeButtonTitle: String {
        mode == .edit ? "Done" : "Cancel"
    }

    var editorHasSavedServer: Bool {
        mode != .new && editingConfigServer != nil
    }

    var safeTab: EditorTab {
        if data.serverType == .bedrock {
            let bedrockTabs: Set<EditorTab> = [.general, .backups, .world, .settings, .bedrockConnect, .docker]
            return bedrockTabs.contains(selectedTab) ? selectedTab : .general
        }
        return selectedTab
    }

    @ViewBuilder
    var tabContent: some View {
        switch selectedTab {
        case .general:        generalTab
        case .jars:           jarsTab
        case .backups:        backupsTab
        case .world:          worldTab
        case .settings:       settingsTab
        case .broadcast:      broadcastTab
        case .bedrockConnect:
            if data.serverType == .java { bedrockConnectTab } else { consoleAccessTab }
        case .docker:         dockerTab
        }
    }

    var contextualHelpGuideIDs: Set<String> {
        [
            "server-editor.general",
            "server-editor.jars",
            "server-editor.backups",
            "server-editor.world",
            "server-editor.settings",
            "server-editor.broadcast",
            "server-editor.bedrock-connect.java",
            "server-editor.bedrock-connect.bedrock",
            "server-editor.docker"
        ]
    }

    var currentTabContentAnchorID: String {
        switch selectedTab {
        case .general: return "serverEditor.content.general"
        case .jars: return "serverEditor.content.jars"
        case .backups: return "serverEditor.content.backups"
        case .world: return "serverEditor.content.world"
        case .settings: return "serverEditor.content.settings"
        case .broadcast: return "serverEditor.content.broadcast"
        case .bedrockConnect:
            return data.serverType == .java
                ? "serverEditor.content.bedrockConnect.java"
                : "serverEditor.content.bedrockConnect.bedrock"
        case .docker: return "serverEditor.content.docker"
        }
    }

    var saveButtonAnchorID: String {
        "serverEditor.saveButton"
    }

    var worldSlotsAnchorID: String {
        "serverEditor.world.slots"
    }

    var worldImportAnchorID: String {
        "serverEditor.world.import"
    }

    var worldSaveCurrentAnchorID: String {
        "serverEditor.world.saveCurrent"
    }

    var worldReplaceAnchorID: String {
        "serverEditor.world.replace"
    }

    var settingsRuntimeAnchorID: String {
        "serverEditor.settings.bedrock.runtime"
    }

    var settingsGeneralAnchorID: String {
        data.serverType == .java ? "serverEditor.settings.java.general" : "serverEditor.settings.bedrock.general"
    }

    var settingsGameplayAnchorID: String {
        data.serverType == .java ? "serverEditor.settings.java.gameplay" : "serverEditor.settings.bedrock.gameplay"
    }

    var settingsNetworkAnchorID: String {
        data.serverType == .java ? "serverEditor.settings.java.network" : "serverEditor.settings.bedrock.network"
    }

    var settingsNotificationsAnchorID: String {
        "serverEditor.settings.notifications"
    }

    var currentContextualHelpGuide: ContextualHelpGuide {
        switch selectedTab {
        case .general:
            return generalHelpGuide
        case .jars:
            return jarsHelpGuide
        case .backups:
            return backupsHelpGuide
        case .world:
            return worldHelpGuide
        case .settings:
            return settingsHelpGuide
        case .broadcast:
            return broadcastHelpGuide
        case .bedrockConnect:
            return data.serverType == .java ? javaBedrockConnectHelpGuide : bedrockConsoleAccessHelpGuide
        case .docker:
            return dockerHelpGuide
        }
    }

    var generalHelpGuide: ContextualHelpGuide {
        let setupBody: String
        let saveBody: String

        if data.serverType == .java {
            setupBody = "Use General for the server's name, folder, memory, and notes. The Paper & Cross-play row is only a status snapshot; version changes belong in JARs."
            saveBody = "Name, folder, memory, and notes stay in this editor until you press Save. Danger Zone is separate and destructive once you confirm it."
        } else {
            setupBody = "Use General for the server's name, folder, and notes. Bedrock runtime packaging is handled elsewhere, so this tab stays focused on identity and storage."
            saveBody = "Name, folder, and notes stay in this editor until you press Save. Danger Zone is separate and destructive once you confirm it."
        }

        return ContextualHelpGuide(
            id: "server-editor.general",
            steps: [
                helpStep(
                    id: "general.scope",
                    title: "General is the admin-side setup hub",
                    body: "This tab covers core server identity and housekeeping. It is for setup and maintenance, not live day-to-day control.",
                    anchorID: tabAnchorID(.general)
                ),
                helpStep(
                    id: "general.decisions",
                    title: "Most edits here are planning changes",
                    body: setupBody,
                    anchorID: currentTabContentAnchorID
                ),
                helpStep(
                    id: "general.save",
                    title: "Save commits these editor fields",
                    body: saveBody,
                    anchorID: saveButtonAnchorID,
                    nextLabel: "Done"
                )
            ]
        )
    }

    var jarsHelpGuide: ContextualHelpGuide {
        let availabilityBody = editorHasSavedServer
            ? "Use JARs when you intentionally update Paper, Geyser, or Floodgate. Most servers only need this when you are changing versions or fixing missing components."
            : "This tab unlocks after the first Save. Once the server exists, use it for intentional Paper, Geyser, and Floodgate updates."

        let actionBody = editorHasSavedServer
            ? "Update from Template acts immediately on the saved server. The footer Save is not the commit step for those update buttons."
            : "Save this server once before expecting JAR actions to work. After that, update buttons act immediately."

        return ContextualHelpGuide(
            id: "server-editor.jars",
            steps: [
                helpStep(
                    id: "jars.scope",
                    title: "JARs is the Java runtime/components tab",
                    body: "This tab exists only for Java servers. It is where Paper and cross-play support are managed, not where you tune gameplay.",
                    anchorID: tabAnchorID(.jars)
                ),
                helpStep(
                    id: "jars.decisions",
                    title: "Only change components on purpose",
                    body: availabilityBody,
                    anchorID: currentTabContentAnchorID
                ),
                helpStep(
                    id: "jars.save",
                    title: "Component updates do not wait for Save",
                    body: actionBody,
                    anchorID: saveButtonAnchorID,
                    nextLabel: "Done"
                )
            ]
        )
    }

    var backupsHelpGuide: ContextualHelpGuide {
        let availabilityBody = editorHasSavedServer
            ? "Auto-Backup is rolling protection, Back Up Now is the manual snapshot path, and Cleanup is for reclaiming space when you need it."
            : "Backups unlock after the first Save. Once the server exists, this tab becomes the safety snapshot and cleanup surface."

        return ContextualHelpGuide(
            id: "server-editor.backups",
            steps: [
                helpStep(
                    id: "backups.scope",
                    title: "Backups is the safety-snapshot tab",
                    body: "Use this tab when you want restore points before risky changes, imports, or maintenance work.",
                    anchorID: tabAnchorID(.backups)
                ),
                helpStep(
                    id: "backups.decisions",
                    title: "Think protection first, cleanup second",
                    body: availabilityBody,
                    anchorID: currentTabContentAnchorID
                ),
                helpStep(
                    id: "backups.save",
                    title: "Backup actions run immediately",
                    body: "Auto-Backup, Back Up Now, and Prune act as soon as you click or toggle them. The footer Save is not the commit step here, and stopping the server first gives the cleanest snapshot.",
                    anchorID: saveButtonAnchorID,
                    nextLabel: "Done"
                )
            ]
        )
    }

    var worldHelpGuide: ContextualHelpGuide {
        if !editorHasSavedServer {
            return ContextualHelpGuide(
                id: "server-editor.world",
                steps: [
                    helpStep(
                        id: "world.scope",
                        title: "World is the world-state management tab",
                        body: "Use this tab when you are preserving, swapping, importing, or restoring actual world data.",
                        anchorID: tabAnchorID(.world)
                    ),
                    helpStep(
                        id: "world.availability",
                        title: "World tools unlock after the first Save",
                        body: "Once the server exists, this tab becomes the slot, import, backup, replace, and rename workspace for world data.",
                        anchorID: currentTabContentAnchorID
                    ),
                    helpStep(
                        id: "world.saveFirst",
                        title: "Save the server first, then come back here",
                        body: "The footer Save creates the server record itself. After that, the world tools in this tab work directly on disk when you trigger them.",
                        anchorID: saveButtonAnchorID,
                        nextLabel: "Done"
                    )
                ]
            )
        }

        return ContextualHelpGuide(
            id: "server-editor.world",
            steps: [
                helpStep(
                    id: "world.scope",
                    title: "World is where you manage reusable world states",
                    body: "Think in slots first. The live world is whatever is currently active; slots are saved copies you can activate, duplicate, export, or delete.",
                    anchorID: tabAnchorID(.world)
                ),
                helpStep(
                    id: "world.demoSlot",
                    title: "Start with a temporary test slot",
                    body: "For a first walkthrough, stop the server, click Create New World, and make a temporary slot like Tour Demo. After you work in it, Save Current World updates that same slot instead of creating duplicates.",
                    anchorID: worldSaveCurrentAnchorID
                ),
                helpStep(
                    id: "world.slotLibrary",
                    title: "That test slot becomes your practice target",
                    body: "After the dummy slot appears, click its card to select it. The slot cards are your reusable world library, and the selected card is the one this tab's slot actions will work with.",
                    anchorID: worldSlotsAnchorID
                ),
                helpStep(
                    id: "world.backup",
                    title: "Back up the test slot before experimenting",
                    body: "Once a slot is selected, this tab shows its slot-specific backup area. Use Back Up Now there to make a restore point for the dummy slot before imports, replacements, or other tests.",
                    anchorID: currentTabContentAnchorID
                ),
                helpStep(
                    id: "world.importVsReplace",
                    title: "Import and replace solve different problems",
                    body: "Import ZIP as New Slot brings in outside worlds safely as new slots. Replace World swaps the live world folder, and Rename World changes the live folder name plus level-name together.",
                    anchorID: worldImportAnchorID
                ),
                helpStep(
                    id: "world.cleanup",
                    title: "Finish by deleting the dummy slot",
                    body: "When you are done learning, click the practice slot's trash button and confirm deletion. That removes the test evidence and leaves your normal world library clean.",
                    anchorID: worldSlotsAnchorID,
                    nextLabel: "Done"
                )
            ]
        )
    }

    var settingsHelpGuide: ContextualHelpGuide {
        if !editorHasSavedServer {
            return ContextualHelpGuide(
                id: "server-editor.settings",
                steps: [
                    helpStep(
                        id: "settings.scope",
                        title: "Settings is for deeper server behavior",
                        body: "Come here when you want to change how the server behaves, not just what it is called or where it lives on disk.",
                        anchorID: tabAnchorID(.settings)
                    ),
                    helpStep(
                        id: "settings.availability",
                        title: "This tab fills in after the first Save",
                        body: "Server Properties and per-server notifications load only after the server exists. Until then, Save is the step that creates the server record.",
                        anchorID: currentTabContentAnchorID
                    ),
                    helpStep(
                        id: "settings.saveFirst",
                        title: "Save first, then return for deeper tuning",
                        body: "After the first Save, this tab becomes the place to tune gameplay, networking, and app-side alerts for this server.",
                        anchorID: saveButtonAnchorID,
                        nextLabel: "Done"
                    )
                ]
            )
        }

        if data.serverType == .java {
            return ContextualHelpGuide(
                id: "server-editor.settings",
                steps: [
                    helpStep(
                        id: "settings.scope",
                        title: "Settings is the deeper behavior tab",
                        body: "This is where you tune how the server behaves once the basic setup is already in place.",
                        anchorID: tabAnchorID(.settings)
                    ),
                    helpStep(
                        id: "settings.java.general",
                        title: "General covers identity and access basics",
                        body: "This block is for MOTD, max players, and Online Mode status. Java Online Mode is enforced on here, so treat it as a locked status rather than a normal toggle.",
                        anchorID: settingsGeneralAnchorID
                    ),
                    helpStep(
                        id: "settings.java.gameplay",
                        title: "Gameplay controls the feel of the server",
                        body: "Difficulty, gamemode, and view distance live here. These are the main knobs for how demanding or casual the world feels to players.",
                        anchorID: settingsGameplayAnchorID
                    ),
                    helpStep(
                        id: "settings.java.network",
                        title: "Network is where join-path ports live",
                        body: "Server Port is the Java TCP port. Bedrock/Geyser Port is the UDP side for cross-play. Only change ports here if you are also ready to update forwarding and join instructions.",
                        anchorID: settingsNetworkAnchorID
                    ),
                    helpStep(
                        id: "settings.notifications",
                        title: "Notifications are app alerts, not server.properties",
                        body: "These toggles only control macOS notifications for this server. They save immediately as you switch them.",
                        anchorID: settingsNotificationsAnchorID
                    ),
                    helpStep(
                        id: "settings.save",
                        title: "Server properties wait for Save",
                        body: "Changes in the General, Gameplay, and Network blocks stay local until you press Save. Notifications do not wait for the footer Save.",
                        anchorID: saveButtonAnchorID,
                        nextLabel: "Done"
                    )
                ]
            )
        }

        return ContextualHelpGuide(
            id: "server-editor.settings",
            steps: [
                helpStep(
                    id: "settings.scope",
                    title: "Settings is the deeper behavior tab",
                    body: "This is where you tune Bedrock behavior once the basic server setup already exists.",
                    anchorID: tabAnchorID(.settings)
                ),
                helpStep(
                    id: "settings.bedrock.runtime",
                    title: "Runtime controls the Bedrock image version",
                    body: "Docker Image is reference info. Pinned Version writes immediately when you change it, and Running Version is status only.",
                    anchorID: settingsRuntimeAnchorID
                ),
                helpStep(
                    id: "settings.bedrock.general",
                    title: "General covers world identity and permissions",
                    body: "Use this block for level name, max players, Online Mode, and Allow Cheats.",
                    anchorID: settingsGeneralAnchorID
                ),
                helpStep(
                    id: "settings.bedrock.gameplay",
                    title: "Gameplay sets how the Bedrock world feels",
                    body: "Difficulty and gamemode live here. This is the quick place to decide whether the world is relaxed, survival-focused, or creative.",
                    anchorID: settingsGameplayAnchorID
                ),
                helpStep(
                    id: "settings.bedrock.network",
                    title: "Network is UDP-only on Bedrock",
                    body: "Server Port and IPv6 Port are both Bedrock UDP join ports. If you change them, update your forwarding and client join instructions too.",
                    anchorID: settingsNetworkAnchorID
                ),
                helpStep(
                    id: "settings.notifications",
                    title: "Notifications are app alerts, not bedrock_server.properties",
                    body: "These toggles only control macOS notifications for this server. They save immediately as you switch them.",
                    anchorID: settingsNotificationsAnchorID
                ),
                helpStep(
                    id: "settings.save",
                    title: "Properties and runtime controls do not save the same way",
                    body: "General, Gameplay, and Network property edits wait for the footer Save. Pinned Version and notification toggles do not.",
                    anchorID: saveButtonAnchorID,
                    nextLabel: "Done"
                )
            ]
        )
    }

    var broadcastHelpGuide: ContextualHelpGuide {
        let availabilityBody = editorHasSavedServer
            ? "Use this only if you want Xbox-friendly discovery. Host and IP Mode affect how the helper advertises your server, while the alt-account section is local notes only."
            : "Broadcast unlocks after the first Save. Once the server exists, this is the optional Java-side helper for Xbox-friendly discovery."

        return ContextualHelpGuide(
            id: "server-editor.broadcast",
            steps: [
                helpStep(
                    id: "broadcast.scope",
                    title: "Broadcast is an optional Java helper tab",
                    body: "This is not required for every server. It is only for the broadcast helper flow that exposes your Bedrock join target more cleanly to Xbox players.",
                    anchorID: tabAnchorID(.broadcast)
                ),
                helpStep(
                    id: "broadcast.decisions",
                    title: "Treat the helper and notes separately",
                    body: availabilityBody,
                    anchorID: currentTabContentAnchorID
                ),
                helpStep(
                    id: "broadcast.save",
                    title: "Profile fields wait for Save",
                    body: "Enable, IP Mode, and alt-account fields stay in the editor until you press Save. Download and folder-opening actions run immediately.",
                    anchorID: saveButtonAnchorID,
                    nextLabel: "Done"
                )
            ]
        )
    }

    var javaBedrockConnectHelpGuide: ContextualHelpGuide {
        return ContextualHelpGuide(
            id: "server-editor.bedrock-connect.java",
            steps: [
                helpStep(
                    id: "bedrockConnectJava.scope",
                    title: "Bedrock Connect is a shared console-access service",
                    body: "On Java servers, this tab explains the global Bedrock Connect service and how this server contributes its host and Bedrock port to the generated console list.",
                    anchorID: tabAnchorID(.bedrockConnect)
                ),
                helpStep(
                    id: "bedrockConnectJava.decisions",
                    title: "Most rows here are global or derived",
                    body: "The service and DNS settings are shared across servers. The host and Bedrock port shown for this server are previews driven by Broadcast and Server Settings.",
                    anchorID: currentTabContentAnchorID
                ),
                helpStep(
                    id: "bedrockConnectJava.save",
                    title: "DNS changes save immediately",
                    body: "The DNS port field writes to app config as soon as you change it, and Download/Open actions also run immediately. The footer Save does not control those global actions.",
                    anchorID: saveButtonAnchorID,
                    nextLabel: "Done"
                )
            ]
        )
    }

    var bedrockConsoleAccessHelpGuide: ContextualHelpGuide {
        let scopeBody = editorHasSavedServer
            ? "On Bedrock servers, this tab still controls the shared Bedrock Connect service. This server's host and Bedrock port simply feed the list console players will see."
            : "On Bedrock servers, this tab can still configure the shared Bedrock Connect service before the server is saved. The per-server listing becomes meaningful once this server has a saved host and Bedrock port."

        return ContextualHelpGuide(
            id: "server-editor.bedrock-connect.bedrock",
            steps: [
                helpStep(
                    id: "bedrockConnectBedrock.scope",
                    title: "Bedrock Connect is still a global service",
                    body: scopeBody,
                    anchorID: tabAnchorID(.bedrockConnect)
                ),
                helpStep(
                    id: "bedrockConnectBedrock.decisions",
                    title: "Console DNS lives here; server behavior does not",
                    body: "Use this tab for the shared console-join pathway. Bedrock gameplay and normal server settings still belong in the other Edit Server tabs.",
                    anchorID: currentTabContentAnchorID
                ),
                helpStep(
                    id: "bedrockConnectBedrock.save",
                    title: "DNS changes save immediately",
                    body: "The DNS port field writes to app config as soon as you change it, and Download/Open actions also run immediately. The footer Save is only for normal editor fields elsewhere.",
                    anchorID: saveButtonAnchorID,
                    nextLabel: "Done"
                )
            ]
        )
    }

    var dockerHelpGuide: ContextualHelpGuide {
        return ContextualHelpGuide(
            id: "server-editor.docker",
            steps: [
                helpStep(
                    id: "docker.scope",
                    title: "Docker is the Bedrock packaging/reference tab",
                    body: "This tab is about how the Bedrock server is packaged and version-pinned, not about live server control.",
                    anchorID: tabAnchorID(.docker)
                ),
                helpStep(
                    id: "docker.decisions",
                    title: "Use it to confirm image and version",
                    body: "This is mainly an admin reference surface. Start, stop, and logs still belong in the live Details workspace.",
                    anchorID: currentTabContentAnchorID
                ),
                helpStep(
                    id: "docker.save",
                    title: "This tab is mostly informational today",
                    body: "The footer Save does not update the Docker image. Version and image update work belongs in Details → Components.",
                    anchorID: saveButtonAnchorID,
                    nextLabel: "Done"
                )
            ]
        )
    }

    func presentContextualHelp() {
        ContextualHelpManager.shared.start(currentContextualHelpGuide)
    }

    func helpStep(
        id: String,
        title: String,
        body: String,
        anchorID: String?,
        nextLabel: String = "Next"
    ) -> ContextualHelpStep {
        ContextualHelpStep(
            id: id,
            title: title,
            body: body,
            anchorID: anchorID,
            nextLabel: nextLabel
        )
    }

    func tabAnchorID(_ tab: EditorTab) -> String {
        switch tab {
        case .general: return "serverEditor.tab.general"
        case .jars: return "serverEditor.tab.jars"
        case .backups: return "serverEditor.tab.backups"
        case .world: return "serverEditor.tab.world"
        case .settings: return "serverEditor.tab.settings"
        case .broadcast: return "serverEditor.tab.broadcast"
        case .bedrockConnect: return "serverEditor.tab.bedrockConnect"
        case .docker: return "serverEditor.tab.docker"
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            editorHeader
            tabBar

            ScrollView {
                tabContent
                    .padding(MSC.Spacing.xl)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .contextualHelpAnchor(currentTabContentAnchorID)
            }
            .frame(maxHeight: .infinity)

            editorFooter
        }
        .frame(minWidth: 980, idealWidth: 980, maxWidth: 980,
               minHeight: 820, idealHeight: 820, maxHeight: 820)
        .overlay(alignment: .top) {
            if showSaveHUD {
                SaveHUDBanner(text: "Settings saved")
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: showSaveHUD)
        .onAppear {
            selectedTab = safeTab
            syncSelectedServerForEditing()
            if selectedTab == .backups { loadBackupsForEditingServer() }
            if selectedTab == .world   { loadWorldDataForEditingServer() }
            loadSettingsDraftsForEditingServer()
            loadBroadcastFieldsFromConfig()
        }
        .onChange(of: selectedTab) { newValue in
            if newValue == .backups { loadBackupsForEditingServer() }
            if newValue == .world   { loadWorldDataForEditingServer() }
        }
        .onChange(of: editingConfigServer?.id) { _ in
            if selectedTab == .world { loadWorldDataForEditingServer() }
            loadSettingsDraftsForEditingServer()
        }
        // Restore backup alert
        .alert("Restore Backup?",
               isPresented: $showRestoreConfirm,
               presenting: selectedBackup) { backup in
            Button("Restore", role: .destructive) { viewModel.restoreBackup(backup) }
            Button("Cancel", role: .cancel) { }
        } message: { backup in
            Text("Are you sure you want to restore from \"\(backup.displayName)\"? This will overwrite the current world folders for the active server.")
        }
        // Server duplicate sheet (existing — not slot duplicate)
                .sheet(isPresented: $showDuplicateSheet) { duplicateSheet }
                // Slot duplicate sheet
                .sheet(isPresented: $showDuplicateSlotSheet) { duplicateSlotSheetView }
                // Delete server confirmation
                .confirmationDialog("Delete Server from Disk?",
                                    isPresented: $showDeleteServerConfirm,
                                    titleVisibility: .visible) {
                    if let cfg = editingConfigServer {
                        Button("Delete \"\(cfg.displayName)\" and remove from disk", role: .destructive) {
                            deleteServerFolderAndConfig(for: cfg)
                        }
                    }
                    Button("Cancel", role: .cancel) { }
                }
                // Slot delete confirmation
                                    .confirmationDialog("Delete World Slot?",
                                                        isPresented: $showSlotDeleteConfirm,
                                                        titleVisibility: .visible) {
                                        if let slot = slotToDelete {
                                            Button("Delete \"\(slot.name)\"", role: .destructive) {
                                                guard let cfg = editingConfigServer else { return }
                                                Task { await viewModel.deleteWorldSlot(slot) }
                                            }
                                        }
                                        Button("Cancel", role: .cancel) { }
                                    }
                            .contextualHelpHost(guideIDs: contextualHelpGuideIDs)
                        }

    // MARK: - Header

    var editorHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: MSC.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 38, height: 38)
                    Image(systemName: mode == .new ? "plus.app.fill" : "server.rack")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode == .new ? "Add Server" : "Edit Server")
                        .font(MSC.Typography.pageTitle)
                    if mode == .edit, let cfg = editingConfigServer {
                        Text(cfg.displayName.isEmpty ? "No name set" : cfg.displayName)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    presentContextualHelp()
                } label: {
                    Label("Explain this tab", systemImage: "questionmark.circle")
                }
                .buttonStyle(MSCSecondaryButtonStyle())
                .help("Explains only the currently selected Edit Server tab.")
            }
            .padding(.horizontal, MSC.Spacing.xxl)
            .padding(.top, MSC.Spacing.xxxl)
            .padding(.bottom, MSC.Spacing.lg)

            Divider()
        }
    }

    // MARK: - Tab Bar

    var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                SETabButton(icon: "gearshape.fill",      label: "General",   tab: .general,   selected: $selectedTab)
                    .contextualHelpAnchor(tabAnchorID(.general))

                if data.serverType == .java {
                    SETabButton(icon: "shippingbox.fill",    label: "JARs",      tab: .jars,      selected: $selectedTab)
                        .contextualHelpAnchor(tabAnchorID(.jars))
                }

                SETabButton(icon: "archivebox.fill",     label: "Backups",   tab: .backups,   selected: $selectedTab)
                    .contextualHelpAnchor(tabAnchorID(.backups))
                SETabButton(icon: "globe",               label: "World",     tab: .world,     selected: $selectedTab)
                    .contextualHelpAnchor(tabAnchorID(.world))
                SETabButton(icon: "slider.horizontal.3", label: "Settings",  tab: .settings,  selected: $selectedTab)
                    .contextualHelpAnchor(tabAnchorID(.settings))

                if data.serverType == .java {
                    SETabButton(icon: "dot.radiowaves.left.and.right", label: "Broadcast",       tab: .broadcast,      selected: $selectedTab)
                        .contextualHelpAnchor(tabAnchorID(.broadcast))
                    SETabButton(icon: "gamecontroller.fill",           label: "Bedrock Connect", tab: .bedrockConnect, selected: $selectedTab)
                        .contextualHelpAnchor(tabAnchorID(.bedrockConnect))
                }

                if data.serverType == .bedrock {
                    SETabButton(icon: "gamecontroller.fill", label: "Bedrock Connect", tab: .bedrockConnect, selected: $selectedTab)
                        .contextualHelpAnchor(tabAnchorID(.bedrockConnect))
                    SETabButton(icon: "shippingbox.fill",    label: "Docker",          tab: .docker,         selected: $selectedTab)
                        .contextualHelpAnchor(tabAnchorID(.docker))
                }
            }
            .padding(.horizontal, MSC.Spacing.xl)
            .padding(.vertical, MSC.Spacing.sm)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Footer

    var editorFooter: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: MSC.Spacing.md) {
                Button(closeButtonTitle, action: onCancel)
                    .buttonStyle(MSCSecondaryButtonStyle())

                Spacer()

                Button("Save") {
                    do {
                        try saveSettingsDraftIfNeeded()
                    } catch {
                        viewModel.showError(title: "Settings Save Failed", message: error.localizedDescription)
                        return
                    }

                    onSave(data)

                    if let cfg = editingConfigServer {
                        viewModel.updateBroadcastProfile(
                            for: cfg.id,
                            enabled: broadcastEnabled,
                            ipMode: broadcastIPMode,
                            altEmail: broadcastAltEmail,
                            altGamertag: broadcastAltGamertag,
                            altPassword: broadcastAltPassword,
                            altAvatarPath: broadcastAvatarPath
                        )
                    }

                    withAnimation { showSaveHUD = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        withAnimation { showSaveHUD = false }
                    }
                }
                .buttonStyle(MSCPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(isSaveDisabled)
                .contextualHelpAnchor(saveButtonAnchorID)
            }
            .padding(.horizontal, MSC.Spacing.xxl)
            .padding(.vertical, MSC.Spacing.lg)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Server Duplicate Sheet (existing — not slot duplicate)

    var duplicateSheet: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {
            Text("Create New Server from Backup")
                .font(.system(size: 16, weight: .bold))

            if let backup = selectedBackup {
                Text("Source: \(backup.displayName)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            TextField("New server display name", text: $newServerName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") { showDuplicateSheet = false }
                    .buttonStyle(MSCSecondaryButtonStyle())
                Button("Create") {
                    if let backup = selectedBackup {
                        viewModel.duplicateBackupToNewServer(from: backup, newDisplayName: newServerName)
                    }
                    showDuplicateSheet = false
                }
                .buttonStyle(MSCPrimaryButtonStyle())
                .disabled(newServerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(MSC.Spacing.xl)
        .frame(minWidth: 400)
    }

   
    // MARK: - Formatting Helpers

        func timeString(from date: Date?) -> String {
            guard let date else { return "—" }
            let f = DateFormatter(); f.dateFormat = "h:mm a"
            return f.string(from: date)
        }

        func shortDate(_ date: Date) -> String {
            let f = DateFormatter()
            f.dateStyle = .short
            f.timeStyle = .none
            return f.string(from: date)
        }

        func formatBytes(_ bytes: Int64) -> String {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return formatter.string(fromByteCount: bytes)
        }

        // MARK: - Helpers

        func crossPlayLabel(for cfg: ConfigServer) -> String {
        let fm = FileManager.default
        let pluginsDir = URL(fileURLWithPath: cfg.serverDir, isDirectory: true)
            .appendingPathComponent("plugins", isDirectory: true)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: pluginsDir.path, isDirectory: &isDir), isDir.boolValue else { return "Disabled" }
        let contents: [URL]
        do { contents = try fm.contentsOfDirectory(at: pluginsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) }
        catch { return "Unknown" }
        let names = contents.filter { $0.pathExtension.lowercased() == "jar" }.map { $0.lastPathComponent.lowercased() }
        let hasGeyser    = names.contains { $0.contains("geyser") }
        let hasFloodgate = names.contains { $0.contains("floodgate") }
        switch (hasGeyser, hasFloodgate) {
        case (true, true):   return "Enabled (Geyser + Floodgate)"
        case (true, false):  return "Partial (Geyser only)"
        case (false, true):  return "Partial (Floodgate only)"
        default:             return "Disabled"
        }
    }

    func crossPlayLabelColor(for cfg: ConfigServer) -> Color {
        let label = crossPlayLabel(for: cfg)
        if label.hasPrefix("Enabled") { return .green }
        if label.hasPrefix("Partial") { return .orange }
        return .secondary
    }

    func loadBroadcastFieldsFromConfig() {
        guard let cfg = editingConfigServer else { return }
        broadcastEnabled     = cfg.xboxBroadcastEnabled
        broadcastIPMode      = cfg.xboxBroadcastIPMode
        broadcastAltEmail    = cfg.xboxBroadcastAltEmail ?? ""
        broadcastAltGamertag = cfg.xboxBroadcastAltGamertag ?? ""
        broadcastAltPassword = cfg.xboxBroadcastAltPassword ?? ""
        if let path = cfg.xboxBroadcastAltAvatarPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            broadcastAvatarPath  = path
            broadcastAvatarImage = NSImage(contentsOf: URL(fileURLWithPath: path))
        } else {
            broadcastAvatarPath  = ""
            broadcastAvatarImage = nil
        }
    }

    func ipModeCaption(for mode: XboxBroadcastIPMode) -> String {
        switch mode {
        case .auto:      return "DuckDNS -> public IP -> private IP (recommended)"
        case .publicIP:  return "Use your router's public IP -- for players outside your home Wi-Fi"
        case .privateIP: return "Use your local LAN IP -- only players on the same Wi-Fi"
        }
    }

    func avatarInitial(for gamertag: String) -> String {
        let t = gamertag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = t.first else { return "?" }
        return String(first).uppercased()
    }

    // MARK: - Notification prefs helpers

    @ViewBuilder
    func notifToggleRow(label: String,
                                isOn: Binding<Bool>,
                                onChange: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: MSC.Spacing.sm) {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .onChange(of: isOn.wrappedValue, perform: onChange)
            Text(label)
                .font(.system(size: 12, weight: .medium))
            Spacer()
        }
    }

    func loadSettingsDraftsForEditingServer() {
        guard mode == .edit, let cfg = editingConfigServer else {
            javaSettingsDraft = nil
            bedrockSettingsDraft = nil
            return
        }

        let javaModel = viewModel.loadServerPropertiesModel(for: cfg)
        javaSettingsDraft = JavaServerSettingsDraft(
            model: javaModel,
            bedrockPortText: javaModel.bedrockPort.map(String.init) ?? ""
        )

        let bedrockModel = viewModel.bedrockPropertiesModel(for: cfg)
        bedrockSettingsDraft = BedrockServerSettingsDraft(
            model: bedrockModel,
            bedrockPortV6Text: String(bedrockModel.serverPortV6)
        )
    }

    func saveSettingsDraftIfNeeded() throws {
        guard mode == .edit, let cfg = editingConfigServer else { return }

        if cfg.isJava, let javaSettingsDraft {
            switch ServerSettingsView.validatedJavaModel(from: javaSettingsDraft) {
            case .success(let validatedModel):
                try viewModel.saveServerPropertiesModel(validatedModel, for: cfg)
                self.javaSettingsDraft = JavaServerSettingsDraft(
                    model: validatedModel,
                    bedrockPortText: validatedModel.bedrockPort.map(String.init) ?? ""
                )
            case .failure(let message):
                throw NSError(domain: "ServerEditorSettings", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
            }
        }

        if cfg.isBedrock, let bedrockSettingsDraft {
            switch ServerSettingsView.validatedBedrockModel(from: bedrockSettingsDraft) {
            case .success(let validatedModel):
                try viewModel.saveBedrockPropertiesModel(validatedModel, for: cfg)
                self.bedrockSettingsDraft = BedrockServerSettingsDraft(
                    model: validatedModel,
                    bedrockPortV6Text: String(validatedModel.serverPortV6)
                )
            case .failure(let message):
                throw NSError(domain: "ServerEditorSettings", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
            }
        }
    }

    func saveNotifPrefs(for server: ConfigServer) {
        let prefs = ServerNotificationPrefs(
            notifyOnStart:       notifOnStart,
            notifyOnStop:        notifOnStop,
            notifyOnPlayerJoin:  notifOnJoin,
            notifyOnPlayerLeave: notifOnLeave
        )
        viewModel.setNotificationPrefs(prefs, forServerId: server.id)
    }

    func syncSelectedServerForEditing() {
        guard mode == .edit, let cfg = editingConfigServer else { return }
        if let uiServer = viewModel.servers.first(where: { $0.id == cfg.id }) {
            viewModel.selectedServer = uiServer
        }
    }

    func loadBackupsForEditingServer() {
        guard mode == .edit, let server = editingConfigServer else { return }
        syncSelectedServerForEditing()
        viewModel.loadBackupsForSelectedServer()
        autoBackupEnabledLocal = server.autoBackupEnabled

        let prefs = server.notificationPrefs
        notifOnStart  = prefs.notifyOnStart
        notifOnStop   = prefs.notifyOnStop
        notifOnJoin   = prefs.notifyOnPlayerJoin
        notifOnLeave  = prefs.notifyOnPlayerLeave
    }

    func loadWorldDataForEditingServer() {
        guard mode == .edit, let _ = editingConfigServer else { return }
        syncSelectedServerForEditing()
        viewModel.loadWorldSlotsForSelectedServer()
        viewModel.loadBackupsForSelectedServer()
    }

    func deleteServerFolderAndConfig(for cfg: ConfigServer) {
        do {
            try viewModel.deleteServerFromDisk(withId: cfg.id)
            onCancel()
        } catch {
            viewModel.logAppMessage("[Server] Failed to delete server folder at \(cfg.serverDir): \(error.localizedDescription)")
        }
    }

    // MARK: - File Pickers

    func exportSlot(_ slot: WorldSlot, cfg: ConfigServer) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = slot.name + ".zip"
        panel.allowedFileTypes = ["zip"]
        panel.prompt = "Export"
        if panel.runModal() == .OK, let url = panel.url {
            Task { await viewModel.exportWorldSlot(slot, to: url) }
        }
    }

    func browseForImportZIP() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowedFileTypes = ["zip"]
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            importZIPPath = url.path
            if importSlotName.isEmpty {
                importSlotName = url.deletingPathExtension().lastPathComponent
            }
        }
    }

    func browseForBroadcastAvatar() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowedFileTypes = ["png","jpg","jpeg","heic","gif"]; panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            broadcastAvatarPath  = url.path
            broadcastAvatarImage = NSImage(contentsOf: url)
        }
    }

    func browseForServerDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.canCreateDirectories = true; panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { data.serverDir = url.path }
    }

    func browseForReplaceSourceZip() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.allowedFileTypes = ["zip"]; panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { replaceSourcePath = url.path }
    }

    func browseForReplaceSourceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { replaceSourcePath = url.path }
    }

    // MARK: - Save HUD

    struct SaveHUDBanner: View {
        let text: String
        var body: some View {
            HStack(spacing: MSC.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                Text(text).font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, MSC.Spacing.lg)
            .padding(.vertical, MSC.Spacing.sm)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .shadow(radius: 8)
        }
    }
}

// MARK: - Support views moved to ServerEditorSupportViews.swift


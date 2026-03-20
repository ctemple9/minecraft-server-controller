//
//  DetailsView.swift
//  MinecraftServerController
//
//  Main details workspace for the selected server.
//

import SwiftUI

struct DetailsView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @ObservedObject private var onboardingManager = OnboardingManager.shared
    @ObservedObject private var contextualHelpManager = ContextualHelpManager.shared

    // Only bindings still needed (sheets still owned by ContentView)
    @Binding var isShowingManageServers: Bool
    @Binding var isShowingPluginTemplates: Bool
    @Binding var isShowingPaperTemplate: Bool
    // Server banner color used for accent tinting in the header and tab strip
    let bannerColor: Color

    @State private var messageTarget: OnlinePlayer?
    @State private var messageText: String = ""
    @State private var selectedPlayerName: String? = nil
    @State private var serverNotesText: String = ""

    // Connection info visibility (single global toggle)
        @State private var showAddresses: Bool = false

    // DuckDNS behavior
    @State private var hasSavedDuckDNS: Bool = false
    @State private var isEditingDuckDNS: Bool = false

    // Copy-to-clipboard HUD feedback
    @State private var showCopiedHUD: Bool = false
    @State private var copiedHUDText: String = ""

    // Inner tabs
    enum DetailsInnerTab: Hashable {
        case overview
        case players
        case worlds
        case packs
        case performance
        case components
        case settings
                case files
            }

    @State private var detailsTab: DetailsInnerTab = .overview
    @State private var isShowingPerformanceHelp: Bool = false

    // Details workspace contextual help
    private let detailsWorkspaceGuideID = "details.workspace"
    private var detailsWorkspaceGuide: ContextualHelpGuide {
            ContextualHelpGuide(id: detailsWorkspaceGuideID, steps: [
                ContextualHelpStep(
                                id: "details.workspace.intro",
                                title: "Your Server Workspace",
                                body: "Everything about your running server lives here. Eight tabs cover status, players, worlds, performance, configuration, and your server files.",
                                anchorID: "details.tab.overview",
                                secondaryAnchorID: "details.tab.content",
                                nextLabel: "Next"
                            ),
                            ContextualHelpStep(
                                id: "details.workspace.overview",
                                title: "Overview Tab",
                                body: "Your live home base. Start/stop, connection info to share with friends, and a health snapshot.",
                                anchorID: "details.tab.overview",
                                secondaryAnchorID: "details.tab.content",
                                nextLabel: "Next"
                            ),
                            ContextualHelpStep(
                                id: "details.workspace.players",
                                title: "Players",
                                body: "Shows who is online and recent session history. Player-specific tools like messaging and banning live here too.",
                                anchorID: "details.tab.players",
                                secondaryAnchorID: "details.tab.content",
                                nextLabel: "Next"
                            ),
                            ContextualHelpStep(
                                id: "details.workspace.worlds",
                                title: "Worlds",
                                body: "Manage world slots, import a world ZIP, and browse backup history. You can keep multiple worlds and switch between them.",
                                anchorID: "details.tab.worlds",
                                secondaryAnchorID: "details.tab.content",
                                nextLabel: "Next"
                            ),
                            ContextualHelpStep(
                                id: "details.workspace.performance",
                                title: "Performance",
                                body: "TPS, RAM, CPU charts, and an overall health read. A quick way to know if your server is under stress.",
                                anchorID: "details.tab.performance",
                                secondaryAnchorID: "details.tab.content",
                                nextLabel: "Next"
                            ),
                            ContextualHelpStep(
                                id: "details.workspace.components",
                                title: "Components",
                                body: "Manage plugins, Bedrock Connect, and other server components. Versions and update checks live here.",
                                anchorID: "details.tab.components",
                                secondaryAnchorID: "details.tab.content",
                                nextLabel: "Next"
                            ),
                            ContextualHelpStep(
                                id: "details.workspace.settings",
                                title: "Settings",
                                body: "Change core server options — difficulty, gamemode, ports, and more. Nothing saves until you click Save Changes.",
                                anchorID: "details.tab.settings",
                                secondaryAnchorID: "details.tab.content",
                                nextLabel: "Next"
                            ),
                            ContextualHelpStep(
                                id: "details.workspace.files",
                                title: "Files",
                                body: "Browse every file in your server directory. Preview and edit configs, properties, and logs directly — no Finder required.",
                                anchorID: "details.tab.files",
                                secondaryAnchorID: "details.tab.content",
                                nextLabel: "Done"
                            ),
            ])
        }

        /// Maps a details workspace guide step ID to the tab it should display.
        private func detailsTabForGuideStep(_ stepID: String) -> DetailsInnerTab? {
            switch stepID {
            case "details.workspace.intro",
                 "details.workspace.overview":   return .overview
            case "details.workspace.players":    return .players
            case "details.workspace.worlds":     return .worlds
            case "details.workspace.performance": return .performance
            case "details.workspace.components": return .components
            case "details.workspace.settings":   return .settings
            case "details.workspace.files":      return .files
            default:                             return nil
            }
        }

    private var isBedrock: Bool {
        guard let s = viewModel.selectedServer else { return false }
        return viewModel.configServer(for: s)?.isBedrock ?? false
    }

    // MARK: - Tab definitions

    private var tabItems: [MSCTabItem<DetailsInnerTab>] {
            [
                MSCTabItem(.overview,     label: "Overview",    icon: "house",             onboardingAnchorID: .detailsOverviewTab,    contextualHelpAnchorID: "details.tab.overview"),
                MSCTabItem(.players,      label: "Players",     icon: "person.2",          onboardingAnchorID: .detailsPlayersTab,     contextualHelpAnchorID: "details.tab.players"),
                MSCTabItem(.worlds,       label: "Worlds",      icon: "globe",             onboardingAnchorID: .detailsWorldsTab,      contextualHelpAnchorID: "details.tab.worlds"),
                MSCTabItem(.packs,        label: "Packs",       icon: "shippingbox",       onboardingAnchorID: .detailsPacksTab,       contextualHelpAnchorID: "details.tab.packs"),
                MSCTabItem(.performance,  label: "Performance", icon: "waveform.path.ecg", onboardingAnchorID: .detailsPerformanceTab, contextualHelpAnchorID: "details.tab.performance"),
                MSCTabItem(.components,   label: "Components",  icon: "cpu",               onboardingAnchorID: .detailsComponentsTab,  contextualHelpAnchorID: "details.tab.components"),
                MSCTabItem(.settings,     label: "Settings",    icon: "gearshape",         onboardingAnchorID: .detailsSettingsTab,    contextualHelpAnchorID: "details.tab.settings"),
                                MSCTabItem(.files,        label: "Files",       icon: "folder",             onboardingAnchorID: .detailsFilesTab,       contextualHelpAnchorID: "details.tab.files"),
            ]
        }

    var body: some View {
        // Keep the outer container plain to avoid redundant framing.
        // The DetailsHeaderSectionView (Tier B chrome) sits flush at the top.
        // Tab strip + content are padded below it.
        VStack(alignment: .leading, spacing: 0) {

            // Full-width Tier B chrome header — handles own background and padding
            DetailsHeaderSectionView(
                isShowingManageServers: $isShowingManageServers,
                bannerColor: bannerColor
            )

            // Tab strip + content: padded working area
            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {

                MSCTabBar(tabs: tabItems, selection: $detailsTab, accentColor: bannerColor)
                    .onboardingAnchor(.detailsTabBar)

                // Tab content
                Group {
                    switch detailsTab {
                    case .overview:
                        DetailsOverviewTabView(
                            isEditingDuckDNS: $isEditingDuckDNS,
                            showCopiedHUD: $showCopiedHUD,
                            copiedHUDText: $copiedHUDText,
                            showAddresses: $showAddresses,
                            hasSavedDuckDNS: $hasSavedDuckDNS,
                            selectedPlayerName: $selectedPlayerName,
                            serverNotesText: $serverNotesText,
                            messageTarget: $messageTarget,
                            messageText: $messageText,
                            onOpenComponentsTab: { detailsTab = .components }
                        )

                    case .players:
                        DetailsPlayersTabView()

                    case .worlds:
                        DetailsWorldsTabView()

                    case .packs:
                        DetailsPacksTabView()

                    case .performance:
                        DetailsPerformanceTabView(isShowingPerformanceHelp: $isShowingPerformanceHelp)

                    case .components:
                        DetailsComponentsTabView()

                    case .settings:
                                            DetailsSettingsTabView(
                                                isShowingPluginTemplates: $isShowingPluginTemplates,
                                                isShowingPaperTemplate: $isShowingPaperTemplate
                                            )

                                        case .files:
                                            ServerFilesTabView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .onboardingAnchor(.detailsTabContent)
                                .contextualHelpAnchor("details.tab.content")
            }
            .padding(.horizontal, MSC.Spacing.lg)
            .padding(.top, MSC.Spacing.xs)
            .padding(.bottom, MSC.Spacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(MSC.Colors.tierAtmosphere)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $messageTarget) { player in
            MessagePlayerSheetView(
                player: player,
                messageTarget: $messageTarget,
                messageText: $messageText
            )
        }
        .sheet(isPresented: $isShowingPerformanceHelp) {
            PerformanceHelpSheetView(isShowingPerformanceHelp: $isShowingPerformanceHelp)
        }
        .sheet(
            isPresented: Binding(
                get: {
                    viewModel.showFirstStartAlert && !onboardingManager.isActive
                },
                set: { newValue in
                    if !newValue {
                        viewModel.showFirstStartAlert = false
                    }
                }
            )
        ) {
            FirstStartSheetView(isShowingManageServers: $isShowingManageServers)
        }
        .onChange(of: viewModel.triggerExplainWorkspace) { _, triggered in
            guard triggered else { return }
            ContextualHelpManager.shared.start(detailsWorkspaceGuide)
            viewModel.triggerExplainWorkspace = false
        }
        .onChange(of: contextualHelpManager.currentStepIndex) { _, _ in
            guard contextualHelpManager.currentGuide?.id == detailsWorkspaceGuideID,
                  let stepID = contextualHelpManager.currentStep?.id,
                  let targetTab = detailsTabForGuideStep(stepID),
                  detailsTab != targetTab else { return }
            withAnimation(MSC.Animation.tabSwitch) {
                detailsTab = targetTab
            }
        }
        .onAppear {
            let trimmed = viewModel.duckdnsInput
                .trimmingCharacters(in: .whitespacesAndNewlines)
            hasSavedDuckDNS = !trimmed.isEmpty
            syncDetailsTabForOnboardingStep(onboardingManager.currentStep)
        }
        .onChange(of: onboardingManager.currentStep) { _, newStep in
            syncDetailsTabForOnboardingStep(newStep)
        }
    }

    private func syncDetailsTabForOnboardingStep(_ step: OnboardingStep) {
        guard onboardingManager.isActive else { return }
        guard let targetTab = onboardingTab(for: step) else { return }
        guard detailsTab != targetTab else { return }

        withAnimation(.easeInOut(duration: 0.18)) {
            detailsTab = targetTab
        }
    }

    private func onboardingTab(for step: OnboardingStep) -> DetailsInnerTab? {
        switch step {
        case .acceptEula, .startButton, .console, .continueDetails, .expandDetails, .detailsOverviewTab, .portForwardGuide:
            return .overview
        case .detailsPlayersTab:
            return .players
        case .detailsWorldsTab:
            return .worlds
        case .detailsPacksTab:
            return .packs
        case .detailsPerformanceTab:
            return .performance
        case .detailsComponentsTab:
            return .components
        case .detailsSettingsTab:
            return .settings
        case .detailsFilesTab:
            return .files
        default:
            return nil
        }
    }
}


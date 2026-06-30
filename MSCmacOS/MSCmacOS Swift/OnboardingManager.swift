//
//  OnboardingManager.swift
//  MinecraftServerController
//
//  Drives the first-run server-creation tour.
//  Singleton — shared by OnboardingOverlayView and any view that needs to
//  broadcast its anchor frame or react to the active step.
//

import SwiftUI
import Combine

// MARK: - Onboarding Step

enum OnboardingStep: Int, CaseIterable {
    case welcome               = 0
    case manageServers         = 1
    case createServer          = 2
    case wizardChoosePath      = 3   // wizard Step 1: path picker
    case serverType            = 4
    case serverName            = 5
    case serverCategory        = 6   // configure: Standard vs Modded (Java, Next-driven)
    case serverFlavor          = 7   // configure: specific flavor (Java, Next-driven)
    case serverVersion         = 8   // configure: Source / version picker (Java, Next-driven)
    case serverCrossplay       = 9   // configure: Geyser+Floodgate (Java + crossplay-capable)
    case serverSettings          = 10  // configure: review + Continue
    case serverConnectivity        = 11  // network step: connectivity type cards
    case serverConnectivityPorts   = 12  // network step: port fields (Next button)
    case serverNetworkContinue     = 13  // network step: spotlight Continue button
    case firstWorld                = 14  // world page: card hides to let user fill, resumes on Continue
    case serverAddOns              = 15  // plugins/mods page (Java w/ add-on support)
    case createButton              = 16
    case dismissManage             = 17
    case acceptEula                = 18
    case startButton               = 19
    case console                   = 20
    case continueDetails           = 21
    case expandDetails             = 22
    case detailsOverviewTab        = 23
    case detailsPlayersTab         = 24
    case detailsWorldsTab          = 25
    case detailsPacksTab           = 26
    case detailsPerformanceTab     = 27
    case detailsComponentsTab      = 28
    case detailsSettingsTab        = 29
    case detailsFilesTab           = 30
    case done                      = 31

    var totalSteps: Int { OnboardingStep.allCases.count - 2 }

    var displayIndex: Int? {
        switch self {
        case .welcome, .done:
            return nil
        default:
            return rawValue
        }
    }

    var title: String {
        switch self {
        case .welcome:               return "Welcome to MSC"
        case .manageServers:         return "Your Server List"
        case .createServer:          return "Create a Server"
        case .wizardChoosePath:      return "Choose Your Path"
        case .serverName:            return "Name Your Server"
        case .serverType:            return "Pick a Type"
        case .serverCategory:        return "Standard or Modded?"
        case .serverFlavor:          return "Choose Your Software"
        case .serverVersion:         return "Pick a Version"
        case .serverCrossplay:       return "Bedrock Cross-play"
        case .serverSettings:          return "Review Your Settings"
        case .serverConnectivity:      return "How Will Friends Connect?"
        case .serverConnectivityPorts: return "Set Your Ports"
        case .serverNetworkContinue:   return "Ready to Continue"
        case .firstWorld:              return "Create Your First World"
        case .serverAddOns:            return "Add \(OnboardingManager.shared.tourAddOnNoun)"
        case .createButton:            return "Create It"
        case .dismissManage:         return "Back to Home"
        case .acceptEula:            return "Accept the EULA"
        case .startButton:           return "Start Your Server"
        case .console:               return "Watch It Boot"
        case .continueDetails:       return "Continue into Details?"
        case .expandDetails:         return "Make More Room"
        case .detailsOverviewTab:    return "Overview"
        case .detailsPlayersTab:     return "Players"
        case .detailsWorldsTab:      return "Worlds"
        case .detailsPacksTab:       return "Packs"
        case .detailsPerformanceTab: return "Performance"
        case .detailsComponentsTab:  return "Components"
        case .detailsSettingsTab:    return "Settings"
        case .detailsFilesTab:       return "Files"
        case .done:                  return "You're All Set 🎉"
        }
    }

    var body: String {
        switch self {
        case .welcome:
            return "Let's get your first Minecraft server online. This tour takes about two minutes — we'll do everything together."
        case .manageServers:
            return "This button opens your server list. Tap it to add your first server."
        case .createServer:
            return "Tap \"Add Server\u{2026}\" to open the server builder."
        case .wizardChoosePath:
            return "Start Fresh sets up a brand new server from scratch. It's already selected for you."
        case .serverName:
            return "Give your server a name. It's just a label for this controller — the world name is set on the next screen and can be different."
        case .serverType:
            return "Java is for PC players. Bedrock is for mobile, console, and Windows 10/11. Pick whichever fits — you can switch before creating."
        case .serverCategory:
            return "Standard servers run plugins and let normal Minecraft clients join. Modded servers add new content, but every player must install the same mods. Pick one, then tap Next."
        case .serverFlavor:
            if OnboardingManager.shared.tourFlavor.category == .modded {
                return "This is the mod loader your server runs on. Fabric is recommended — it's lightweight and great for performance mods. Every player needs the matching loader. Try the options, then tap Next."
            } else {
                return "This is the actual server software. Paper is recommended — it's fast and supports plugins. Try the options if you like, then tap Next."
            }
        case .serverVersion:
            return "We've set the latest version for you, which is best for most servers. You can pin a specific version here if you need one. Tap Next to continue."
        case .serverCrossplay:
            return "Turn this on to let Bedrock players — console, mobile, and Windows — join your Java server. MSC adds the Geyser and Floodgate plugins for you. Tap Next when you're set."
        case .serverSettings:
            if OnboardingManager.shared.tourServerType == .java {
                return "Everything's set. Tap Continue at the bottom to move on and set up how players connect."
            } else {
                return "Choose your Docker image and adjust the player limit if needed. The server port is set on the next step."
            }
        case .serverConnectivity:
            return "Choose how friends outside your network will join. Port Forwarding uses your router. Tunnel (playit.gg) works without any router access — a free relay service that adds ~10–50 ms."
        case .serverConnectivityPorts:
            return "These are the ports your server listens on. The defaults (25565 for Java, 19132 for Bedrock) work for most setups. Adjust them only if you need to run multiple servers."
        case .serverNetworkContinue:
            return "Your connectivity is configured. Tap Continue at the bottom to move on and set up your world."
        case .firstWorld:
            return "Choose \"New world\" for a fresh start, then set the world name, difficulty, game mode, and optional seed. You can add more worlds later from the Worlds tab, but only one world is active at a time."
        case .serverAddOns:
            let noun = OnboardingManager.shared.tourAddOnNoun.lowercased()
            return "Use Browse Modrinth to search and add \(noun) by name, or Import to add your own files. Not ready? You can skip this and add \(noun) anytime after the server is created. Tap Continue when you're done."
        case .createButton:
            return "Check the summary, give your server a display name, then tap Create Server to build it."
        case .dismissManage:
            return "Your server is ready! Click Done to return to the main screen."
        case .acceptEula:
            return "Minecraft requires you to accept the EULA before the server can start. Tap Accept EULA to agree."
        case .startButton:
            return "Your server is ready. Hit Start to bring it online for the first time."
        case .console:
            return "Watch here as your server boots. When you see \"Done!\" in the log — you're live and ready for players."
        case .continueDetails:
            return "Great — your server is up. Do you want to keep going and take a quick tour of the Details workspace?"
        case .expandDetails:
            return "Before we walk through the Details workspace, pull this divider down a bit to give the top section more room."
        case .detailsOverviewTab:
            return "Overview is your live home base. It gives you status, connection info, and a quick read on server health."
        case .detailsPlayersTab:
            return "Players shows who is online, recent session activity, and player-specific tools."
        case .detailsWorldsTab:
            return "Worlds is where you manage world slots, imports, and backups. This is also where you come later to add brand-new worlds, switch the active world, and keep per-world backups organized."
        case .detailsPacksTab:
            return "Packs is where you manage resource packs for this server."
        case .detailsPerformanceTab:
            return "Performance gives you a quick view of TPS, memory, CPU, and overall server health."
        case .detailsComponentsTab:
            if OnboardingManager.shared.tourServerType == .java {
                return "Components is where you manage Paper, plugins, and Xbox Broadcast."
            } else {
                return "Components is where you manage the Bedrock runtime, image version, and Xbox Broadcast tools."
            }
        case .detailsSettingsTab:
            return "Settings is where you change core server options. Changes stay local here until you click Save Changes."
        case .detailsFilesTab:
            return "Files lets you browse and preview every file in your server directory — configs, logs, world data, and more. You can also edit text files directly from here."
        case .done:
            return "Your server is running. Local players can join now, and the port forwarding guide will help you open it up for friends outside your network. You can restart this tour anytime from Preferences."
        }
    }

    var actionLabel: String {
        switch self {
        case .welcome:
            return "Let's go →"
        case .done:
            return "Finish"
        default:
            return "Next"
        }
    }

    var requiresUserAction: Bool {
        switch self {
        case .manageServers,
             .createServer,
             .wizardChoosePath,
             .serverSettings,
             .serverNetworkContinue,
             .createButton,
             .dismissManage,
             .acceptEula,
             .startButton:
            return true
        default:
            return false
        }
    }

    /// Custom instruction shown instead of the default "Tap the highlighted element above".
    var instruction: String? {
        switch self {
        case .wizardChoosePath, .serverSettings, .serverNetworkContinue:
            return "Tap Continue at the bottom to proceed"
        case .createButton:
            return "Give your server a name, then tap Create Server"
        default:
            return nil
        }
    }

    /// Steps that sit on a form the user needs to fill (World, Plugins/Mods). Their
    /// card shows a "Got it" button that hides the coach mark so the whole page is
    /// usable; the tour resumes when the user taps the wizard's Continue button.
    var allowsCardHide: Bool {
        switch self {
        case .firstWorld, .serverAddOns, .createButton: return true
        default:                                        return false
        }
    }

    /// Steps where the whole sheet is uniformly dimmed behind the coach mark (rather than
    /// spotlight-lit). Focuses attention on the card; the dim lifts when the card is hidden
    /// via "Got it" so the user can fill the page. Applies to all three full-page form steps.
    var dimsSheetBehindCard: Bool {
        switch self {
        case .firstWorld, .serverAddOns, .createButton: return true
        default:                                        return false
        }
    }

}

// MARK: - Anchor IDs

enum OnboardingAnchorID: String {
    case manageServersButton     = "ob_manage_servers"
    case createServerButton      = "ob_create_server"
    case wizardPathPicker        = "ob_wizard_path_picker"
    case wizardStartFreshCard    = "ob_wizard_fresh_card"
    case wizardContinueButton    = "ob_wizard_continue"
    case serverNameField         = "ob_server_name"
    case serverTypeSelector      = "ob_server_type"
    case serverCategoryArea      = "ob_server_category"
    case serverFlavorArea        = "ob_server_flavor"
    case serverSourceArea        = "ob_server_source"
    case serverCrossplayArea     = "ob_server_crossplay"
    case serverSettingsArea          = "ob_server_settings"
    case serverConnectivityArea      = "ob_server_connectivity"
    case serverConnectivityPortsArea = "ob_server_connectivity_ports"
    case confirmPageArea             = "ob_confirm_page"
    case wizardBodyArea              = "ob_wizard_body"
    case wizardSheetArea             = "ob_wizard_sheet"
    case worldSourceArea         = "ob_world_source"
    case worldCreationArea       = "ob_world_creation"
    case createSaveButton        = "ob_create_save"
    case manageServersDoneButton = "ob_manage_done"
    case acceptEulaButton        = "ob_accept_eula"
    case startButton             = "ob_start_button"
    case consolePanel            = "ob_console_panel"
    case consoleDividerHandle    = "ob_console_divider_handle"
    case detailsTabBar           = "ob_details_tabs"
    case detailsTabContent       = "ob_details_tab_content"
    case detailsOverviewTab      = "ob_details_overview_tab"
    case detailsPlayersTab       = "ob_details_players_tab"
    case detailsWorldsTab        = "ob_details_worlds_tab"
    case detailsPacksTab         = "ob_details_packs_tab"
    case detailsPerformanceTab   = "ob_details_performance_tab"
    case detailsComponentsTab    = "ob_details_components_tab"
    case detailsSettingsTab      = "ob_details_settings_tab"
    case detailsFilesTab         = "ob_details_files_tab"
    case portForwardGuideButton  = "ob_port_forward_guide_button"
}

// MARK: - OnboardingManager

@MainActor
final class OnboardingManager: ObservableObject {
    static let shared = OnboardingManager()

    @Published private(set) var isActive: Bool = false
    @Published private(set) var currentStep: OnboardingStep = .welcome
    @Published var anchorFrames: [String: CGRect] = [:]

    /// True when the user tapped "Got it" on a form step (World, Plugins) to dismiss
    /// the coach mark and fill the page. The dim/card are suppressed; the tour resumes
    /// (and this resets) when they tap the wizard's Continue button. See `allowsCardHide`.
    @Published var cardHidden: Bool = false

    /// Accent color for the overlay UI — set by AppViewModel.syncTourAccentColor().
    @Published var accentColor: Color = .green

    var tourServerType: ServerType = .java
    /// The flavor the user has selected during the tour. Drives whether the
    /// cross-play step applies (only standard plugin servers can host Geyser).
    var tourFlavor: JavaServerFlavor = .paper

    /// "Plugins" or "Mods" for the current tour flavor (used in the add-ons step copy).
    var tourAddOnNoun: String { tourFlavor.addOnKind?.displayName ?? "Add-ons" }

    /// Whether a step is relevant given the current tour selections. Steps that
    /// don't apply are skipped during advance() so the linear tour can branch
    /// (e.g. Bedrock skips the Java software steps; non-Paper skips cross-play).
    private func isApplicable(_ step: OnboardingStep) -> Bool {
        switch step {
        case .serverCategory, .serverFlavor, .serverVersion:
            return tourServerType == .java
        case .serverCrossplay:
            return tourServerType == .java
                && tourFlavor.category == .standard
                && tourFlavor != .vanilla
        case .serverAddOns:
            // Mirrors AddServerWizardView.hasAddOnsStep: Java flavors that accept
            // plugins/mods (everything except Vanilla).
            return tourServerType == .java && tourFlavor.addOnKind != nil
        default:
            return true
        }
    }

    private let defaultsKey = "msc_onboarding_tour_complete"

    var hasCompletedTour: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    private init() {}

    func startIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: defaultsKey) else { return }
        start()
    }

    func reset() {
        UserDefaults.standard.set(false, forKey: defaultsKey)
        start()
    }

    func forceStart() {
        start()
    }

    func complete() {
        UserDefaults.standard.set(true, forKey: defaultsKey)
        SwiftUI.withAnimation(.easeInOut(duration: 0.3)) {
            isActive = false
        }
        currentStep = .welcome
    }

    /// Dismisses the coach mark on a form step so the user can fill the page. The tour
    /// stays on the same step and resumes (card reappears) on the next advance/jump.
    func hideCard() {
        SwiftUI.withAnimation(.easeInOut(duration: 0.2)) { cardHidden = true }
    }

    /// Brings a hidden coach mark back (the "Show tip" affordance).
    func showCard() {
        SwiftUI.withAnimation(.easeInOut(duration: 0.2)) { cardHidden = false }
    }

    func advance() {
        guard isActive else { return }
        cardHidden = false

        if currentStep == .done {
            complete()
            return
        }

        var next = OnboardingStep(rawValue: currentStep.rawValue + 1) ?? .done
        while next != .done && !isApplicable(next) {
            next = OnboardingStep(rawValue: next.rawValue + 1) ?? .done
        }
        SwiftUI.withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            currentStep = next
        }
    }

    func jumpTo(_ step: OnboardingStep) {
        guard isActive else { return }
        cardHidden = false

        SwiftUI.withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            currentStep = step
        }
    }

    private func start() {
        anchorFrames = [:]
        currentStep = .welcome
        tourServerType = .java
        tourFlavor = .paper
        cardHidden = false

        SwiftUI.withAnimation(.easeIn(duration: 0.25)) {
            isActive = true
        }
    }
}


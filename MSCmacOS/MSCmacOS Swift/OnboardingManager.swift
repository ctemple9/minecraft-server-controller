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
    case serverName            = 3
    case serverType            = 4
    case serverSettings        = 5
    case firstWorld            = 6   // ← NEW: dedicated world creation step
    case createButton          = 7
    case dismissManage         = 8
    case acceptEula            = 9
    case startButton           = 10
    case console               = 11
    case continueDetails       = 12
    case expandDetails         = 13
    case detailsOverviewTab    = 14
    case detailsPlayersTab     = 15
    case detailsWorldsTab      = 16
    case detailsPacksTab       = 17
    case detailsPerformanceTab = 18
    case detailsComponentsTab  = 19
    case detailsSettingsTab    = 20
    case detailsFilesTab       = 21
    case portForwardGuide      = 22
    case done                  = 23

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
        case .serverName:            return "Name Your Server"
        case .serverType:            return "Pick a Type"
        case .serverSettings:        return "Review Your Settings"
        case .firstWorld:            return "Create Your First World"
        case .createButton:          return "Create It"
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
        case .portForwardGuide:      return "External Players"
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
            return "Tap \"Create New Server…\" to open the server builder."
        case .serverName:
            return "Give your server a name here. The world itself is set up in the next step and can use a different name."
        case .serverType:
            return "Java is for PC players. Bedrock is for mobile, console, and Windows 10/11. Pick whichever fits — you can switch before creating."
        case .serverSettings:
            if OnboardingManager.shared.tourServerType == .java {
                return "Set the Java port here and turn on Bedrock cross-play if you want console and mobile players to join."
            } else {
                return "Set the Bedrock port here and adjust the image or player limit if needed."
            }
        case .firstWorld:
            return "This section creates the first world for your server. Choose \"New world\" for a fresh start, then set the world name, difficulty, game mode, and optional seed. You can add more worlds later from the Worlds tab, but only one world is active at a time."
        case .createButton:
            return "Everything looks good! Tap Create to build your server."
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
                return "Components is where you manage Paper, plugins, Broadcast, and Bedrock Connect."
            } else {
                return "Components is where you manage the Bedrock runtime, image version, and Bedrock Connect tools."
            }
        case .detailsSettingsTab:
            return "Settings is where you change core server options. Changes stay local here until you click Save Changes."
        case .detailsFilesTab:
            return "Files lets you browse and preview every file in your server directory — configs, logs, world data, and more. You can also edit text files directly from here."
        case .portForwardGuide:
            return "Local players are covered. For friends outside your home network, use the Port Forwarding Guide button in the header to open the router guide and finish external access."
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
             .createButton,
             .dismissManage,
             .acceptEula,
             .startButton,
             .portForwardGuide:
            return true
        default:
            return false
        }
    }
}

// MARK: - Anchor IDs

enum OnboardingAnchorID: String {
    case manageServersButton     = "ob_manage_servers"
    case createServerButton      = "ob_create_server"
    case serverNameField         = "ob_server_name"
    case serverTypeSelector      = "ob_server_type"
    case serverSettingsArea      = "ob_server_settings"
    case worldSourceArea         = "ob_world_source"
    case worldCreationArea       = "ob_world_creation"   // ← NEW: dedicated world step anchor
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

    /// Accent color for the overlay UI — set by AppViewModel.syncTourAccentColor().
    @Published var accentColor: Color = .green

    var tourServerType: ServerType = .java

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

    func advance() {
        guard isActive else { return }

        if currentStep == .done {
            complete()
            return
        }

        let next = OnboardingStep(rawValue: currentStep.rawValue + 1) ?? .done
        SwiftUI.withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            currentStep = next
        }
    }

    func jumpTo(_ step: OnboardingStep) {
        guard isActive else { return }

        SwiftUI.withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            currentStep = step
        }
    }

    private func start() {
        anchorFrames = [:]
        currentStep = .welcome
        tourServerType = .java

        SwiftUI.withAnimation(.easeIn(duration: 0.25)) {
            isActive = true
        }
    }
}


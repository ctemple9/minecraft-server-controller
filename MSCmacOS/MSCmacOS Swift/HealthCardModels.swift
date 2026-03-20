//
//  HealthCardModels.swift
//  MinecraftServerController
//
//  Shared data models for server health cards.
//

import Foundation

// MARK: - HealthStatus

enum HealthStatus: String, Equatable {
    case green   // check passed
    case yellow  // inconclusive or present-but-not-optimal
    case red     // definitively failed
    case gray    // not yet checked / requires server to have run
}

// MARK: - HealthCardAction

enum HealthCardAction: Equatable {
    case openURL(String)
    case openDockerDesktop
    case pullDockerImage
    case openConsoleLog
    case locateFolder
    case triggerDownload
    case openComponentsTab   // deep-link from health card into the Components tab
    case openRouterPortForwardGuide
}

// MARK: - HealthCardResult

struct HealthCardResult: Identifiable {
    let id: String                    // e.g. "directory", "java", "jar", "ram", "port", "lastStartup"
    let status: HealthStatus
    let detectedValue: String?        // shown on card back
    let actionLabel: String?
    let actionType: HealthCardAction?
}

// MARK: - LastStartupResult (persisted to {serverDir}/last_startup_result.json)

struct LastStartupResult: Codable {
    var startedAt: Date
    var wasClean: Bool
    var fatalErrors: [String]
    var warnings: [String]
}


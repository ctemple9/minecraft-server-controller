//
//  RouterPortForwardGuideSheetViewModel.swift
//  MinecraftServerController
//
//  Local view model for the Router Port Forwarding Guide sheet.
//  Phase UI-4: adds troubleshooting engine, selectedSymptoms, troubleshootingReport,
//  runAnalysis(), resetTroubleshooting(), navigateBackFromTroubleshooting(), and
//  supporting computed helpers for the troubleshooting screen.
//

import Foundation
import Combine
import SwiftUI

// MARK: - Screen enum

/// The three top-level screens inside the Router Port Forwarding Guide sheet.
enum RouterPortForwardGuideScreen: Equatable {
    case picker
    case guideReader(guideID: String)
    case troubleshooting
}

// MARK: - View model

@MainActor
final class RouterPortForwardGuideSheetViewModel: ObservableObject {

    // MARK: - Published state — screen navigation

    @Published var currentScreen: RouterPortForwardGuideScreen = .picker
    @Published var selectedGuideID: String? = nil

    // MARK: - Published state — picker funnel

    /// Currently displayed decision-tree node.
    @Published var currentNodeID: RouterPortForwardDecisionNodeID = .start

    /// Breadcrumb stack used by goBack(). Does not include .start.
    @Published var nodeHistory: [RouterPortForwardDecisionNodeID] = []

    /// Live search results from the matcher. nil = no query entered yet.
    @Published var searchResults: RouterPortForwardGuideMatcher.MatchResult? = nil

    /// Raw text in the search field (bound through runSearch).
    @Published var pickerQuery: String = ""

    /// Suggested search terms inherited from the choice that led to the current node.
    /// Shown as prompt chips when the search field is empty.
    @Published var currentSuggestedTerms: [String] = []

    // MARK: - Published state — troubleshooting (Phase UI-4)

    /// The set of symptom IDs the user has checked in the troubleshooting screen.
    @Published var selectedSymptoms: Set<RouterPortForwardSymptomID> = []

    /// The most recent analysis result. nil until the user taps Analyze.
    @Published var troubleshootingReport: RouterPortForwardTroubleshootingReport? = nil

    // MARK: - Repository + matcher + troubleshooting engine

    private let repository: RouterPortForwardGuideRepository
    private let matcher: RouterPortForwardGuideMatcher
    private let troubleshootingEngine: RouterPortForwardTroubleshootingEngine

    /// All guides from the repository — used by the picker to detect the empty-catalog state.
    var allGuides: [RouterPortForwardGuide] {
        repository.allGuides
    }

    /// Best available generic router guide for the "Use generic guide" escape hatch.
    var genericRouterGuide: RouterPortForwardGuide? {
        repository.guides(family: .genericRouter).first ?? repository.allGuides.first
    }

    /// Advanced troubleshooting guide — used in the 0-causes fallback state.
    var advancedTroubleshootingGuide: RouterPortForwardGuide? {
        allGuides.first { $0.family == .advancedTroubleshooting }
    }

    /// All symptoms the engine knows about. Drives the checklist.
    var supportedSymptoms: [RouterPortForwardSymptom] {
        troubleshootingEngine.supportedSymptoms
    }

    // MARK: - Decision tree (read-only after init)

    private(set) var decisionTree: [RouterPortForwardDecisionNode]

    // MARK: - Runtime context (set at init, consumed in later phases)

    private(set) var runtimeContext: RouterPortForwardGuideRuntimeContext?

    // MARK: - Init

    init(runtimeContext: RouterPortForwardGuideRuntimeContext?) {
        self.runtimeContext = runtimeContext
        let repo = RouterPortForwardGuideRepository()
        self.repository = repo
        self.matcher   = RouterPortForwardGuideMatcher(repository: repo)
        self.troubleshootingEngine = RouterPortForwardTroubleshootingEngine(repository: repo)
        self.decisionTree = RouterPortForwardFallbackDecisionTree.makeTree(
            detectedGatewayIPAddress: runtimeContext?.detectedGatewayIPAddress
        )
    }

    // MARK: - Computed

    /// The decision node currently on screen. nil only if the tree is somehow empty.
    var currentNode: RouterPortForwardDecisionNode? {
        decisionTree.first { $0.id == currentNodeID }
    }

    // MARK: - Picker navigation

    /// Advance to a new decision-tree node, pushing current onto the history stack.
    /// Pass `suggestedTerms` from the choice that triggered the advance so the
    /// freeTextSearch empty state can show prompt chips.
    func advanceToNode(
        _ nodeID: RouterPortForwardDecisionNodeID,
        suggestedTerms: [String] = []
    ) {
        nodeHistory.append(currentNodeID)
        currentNodeID = nodeID
        currentSuggestedTerms = suggestedTerms
        // Reset search state for the new node.
        pickerQuery = ""
        searchResults = nil
    }

    /// Pop the history stack and return to the previous node.
    /// No-ops if already at the root — cannot go below .start.
    func goBack() {
        guard !nodeHistory.isEmpty else { return }
        currentNodeID = nodeHistory.removeLast()
        pickerQuery = ""
        searchResults = nil
        currentSuggestedTerms = []
    }

    /// Run the matcher against the given query and publish results.
    /// Passing an empty/whitespace-only string clears the results.
    func runSearch(_ query: String) {
        pickerQuery = query
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = nil
            return
        }
        searchResults = matcher.match(query)
    }

    // MARK: - Screen navigation

    func navigateToGuide(id: String) {
        selectedGuideID = id
        currentScreen = .guideReader(guideID: id)
    }

    func navigateToTroubleshooting() {
        currentScreen = .troubleshooting
    }

    /// Return to the picker and reset it to the .start node.
    func navigateToPicker() {
        currentScreen = .picker
        currentNodeID = .start
        nodeHistory = []
        pickerQuery = ""
        searchResults = nil
        currentSuggestedTerms = []
    }

    /// Navigate directly to the best available generic router guide.
    /// Falls back to the first guide in the catalog if the generic family isn't seeded.
    func navigateToGenericGuide() {
        if let guide = genericRouterGuide {
            navigateToGuide(id: guide.id)
        }
    }

    /// Navigate back from the troubleshooting screen to wherever the user came from.
    /// If a guide was open, returns to the guide reader; otherwise returns to the picker.
    func navigateBackFromTroubleshooting() {
        if let id = selectedGuideID {
            currentScreen = .guideReader(guideID: id)
        } else {
            navigateToPicker()
        }
    }

    // MARK: - Troubleshooting actions (Phase UI-4)

    /// Run the analysis engine against the currently selected symptoms.
    /// Sets `troubleshootingReport` with the result. Safe to call on main actor.
    func runAnalysis() {
        troubleshootingReport = troubleshootingEngine.analyze(
            symptomIDs: selectedSymptoms,
            runtimeContext: runtimeContext
        )
    }

    /// Clear selected symptoms and dismiss the current analysis result.
    func resetTroubleshooting() {
        selectedSymptoms = []
        troubleshootingReport = nil
    }

    /// Human-readable title for a symptom ID — looks up the engine's symptom list.
    func symptomTitle(for id: RouterPortForwardSymptomID) -> String {
        troubleshootingEngine.symptom(id: id)?.title ?? id.rawValue
    }
}

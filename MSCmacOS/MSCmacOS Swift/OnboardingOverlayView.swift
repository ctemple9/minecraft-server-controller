//
//  OnboardingOverlayView.swift
//  MinecraftServerController
//
//  Full-window spotlight overlay for the first-run onboarding tour.
//
//  Multiple instances coexist — one on ContentView for main-window steps,
//  one inside ManageServersView, one inside CreateServerView.  Each specifies
//  which steps it "owns" via `ownedSteps`.
//
//  Accent color: reads manager.accentColor (set by AppViewModel.syncTourAccentColor).
//  Defaults to .green when no server or global accent is configured.
//

import SwiftUI

struct OnboardingOverlayView: View {
    /// Which onboarding steps this overlay instance is responsible for.
    let ownedSteps: Set<OnboardingStep>

    @ObservedObject private var manager = OnboardingManager.shared

    @State private var animatedSpotlight: CGRect = .zero
    @State private var overlayGlobalOrigin: CGPoint = .zero

    /// Whether the current step belongs to this overlay instance.
    private var isOwned: Bool {
        ownedSteps.contains(manager.currentStep)
    }

    var body: some View {
        if manager.isActive && isOwned {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    if manager.cardHidden {
                        // Card dismissed so the user can fill the page — no dim, full interaction.
                        Color.clear
                    } else if manager.currentStep.dimsSheetBehindCard {
                        // Uniformly dim the whole sheet behind the card (no spotlight cutout).
                        // Non-blocking so the page stays usable; the dim lifts on "Got it".
                        Color.black.opacity(0.72)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                    } else if manager.currentStep == .welcome || manager.currentStep == .done {
                        Color.black.opacity(0.72)
                            .ignoresSafeArea()
                    } else if animatedSpotlight == .zero {
                        Color.black.opacity(0.72)
                            .ignoresSafeArea()
                    } else {
                        ZStack(alignment: .topLeading) {
                            dimLayer(in: geo.size)
                        }
                        .allowsHitTesting(false)
                    }

                    tooltipCard(in: geo.size)
                }
                .onAppear {
                    overlayGlobalOrigin = geo.frame(in: .global).origin
                    updateSpotlight()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        overlayGlobalOrigin = geo.frame(in: .global).origin
                        updateSpotlight()
                    }
                }
                .onChange(of: manager.currentStep) { _, _ in
                    overlayGlobalOrigin = geo.frame(in: .global).origin
                    updateSpotlight()
                }
                .onChange(of: manager.anchorFrames) { _, _ in
                    overlayGlobalOrigin = geo.frame(in: .global).origin
                    updateSpotlight()
                }
            }
            .ignoresSafeArea()
            .transition(.opacity)
            .zIndex(9999)
        }
    }

    // MARK: - Dim Layer (4 rects)

    @ViewBuilder
    private func dimLayer(in size: CGSize) -> some View {
        let s = animatedSpotlight
        let pad: CGFloat = 10
        let r = s.insetBy(dx: -pad, dy: -pad)

        let dimColor = Color.black.opacity(0.72)

        dimColor
            .frame(width: size.width, height: max(0, r.minY))
            .position(x: size.width / 2, y: max(0, r.minY) / 2)

        let bottomHeight = max(0, size.height - r.maxY)
        dimColor
            .frame(width: size.width, height: bottomHeight)
            .position(x: size.width / 2, y: r.maxY + bottomHeight / 2)

        let midHeight = max(0, r.height)
        dimColor
            .frame(width: max(0, r.minX), height: midHeight)
            .position(x: max(0, r.minX) / 2, y: r.midY)

        let rightWidth = max(0, size.width - r.maxX)
        dimColor
            .frame(width: rightWidth, height: midHeight)
            .position(x: r.maxX + rightWidth / 2, y: r.midY)

        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(manager.accentColor.opacity(0.6), lineWidth: 2)
            .frame(width: r.width, height: r.height)
            .position(x: r.midX, y: r.midY)
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: animatedSpotlight)

        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Color.white.opacity(0.2), lineWidth: 4)
            .blur(radius: 4)
            .frame(width: r.width, height: r.height)
            .position(x: r.midX, y: r.midY)
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: animatedSpotlight)
    }

    // MARK: - Tooltip Card

    @ViewBuilder
    private func tooltipCard(in size: CGSize) -> some View {
        let step = manager.currentStep
        if manager.cardHidden {
            // Card dismissed so the user can fill the page; offer Show tip + Skip.
            tourControlPills(in: size, showShowTip: true)
        } else if step == .welcome || step == .done {
            fullScreenCard(step: step, in: size)
        } else {
            anchoredCard(step: step, in: size)
        }
    }

    // MARK: - Full Screen Card (welcome / done)

    @ViewBuilder
    private func fullScreenCard(step: OnboardingStep, in size: CGSize) -> some View {
        VStack(spacing: MSC.Spacing.xl) {
            ZStack {
                Circle()
                    .fill(manager.accentColor.opacity(0.15))
                    .frame(width: 72, height: 72)
                Image(systemName: step == .welcome ? "sparkles" : "checkmark.seal.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(manager.accentColor)
            }

            VStack(spacing: MSC.Spacing.sm) {
                Text(step.title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(step.body)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 360)
            }

            HStack(spacing: MSC.Spacing.md) {
                if step == .welcome {
                    Button("Skip tour") { manager.complete() }
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                        .buttonStyle(.plain)
                }
                Button(step.actionLabel) { manager.advance() }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(manager.accentColor.contrastingLabel)
                    .padding(.horizontal, MSC.Spacing.xl)
                    .padding(.vertical, MSC.Spacing.sm)
                    .background(Capsule().fill(manager.accentColor))
                    .buttonStyle(.plain)
            }
        }
        .padding(MSC.Spacing.xxl)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        )
        .frame(maxWidth: 440)
        .position(x: size.width / 2, y: size.height / 2)
    }

    // MARK: - Anchored Tooltip

    @ViewBuilder
    private func anchoredCard(step: OnboardingStep, in size: CGSize) -> some View {
        let s = animatedSpotlight
        let pad: CGFloat = 10
        let spotlight = s == .zero
            ? CGRect(x: size.width / 2 - 100, y: size.height / 2 - 30, width: 200, height: 60)
            : s.insetBy(dx: -pad, dy: -pad)

        let cardWidth: CGFloat = 320
        let cardEstimatedHeight: CGFloat = step == .continueDetails ? 196 : 170

        let spaceBelow = size.height - (spotlight.maxY + 16)
        let placeBelow = spaceBelow >= cardEstimatedHeight

        let idealY: CGFloat = placeBelow
            ? spotlight.maxY + 16 + cardEstimatedHeight / 2
            : spotlight.minY - 16 - cardEstimatedHeight / 2

        // When the spotlight is in the lower 35% of the view (footer buttons like
        // Continue or Create Server), park the card at the top so it doesn't block
        // the content the user needs to read or fill in.
        let isBottomAnchored = spotlight.midY > size.height * 0.65
        // When the spotlight is so tall it covers most of the screen, park the card
        // INSIDE the spotlight near its top edge so it stays fully visible.
        let isTallSpotlight = !isBottomAnchored && spotlight.height > size.height * 0.65

        let cardY: CGFloat = isBottomAnchored
            ? cardEstimatedHeight / 2 + 80
            : isTallSpotlight
                // Form steps (World, Mods) center on the sheet — the user reads, then taps
                // "Got it" to hide the card and fill the page. Other full-sheet steps (Confirm)
                // sit low so the card doesn't cover the fields they must edit.
                ? (step.allowsCardHide ? size.height / 2 : spotlight.maxY - cardEstimatedHeight / 2 - 70)
                : idealY

        let cardX: CGFloat = (isBottomAnchored || isTallSpotlight)
            ? size.width / 2
            : max(cardWidth / 2 + 16, min(size.width - cardWidth / 2 - 16, spotlight.midX))

        VStack(alignment: .leading, spacing: MSC.Spacing.md) {
            if let idx = step.displayIndex {
                HStack(spacing: MSC.Spacing.sm) {
                                   GeometryReader { geo in
                                       ZStack(alignment: .leading) {
                                           Capsule()
                                               .fill(Color.white.opacity(0.15))
                                           Capsule()
                                               .fill(manager.accentColor)
                                               .frame(width: geo.size.width * CGFloat(idx) / CGFloat(step.totalSteps))
                                               .animation(.spring(response: 0.4, dampingFraction: 0.8), value: idx)
                                       }
                                   }
                                   .frame(height: 4)

                                   Text("Step \(idx) of \(step.totalSteps)")
                                       .font(.system(size: 10, weight: .medium))
                                       .foregroundStyle(.white.opacity(0.5))
                                       .fixedSize()
                               }
            }

            Text(step.title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(step.body)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            if step == .continueDetails {
                HStack(spacing: MSC.Spacing.sm) {
                    Button("Finish tour") { manager.complete() }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, MSC.Spacing.lg)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                        .buttonStyle(.plain)

                    Spacer()

                    Button("Continue") { manager.advance() }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(manager.accentColor.contrastingLabel)
                        .padding(.horizontal, MSC.Spacing.lg)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(manager.accentColor))
                        .buttonStyle(.plain)
                }
            } else if step.allowsCardHide {
                // Form step — "Got it" hides the card so the user can fill the page;
                // the tour resumes when they tap the wizard's Continue button.
                HStack(spacing: 6) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(manager.accentColor)
                    Text(step == .createButton ? "then tap Create Server when you're done" : "then tap Continue when you're done")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                    Spacer()
                    Button("Got it") { manager.hideCard() }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(manager.accentColor.contrastingLabel)
                        .padding(.horizontal, MSC.Spacing.lg)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(manager.accentColor))
                        .buttonStyle(.plain)
                }
            } else if !step.requiresUserAction {
                HStack {
                    Spacer()
                    Button(step.actionLabel) { manager.advance() }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(manager.accentColor.contrastingLabel)
                        .padding(.horizontal, MSC.Spacing.lg)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(manager.accentColor))
                        .buttonStyle(.plain)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(manager.accentColor)
                    Text(step.instruction ?? "Tap the highlighted element above")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
        .padding(MSC.Spacing.lg)
        .frame(width: cardWidth)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
        )
        .position(x: cardX, y: cardY)

        if step != .dismissManage && step != .continueDetails {
            tourControlPills(in: size, showShowTip: false)
        }
    }

    // MARK: - Helpers

    private func globalAnchorFrame(for step: OnboardingStep) -> CGRect {
        let f = manager.anchorFrames
        switch step {
        case .manageServers:         return f[OnboardingAnchorID.manageServersButton.rawValue] ?? .zero
        case .createServer:          return f[OnboardingAnchorID.createServerButton.rawValue] ?? .zero
        case .wizardChoosePath:      return f[OnboardingAnchorID.wizardContinueButton.rawValue] ?? .zero
        case .serverName:            return f[OnboardingAnchorID.serverNameField.rawValue] ?? .zero
        case .serverType:            return f[OnboardingAnchorID.serverTypeSelector.rawValue] ?? .zero
        case .serverCategory:        return f[OnboardingAnchorID.serverCategoryArea.rawValue] ?? .zero
        case .serverFlavor:          return f[OnboardingAnchorID.serverFlavorArea.rawValue] ?? .zero
        case .serverVersion:         return f[OnboardingAnchorID.serverSourceArea.rawValue] ?? .zero
        case .serverCrossplay:       return f[OnboardingAnchorID.serverCrossplayArea.rawValue] ?? .zero
        case .serverSettings:          return f[OnboardingAnchorID.wizardContinueButton.rawValue] ?? .zero
        case .serverConnectivity:      return f[OnboardingAnchorID.serverConnectivityArea.rawValue] ?? .zero
        case .serverConnectivityPorts: return f[OnboardingAnchorID.serverConnectivityPortsArea.rawValue] ?? .zero
        case .serverNetworkContinue:   return f[OnboardingAnchorID.wizardContinueButton.rawValue] ?? .zero
        case .firstWorld:              return f[OnboardingAnchorID.wizardSheetArea.rawValue] ?? .zero
        case .serverAddOns:            return f[OnboardingAnchorID.wizardSheetArea.rawValue] ?? .zero
        case .createButton:            return f[OnboardingAnchorID.wizardSheetArea.rawValue] ?? .zero
        case .dismissManage:         return f[OnboardingAnchorID.manageServersDoneButton.rawValue] ?? .zero
        case .acceptEula:            return f[OnboardingAnchorID.acceptEulaButton.rawValue] ?? .zero
        case .startButton:           return f[OnboardingAnchorID.startButton.rawValue] ?? .zero
        case .console:               return f[OnboardingAnchorID.consolePanel.rawValue] ?? .zero
        case .continueDetails:       return f[OnboardingAnchorID.consolePanel.rawValue] ?? .zero
        case .expandDetails:         return f[OnboardingAnchorID.consoleDividerHandle.rawValue] ?? .zero
        case .detailsOverviewTab,
             .detailsPlayersTab,
             .detailsWorldsTab,
             .detailsPacksTab,
             .detailsPerformanceTab,
             .detailsComponentsTab,
             .detailsSettingsTab,
             .detailsFilesTab:
            return detailWorkspaceSpotlightFrame(for: step, frames: f)
        default:
            return .zero
        }
    }

    private func unionFrame(_ lhs: CGRect, _ rhs: CGRect) -> CGRect {
        switch (lhs == .zero, rhs == .zero) {
        case (true, true):
            return .zero
        case (false, true):
            return lhs
        case (true, false):
            return rhs
        case (false, false):
            return lhs.union(rhs)
        }
    }

    private func detailWorkspaceSpotlightFrame(
        for step: OnboardingStep,
        frames: [String: CGRect]
    ) -> CGRect {
        let activeTabFrame = detailTabAnchorFrame(for: step, frames: frames)
        if activeTabFrame != .zero { return activeTabFrame }

        let tabBarFrame = frames[OnboardingAnchorID.detailsTabBar.rawValue] ?? .zero
        if tabBarFrame != .zero { return tabBarFrame }

        return frames[OnboardingAnchorID.detailsTabContent.rawValue] ?? .zero
    }

    private func detailTabAnchorFrame(
        for step: OnboardingStep,
        frames: [String: CGRect]
    ) -> CGRect {
        let anchorID: OnboardingAnchorID

        switch step {
        case .detailsOverviewTab:
            anchorID = .detailsOverviewTab
        case .detailsPlayersTab:
            anchorID = .detailsPlayersTab
        case .detailsWorldsTab:
            anchorID = .detailsWorldsTab
        case .detailsPacksTab:
            anchorID = .detailsPacksTab
        case .detailsPerformanceTab:
            anchorID = .detailsPerformanceTab
        case .detailsComponentsTab:
            anchorID = .detailsComponentsTab
        case .detailsSettingsTab:
            anchorID = .detailsSettingsTab
        case .detailsFilesTab:
            anchorID = .detailsFilesTab
        default:
            return .zero
        }

        return frames[anchorID.rawValue] ?? .zero
    }

    /// Local frame of the whole wizard sheet, or .zero when this overlay isn't over the wizard.
    private func sheetLocalFrame() -> CGRect {
        toLocal(manager.anchorFrames[OnboardingAnchorID.wizardSheetArea.rawValue] ?? .zero)
    }

    /// Skip tour (+ optional Show tip) controls. When over the wizard sheet they align as a
    /// neat row just left of the Done button with matching spacing; otherwise they fall back
    /// to the window's top-right corner.
    @ViewBuilder
    private func tourControlPills(in size: CGSize, showShowTip: Bool) -> some View {
        let sheet = sheetLocalFrame()
        let pills = HStack(spacing: MSC.Spacing.sm) {
            if showShowTip {
                Button("Show tip") { manager.showCard() }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(manager.accentColor.contrastingLabel)
                    .padding(.horizontal, MSC.Spacing.md)
                    .padding(.vertical, MSC.Spacing.xs)
                    .background(Capsule().fill(manager.accentColor))
                    .buttonStyle(.plain)
            }
            Button("Skip tour") { manager.complete() }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.horizontal, MSC.Spacing.md)
                .padding(.vertical, MSC.Spacing.xs)
                .background(Capsule().fill(Color.white.opacity(0.12)))
                .buttonStyle(.plain)
        }

        if sheet != .zero {
            // Reserve the Done button's slot (~50pt) + an 8pt gap so the pills sit just
            // to its left on the same row, evenly spaced.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                pills
                Spacer(minLength: 0).frame(width: 58)
            }
            .frame(width: max(0, sheet.width - MSC.Spacing.xl * 2))
            .position(x: sheet.midX, y: sheet.minY + 32)
        } else {
            pills.position(x: size.width - 90, y: 40)
        }
    }

    private func toLocal(_ globalFrame: CGRect) -> CGRect {
        guard globalFrame != .zero else { return .zero }
        return CGRect(
            x: globalFrame.origin.x - overlayGlobalOrigin.x,
            y: globalFrame.origin.y - overlayGlobalOrigin.y,
            width: globalFrame.width,
            height: globalFrame.height
        )
    }

    private func updateSpotlight() {
        let globalFrame = globalAnchorFrame(for: manager.currentStep)
        let local = toLocal(globalFrame)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            animatedSpotlight = local
        }
    }
}

// MARK: - Color contrast helper

private extension Color {
    /// Returns black or white depending on which has better contrast against this color.
    var contrastingLabel: Color {
        #if os(macOS)
        let ns = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor(self)
        let luminance = 0.2126 * ns.redComponent + 0.7152 * ns.greenComponent + 0.0722 * ns.blueComponent
        return luminance > 0.45 ? .black : .white
        #else
        return .black
        #endif
    }
}


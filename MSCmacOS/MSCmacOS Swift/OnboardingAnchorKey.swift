//
//  OnboardingAnchorKey.swift
//  MinecraftServerController
//
//  Broadcasts each anchor view's global frame directly into
//  OnboardingManager.shared.anchorFrames.
//
//  Uses three reporting mechanisms for bulletproof coverage:
//  1. onAppear — reports frame when the view first appears
//  2. onChange(of: geo.frame) — reports when layout changes (resize, etc.)
//  3. onReceive($isActive) — re-reports when tour starts/restarts,
//     covering the case where views are already on screen
//

import SwiftUI

// MARK: - View Modifier

private struct OnboardingAnchorModifier: ViewModifier {
    let anchorID: OnboardingAnchorID

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            reportFrame(geo)
                        }
                        .onChange(of: geo.frame(in: .global)) { _, _ in
                            reportFrame(geo)
                        }
                        .onReceive(OnboardingManager.shared.$isActive) { active in
                            if active {
                                // Re-report when tour (re)starts so frames
                                // are always available even if they were stale.
                                reportFrame(geo)
                            }
                        }
                }
            )
    }

    private func reportFrame(_ geo: GeometryProxy) {
        let frame = geo.frame(in: .global)
        guard frame.width > 0, frame.height > 0 else { return }
        OnboardingManager.shared.anchorFrames[anchorID.rawValue] = frame
    }
}

// MARK: - Convenience Extension

extension View {
    func onboardingAnchor(_ id: OnboardingAnchorID) -> some View {
        modifier(OnboardingAnchorModifier(anchorID: id))
    }
}

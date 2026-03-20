import SwiftUI
import Combine

enum ContextualHelpCardPlacement {
    case auto, above, below
}

struct ContextualHelpStep: Identifiable, Hashable {
    let id: String
    let title: String
    let body: String
    let anchorID: String?
    let secondaryAnchorID: String?
    let nextLabel: String
    let preferredPlacement: ContextualHelpCardPlacement

    init(
        id: String,
        title: String,
        body: String,
        anchorID: String? = nil,
        secondaryAnchorID: String? = nil,
        nextLabel: String = "Next",
        preferredPlacement: ContextualHelpCardPlacement = .auto
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.anchorID = anchorID
        self.secondaryAnchorID = secondaryAnchorID
        self.nextLabel = nextLabel
        self.preferredPlacement = preferredPlacement
    }
}

struct ContextualHelpGuide: Identifiable, Hashable {
    let id: String
    let steps: [ContextualHelpStep]

    init(id: String, steps: [ContextualHelpStep]) {
        self.id = id
        self.steps = steps
    }
}

@MainActor
final class ContextualHelpManager: ObservableObject {
    static let shared = ContextualHelpManager()

    @Published private(set) var isActive: Bool = false
    @Published private(set) var currentGuide: ContextualHelpGuide?
    @Published private(set) var currentStepIndex: Int = 0
    @Published var anchorFrames: [String: CGRect] = [:]

    /// Accent color for the overlay UI — set by AppViewModel.syncTourAccentColor().
    /// Defaults to green to match the original design.
    @Published var accentColor: Color = .green

    private init() {}

    var currentStep: ContextualHelpStep? {
        guard let guide = currentGuide, guide.steps.indices.contains(currentStepIndex) else { return nil }
        return guide.steps[currentStepIndex]
    }

    var totalSteps: Int {
        currentGuide?.steps.count ?? 0
    }

    var displayStepNumber: Int {
        guard currentGuide != nil else { return 0 }
        return currentStepIndex + 1
    }

    var canGoBack: Bool {
        currentStepIndex > 0
    }

    var isLastStep: Bool {
        guard let guide = currentGuide else { return false }
        return currentStepIndex >= guide.steps.count - 1
    }

    func start(_ guide: ContextualHelpGuide) {
        guard !guide.steps.isEmpty else { return }

        anchorFrames = [:]
        currentGuide = guide
        currentStepIndex = 0

        withAnimation(.easeIn(duration: 0.22)) {
            isActive = true
        }
    }

    func advance() {
        guard isActive, let guide = currentGuide else { return }

        if currentStepIndex >= guide.steps.count - 1 {
            dismiss()
            return
        }

        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            currentStepIndex += 1
        }
    }

    func goBack() {
        guard isActive, currentStepIndex > 0 else { return }

        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            currentStepIndex -= 1
        }
    }

    func dismiss() {
        withAnimation(.easeInOut(duration: 0.22)) {
            isActive = false
        }

        currentGuide = nil
        currentStepIndex = 0
    }
}

private struct ContextualHelpAnchorModifier: ViewModifier {
    let anchorID: String

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
                        .onReceive(ContextualHelpManager.shared.$isActive) { active in
                            if active {
                                reportFrame(geo)
                            }
                        }
                }
            )
    }

    private func reportFrame(_ geo: GeometryProxy) {
        let frame = geo.frame(in: .global)
        guard frame.width > 0, frame.height > 0 else { return }
        ContextualHelpManager.shared.anchorFrames[anchorID] = frame
    }
}

struct ContextualHelpOverlayView: View {
    let ownedGuideIDs: Set<String>

    @ObservedObject private var manager = ContextualHelpManager.shared

    @State private var animatedSpotlight: CGRect = .zero
    @State private var overlayGlobalOrigin: CGPoint = .zero

    private var isOwned: Bool {
        guard let guideID = manager.currentGuide?.id else { return false }
        return ownedGuideIDs.contains(guideID)
    }

    var body: some View {
        if manager.isActive, isOwned, let step = manager.currentStep {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    if step.anchorID == nil || animatedSpotlight == .zero {
                        Color.black.opacity(0.72)
                            .ignoresSafeArea()
                    } else {
                        dimLayer(in: geo.size)
                    }

                    tooltipCard(for: step, in: geo.size)
                }
                .onAppear {
                    overlayGlobalOrigin = geo.frame(in: .global).origin
                    updateSpotlight()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        overlayGlobalOrigin = geo.frame(in: .global).origin
                        updateSpotlight()
                    }
                }
                .onChange(of: manager.currentStepIndex) { _, _ in
                    overlayGlobalOrigin = geo.frame(in: .global).origin
                    updateSpotlight()
                }
                .onChange(of: manager.anchorFrames) { _, _ in
                    overlayGlobalOrigin = geo.frame(in: .global).origin
                    updateSpotlight()
                }
            }
            .ignoresSafeArea()
            .onExitCommand {
                manager.dismiss()
            }
            .transition(.opacity)
            .zIndex(9998)
        }
    }

    @ViewBuilder
    private func dimLayer(in size: CGSize) -> some View {
        let pad: CGFloat = 10
        let r = animatedSpotlight.insetBy(dx: -pad, dy: -pad)
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

    @ViewBuilder
    private func tooltipCard(for step: ContextualHelpStep, in size: CGSize) -> some View {
        if step.anchorID == nil || animatedSpotlight == .zero {
            centeredCard(for: step, in: size)
        } else {
            anchoredCard(for: step, in: size)
        }
    }

    @ViewBuilder
    private func centeredCard(for step: ContextualHelpStep, in size: CGSize) -> some View {
        let cardWidth = max(280, min(350, size.width - 56))
        let maxCardHeight = max(180, min(280, size.height - 64))
        let maxBodyHeight = max(66, maxCardHeight - 88)

        helpCardContent(for: step, horizontalPadding: 14, maxBodyHeight: maxBodyHeight)
            .frame(width: cardWidth)
            .background(cardBackground)
            .position(x: size.width / 2, y: size.height / 2)
    }

    @ViewBuilder
    private func anchoredCard(for step: ContextualHelpStep, in size: CGSize) -> some View {
        let pad: CGFloat = 10
        let spotlight = animatedSpotlight.insetBy(dx: -pad, dy: -pad)
        let cardWidth = max(250, min(320, size.width - 56))
        let maxCardHeight = max(180, min(260, size.height - 56))
        let maxBodyHeight = max(66, maxCardHeight - 82)

        let spaceBelow = size.height - (spotlight.maxY + 16)
                let spaceAbove = spotlight.minY - 16
                let placeBelow: Bool = step.preferredPlacement == .above ? false
                                     : step.preferredPlacement == .below ? true
                                     : spaceBelow >= spaceAbove

        let unclampedY: CGFloat = placeBelow
            ? spotlight.maxY + 16 + maxCardHeight / 2
            : spotlight.minY - 16 - maxCardHeight / 2
        let minCardMidY = maxCardHeight / 2 + 16
        let maxCardMidY = size.height - maxCardHeight / 2 - 16
        let cardY = min(max(unclampedY, minCardMidY), maxCardMidY)
        let cardX = max(cardWidth / 2 + 16,
                        min(size.width - cardWidth / 2 - 16, spotlight.midX))

        helpCardContent(for: step, horizontalPadding: 12, maxBodyHeight: maxBodyHeight)
            .frame(width: cardWidth)
            .background(cardBackground)
            .position(x: cardX, y: cardY)
    }

    private func helpCardContent(for step: ContextualHelpStep, horizontalPadding: CGFloat, maxBodyHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow

            titleAndBody(for: step)
                .frame(maxWidth: .infinity, alignment: .leading)

            buttonRow(for: step)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 5) {
                ForEach(1...max(manager.totalSteps, 1), id: \.self) { index in
                    Circle()
                        .fill(index == manager.displayStepNumber ? manager.accentColor : Color.white.opacity(0.25))
                        .frame(width: index == manager.displayStepNumber ? 7 : 4,
                               height: index == manager.displayStepNumber ? 7 : 4)
                }
            }

            Spacer()

            Text("Step \(manager.displayStepNumber) of \(manager.totalSteps)")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))

            Button {
                manager.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.white.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close help")
        }
    }

    private func titleAndBody(for step: ContextualHelpStep) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(step.title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(step.body)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func buttonRow(for step: ContextualHelpStep) -> some View {
        HStack(spacing: 8) {
            if manager.canGoBack {
                Button("Back") {
                    manager.goBack()
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.12)))
                .buttonStyle(.plain)
            }

            Spacer()

            Button(manager.isLastStep ? "Done" : step.nextLabel) {
                manager.advance()
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(manager.accentColor.contrastingLabel)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(manager.accentColor))
            .buttonStyle(.plain)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            )
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
            guard let anchorID = manager.currentStep?.anchorID,
                  let globalFrame = manager.anchorFrames[anchorID] else {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    animatedSpotlight = .zero
                }
                return
            }

            var combined = globalFrame
            if let secondaryID = manager.currentStep?.secondaryAnchorID,
               let secondaryFrame = manager.anchorFrames[secondaryID],
               secondaryFrame != .zero {
                combined = combined.union(secondaryFrame)
            }

            let local = toLocal(combined)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                animatedSpotlight = local
            }
        }
}

extension View {
    @ViewBuilder
    func contextualHelpAnchor(_ id: String?) -> some View {
        if let id {
            modifier(ContextualHelpAnchorModifier(anchorID: id))
        } else {
            self
        }
    }

    func contextualHelpHost(guideIDs: Set<String>) -> some View {
        overlay {
            ContextualHelpOverlayView(ownedGuideIDs: guideIDs)
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

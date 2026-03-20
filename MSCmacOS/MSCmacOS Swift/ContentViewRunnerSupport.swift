import SwiftUI
import SpriteKit
#if os(macOS)
import AppKit
#endif

// MARK: - Server status indicator view

struct ServerStatusIndicatorView: View {
    let isRunning: Bool
    @State private var isPulsing: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isRunning ? Color.green : Color.white.opacity(0.5))
                .frame(width: 10, height: 10)
                .scaleEffect(isRunning && isPulsing ? 1.3 : 1.0)
                .shadow(color: isRunning ? Color.green.opacity(0.9) : Color.clear, radius: 6, x: 0, y: 0)

            Text(isRunning ? "Server running" : "Server stopped")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.90))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background {
            ZStack {
                Capsule()
                    .fill(.ultraThinMaterial)

                Capsule()
                    .fill(Color.white.opacity(isRunning ? 0.12 : 0.06))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.16), Color.clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.72)
                        )
                    )
            }
        }
        .overlay {
            Capsule()
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.16), radius: 6, x: 0, y: 3)
        .onAppear { isPulsing = isRunning }
        .onChange(of: isRunning) { _, newValue in isPulsing = newValue }
        .animation(
            isRunning
                ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true)
                : .easeOut(duration: 0.2),
            value: isPulsing
        )
    }
}

// MARK: - Runner banner view

struct RunnerBannerView: View {
    let isRunning: Bool
    let bannerColor: Color

    private let sceneHeight: CGFloat = 50
    @State private var scene = RunnerScene(size: CGSize(width: 400, height: 50))

    var body: some View {
        SpriteView(
                    scene: scene,
                    preferredFramesPerSecond: 30,
                    options: [.ignoresSiblingOrder],
                    debugOptions: []
                )
                .frame(maxWidth: .infinity, maxHeight: sceneHeight)
                .clipShape(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous))
                .overlay {
                    ZStack {
                        // Specular highlight — top curved edge of the glass screen
                        RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.10), Color.clear],
                                    startPoint: .top,
                                    endPoint: UnitPoint(x: 0.5, y: 0.45)
                                )
                            )
                        // Hairline rim border — glassware has a rim
                        RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                    }
                }
                .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
                .contentShape(Rectangle())
                .onTapGesture {
                    scene.handleUserJumpInput()
                }
                .onAppear {
            scene.scaleMode = .resizeFill
            scene.isPaused = !isRunning
            scene.setBackgroundColor(bannerColor.toSKColor())
        }
        .onChange(of: isRunning) { _, newValue in scene.isPaused = !newValue }
        .onChange(of: bannerColor) { _, newColor in scene.setBackgroundColor(newColor.toSKColor()) }
    }
}


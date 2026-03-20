import SwiftUI
import AVKit
import AVFoundation
import Combine
#if os(macOS)
import AppKit
#endif

/// Splash on cold launch only, then show ContentView.
/// - Plays `splash_intro.(mp4|mov|m4v)` once and dismisses when it ends.
/// - If the video is missing, shows a fallback briefly then dismisses.
struct SplashGateView: View {

    @State private var isShowingSplash = true

    // Safety: never get stuck on splash.
    private let maxSplashTime: TimeInterval = 12.0

    var body: some View {
        Group {
            if isShowingSplash {
                SplashView {
                    dismissSplash()
                }
                .transition(.opacity)
            } else {
                ContentView()
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + maxSplashTime) {
                dismissSplash()
            }
        }
    }

    private func dismissSplash() {
        guard isShowingSplash else { return }
        withAnimation(.easeOut(duration: 0.20)) {
            isShowingSplash = false
        }
    }
}

private struct SplashView: View {
    let onFinished: () -> Void

    @StateObject private var model = SplashVideoPlayerModel()
    @State private var didFinish = false

    private let fallbackDuration: TimeInterval = 1.0
    private let bg = Color(.sRGB, red: 25.5 / 255, green: 23.5 / 255, blue: 21.5 / 255, opacity: 1.0)
    private let videoAspect: CGFloat = 704.0 / 1280.0

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            if model.hasVideo {
                GeometryReader { proxy in
                    let targetWidth = min(proxy.size.width, proxy.size.height) * 0.25
                    let targetHeight = targetWidth / videoAspect

                    MacSplashVideoLayerView(
                        player: model.player,
                        isReadyToDisplay: model.isReadyToDisplay
                    )
                    .frame(width: targetWidth, height: targetHeight)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
                .ignoresSafeArea()
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "gamecontroller")
                        .font(.system(size: 44, weight: .semibold))
                    Text("Minecraft Server Controller")
                        .font(.headline)
                        .opacity(0.9)
                }
                .foregroundStyle(.white)
            }
        }
        .onAppear {
            model.prepareAndPlay()

            if !model.hasVideo {
                DispatchQueue.main.asyncAfter(deadline: .now() + fallbackDuration) {
                    finishOnce()
                }
            }
        }
        .onDisappear {
            model.pause()
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            guard model.hasVideo else { return }
            guard let endedItem = notification.object as? AVPlayerItem else { return }
            guard endedItem === model.currentItem else { return }

            model.pause()
            finishOnce()
        }
    }

    private func finishOnce() {
        guard !didFinish else { return }
        didFinish = true
        onFinished()
    }
}

private final class SplashVideoPlayerModel: ObservableObject {
    let player: AVPlayer
    let hasVideo: Bool
    let currentItem: AVPlayerItem?

    @Published var isReadyToDisplay = false

    private var statusObserver: NSKeyValueObservation?

    init() {
        if let url = Self.findSplashVideoURL() {
            let item = AVPlayerItem(url: url)
            self.currentItem = item
            self.player = AVPlayer(playerItem: item)
            self.hasVideo = true

            statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                DispatchQueue.main.async {
                    self?.isReadyToDisplay = (item.status == .readyToPlay)
                }
            }
        } else {
            self.currentItem = nil
            self.player = AVPlayer()
            self.hasVideo = false
            self.isReadyToDisplay = false
        }
    }

    func prepareAndPlay() {
        guard hasVideo else {
            player.play()
            return
        }

        player.seek(to: .zero)
        player.play()
    }

    func pause() {
        player.pause()
    }

    private static func findSplashVideoURL() -> URL? {
        let candidateBaseNames = ["splash_intro", "splash_intro (1)"]

        for baseName in candidateBaseNames {
            for ext in ["mp4", "mov", "m4v"] {
                if let url = Bundle.main.url(forResource: baseName, withExtension: ext) {
                    return url
                }
            }
        }

        return nil
    }
}

private struct MacSplashVideoLayerView: NSViewRepresentable {
    let player: AVPlayer
    let isReadyToDisplay: Bool

    func makeNSView(context: Context) -> SplashPlayerContainerView {
        let view = SplashPlayerContainerView()
        view.configure(player: player)
        view.setReadyToDisplay(isReadyToDisplay)
        return view
    }

    func updateNSView(_ nsView: SplashPlayerContainerView, context: Context) {
        nsView.configure(player: player)
        nsView.setReadyToDisplay(isReadyToDisplay)
    }
}

private final class SplashPlayerContainerView: NSView {
    private let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.clear.cgColor
        playerLayer.opacity = 0.0

        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }

    func configure(player: AVPlayer) {
        if playerLayer.player !== player {
            playerLayer.player = player
        }
    }

    func setReadyToDisplay(_ ready: Bool) {
        playerLayer.opacity = ready ? 1.0 : 0.0
    }
}

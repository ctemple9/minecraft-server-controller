import SwiftUI
import AppKit
import Combine

// Shared UserDefaults key for the "don't show again" quit warning preference.
let MSCSuppressQuitWarningKey = "MSC.suppressQuitWhileRunningWarning"

// Main window size persistence keys (content size, not full frame).
private let MSCMainWindowContentWidthKey = "MSC.mainWindowContentWidth"
private let MSCMainWindowContentHeightKey = "MSC.mainWindowContentHeight"

private let MSCMainWindowDefaultWidth: CGFloat = 1600
private let MSCMainWindowDefaultHeight: CGFloat = 940

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    var viewModel: AppViewModel?

    // Held so we can identify the main window by identity (===) for sizing persistence.
    weak var mainWindow: NSWindow?

    private var mainWindowResizeObserver: NSObjectProtocol?

    // MARK: - Graceful-quit bookkeeping
    //
    // When Cmd+Q / Quit is issued while a server is running we defer termination
    // (.terminateLater), run the same graceful stop the Stop button uses, and reply
    // to the termination request only once — either when the server actually stops
    // (isServerRunning flips to false) or after a hard timeout.
    private var pendingQuitCancellable: AnyCancellable?
    private var pendingQuitTimeout: DispatchWorkItem?
    private var hasRepliedToPendingQuit = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Single-instance guard for launchd watchdog compatibility.
        // When launchd relaunches MSC it doesn't know an instance is already running,
        // so it starts a second one. We detect this, activate the existing window, and
        // exit(0). launchd won't restart on a clean exit (KeepAlive.SuccessfulExit = false).
        let me = NSRunningApplication.current
        if let existing = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == me.bundleIdentifier && $0.processIdentifier != me.processIdentifier
        }) {
            existing.activate(options: .activateIgnoringOtherApps)
            exit(0)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        NSColorPanel.setPickerMask(.wheelModeMask)
        NSColorPanel.setPickerMode(.wheel)
    }

    /// Intercepts Cmd+Q / Quit so a running server is stopped *gracefully* before the
    /// app exits, instead of being hard-killed by `applicationWillTerminate`.
    ///
    /// - No server running → terminate immediately.
    /// - Server running, warning suppressed → skip the dialog but STILL perform a
    ///   graceful stop (the suppression only silences the prompt, never the safe stop;
    ///   the Bedrock VM must never be hard-powered-off mid-write).
    /// - Server running, warning not suppressed → confirm with an NSAlert (with a
    ///   "Don't ask again" checkbox wired to `MSCSuppressQuitWarningKey`).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let viewModel, viewModel.isServerRunning else {
            return .terminateNow
        }

        let suppressed = UserDefaults.standard.bool(forKey: MSCSuppressQuitWarningKey)
        if suppressed {
            beginGracefulShutdownForQuit(viewModel)
            return .terminateLater
        }

        let alert = NSAlert()
        alert.messageText = "A server is running"
        alert.informativeText = "Quitting now will stop the running Minecraft server. "
            + "MSC will stop it safely (saving the world first) before quitting."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Stop Server & Quit")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return .terminateCancel
        }

        if alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: MSCSuppressQuitWarningKey)
        }

        beginGracefulShutdownForQuit(viewModel)
        return .terminateLater
    }

    /// Runs the exact Stop-button path (`stopServer()`), which fires the stop-time
    /// auto-backup, tears down broadcasts/playit, marks the stop as user-requested (so
    /// no "unexpected stop" dialog), and sends the graceful stop to the backend —
    /// `stop()`, never `terminate()`, for the Bedrock VM. Then waits for the server to
    /// actually terminate before replying to the deferred termination request.
    private func beginGracefulShutdownForQuit(_ viewModel: AppViewModel) {
        hasRepliedToPendingQuit = false

        viewModel.stopServer()

        // Reply as soon as the backend's onDidTerminate handler flips isServerRunning
        // to false. The @Published publisher also delivers the current value on
        // subscription, so an already-stopped server resolves immediately.
        pendingQuitCancellable = viewModel.$isServerRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running in
                guard let self, !running else { return }
                self.finishPendingQuit()
            }

        // Hard timeout aligned with the VM's internal 20 s force-stop fallback. If the
        // server still hasn't stopped, we let termination proceed anyway —
        // applicationWillTerminate's force-cleanup is the last-resort backstop.
        let timeout = DispatchWorkItem { [weak self] in
            self?.finishPendingQuit()
        }
        pendingQuitTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: timeout)
    }

    /// Replies to the deferred termination request exactly once, then lets the normal
    /// termination sequence (applicationWillTerminate) run.
    private func finishPendingQuit() {
        guard !hasRepliedToPendingQuit else { return }
        hasRepliedToPendingQuit = true
        pendingQuitTimeout?.cancel()
        pendingQuitTimeout = nil
        pendingQuitCancellable = nil
        NSApplication.shared.reply(toApplicationShouldTerminate: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        WatchdogRunner.markSessionEnded()  // clean quit — watchdog must not restart
        viewModel?.forceTerminateAllRunningProcesses()
    }

    /// Configures the main window once SwiftUI has attached content to it.
    /// - Applies the persisted content size (or a default on first launch).
    /// - Persists content size on resize.
    func configureMainWindowIfNeeded(_ window: NSWindow) {
        // Avoid reconfiguring the same window repeatedly.
        if let existing = mainWindow, existing === window { return }

        mainWindow = window

        // NSVisualEffectView needs a non-opaque, clear-background
        // window so its behindWindow blending can sample the desktop below.
        window.isOpaque = false
        window.backgroundColor = .clear

        applyInitialWindowContentSizeIfNeeded(to: window)
        installMainWindowResizePersistence(for: window)
    }

    private func applyInitialWindowContentSizeIfNeeded(to window: NSWindow) {
        let defaults = UserDefaults.standard

        let hasStoredSize = defaults.object(forKey: MSCMainWindowContentWidthKey) != nil
            && defaults.object(forKey: MSCMainWindowContentHeightKey) != nil

        if hasStoredSize {
            let w = defaults.double(forKey: MSCMainWindowContentWidthKey)
            let h = defaults.double(forKey: MSCMainWindowContentHeightKey)

            // Defensive bounds — ignore corrupt/zero values.
            if w >= 300, h >= 300 {
                window.setContentSize(NSSize(width: w, height: h))
                window.center()
            } else {
                window.setContentSize(NSSize(width: MSCMainWindowDefaultWidth, height: MSCMainWindowDefaultHeight))
                window.center()
            }
        } else {
            window.setContentSize(NSSize(width: MSCMainWindowDefaultWidth, height: MSCMainWindowDefaultHeight))
            window.center()
        }
    }

    private func installMainWindowResizePersistence(for window: NSWindow) {
        if let token = mainWindowResizeObserver {
            NotificationCenter.default.removeObserver(token)
            mainWindowResizeObserver = nil
        }

        mainWindowResizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { _ in
            guard let contentSize = window.contentView?.frame.size else { return }
            UserDefaults.standard.set(Double(contentSize.width), forKey: MSCMainWindowContentWidthKey)
            UserDefaults.standard.set(Double(contentSize.height), forKey: MSCMainWindowContentHeightKey)
        }
    }
}

// MARK: - App Entry Point

@main
struct MinecraftServerControllerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = AppViewModel()

    init() {
        appDelegate.viewModel = viewModel
    }

    var body: some Scene {
        WindowGroup {
            SplashGateView()
                .environmentObject(viewModel)
                .onAppear {
                    appDelegate.viewModel = viewModel
                }
                .background(MSCMainWindowAccessor { window in
                    appDelegate.configureMainWindowIfNeeded(window)
                })
        }
        .defaultSize(width: MSCMainWindowDefaultWidth, height: MSCMainWindowDefaultHeight)
    }
}

// MARK: - NSWindow Access (SwiftUI → AppKit Bridge)

/// A tiny AppKit bridge that lets SwiftUI hand us the concrete `NSWindow` that
/// SwiftUI is actually using, without relying on `NSApplication.shared.windows`.
fileprivate struct MSCMainWindowAccessor: NSViewRepresentable {
    typealias NSViewType = WindowResolverView

    let onWindowResolved: (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowResolverView {
        let view = WindowResolverView()
        view.onWindowResolved = onWindowResolved
        return view
    }

    func updateNSView(_ nsView: WindowResolverView, context: Context) {
        nsView.onWindowResolved = onWindowResolved
    }

    fileprivate final class WindowResolverView: NSView {
        var onWindowResolved: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window, let onWindowResolved {
                onWindowResolved(window)
            }
        }
    }
}

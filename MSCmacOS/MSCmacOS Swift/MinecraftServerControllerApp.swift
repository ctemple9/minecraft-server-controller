import SwiftUI
import AppKit

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

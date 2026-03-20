//
//  QuickStartWindowController.swift
//  MinecraftServerController
//

import SwiftUI
import AppKit

final class QuickStartWindowController {
    static let shared = QuickStartWindowController()

    private var window: NSWindow?

    func show(viewModel: AppViewModel) {
        // If window already exists, just bring it to front.
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = QuickStartView()
            .environmentObject(viewModel)

        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Quick Start"
        window.contentViewController = hostingController
        window.center()
        window.isReleasedWhenClosed = false

        // Clear our reference when the user closes the window.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] notification in
            guard
                let self,
                let closingWindow = notification.object as? NSWindow,
                closingWindow == self.window
            else { return }

            self.window = nil
        }

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}


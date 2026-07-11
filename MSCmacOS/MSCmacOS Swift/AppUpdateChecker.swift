//  AppUpdateChecker.swift
//  MinecraftServerController
//
//  Provides manual "Check for Updates…" against MSC's own GitHub releases.
//  No auto-check on launch — manual-only is intentional for privacy (O2).

import Foundation
import AppKit
import Combine

// ---------------------------------------------------------------------------
// MARK: - Repo coordinates
// ---------------------------------------------------------------------------

// NOTE (human): Confirm these match your public GitHub repo slug before
// tagging the first release. Derived from `git remote -v` at implementation time.
let mscGitHubOwner = "ctemple9"
let mscGitHubRepo  = "minecraft-server-controller"

// ---------------------------------------------------------------------------
// MARK: - AppUpdateChecker
// ---------------------------------------------------------------------------

/// Observable update-check state for use in the About view.
@MainActor
final class AppUpdateChecker: ObservableObject {

    enum State {
        case idle
        case checking
        case upToDate(currentVersion: String)
        case updateAvailable(latestTag: String, releaseURL: URL)
        case error(String)
    }

    @Published private(set) var state: State = .idle

    // MARK: - Triggered from a SwiftUI view (inline result display)

    func checkForUpdates() {
        if case .checking = state { return }
        state = .checking
        Task { await performCheck() }
    }

    // MARK: - Triggered from the app menu (NSAlert result display)

    /// Checks for updates and presents an NSAlert with the result.
    /// Call from a `Commands` builder where no SwiftUI presentation context is available.
    static func checkForUpdatesShowingAlert() {
        Task { @MainActor in
            let checker = AppUpdateChecker()
            checker.state = .checking
            await checker.performCheck()
            checker.showResultAlert()
        }
    }

    // MARK: - Core check

    private func performCheck() async {
        do {
            let latestTag = try await GitHubReleaseChecker.fetchLatestReleaseTag(
                owner: mscGitHubOwner,
                repo: mscGitHubRepo
            )
            let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

            if isLatestNewer(latestTag: latestTag, than: current) {
                let releaseURLString = "https://github.com/\(mscGitHubOwner)/\(mscGitHubRepo)/releases/tag/\(latestTag)"
                let releaseURL = URL(string: releaseURLString)
                    ?? URL(string: "https://github.com/\(mscGitHubOwner)/\(mscGitHubRepo)/releases")!
                state = .updateAvailable(latestTag: latestTag, releaseURL: releaseURL)
            } else {
                state = .upToDate(currentVersion: current)
            }
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    // MARK: - Semantic version comparison

    /// Returns `true` only when the latest GitHub release tag represents a version
    /// strictly newer than the running app's version. Strips a leading "v" before
    /// comparing. Comparison is numeric per component (e.g. 1.9 < 1.10).
    private func isLatestNewer(latestTag: String, than current: String) -> Bool {
        let latest = latestTag.hasPrefix("v") ? String(latestTag.dropFirst()) : latestTag
        let latestParts  = latest.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }

        let count = max(latestParts.count, currentParts.count)
        for i in 0..<count {
            let l = i < latestParts.count  ? latestParts[i]  : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if l != c { return l > c }
        }
        return false  // equal versions → not newer
    }

    // MARK: - NSAlert (menu-item path)

    private func showResultAlert() {
        let alert = NSAlert()
        switch state {
        case .upToDate(let v):
            alert.messageText     = "You're up to date"
            alert.informativeText = "Minecraft Server Controller \(v) is the latest version."
            alert.alertStyle      = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()

        case .updateAvailable(let tag, let url):
            alert.messageText     = "Update available"
            alert.informativeText = "Version \(tag) is available on GitHub. View the release page to download."
            alert.alertStyle      = .informational
            alert.addButton(withTitle: "View Release")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(url)
            }

        case .error(let message):
            alert.messageText     = "Update check failed"
            alert.informativeText = message
            alert.alertStyle      = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()

        default:
            break
        }
    }
}

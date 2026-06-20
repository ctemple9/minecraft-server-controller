//
//  WatchdogRunner.swift
//  MinecraftServerController
//
//  Polling-based launchd watchdog. Instead of KeepAlive (which requires launchd to
//  have started the process), a shell script runs every 30 seconds via StartInterval.
//  It checks a session cookie file: if the cookie exists (MSC was running) and MSC is
//  no longer running, it relaunches MSC. The cookie is created on startup and deleted
//  on a clean quit — a crash leaves it behind, which is exactly what triggers recovery.
//
//  nonisolated static funcs throughout: this file has no @MainActor context, so the
//  project's -default-isolation=MainActor flag doesn't infer @MainActor here.
//

import Foundation

enum WatchdogRunner {

    static let label = "com.templetech.minecraftservercontroller.watchdog"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var sessionCookieURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.templetech.minecraftservercontroller/watchdog-active")
    }

    // MARK: - Session cookie (called by AppViewModel / AppDelegate, not launchctl)

    // Called on every MSC launch — tells the watchdog script this session is active.
    // Safe to call unconditionally: if the watchdog plist isn't installed, the cookie
    // is a tiny harmless file that nothing reads.
    nonisolated static func markSessionActive() {
        let dir = sessionCookieURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: sessionCookieURL.path, contents: nil)
    }

    // Called from applicationWillTerminate — tells the watchdog this was a clean quit.
    // If MSC crashes, this is never called, so the cookie persists and triggers recovery.
    nonisolated static func markSessionEnded() {
        try? FileManager.default.removeItem(at: sessionCookieURL)
    }

    // MARK: - Watchdog lifecycle

    // Writes the polling plist and loads it. bundlePath = Bundle.main.bundlePath.
    nonisolated static func enable(bundlePath: String) throws {
        let url = plistURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try buildPlist(bundlePath: bundlePath).write(to: url, atomically: true, encoding: .utf8)
        _ = runLaunchctl(["unload", url.path])  // remove stale registration if any
        try runLaunchctlOrThrow(["load", url.path])
    }

    // Unloads the plist and removes all watchdog artifacts.
    nonisolated static func disable() throws {
        try runLaunchctlOrThrow(["unload", plistURL.path])
        try? FileManager.default.removeItem(at: plistURL)
        markSessionEnded()
    }

    // Returns whether the watchdog is loaded and what bundle path it's watching.
    // The bundle path is stored in a custom MSCBundlePath key (launchd ignores
    // unknown keys) so we can detect stale paths without parsing the shell command.
    nonisolated static func checkStatus() -> (isLoaded: Bool, storedBundlePath: String?) {
        let isLoaded = runLaunchctl(["list", label]).exitCode == 0

        var storedPath: String? = nil
        if let data = try? Data(contentsOf: plistURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            storedPath = plist["MSCBundlePath"] as? String
        }

        return (isLoaded, storedPath)
    }

    // MARK: - Private

    private static func buildPlist(bundlePath: String) -> String {
        let cookie = sessionCookieURL.path
        // Single-quoted paths handle spaces; app names don't contain single quotes.
        // pgrep -f matches the full command line — since the MSC executable lives inside
        // bundlePath, any running MSC process will have bundlePath in its argv[0].
        let pollCommand = """
            [ -f '\(cookie)' ] \
            && ! /usr/bin/pgrep -f '\(bundlePath)' > /dev/null 2>&1 \
            && /bin/sleep 10 \
            && /usr/bin/open '\(bundlePath)'; \
            exit 0
            """

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/bin/sh</string>
                <string>-c</string>
                <string>\(pollCommand)</string>
            </array>
            <key>StartInterval</key>
            <integer>30</integer>
            <key>RunAtLoad</key>
            <false/>
            <key>MSCBundlePath</key>
            <string>\(bundlePath)</string>
        </dict>
        </plist>
        """
    }

    // Read pipe BEFORE waitUntilExit — same fix as JavaProcessScanner to avoid the
    // pipe-buffer deadlock when output exceeds the 64 KB kernel buffer.
    @discardableResult
    private nonisolated static func runLaunchctl(_ args: [String]) -> (exitCode: Int32, output: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        guard (try? proc.run()) != nil else { return (-1, "") }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        let output = [outData, errData]
            .compactMap { String(data: $0, encoding: .utf8) }
            .joined()
        return (proc.terminationStatus, output)
    }

    private nonisolated static func runLaunchctlOrThrow(_ args: [String]) throws {
        let result = runLaunchctl(args)
        guard result.exitCode == 0 else {
            let detail = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(
                domain: "WatchdogRunner",
                code: Int(result.exitCode),
                userInfo: [NSLocalizedDescriptionKey:
                    "launchctl \(args.first ?? "") failed (exit \(result.exitCode))\(detail.isEmpty ? "" : ": \(detail)")"]
            )
        }
    }
}

//
//  PrerequisitesView.swift
//  MinecraftServerController
//
//  Dependency checker for Java hosting, Bedrock hosting, and optional
//  remote-access tooling such as Tailscale.
//

import SwiftUI
import AppKit

// MARK: - Prerequisite Item Model

struct PrerequisiteItem: Identifiable {
    let id: String
    let name: String
    let description: String
    var status: PrerequisiteStatus
    let downloadURL: String?
    let downloadLabel: String?
    /// Additional detail shown under the status (e.g. version string, path)
    var detail: String?
}

enum PrerequisiteStatus {
    case checking
    case ready(detail: String? = nil)
    case attention(reason: String)
    case missing(reason: String)
}

// MARK: - Main View

struct PrerequisitesView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var javaItem = PrerequisiteItem(
        id: "java",
        name: "Java Runtime (JDK)",
        description: "Required to run Paper/Java servers. Java 21 (Temurin) recommended.",
        status: .checking,
        downloadURL: "https://adoptium.net/temurin/releases/?version=21&package=jdk&os=mac&arch=x64",
        downloadLabel: "Download Temurin 21",
        detail: nil
    )

    @State private var dockerItem = PrerequisiteItem(
        id: "docker",
        name: "Docker Desktop",
        description: "Required to run Bedrock servers on macOS. Hosts the Linux BDS binary in a container.",
        status: .checking,
        downloadURL: "https://www.docker.com/products/docker-desktop/",
        downloadLabel: "Download Docker Desktop",
        detail: nil
    )

    @State private var tailscaleItem = PrerequisiteItem(
        id: "tailscale",
        name: "Tailscale",
        description: "Optional. Enables MSC Remote (iOS) to connect from outside your home network.",
        status: .checking,
        downloadURL: "https://tailscale.com/download/mac",
        downloadLabel: "Download Tailscale",
        detail: nil
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // HEADER
            VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                Text("Prerequisites")
                    .font(MSC.Typography.pageTitle)
                Text("Dependency status for Java and Bedrock server hosting.")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.caption)
            }
            .padding(.horizontal, MSC.Spacing.xl)
            .padding(.top, MSC.Spacing.xl)
            .padding(.bottom, MSC.Spacing.lg)

            Divider()

            // SCROLLABLE BODY
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: MSC.Spacing.lg) {

                    // JAVA TRACK
                    trackCard(
                        title: "Java Servers",
                        systemImage: "cup.and.heat.waves",
                        items: [javaItem, tailscaleItem]
                    )

                    // BEDROCK TRACK
                    trackCard(
                        title: "Bedrock Servers",
                        systemImage: "shippingbox",
                        items: [dockerItem, tailscaleItem]
                    )

                    // NOTES
                    notesCard
                }
                .padding(.horizontal, MSC.Spacing.xl)
                .padding(.vertical, MSC.Spacing.lg)
            }
            .frame(maxHeight: .infinity)

            Divider()

            // FOOTER
            HStack {
                Button("Check Again") {
                    runAllChecks()
                }
                .buttonStyle(MSCSecondaryButtonStyle())

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(MSCPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, MSC.Spacing.xl)
            .padding(.vertical, MSC.Spacing.lg)
        }
        .frame(minWidth: 580, minHeight: 520)
        .onAppear {
            runAllChecks()
        }
    }

    // MARK: - Track Card

    @ViewBuilder
    private func trackCard(title: String, systemImage: String, items: [PrerequisiteItem]) -> some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {
            Label(title, systemImage: systemImage)
                .font(MSC.Typography.cardTitle)
                .foregroundStyle(.secondary)

            Divider()

            // Deduplicate items that appear in both tracks (Tailscale)
            let uniqueItems = deduplicated(items)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(uniqueItems.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider()
                            .padding(.vertical, MSC.Spacing.xs)
                    }
                    prereqRow(item: item)
                }
            }
        }
        .pscCard()
    }

    // Remove duplicates while preserving order
    private func deduplicated(_ items: [PrerequisiteItem]) -> [PrerequisiteItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }

    // MARK: - Prerequisite Row

    @ViewBuilder
    private func prereqRow(item: PrerequisiteItem) -> some View {
        HStack(alignment: .top, spacing: MSC.Spacing.md) {

            // Status icon
            statusIcon(for: item.status)
                .frame(width: 20)
                .padding(.top, 2)

            // Name + description + detail
            VStack(alignment: .leading, spacing: MSC.Spacing.xxs) {
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))

                Text(item.description)
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.caption)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = statusDetail(for: item) {
                    Text(detail)
                        .font(MSC.Typography.mono)
                        .foregroundStyle(statusDetailColor(for: item.status))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }

                if case .missing = item.status, let url = item.downloadURL, let label = item.downloadLabel {
                    Button(label + " \u{2197}") {
                        openURL(url)
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                    .controlSize(.small)
                    .padding(.top, MSC.Spacing.xs)
                }

                if case .attention = item.status, let url = item.downloadURL, let label = item.downloadLabel {
                    Button(label + " \u{2197}") {
                        openURL(url)
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                    .controlSize(.small)
                    .padding(.top, MSC.Spacing.xs)
                }
            }

            Spacer()
        }
        .padding(.vertical, MSC.Spacing.xs)
    }

    // MARK: - Status Icon

    @ViewBuilder
    private func statusIcon(for status: PrerequisiteStatus) -> some View {
        switch status {
        case .checking:
            ProgressView()
                .scaleEffect(0.65)
                .frame(width: 18, height: 18)
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(MSC.Colors.success)
                .font(.system(size: 18))
        case .attention:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(MSC.Colors.warning)
                .font(.system(size: 18))
        case .missing:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(MSC.Colors.error)
                .font(.system(size: 18))
        }
    }

    private func statusDetail(for item: PrerequisiteItem) -> String? {
        switch item.status {
        case .ready(let d):
            return d
        case .attention(let reason):
            return reason
        case .missing(let reason):
            return reason
        case .checking:
            return nil
        }
    }

    private func statusDetailColor(for status: PrerequisiteStatus) -> Color {
        switch status {
        case .ready:       return MSC.Colors.success
        case .attention:   return MSC.Colors.warning
        case .missing:     return MSC.Colors.error
        case .checking:    return MSC.Colors.caption
        }
    }

    // MARK: - Notes Card

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
            Label("Notes", systemImage: "info.circle")
                .font(MSC.Typography.cardTitle)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                noteRow(icon: "cup.and.heat.waves", text: "Java is only required for Java/Paper servers. Bedrock servers run via Docker and don't need Java.")
                noteRow(icon: "shippingbox", text: "Docker Desktop is only required for Bedrock servers. Start Docker Desktop before launching a Bedrock server.")
                noteRow(icon: "iphone.and.arrow.forward", text: "Tailscale is optional for both server types. It enables MSC Remote to connect to this Mac from outside your home network.")
                noteRow(icon: "wifi", text: "For friends to join, you'll need to port-forward TCP 2 (Java) or UDP (Bedrock) on your router.")
            }
        }
        .pscCard()
    }

    @ViewBuilder
    private func noteRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: MSC.Spacing.sm) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(MSC.Colors.tertiary)
                .frame(width: 16)
                .padding(.top, 1)
            Text(text)
                .font(MSC.Typography.caption)
                .foregroundStyle(MSC.Colors.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Detection Logic

    private func runAllChecks() {
        // Set all to checking first
        javaItem.status = .checking
        dockerItem.status = .checking
        tailscaleItem.status = .checking

        checkJava()
        checkDocker()
        checkTailscale()
    }

    private func checkJava() {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = detectJava(configuredPath: viewModel.configManager.config.javaPath)
            DispatchQueue.main.async {
                self.javaItem.status = result
            }
        }
    }

    private func checkDocker() {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = detectDocker()
            DispatchQueue.main.async {
                self.dockerItem.status = result
            }
        }
    }

    private func checkTailscale() {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = detectTailscale()
            DispatchQueue.main.async {
                self.tailscaleItem.status = result
            }
        }
    }

    // MARK: - Java Detection

    private func detectJava(configuredPath: String) -> PrerequisiteStatus {
        // Try the configured path first, fall back to PATH
        let candidatePaths: [String]
        let trimmed = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != "java" {
            candidatePaths = [trimmed, "java"]
        } else {
            candidatePaths = ["java"]
        }

        for candidate in candidatePaths {
            if let result = runJavaVersionCheck(path: candidate) {
                return result
            }
        }
        return .missing(reason: "Java not found. Install Temurin 21 or set your Java path in Preferences.")
    }

    private func runJavaVersionCheck(path: String) -> PrerequisiteStatus? {
        // Resolve the actual binary path if it's a bare name
        let resolvedPath: String
        if path.hasPrefix("/") {
            resolvedPath = path
        } else {
            // Use `which` to resolve PATH binary
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            proc.arguments = [path]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()
            do {
                try proc.run()
                proc.waitUntilExit()
                let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if out.isEmpty { return nil }
                resolvedPath = out
            } catch {
                return nil
            }
        }

        guard FileManager.default.isExecutableFile(atPath: resolvedPath) else { return nil }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: resolvedPath)
        proc.arguments = ["-version"]
        let pipe = Pipe()
        // java -version writes to stderr
        proc.standardError = pipe
        proc.standardOutput = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return nil
        }

        let raw = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let versionLine = raw.components(separatedBy: "\n").first(where: { $0.contains("version") }) ?? raw
        let versionString = versionLine.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !versionString.isEmpty else { return nil }

        // Extract major version number for a readability check
        // Format: openjdk version "21.0.3" 2024-04-16
        //     or: java version "1.8.0_281"
        let majorVersion = extractJavaMajorVersion(from: versionString)

        if let major = majorVersion {
            if major < 17 {
                return .attention(reason: "Java \(major) detected. Java 17 or later is required for recent Paper builds. Upgrade to Java 21.\nPath: \(resolvedPath)")
            } else if major < 21 {
                return .attention(reason: "Java \(major) detected. Java 21 is recommended for best compatibility.\nPath: \(resolvedPath)")
            } else {
                return .ready(detail: "Java \(major) found at \(resolvedPath)")
            }
        }

        // Couldn't parse version — still present, report what we found
        return .ready(detail: "\(versionString)\nPath: \(resolvedPath)")
    }

    private func extractJavaMajorVersion(from versionLine: String) -> Int? {
        // Matches: "21.0.3", "17", "1.8.0_281"
        let pattern = #"\"(\d+)(?:\.(\d+))?[^\"]*\""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: versionLine, range: NSRange(versionLine.startIndex..., in: versionLine)) else {
            return nil
        }
        guard let firstRange = Range(match.range(at: 1), in: versionLine),
              let major = Int(versionLine[firstRange]) else { return nil }

        // Legacy Java 1.x -> real version is minor (1.8 = Java 8)
        if major == 1 {
            guard let secondRange = Range(match.range(at: 2), in: versionLine),
                  let minor = Int(versionLine[secondRange]) else { return nil }
            return minor
        }
        return major
    }

    // MARK: - Docker Detection

    private func detectDocker() -> PrerequisiteStatus {
        // Check if Docker CLI exists
        guard let dockerPath = DockerUtility.dockerPath() else {
            return .missing(reason: "Docker Desktop not found. Install Docker Desktop, then restart the app.")
        }

        // Check if daemon is running
        let available = DockerUtility.isDockerAvailable()
        if available {
            // Try to get Docker version for display
            let version = dockerVersion(at: dockerPath) ?? "installed"
            return .ready(detail: "Docker \(version) — daemon running")
        } else {
            return .attention(reason: "Docker is installed but the daemon is not running. Open Docker Desktop and wait for it to start.")
        }
    }

    private func dockerVersion(at path: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = ["version", "--format", "{{.Client.Version}}"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return nil
        }
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return out.isEmpty ? nil : out
    }

    // MARK: - Tailscale Detection

    private func detectTailscale() -> PrerequisiteStatus {
        // Check for Tailscale app bundle
        let appPaths = [
            "/Applications/Tailscale.app",
            "/Applications/Utilities/Tailscale.app",
            "\(NSHomeDirectory())/Applications/Tailscale.app"
        ]
        let appInstalled = appPaths.contains { FileManager.default.fileExists(atPath: $0) }

        // Check for Tailscale CLI
        let cliPaths = [
            "/usr/local/bin/tailscale",
            "/opt/homebrew/bin/tailscale"
        ]
        let cliInstalled = cliPaths.contains { FileManager.default.isExecutableFile(atPath: $0) }

        // Check for Tailscale IP (100.x.x.x) — indicates it's connected
        if let tsIP = activeTailscaleIP() {
            return .ready(detail: "Connected — Tailscale IP: \(tsIP)")
        }

        if appInstalled || cliInstalled {
            return .attention(reason: "Tailscale is installed but not connected. Open Tailscale and sign in to enable remote access.")
        }

        return .missing(reason: "Not installed. Optional — only needed for away-from-home access via MSC Remote.")
    }

    private func activeTailscaleIP() -> String? {
        // Check network interfaces for a 100.x.x.x address (Tailscale's range)
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let addr = ptr.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let len = socklen_t(addr.pointee.sa_len)
            if getnameinfo(addr, len, &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(cString: hostname)
                if ip.hasPrefix("100.") {
                    return ip
                }
            }
        }
        return nil
    }

    // MARK: - Helpers

    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Static checker for launch-time detection

extension PrerequisitesView {

    /// Returns true if any critical dependency (Java or Docker, depending on servers configured)
    /// is missing. Used at launch to decide whether to auto-show the Prerequisites screen.
    static func hasCriticalMissingDependency(for serverTypes: Set<ServerType>) -> Bool {
        // Check Java if any Java servers are configured
        if serverTypes.contains(.java) {
            let javaOK = isJavaInstalled()
            if !javaOK { return true }
        }
        // Check Docker if any Bedrock servers are configured
        if serverTypes.contains(.bedrock) {
            let dockerOK = DockerUtility.dockerPath() != nil
            if !dockerOK { return true }
        }
        return false
    }

    private static func isJavaInstalled() -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["java"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch { return false }
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !out.isEmpty
    }
}


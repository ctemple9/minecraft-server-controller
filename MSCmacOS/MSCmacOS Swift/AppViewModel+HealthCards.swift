//
//  AppViewModel+HealthCards.swift
//  MinecraftServerController
//
//  Runs diagnostic checks and publishes results to `healthCards`.
//

import Foundation
import AppKit
import Network

// MARK: - Health card refresh entry point

extension AppViewModel {

    /// Runs all health checks for the given server and publishes results to `healthCards`.
    /// Safe to call from any async context; always publishes on MainActor.
    func refreshHealthCards(for server: ConfigServer) async {
        let cards: [HealthCardResult]
        if server.isBedrock {
            cards = await buildBedrockCards(for: server)
        } else {
            cards = await buildJavaCards(for: server)
        }
        await MainActor.run {
            self.healthCards = cards
        }
    }

    // MARK: - Convenience: refresh for the currently selected server

    func refreshHealthCardsForSelectedServer() {
        guard let sel = selectedServer,
              let cfg = configServer(for: sel) else { return }
        Task {
            await refreshHealthCards(for: cfg)
        }
    }

    // MARK: - Java cards (6 cards)

    private func buildJavaCards(for server: ConfigServer) async -> [HealthCardResult] {
        // Read the actual port from server.properties rather than assuming 25565.
        // This means changing the port in settings immediately affects the health card.
        let javaPort = await MainActor.run { loadServerPropertiesModel(for: server).serverPort }
        async let dir   = checkDirectory(for: server)
        async let java  = checkJavaRuntime(for: server)
        async let jar   = checkComponentJars(for: server)
        async let ram   = checkRAMAllocation(for: server)
        async let port  = checkPortReachability(port: javaPort, isUDP: false, serverHasEverStarted: server.hasEverStarted)
        async let start = checkLastStartup(for: server)
        return await [dir, java, jar, ram, port, start]
    }

    // MARK: - Bedrock cards (6 cards: directory, docker, components(BDS+BC), worldData, port, lastStartup)

    private func buildBedrockCards(for server: ConfigServer) async -> [HealthCardResult] {
        // Read the actual Bedrock port (from config or Geyser config), fall back to 19132.
        let bedrockPort = await MainActor.run { effectiveBedrockPort(for: server) ?? 19132 }
        let playerCount = await MainActor.run { onlinePlayers.count }
        async let dir    = checkDirectory(for: server)
        async let docker = checkDockerForHealthCard()
        async let comps  = checkBedrockComponents(for: server)
        async let world  = checkBedrockWorldData(for: server)
        async let port   = checkPortReachability(port: bedrockPort, isUDP: true, serverHasEverStarted: server.hasEverStarted, onlinePlayerCount: playerCount)
        async let start  = checkLastStartup(for: server)
        return await [dir, docker, comps, world, port, start]
    }

    // MARK: - Resolved executable paths

    private func resolvedPath(candidates: [String]) -> String? {
        candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    private var javaSearchPaths: [String] {
        var paths: [String] = []
        let configured = configManager.config.javaPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !configured.isEmpty && configured != "java" {
            paths.append(configured)
        }
        if let javaHome = ProcessInfo.processInfo.environment["JAVA_HOME"] {
            paths.append((javaHome as NSString).appendingPathComponent("bin/java"))
        }
        if let jhPath = resolveJavaHomeOutput() {
            paths.append(jhPath)
        }
        paths += [
            "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java",
            "/Library/Java/JavaVirtualMachines/temurin-22.jdk/Contents/Home/bin/java",
            "/Library/Java/JavaVirtualMachines/temurin-23.jdk/Contents/Home/bin/java",
            "/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home/bin/java",
            "/opt/homebrew/opt/openjdk@21/bin/java",
            "/opt/homebrew/opt/openjdk@22/bin/java",
            "/opt/homebrew/opt/openjdk@17/bin/java",
            "/opt/homebrew/opt/openjdk/bin/java",
            "/usr/local/opt/openjdk@21/bin/java",
            "/usr/local/opt/openjdk@22/bin/java",
            "/usr/local/opt/openjdk@17/bin/java",
            "/usr/local/opt/openjdk/bin/java",
            "/Library/Java/JavaVirtualMachines/zulu-21.jdk/Contents/Home/bin/java",
            "/Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home/bin/java",
            "/Library/Java/JavaVirtualMachines/jdk-21.jdk/Contents/Home/bin/java",
            "/usr/bin/java",
        ]
        return paths
    }

    private func resolveJavaHomeOutput() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/libexec/java_home")
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let home = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !home.isEmpty else { return nil }
            return (home as NSString).appendingPathComponent("bin/java")
        } catch {
            return nil
        }
    }

    private var dockerSearchPaths: [String] {
        [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/usr/local/opt/docker/bin/docker",
            "/usr/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
        ]
    }

    // MARK: - Card: Server Directory

    private func checkDirectory(for server: ConfigServer) async -> HealthCardResult {
        let path = server.serverDir
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: path, isDirectory: &isDir)

        guard exists, isDir.boolValue else {
            return HealthCardResult(
                id: "directory",
                status: .red,
                detectedValue: "Path not found:\n\(path)",
                actionLabel: "Locate Folder",
                actionType: .locateFolder
            )
        }

        let writable = fm.isWritableFile(atPath: path)
        let readable = fm.isReadableFile(atPath: path)

        if writable && readable {
            return HealthCardResult(id: "directory", status: .green, detectedValue: path, actionLabel: nil, actionType: nil)
        } else {
            return HealthCardResult(
                id: "directory",
                status: .yellow,
                detectedValue: "Exists but may have permission issues:\n\(path)",
                actionLabel: "Locate Folder",
                actionType: .locateFolder
            )
        }
    }

    // MARK: - Card: Java Runtime

    private func checkJavaRuntime(for server: ConfigServer) async -> HealthCardResult {
        for candidate in javaSearchPaths {
            guard FileManager.default.fileExists(atPath: candidate) else { continue }
            let result = await runProcess(executable: candidate, arguments: ["-version"], timeoutSeconds: 5)
            let combinedOutput = result.stderr + result.stdout
            guard result.exitCode == 0, !combinedOutput.isEmpty else { continue }

            let versionString = extractJavaVersion(from: combinedOutput)
            let majorVersion  = parseJavaMajorVersion(from: versionString)

            if let major = majorVersion {
                if major >= 21 {
                    return HealthCardResult(
                        id: "java",
                        status: .green,
                        detectedValue: "\(versionString ?? "Java \(major)") — minimum is Java 21 \u{2713}\nPath: \(candidate)",
                        actionLabel: nil,
                        actionType: nil
                    )
                } else {
                    return HealthCardResult(
                        id: "java",
                        status: .yellow,
                        detectedValue: "\(versionString ?? "Java \(major)") detected — minimum is Java 21\nPath: \(candidate)",
                        actionLabel: "Download Java",
                        actionType: .openURL("https://adoptium.net")
                    )
                }
            }

            return HealthCardResult(
                id: "java",
                status: .yellow,
                detectedValue: "Java found but version unreadable.\nOutput: \(combinedOutput.prefix(120))\nPath: \(candidate)",
                actionLabel: "Download Java",
                actionType: .openURL("https://adoptium.net")
            )
        }

        return HealthCardResult(
            id: "java",
            status: .red,
            detectedValue: "Java not found. Checked \(javaSearchPaths.count) locations.\nInstall Adoptium Temurin 21 or set your Java path in Preferences.",
            actionLabel: "Download Java",
            actionType: .openURL("https://adoptium.net")
        )
    }

    // MARK: - Card: Docker Runtime (Bedrock)

    private func checkDockerForHealthCard() async -> HealthCardResult {
        guard let dockerPath = resolvedPath(candidates: dockerSearchPaths) else {
            return HealthCardResult(
                id: "docker",
                status: .red,
                detectedValue: "Docker binary not found.\nChecked \(dockerSearchPaths.count) locations.\nInstall Docker Desktop to run Bedrock servers.",
                actionLabel: "Download Docker Desktop",
                actionType: .openURL("https://www.docker.com/products/docker-desktop")
            )
        }

        let versionResult = await runProcess(executable: dockerPath, arguments: ["--version"], timeoutSeconds: 4)
        let versionString = versionResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        let infoResult = await runProcess(executable: dockerPath, arguments: ["info"], timeoutSeconds: 5)
        let daemonRunning = infoResult.exitCode == 0

        if daemonRunning {
            return HealthCardResult(
                id: "docker",
                status: .green,
                detectedValue: versionString.isEmpty ? "Docker installed, daemon running." : "\(versionString)\nDaemon: running",
                actionLabel: nil,
                actionType: nil
            )
        } else {
            return HealthCardResult(
                id: "docker",
                status: .yellow,
                detectedValue: "\(versionString.isEmpty ? "Docker installed" : versionString)\nDaemon not running — open Docker Desktop first.",
                actionLabel: "Open Docker Desktop",
                actionType: .openDockerDesktop
            )
        }
    }

    // MARK: - Card: Components (Java)
    //
    // Java: Paper · Geyser · Floodgate · XboxBroadcast · BedrockConnect (as plugin)
    // Red    — Paper JAR missing (required)
    // Yellow — at least one installed JAR has an update available
    // Green  — all installed JARs up to date

    private func checkComponentJars(for server: ConfigServer) async -> HealthCardResult {
        guard FileManager.default.fileExists(atPath: server.paperJarPath) else {
            return HealthCardResult(
                id: "jar",
                status: .red,
                detectedValue: "Paper JAR not found at:\n\(server.paperJarPath)\nDownload it from the Components tab.",
                actionLabel: "Go to Components",
                actionType: .openComponentsTab
            )
        }

        let snap = await MainActor.run { componentsSnapshot }

        let allComponents: [(name: String, local: String?, online: String?)] = [
            ("Paper",          snap.paper.local,          snap.paper.online),
            ("Geyser",         snap.geyser.local,         snap.geyser.online),
            ("Floodgate",      snap.floodgate.local,      snap.floodgate.online),
            ("XboxBroadcast",  snap.broadcast.local,      snap.broadcast.online),
            ("BedrockConnect", snap.bedrockConnect.local,  snap.bedrockConnect.online),
        ]

        let installed = allComponents.filter { $0.local != nil }
        guard !installed.isEmpty else {
            return HealthCardResult(
                id: "jar",
                status: .gray,
                detectedValue: "No component JARs found. Download Paper from the Components tab.",
                actionLabel: "Go to Components",
                actionType: .openComponentsTab
            )
        }

        let outdated = installed.filter { c in
            guard let local = c.local, let online = c.online else { return false }
            return !jarVersionsMatchForHealth(local, online)
        }

        let detailLines: [String] = installed.compactMap { c in
            guard let local = c.local else { return nil }
            if let online = c.online {
                let marker = jarVersionsMatchForHealth(local, online) ? "\u{2713}" : "\u{2191}"
                return "\(marker) \(c.name): \(local)"
            }
            return "\u{00B7} \(c.name): \(local)"
        }
        let detail = detailLines.joined(separator: "\n")

        if !outdated.isEmpty {
            let names = outdated.map { $0.name }.joined(separator: ", ")
            return HealthCardResult(
                id: "jar",
                status: .yellow,
                detectedValue: "Update available: \(names)\n\n\(detail)",
                actionLabel: "Go to Components",
                actionType: .openComponentsTab
            )
        }

        let onlineChecked = installed.contains { $0.online != nil }
        let suffix = onlineChecked ? " — all up to date" : " installed"
        return HealthCardResult(
            id: "jar",
            status: .green,
            detectedValue: "\(installed.count) component\(installed.count == 1 ? "" : "s")\(suffix)\n\n\(detail)",
            actionLabel: nil,
            actionType: nil
        )
    }

    // MARK: - Card: Bedrock Components (merged: BDS Image + BedrockConnect standalone)
    //
    // This replaces both the old standalone bdsImage card and the old jar card for Bedrock.
    // Worst status wins: if BDS image is red, the whole card is red.
    // BedrockConnect is optional — gray if not installed, green/yellow if installed.

    private func checkBedrockComponents(for server: ConfigServer) async -> HealthCardResult {
        // --- BDS Image check (primary — determines red vs not-red) ---
        let imageResult = await checkBedrockImageStatus()

        // RED: BDS image is not pulled. Nothing else matters.
        if imageResult.status == .red {
            return HealthCardResult(
                id: "jar",
                status: .red,
                detectedValue: "BDS Image: not pulled\nPull the itzg/minecraft-bedrock-server image before starting your server.",
                actionLabel: "Pull BDS Image",
                actionType: .pullDockerImage
            )
        }

        // Image is present. Now check BedrockConnect — but ONLY if it is enabled.
        // If BC is not enabled, its installation state is irrelevant and does not affect status.
        let bcEnabled = server.bedrockConnectStandaloneEnabled
        let bcInstalled = await MainActor.run { isBedrockConnectJarInstalled }

        var lines: [String] = []
        lines.append("BDS Image: \(imageResult.summary)")

        if bcEnabled && !bcInstalled {
            // YELLOW: User turned on BC but hasn't downloaded the JAR yet.
            lines.append("BedrockConnect: enabled but JAR not installed")
            return HealthCardResult(
                id: "jar",
                status: .yellow,
                detectedValue: lines.joined(separator: "\n"),
                actionLabel: "Go to Components",
                actionType: .openComponentsTab
            )
        }

        // GREEN: image is present; BC is either not enabled (irrelevant) or enabled+installed.
        if bcEnabled && bcInstalled {
            lines.append("BedrockConnect: installed and enabled")
        } else {
            lines.append("BedrockConnect: not enabled")
        }

        return HealthCardResult(
            id: "jar",
            status: .green,
            detectedValue: lines.joined(separator: "\n"),
            actionLabel: "Manage in Components",
            actionType: .openComponentsTab
        )
    }

    private struct ComponentCheckSummary {
        let status: HealthStatus
        let summary: String
    }

    private func checkBedrockImageStatus() async -> ComponentCheckSummary {
        guard let dockerPath = resolvedPath(candidates: dockerSearchPaths) else {
            return ComponentCheckSummary(status: .gray, summary: "Docker not found")
        }

        let result = await runProcess(
            executable: dockerPath,
            arguments: ["images", "itzg/minecraft-bedrock-server", "--format", "{{.Tag}} {{.CreatedSince}}"],
            timeoutSeconds: 6
        )

        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.exitCode != 0 || output.isEmpty {
            return ComponentCheckSummary(status: .red, summary: "Not pulled")
        }
        let firstLine = output.components(separatedBy: "\n").first ?? output
        return ComponentCheckSummary(status: .green, summary: firstLine)
    }

    // Must be called on MainActor since it reads isBedrockConnectJarInstalled
    @MainActor
    private func checkBedrockConnectStandaloneStatus(for server: ConfigServer) -> ComponentCheckSummary {
        // Check if BedrockConnect standalone JAR is installed in the app's BC directory
        let jarExists = isBedrockConnectJarInstalled
        if !jarExists {
            return ComponentCheckSummary(status: .gray, summary: "Not installed (optional)")
        }

        // Check if it's enabled for this server
        let enabled = server.bedrockConnectStandaloneEnabled
        if !enabled {
            return ComponentCheckSummary(status: .yellow, summary: "Installed, not enabled")
        }

        return ComponentCheckSummary(status: .green, summary: "Installed and enabled")
    }

    // MARK: - Card: RAM Allocation (Java)

    private func checkRAMAllocation(for server: ConfigServer) async -> HealthCardResult {
        let allocatedGB = server.maxRamGB
        let physicalBytes = ProcessInfo.processInfo.physicalMemory
        let physicalGB = Int(physicalBytes / (1024 * 1024 * 1024))

        if allocatedGB <= 0 || (physicalGB > 0 && allocatedGB > physicalGB) {
            return HealthCardResult(
                id: "ram",
                status: .red,
                detectedValue: "Configured: \(allocatedGB) GB — Physical RAM: \(physicalGB) GB\nAllocation exceeds physical memory.",
                actionLabel: nil,
                actionType: nil
            )
        }

        let fraction = physicalGB > 0 ? Double(allocatedGB) / Double(physicalGB) : 0

        if fraction > 0.8 {
            return HealthCardResult(
                id: "ram",
                status: .yellow,
                detectedValue: "Configured: \(allocatedGB) GB — Physical RAM: \(physicalGB) GB\n\(Int(fraction * 100))% of system RAM — may cause instability.",
                actionLabel: nil,
                actionType: nil
            )
        }

        return HealthCardResult(
            id: "ram",
            status: .green,
            detectedValue: "Configured: \(allocatedGB) GB — Physical RAM: \(physicalGB) GB",
            actionLabel: nil,
            actionType: nil
        )
    }

    // MARK: - Card: World Data (Bedrock)

    private func checkBedrockWorldData(for server: ConfigServer) async -> HealthCardResult {
        let worldsPath = (server.serverDir as NSString).appendingPathComponent("worlds")
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: worldsPath, isDirectory: &isDir)

        guard exists, isDir.boolValue else {
            if !server.hasEverStarted {
                return HealthCardResult(
                    id: "worldData",
                    status: .gray,
                    detectedValue: "worlds/ will be created automatically when you start the server for the first time.",
                    actionLabel: nil,
                    actionType: nil
                )
            }
            return HealthCardResult(
                id: "worldData",
                status: .red,
                detectedValue: "worlds/ directory not found at:\n\(worldsPath)\nExpected after server has run at least once.",
                actionLabel: "Locate World Data",
                actionType: .locateFolder
            )
        }

        let contents = (try? fm.contentsOfDirectory(atPath: worldsPath)) ?? []
        if contents.isEmpty {
            return HealthCardResult(
                id: "worldData",
                status: .yellow,
                detectedValue: "worlds/ exists but appears empty.\nStart the server to generate world data.",
                actionLabel: nil,
                actionType: nil
            )
        }

        return HealthCardResult(
            id: "worldData",
            status: .green,
            detectedValue: "\(contents.count) item(s) found in worlds/",
            actionLabel: nil,
            actionType: nil
        )
    }

    // MARK: - Card: Port Reachability
    //
    // Strategy:
    //   1. Local loopback probe — confirms the process is actually listening on the port.
    //      Uses NWConnection for TCP or a UDP send-receive for UDP.
    //   2. External TCP check — confirms the port is reachable from the internet.
    //      UDP external checks are inherently unreliable (stateless protocol); skip for Bedrock.
    //
    // Result logic:
    //   - Local fails:    red   "Server is not listening on port X — is it running?"
    //   - Local ok, external fails (TCP only): yellow  "Server is up locally, port may not be forwarded"
    //   - Local ok, external ok (TCP):         green   "Port X is open and reachable"
    //   - Local ok, UDP:                       yellow  "Server is listening locally; UDP external checks are unreliable"
    //   - Not yet started:                     gray

    // onlinePlayerCount: Bedrock UDP card turns green when > 0 (player presence proves port is open).
    private func checkPortReachability(port: Int, isUDP: Bool, serverHasEverStarted: Bool, onlinePlayerCount: Int = 0) async -> HealthCardResult {
        let cardID = "port"
        let guideURL = "https://minecraft.wiki/w/Tutorials/Setting_up_a_server#Forwarding_ports"

        guard serverHasEverStarted else {
            return HealthCardResult(
                id: cardID,
                status: .gray,
                detectedValue: "Waiting for first start\nPort \(port) (\(isUDP ? "UDP" : "TCP"))",
                actionLabel: "View Port Setup Guide",
                actionType: .openRouterPortForwardGuide
            )
        }

        // --- Step 1: Local loopback probe ---
        let localListening = await probeLocalPort(port: port, isUDP: isUDP)

        if !localListening {
            return HealthCardResult(
                id: cardID,
                status: .red,
                detectedValue: "Port \(port) (\(isUDP ? "UDP" : "TCP"))\nNot listening locally\nStart the server before checking reachability.",
                actionLabel: "View Port Setup Guide",
                actionType: .openRouterPortForwardGuide
            )
        }

        // --- UDP: can't verify externally, but a connected player proves port is open ---
        if isUDP {
            if onlinePlayerCount > 0 {
                let s = onlinePlayerCount == 1 ? "" : "s"
                return HealthCardResult(
                    id: cardID,
                    status: .green,
                    detectedValue: "Port \(port) (UDP)\nListening locally \u{2713}\n\(onlinePlayerCount) player\(s) connected \u{2713}\nPort is reachable.",
                    actionLabel: nil,
                    actionType: nil
                )
            }
            return HealthCardResult(
                id: cardID,
                status: .yellow,
                detectedValue: "Port \(port) (UDP)\nListening locally \u{2713}\nUDP cannot be verified externally\nWill turn green when a player connects.",
                actionLabel: "View Port Setup Guide",
                actionType: .openRouterPortForwardGuide
            )
        }

        // --- Step 2: External TCP check ---
        guard let url = URL(string: "https://portchecker.io/api/v1/query") else {
            return portResultLocalOnly(port: port)
        }

        let publicIP = await MainActor.run { cachedPublicIPAddress } ?? "unknown"

        var request = URLRequest(url: url, timeoutInterval: 8)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["host": publicIP, "ports": [port]]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return portResultLocalOnly(port: port)
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let checks = json["check"] as? [[String: Any]],
               let first = checks.first,
               let status = first["status"] as? String {
                switch status {
                case "open":
                    return HealthCardResult(
                        id: cardID,
                        status: .green,
                        detectedValue: "Port \(port) (TCP)\nListening locally \u{2713}\nReachable from internet \u{2713}\nPublic IP \(publicIP)",
                        actionLabel: nil,
                        actionType: nil
                    )
                case "closed":
                    return HealthCardResult(
                        id: cardID,
                        status: .yellow,
                        detectedValue: "Port \(port) (TCP)\nListening locally \u{2713}\nNot reachable externally \u{2717}\nPublic IP \(publicIP)\nCheck router port forwarding.",
                        actionLabel: "View Port Setup Guide",
                        actionType: .openRouterPortForwardGuide
                    )
                default:
                    break
                }
            }
            return portResultLocalOnly(port: port)
        } catch {
            return portResultLocalOnly(port: port)
        }
    }

    /// Probes 127.0.0.1 on the given port to see if anything is listening.
    /// TCP: attempts a connection with a 2s timeout.
    /// UDP: sends a zero-byte datagram and checks for an immediate port-unreachable ICMP (best-effort).
    private func probeLocalPort(port: Int, isUDP: Bool) async -> Bool {
        if isUDP {
            // UDP is stateless — we can't reliably confirm a listener via loopback.
            // A "port unreachable" ICMP response means nothing is listening; no response
            // often means something is. Use a best-effort approach: attempt a connection
            // via NWConnection with UDP and accept the ambiguity.
            return await withCheckedContinuation { continuation in
                let host = NWEndpoint.Host("127.0.0.1")
                let port = NWEndpoint.Port(integerLiteral: UInt16(port))
                let connection = NWConnection(host: host, port: port, using: .udp)

                final class ResolutionState {
                    let lock = NSLock()
                    var resolved = false
                }
                let state = ResolutionState()
                func finish(_ value: Bool) {
                    state.lock.lock()
                    defer { state.lock.unlock() }
                    guard !state.resolved else { return }
                    state.resolved = true
                    connection.cancel()
                    continuation.resume(returning: value)
                }

                let timeout = DispatchWorkItem {
                    // UDP ambiguity: assume listening if we got this far (no immediate error)
                    finish(true)
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 1.5, execute: timeout)

                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        timeout.cancel()
                        finish(true)
                    case .failed:
                        timeout.cancel()
                        finish(false)
                    default:
                        break
                    }
                }
                connection.start(queue: .global())
            }
        } else {
            // TCP: a successful connect proves a listener is present.
            return await withCheckedContinuation { continuation in
                let host = NWEndpoint.Host("127.0.0.1")
                let port = NWEndpoint.Port(integerLiteral: UInt16(port))
                let connection = NWConnection(host: host, port: port, using: .tcp)

                final class ResolutionState {
                    let lock = NSLock()
                    var resolved = false
                }
                let state = ResolutionState()
                func finish(_ value: Bool) {
                    state.lock.lock()
                    defer { state.lock.unlock() }
                    guard !state.resolved else { return }
                    state.resolved = true
                    connection.cancel()
                    continuation.resume(returning: value)
                }

                let timeout = DispatchWorkItem {
                    finish(false)
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 2.0, execute: timeout)

                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        timeout.cancel()
                        finish(true)
                    case .failed, .waiting:
                        timeout.cancel()
                        finish(false)
                    default:
                        break
                    }
                }
                connection.start(queue: .global())
            }
        }
    }

    private func portResultLocalOnly(port: Int) -> HealthCardResult {
        HealthCardResult(
            id: "port",
            status: .yellow,
            detectedValue: "Port \(port) (TCP)\nListening locally \u{2713}\nExternal check inconclusive\nTest from another network to verify.",
            actionLabel: "View Port Setup Guide",
            actionType: .openRouterPortForwardGuide
        )
    }

    // MARK: - Card: Last Startup

    private func checkLastStartup(for server: ConfigServer) async -> HealthCardResult {
        let resultPath = (server.serverDir as NSString)
            .appendingPathComponent("last_startup_result.json")

        guard FileManager.default.fileExists(atPath: resultPath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: resultPath)),
              let result = try? JSONDecoder().decode(LastStartupResult.self, from: data) else {
            return HealthCardResult(
                id: "lastStartup",
                status: .gray,
                detectedValue: "Start your server for the first time to see health data here.",
                actionLabel: nil,
                actionType: nil
            )
        }

        if result.wasClean {
            return HealthCardResult(
                id: "lastStartup",
                status: .green,
                detectedValue: "Last start: \(formatDate(result.startedAt))\nNo fatal errors detected.",
                actionLabel: nil,
                actionType: nil
            )
        } else if !result.fatalErrors.isEmpty {
            let preview = result.fatalErrors.prefix(3).joined(separator: "\n")
            return HealthCardResult(
                id: "lastStartup",
                status: .red,
                detectedValue: "Last start: \(formatDate(result.startedAt))\n\(preview)",
                actionLabel: "View Full Console Log",
                actionType: .openConsoleLog
            )
        } else if !result.warnings.isEmpty {
            return HealthCardResult(
                id: "lastStartup",
                status: .yellow,
                detectedValue: "Last start: \(formatDate(result.startedAt))\n\(result.warnings.count) warning(s) logged.",
                actionLabel: nil,
                actionType: nil
            )
        }

        return HealthCardResult(
            id: "lastStartup",
            status: .yellow,
            detectedValue: "Last start: \(formatDate(result.startedAt))\nResult inconclusive.",
            actionLabel: nil,
            actionType: nil
        )
    }

    // MARK: - LastStartupResult persistence

    func writeLastStartupResult(for server: ConfigServer, wasClean: Bool, fatalErrors: [String], warnings: [String]) {
        let result = LastStartupResult(
            startedAt: Date(),
            wasClean: wasClean,
            fatalErrors: fatalErrors,
            warnings: warnings
        )
        let path = (server.serverDir as NSString).appendingPathComponent("last_startup_result.json")
        if let data = try? JSONEncoder().encode(result) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    func jarVersionsMatchForHealth(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        if let ba = jarBuildNumberForHealth(a), let bb = jarBuildNumberForHealth(b) { return ba == bb }
        return false
    }

    func jarBuildNumberForHealth(_ s: String) -> Int? {
        let lower = s.lowercased()
        guard let range = lower.range(of: "build") else { return nil }
        let after = lower[range.upperBound...]
        return Int(after.filter { $0.isNumber })
    }

    private func extractJavaVersion(from output: String) -> String? {
        let pattern = #"version\s+"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range(at: 1), in: output) else { return nil }
        return String(output[range])
    }

    private func parseJavaMajorVersion(from version: String?) -> Int? {
        guard let v = version else { return nil }
        let parts = v.components(separatedBy: ".")
        guard let first = parts.first, let major = Int(first) else { return nil }
        if major == 1, parts.count > 1, let minor = Int(parts[1]) { return minor }
        return major
    }

    // MARK: - Process runner

    struct ProcessResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    func runProcess(executable: String, arguments: [String], timeoutSeconds: Double = 6) async -> ProcessResult {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: ProcessResult(exitCode: 1, stdout: "", stderr: error.localizedDescription))
                    return
                }

                let deadline = DispatchTime.now() + timeoutSeconds
                DispatchQueue.global().asyncAfter(deadline: deadline) {
                    if process.isRunning { process.terminate() }
                }

                process.waitUntilExit()

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                continuation.resume(returning: ProcessResult(
                    exitCode: process.terminationStatus,
                    stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                    stderr: String(data: stderrData, encoding: .utf8) ?? ""
                ))
            }
        }
    }
}


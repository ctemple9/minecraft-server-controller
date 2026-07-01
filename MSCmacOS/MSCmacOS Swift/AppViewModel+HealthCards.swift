//
//  AppViewModel+HealthCards.swift
//  MinecraftServerController
//
//  Runs diagnostic checks and publishes results to `healthCards`.
//

import Foundation
import AppKit
import Network
import Virtualization

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
        let (running, startTime, host) = await currentPortCheckContext()
        async let dir   = checkDirectory(for: server)
        async let java  = checkJavaRuntime(for: server)
        async let jar   = checkComponentJars(for: server)
        async let ram   = checkRAMAllocation(for: server)
        async let port  = checkPortReachability(port: javaPort, isUDP: false, serverHasEverStarted: server.hasEverStarted, isRunning: running, serverStartTime: startTime, host: host, serverDir: server.serverDir)
        async let start = checkLastStartup(for: server)
        return await [dir, java, jar, ram, port, start]
    }

    // MARK: - Bedrock cards (6 cards: directory, vm-runtime, components(BDS), worldData, port, lastStartup)

    private func buildBedrockCards(for server: ConfigServer) async -> [HealthCardResult] {
        // Read the actual Bedrock port (from config or Geyser config), fall back to 19132.
        let bedrockPort = await MainActor.run { effectiveBedrockPort(for: server) ?? 19132 }
        let playerCount = await MainActor.run { onlinePlayers.count }
        let (running, startTime, host) = await currentPortCheckContext()
        async let dir    = checkDirectory(for: server)
        async let vm     = checkVMRuntimeForHealthCard()
        async let comps  = checkBedrockComponents(for: server)
        async let world  = checkBedrockWorldData(for: server)
        async let port   = checkPortReachability(port: bedrockPort, isUDP: true, serverHasEverStarted: server.hasEverStarted, isRunning: running, serverStartTime: startTime, host: host, serverDir: server.serverDir, onlinePlayerCount: playerCount)
        async let start  = checkLastStartup(for: server)
        return await [dir, vm, comps, world, port, start]
    }

    /// Reads the live state the port check needs from the main actor in one hop:
    /// whether the server is running, when it started (for the boot grace period),
    /// and the public-facing host to probe (DuckDNS hostname if set, else public IP).
    private func currentPortCheckContext() async -> (running: Bool, startTime: Date?, host: String?) {
        await MainActor.run {
            let duck = duckdnsInput.trimmingCharacters(in: .whitespacesAndNewlines)
            let host = duck.isEmpty ? cachedPublicIPAddress : duck
            return (isServerRunning, serverStartTime, host)
        }
    }

    // MARK: - Resolved executable paths

    private func resolvedPath(candidates: [String]) -> String? {
        candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    // Static candidate list — no subprocess; resolveJavaHomeOutput is called
    // asynchronously from checkJavaRuntime so it never blocks the main thread.
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

    // nonisolated + static: no actor state accessed, safe to call from Task.detached.
    private nonisolated static func resolveJavaHomeOutput() -> String? {
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
        // Build the candidate list. Resolve java_home off the main actor (it
        // spawns a subprocess and waits), then prepend it to the static list.
        var searchPaths = javaSearchPaths
        // Resolve java_home off the main actor; `process.waitUntilExit()` blocks the
        // calling thread, so running it in Task.detached avoids freezing the UI.
        let resolvedJH: String? = await Task.detached(priority: .userInitiated) {
            AppViewModel.resolveJavaHomeOutput()
        }.value
        if let jhPath = resolvedJH, !searchPaths.contains(jhPath) {
            // Priority: configured path, JAVA_HOME, then java_home output, then hardcoded.
            // The first two (configured + JAVA_HOME) were already prepended above; count
            // them so we insert java_home right after them.
            let cfg = configManager.config.javaPath.trimmingCharacters(in: .whitespacesAndNewlines)
            var prefixCount = 0
            if !cfg.isEmpty && cfg != "java" { prefixCount += 1 }
            if ProcessInfo.processInfo.environment["JAVA_HOME"] != nil { prefixCount += 1 }
            searchPaths.insert(jhPath, at: prefixCount)
        }

        for candidate in searchPaths {
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
            detectedValue: "Java not found. Checked \(searchPaths.count) locations.\nInstall Adoptium Temurin 21 or set your Java path in Preferences.",
            actionLabel: "Download Java",
            actionType: .openURL("https://adoptium.net")
        )
    }

    // MARK: - Card: VM Runtime (Bedrock)

    private func checkVMRuntimeForHealthCard() async -> HealthCardResult {
        // The VM runtime is bundled with the app — always available when the app runs.
        // VZVirtualMachine.isSupported is the only real gating condition.
        let supported = VZVirtualMachine.isSupported
        if supported {
            return HealthCardResult(
                id: "vm",
                status: .green,
                detectedValue: "Apple Virtualization — built-in\nBedrock Dedicated Server runs in a lightweight VM.",
                actionLabel: nil,
                actionType: nil
            )
        } else {
            return HealthCardResult(
                id: "vm",
                status: .red,
                detectedValue: "Apple Virtualization is not supported on this Mac.\nRequires macOS 11 or later on Apple Silicon or Intel.",
                actionLabel: nil,
                actionType: nil
            )
        }
    }

    // MARK: - Card: Docker Runtime (kept for reference — no longer used)
    /* private func checkDockerForHealthCard() async -> HealthCardResult { ... } */

    // MARK: - Card: Components (Java)
    //
    // Java: Paper · Geyser · Floodgate · XboxBroadcast
    // Red    — Paper JAR missing (required)
    // Yellow — at least one installed JAR has an update available
    // Green  — all installed JARs up to date

    private func checkComponentJars(for server: ConfigServer) async -> HealthCardResult {
        // installStep flavors (Forge, NeoForge) launch from a generated args file, not a JAR.
        // Check that the args file exists instead of paperJarPath (which is "" for these).
        if server.javaFlavor.provisioningKind == .installStep {
            let serverDirURL = URL(fileURLWithPath: server.serverDir, isDirectory: true)
            let argsExists: Bool
            switch server.javaFlavor {
            case .neoforge: argsExists = NeoForgeInstaller.findArgsFile(in: serverDirURL) != nil
            case .forge:    argsExists = ForgeInstaller.findArgsFile(in: serverDirURL) != nil
            default:        argsExists = false
            }
            if !argsExists {
                return HealthCardResult(
                    id: "jar",
                    status: .red,
                    detectedValue: "\(server.javaFlavor.displayName) install incomplete — args file not found.\nTry recreating the server.",
                    actionLabel: nil,
                    actionType: nil
                )
            }
            // Mods check: report how many mods are installed.
            let modsURL = serverDirURL.appendingPathComponent("mods", isDirectory: true)
            let modCount = (try? FileManager.default.contentsOfDirectory(atPath: modsURL.path))?.filter { $0.hasSuffix(".jar") }.count ?? 0
            return HealthCardResult(
                id: "jar",
                status: .green,
                detectedValue: modCount == 0
                    ? "\(server.javaFlavor.displayName) ready · no mods installed yet"
                    : "\(server.javaFlavor.displayName) ready · \(modCount) mod\(modCount == 1 ? "" : "s") installed",
                actionLabel: "Go to Components",
                actionType: .openComponentsTab
            )
        }

        let flavorName = server.javaFlavor.displayName

        guard FileManager.default.fileExists(atPath: server.paperJarPath) else {
            return HealthCardResult(
                id: "jar",
                status: .red,
                detectedValue: "\(flavorName) JAR not found at:\n\(server.paperJarPath)\nDownload it from the Components tab.",
                actionLabel: "Go to Components",
                actionType: .openComponentsTab
            )
        }

        let snap = await MainActor.run { componentsSnapshot }

        // Only compare against the Paper online API when the server is actually Paper.
        // For Purpur, Vanilla, Fabric, etc. snap.paper.online is always a Paper build
        // string that will never match their local version, causing false WARN states.
        let flavorOnline: String? = server.javaFlavor == .paper ? snap.paper.online : nil

        let allComponents: [(name: String, local: String?, online: String?)] = [
            (flavorName,    snap.paper.local,       flavorOnline),
            ("Geyser",      snap.geyser.local,      snap.geyser.online),
            ("Floodgate",   snap.floodgate.local,   snap.floodgate.online),
            ("Broadcast",   snap.broadcast.local,   snap.broadcast.online),
        ]

        let installed = allComponents.filter { $0.local != nil }
        guard !installed.isEmpty else {
            return HealthCardResult(
                id: "jar",
                status: .gray,
                detectedValue: "No component JARs found. Download \(flavorName) from the Components tab.",
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

    // MARK: - Card: Bedrock Components (BDS binary)

    private func checkBedrockComponents(for server: ConfigServer) async -> HealthCardResult {
        let binaryPath = (server.serverDir as NSString).appendingPathComponent("bedrock_server")
        let markerPath = (server.serverDir as NSString).appendingPathComponent(".msc_bds_version")
        let fm = FileManager.default

        if fm.isExecutableFile(atPath: binaryPath) {
            let version = (try? String(contentsOfFile: markerPath, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown version"
            return HealthCardResult(
                id: "jar",
                status: .green,
                detectedValue: "BDS \(version) installed",
                actionLabel: "Manage in Components",
                actionType: .openComponentsTab
            )
        } else {
            return HealthCardResult(
                id: "jar",
                status: .yellow,
                detectedValue: "BDS not yet downloaded.\nThe server will download it automatically on first start.",
                actionLabel: "Manage in Components",
                actionType: .openComponentsTab
            )
        }
    }

    // MARK: - Docker image check (kept for reference — no longer used)
    /* private func checkBedrockImageStatus() async -> ComponentCheckSummary { ... } */

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
    // Strategy (Option A — external status API):
    //   The card only makes a definitive reachability claim while the server is
    //   actually running, because port forwarding cannot be validated against a
    //   dead server. A local loopback probe disambiguates "off/booting" from
    //   "running but misconfigured"; an external status-API ping (mcsrvstat.us,
    //   which speaks Java SLP and Bedrock RakNet from the internet side) answers
    //   "can players actually reach it?" and yields MOTD/player count for free.
    //
    // Result logic:
    //   - Never started:               gray   "Waiting for first start"
    //   - Off (ran before):            gray   "Server is off" (+ last-verified-reachable if cached)
    //   - Booting (grace period):      gray   "Server starting up — checking…"
    //   - Running, not listening:      red    "Running but nothing is listening on this port"
    //   - Running, listening, online:  green  "Reachable from internet" (+ MOTD/players)
    //   - Running, listening, offline: yellow "Listening locally but not reachable — check forwarding"
    //   - External check inconclusive: yellow local-only
    //
    // onlinePlayerCount: Bedrock UDP fallback — a connected player proves the port
    // is open even if the external API can't confirm it.
    private func checkPortReachability(port: Int, isUDP: Bool, serverHasEverStarted: Bool, isRunning: Bool, serverStartTime: Date?, host: String?, serverDir: String, onlinePlayerCount: Int = 0) async -> HealthCardResult {
        let cardID = "port"
        let proto = isUDP ? "UDP" : "TCP"

        // Never started → nothing to verify yet.
        guard serverHasEverStarted else {
            return HealthCardResult(
                id: cardID,
                status: .gray,
                detectedValue: "Waiting for first start\nPort \(port) (\(proto))",
                actionLabel: "View Port Setup Guide",
                actionType: .openRouterPortForwardGuide
            )
        }

        // Server off → forwarding can't be validated against a dead server.
        // Surface the last known-good result if we have one so an idle server
        // doesn't look broken.
        guard isRunning else {
            if let rec = readPortCheckRecord(serverDir), rec.wasReachable {
                return HealthCardResult(
                    id: cardID,
                    status: .gray,
                    detectedValue: "Server is off\nLast verified reachable \(relativeTime(rec.checkedAt))\nStart the server to re-check.",
                    actionLabel: nil,
                    actionType: nil
                )
            }
            return HealthCardResult(
                id: cardID,
                status: .gray,
                detectedValue: "Server is off\nStart it to verify port \(port) (\(proto)) reachability.",
                actionLabel: "View Port Setup Guide",
                actionType: .openRouterPortForwardGuide
            )
        }

        // Boot grace window: the port may not be bound yet and the external API
        // may still hold a stale "offline" cache. Don't flash red/yellow during this.
        let secondsSinceStart = serverStartTime.map { Date().timeIntervalSince($0) } ?? .greatestFiniteMagnitude
        let inGracePeriod = secondsSinceStart < 45

        // --- Stage 1: Local loopback probe — is anything listening to forward to? ---
        let localListening = await probeLocalPort(port: port, isUDP: isUDP)

        if !localListening {
            if inGracePeriod {
                return HealthCardResult(
                    id: cardID,
                    status: .gray,
                    detectedValue: "Port \(port) (\(proto))\nServer starting up — checking…",
                    actionLabel: nil,
                    actionType: nil
                )
            }
            return HealthCardResult(
                id: cardID,
                status: .red,
                detectedValue: "Port \(port) (\(proto))\nServer is running but nothing is listening on this port.\nCheck the port in your server settings.",
                actionLabel: "View Port Setup Guide",
                actionType: .openRouterPortForwardGuide
            )
        }

        // --- Stage 2: External reachability via status API ---
        // Validates port forwarding from the internet side (avoids NAT-hairpin
        // false negatives that a self-ping from inside the LAN would hit).
        guard let host = host, !host.isEmpty, host != "unknown" else {
            return portResultLocalOnly(port: port, isUDP: isUDP)
        }

        if let result = await queryServerStatus(host: host, port: port, isUDP: isUDP) {
            if result.online {
                writePortCheckRecord(serverDir, reachable: true, port: port)
                var lines = [
                    "Port \(port) (\(proto))",
                    "Listening locally \u{2713}",
                    "Reachable from internet \u{2713}",
                ]
                if let on = result.playersOnline, let mx = result.playersMax {
                    lines.append("Players: \(on)/\(mx)")
                }
                if let motd = result.motd, !motd.isEmpty {
                    lines.append("MOTD: \(motd)")
                }
                lines.append("Host: \(host)")
                return HealthCardResult(id: cardID, status: .green, detectedValue: lines.joined(separator: "\n"), actionLabel: nil, actionType: nil)
            }

            // API reports offline.
            if inGracePeriod {
                return HealthCardResult(
                    id: cardID,
                    status: .gray,
                    detectedValue: "Port \(port) (\(proto))\nListening locally \u{2713}\nServer starting up — checking external reachability…",
                    actionLabel: nil,
                    actionType: nil
                )
            }
            // UDP fallback: a connected player proves the port is open even if the API can't see it.
            if isUDP && onlinePlayerCount > 0 {
                writePortCheckRecord(serverDir, reachable: true, port: port)
                let s = onlinePlayerCount == 1 ? "" : "s"
                return HealthCardResult(
                    id: cardID,
                    status: .green,
                    detectedValue: "Port \(port) (UDP)\nListening locally \u{2713}\n\(onlinePlayerCount) player\(s) connected \u{2713}\nPort is reachable.",
                    actionLabel: nil,
                    actionType: nil
                )
            }
            writePortCheckRecord(serverDir, reachable: false, port: port)
            return HealthCardResult(
                id: cardID,
                status: .yellow,
                detectedValue: "Port \(port) (\(proto))\nListening locally \u{2713}\nNot reachable from the internet \u{2717}\nHost: \(host)\nCheck your router's port forwarding.",
                actionLabel: "View Port Setup Guide",
                actionType: .openRouterPortForwardGuide
            )
        }

        // API unreachable/inconclusive — fall back to a local-only result.
        if isUDP && onlinePlayerCount > 0 {
            let s = onlinePlayerCount == 1 ? "" : "s"
            return HealthCardResult(
                id: cardID,
                status: .green,
                detectedValue: "Port \(port) (UDP)\nListening locally \u{2713}\n\(onlinePlayerCount) player\(s) connected \u{2713}\nPort is reachable.",
                actionLabel: nil,
                actionType: nil
            )
        }
        return portResultLocalOnly(port: port, isUDP: isUDP)
    }

    // MARK: - External status API (mcsrvstat.us)

    private struct ExternalPingResult {
        let online: Bool
        let playersOnline: Int?
        let playersMax: Int?
        let motd: String?
    }

    /// Pings the public-facing host via mcsrvstat.us from the internet side.
    /// Uses the Bedrock endpoint for UDP (RakNet) and the Java endpoint otherwise (SLP).
    /// Returns nil on transport/parse failure so the caller can fall back gracefully.
    private func queryServerStatus(host: String, port: Int, isUDP: Bool) async -> ExternalPingResult? {
        let base = isUDP ? "https://api.mcsrvstat.us/bedrock/3/" : "https://api.mcsrvstat.us/3/"
        guard let encodedHost = host.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              let url = URL(string: "\(base)\(encodedHost):\(port)") else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("MinecraftServerController/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            let online = (json["online"] as? Bool) ?? false
            var playersOnline: Int? = nil
            var playersMax: Int? = nil
            if let players = json["players"] as? [String: Any] {
                playersOnline = players["online"] as? Int
                playersMax = players["max"] as? Int
            }
            var motd: String? = nil
            if let motdObj = json["motd"] as? [String: Any], let clean = motdObj["clean"] as? [String] {
                motd = clean.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return ExternalPingResult(online: online, playersOnline: playersOnline, playersMax: playersMax, motd: motd)
        } catch {
            return nil
        }
    }

    private func portResultLocalOnly(port: Int, isUDP: Bool) -> HealthCardResult {
        HealthCardResult(
            id: "port",
            status: .yellow,
            detectedValue: "Port \(port) (\(isUDP ? "UDP" : "TCP"))\nListening locally \u{2713}\nExternal check inconclusive\nTest from another network to verify.",
            actionLabel: "View Port Setup Guide",
            actionType: .openRouterPortForwardGuide
        )
    }

    // MARK: - Last known-good port check (persisted to {serverDir}/last_port_check.json)

    private func portCheckRecordPath(_ serverDir: String) -> String {
        (serverDir as NSString).appendingPathComponent("last_port_check.json")
    }

    private func readPortCheckRecord(_ serverDir: String) -> PortCheckRecord? {
        let path = portCheckRecordPath(serverDir)
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return try? JSONDecoder().decode(PortCheckRecord.self, from: data)
    }

    private func writePortCheckRecord(_ serverDir: String, reachable: Bool, port: Int) {
        let record = PortCheckRecord(checkedAt: Date(), wasReachable: reachable, port: port)
        if let data = try? JSONEncoder().encode(record) {
            try? data.write(to: URL(fileURLWithPath: portCheckRecordPath(serverDir)))
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
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
            let softProblems = result.problems ?? []
            if !softProblems.isEmpty {
                return HealthCardResult(
                    id: "lastStartup",
                    status: .yellow,
                    detectedValue: "Last start: \(formatDate(result.startedAt))\nServer started, but \(softProblems.count) add-on\(softProblems.count == 1 ? "" : "s") failed to load.",
                    actionLabel: "Diagnose Add-ons",
                    actionType: .diagnoseStartup
                )
            }
            return HealthCardResult(
                id: "lastStartup",
                status: .green,
                detectedValue: "Last start: \(formatDate(result.startedAt))\nNo fatal errors detected.",
                actionLabel: nil,
                actionType: nil
            )
        } else if !result.fatalErrors.isEmpty {
            let preview = result.fatalErrors.prefix(3).joined(separator: "\n")
            let hasProblems = !(result.problems ?? []).isEmpty
            return HealthCardResult(
                id: "lastStartup",
                status: .red,
                detectedValue: "Last start: \(formatDate(result.startedAt))\n\(preview)",
                actionLabel: hasProblems ? "Diagnose Startup" : "View Full Console Log",
                actionType: hasProblems ? .diagnoseStartup : .openConsoleLog
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

    func writeLastStartupResult(for server: ConfigServer, wasClean: Bool, fatalErrors: [String], warnings: [String], problems: [StartupProblem] = []) {
        let result = LastStartupResult(
            startedAt: Date(),
            wasClean: wasClean,
            fatalErrors: fatalErrors,
            warnings: warnings,
            problems: problems.isEmpty ? nil : problems
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


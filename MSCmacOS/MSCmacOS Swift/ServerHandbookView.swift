//
//  ServerHandbookView.swift
//  MinecraftServerController
//
//  Long-form in-app reference handbook covering hosting concepts, workflows,
//  and feature explanations for both Java and Bedrock servers.
//

import SwiftUI

// MARK: - Topic Model

enum HandbookTopic: String, CaseIterable, Identifiable {
    // Concepts
    case overview
    case networkingBasics
    case ramPerformance
    // Java Servers
    case standardVsModded
    case paper
    case vanilla
    case purpur
    case jarsJava
    case eulaOnlineMode
    case pluginsGeyserFloodgate
    // Java Modded
    case fabric
    case neoforge
    case forge
    case modsModBrowser
    case clientRequirementsModded
    // Bedrock Servers
    case bedrock
    case docker
    // Connection & Access
    case portsForwardingDuckDNS
    case playitSetup
    case tailscale
    case broadcast
    case remoteAccess
    // Server Management
    case worldsBackups
    case worldConversion
    case serverTransfer
    case serverFiles
    case watchdog
    case playerManagement
    // Getting Started
    case firstServer
    case firstModdedServer
    case bedrockSetup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:                  return "Overview"
        case .networkingBasics:          return "How Servers Connect"
        case .ramPerformance:            return "RAM & Performance"
        case .standardVsModded:         return "Standard vs Modded"
        case .paper:                     return "What is Paper?"
        case .vanilla:                   return "Vanilla Server"
        case .purpur:                    return "What is Purpur?"
        case .jarsJava:                  return "JAR Files & Java"
        case .eulaOnlineMode:            return "EULA & Online Mode"
        case .pluginsGeyserFloodgate:    return "Plugins & Cross-Play"
        case .fabric:                    return "What is Fabric?"
        case .neoforge:                  return "What is NeoForge?"
        case .forge:                     return "What is Forge?"
        case .modsModBrowser:            return "Mods & Mod Browser"
        case .clientRequirementsModded:  return "Client Requirements"
        case .bedrock:                   return "What is Bedrock Dedicated Server?"
        case .docker:                    return "How Bedrock Runs"
        case .portsForwardingDuckDNS:    return "Port Forwarding & DuckDNS"
        case .playitSetup:               return "Playit.gg Tunneling"
        case .tailscale:                 return "Tailscale"
        case .broadcast:                 return "Xbox Broadcast"
        case .remoteAccess:              return "MSC Remote (iOS)"
        case .worldsBackups:             return "Worlds & Backups"
        case .worldConversion:           return "World Conversion"
        case .serverTransfer:            return "Server Import & Transfer"
        case .serverFiles:               return "Server Files Browser"
        case .watchdog:                  return "Watchdog & Crash Recovery"
        case .playerManagement:          return "Player Management"
        case .firstServer:               return "Your First Java Server"
        case .firstModdedServer:         return "Your First Modded Server"
        case .bedrockSetup:              return "Your First Bedrock Server"
        }
    }

    var icon: String {
        switch self {
        case .overview:                  return "house.fill"
        case .networkingBasics:          return "globe.americas.fill"
        case .ramPerformance:            return "memorychip.fill"
        case .standardVsModded:         return "tray.2.fill"
        case .paper:                     return "server.rack"
        case .vanilla:                   return "leaf.fill"
        case .purpur:                    return "crown.fill"
        case .jarsJava:                  return "shippingbox.fill"
        case .eulaOnlineMode:            return "checkmark.seal.fill"
        case .pluginsGeyserFloodgate:    return "puzzlepiece.fill"
        case .fabric:                    return "gearshape.fill"
        case .neoforge:                  return "hammer.fill"
        case .forge:                     return "wrench.and.screwdriver.fill"
        case .modsModBrowser:            return "puzzlepiece.extension.fill"
        case .clientRequirementsModded:  return "person.badge.key.fill"
        case .bedrock:                   return "cube.fill"
        case .docker:                    return "memorychip"
        case .portsForwardingDuckDNS:    return "network"
        case .playitSetup:               return "antenna.radiowaves.left.and.right"
        case .tailscale:                 return "lock.shield.fill"
        case .broadcast:                 return "dot.radiowaves.left.and.right"
        case .remoteAccess:              return "iphone"
        case .worldsBackups:             return "archivebox.fill"
        case .worldConversion:           return "arrow.2.circlepath"
        case .serverTransfer:            return "square.and.arrow.down.fill"
        case .serverFiles:               return "folder.fill"
        case .watchdog:                  return "stethoscope"
        case .playerManagement:          return "person.2.fill"
        case .firstServer:               return "flag.checkered"
        case .firstModdedServer:         return "flag.checkered"
        case .bedrockSetup:              return "flag.checkered"
        }
    }

    var category: HandbookCategory {
        switch self {
        case .overview, .networkingBasics, .ramPerformance:
            return .concepts
        case .standardVsModded, .paper, .vanilla, .purpur, .jarsJava, .eulaOnlineMode, .pluginsGeyserFloodgate:
            return .java
        case .fabric, .neoforge, .forge, .modsModBrowser, .clientRequirementsModded:
            return .moddedJava
        case .bedrock, .docker:
            return .bedrockCat
        case .portsForwardingDuckDNS, .playitSetup, .tailscale, .broadcast, .remoteAccess:
            return .connection
        case .worldsBackups, .worldConversion, .serverTransfer, .serverFiles, .watchdog, .playerManagement:
            return .management
        case .firstServer, .firstModdedServer, .bedrockSetup:
            return .gettingStarted
        }
    }
}

enum HandbookCategory: String, CaseIterable {
    case concepts       = "Concepts"
    case java           = "Java Servers"
    case moddedJava     = "Modded Servers"
    case bedrockCat     = "Bedrock Servers"
    case connection     = "Connection & Access"
    case management     = "Server Management"
    case gettingStarted = "Getting Started"

    var color: Color {
        switch self {
        case .concepts:       return .blue
        case .java:           return .orange
        case .moddedJava:     return .indigo
        case .bedrockCat:     return .green
        case .connection:     return .purple
        case .management:     return .teal
        case .gettingStarted: return .mint
        }
    }
}

// MARK: - Main View

struct ServerHandbookView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTopic: HandbookTopic = .overview
    @State private var visitedTopics: Set<HandbookTopic> = [.overview]
    @State private var searchText: String = ""
    @State private var topicTransitionID: UUID = UUID()

    private var filteredTopics: [HandbookTopic] {
        if searchText.isEmpty { return HandbookTopic.allCases }
        return HandbookTopic.allCases.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var progressFraction: Double {
        Double(visitedTopics.count) / Double(HandbookTopic.allCases.count)
    }

    private func selectTopic(_ topic: HandbookTopic) {
        withAnimation(.easeInOut(duration: 0.18)) {
            selectedTopic = topic
            visitedTopics.insert(topic)
            topicTransitionID = UUID()
        }
    }

    private func nextTopic() {
        let all = HandbookTopic.allCases
        if let idx = all.firstIndex(of: selectedTopic), idx + 1 < all.count {
            selectTopic(all[idx + 1])
        }
    }

    private func previousTopic() {
        let all = HandbookTopic.allCases
        if let idx = all.firstIndex(of: selectedTopic), idx > 0 {
            selectTopic(all[idx - 1])
        }
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Hero Banner ───────────────────────────────────────────────
            heroHeader

            // ── Content area ─────────────────────────────────────────────
            HStack(spacing: 0) {

                // Left sidebar
                sidebar
                    .frame(width: 220)

                Divider()

                // Right content
                VStack(spacing: 0) {
                    ScrollView {
                        content(for: selectedTopic)
                            .padding(MSC.Spacing.xxl)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .id(topicTransitionID)
                    }

                    // Nav footer
                    navFooter
                }
            }
        }
        .frame(minWidth: 820, idealWidth: 1020, minHeight: 520, idealHeight: 700)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        ZStack(alignment: .bottomLeading) {
            Image("WorldBanner")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 200)
                .clipped()
                .overlay(
                    LinearGradient(
                        colors: [.black.opacity(0.65), .black.opacity(0.1), .clear],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Server Handbook")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Your long-term reference for hosting, configuring, and managing Minecraft servers on your Mac.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, MSC.Spacing.xl)
            .padding(.bottom, MSC.Spacing.lg)

            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        viewModel.markHandbookShown()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(Circle().fill(.black.opacity(0.4)))
                    }
                    .buttonStyle(.plain)
                    .padding(MSC.Spacing.md)
                }
                Spacer()
            }

            // Progress indicator (top-right)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    progressPill
                        .padding(.horizontal, MSC.Spacing.xl)
                        .padding(.bottom, MSC.Spacing.lg)
                }
            }
        }
        .frame(height: 200)
    }

    private var progressPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.8))
            Text("\(visitedTopics.count) of \(HandbookTopic.allCases.count) topics read")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25)).frame(height: 4)
                    Capsule().fill(.white).frame(width: geo.size.width * progressFraction, height: 4)
                }
            }
            .frame(width: 60, height: 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(.black.opacity(0.35)))
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Search topics\u{2026}", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, MSC.Spacing.md)
            .padding(.vertical, MSC.Spacing.sm)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: MSC.Radius.sm))
            .padding(.horizontal, MSC.Spacing.md)
            .padding(.top, MSC.Spacing.md)
            .padding(.bottom, MSC.Spacing.sm)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if searchText.isEmpty {
                        ForEach(HandbookCategory.allCases, id: \.self) { category in
                            let topicsInCategory = HandbookTopic.allCases.filter { $0.category == category }
                            if !topicsInCategory.isEmpty {
                                sidebarSection(category: category, topics: topicsInCategory)
                            }
                        }
                    } else {
                        ForEach(filteredTopics) { topic in
                            sidebarRow(topic: topic)
                        }
                    }
                }
                .padding(.vertical, MSC.Spacing.sm)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func sidebarSection(category: HandbookCategory, topics: [HandbookTopic]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(category.rawValue.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(category.color.opacity(0.8))
                .tracking(1.0)
                .padding(.horizontal, MSC.Spacing.lg)
                .padding(.top, MSC.Spacing.md)
                .padding(.bottom, MSC.Spacing.xs)

            ForEach(topics) { topic in
                sidebarRow(topic: topic)
            }
        }
    }

    private func sidebarRow(topic: HandbookTopic) -> some View {
        let isSelected = selectedTopic == topic
        let isVisited = visitedTopics.contains(topic)

        return Button { selectTopic(topic) } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? topic.category.color : topic.category.color.opacity(0.12))
                        .frame(width: 22, height: 22)
                    Image(systemName: topic.icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : topic.category.color)
                }

                Text(topic.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer()

                if isVisited && !isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
            }
            .padding(.horizontal, MSC.Spacing.md)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, MSC.Spacing.xs)
    }

    // MARK: - Nav Footer

    private var navFooter: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                let all = HandbookTopic.allCases
                let isFirst = selectedTopic == all.first
                let isLast = selectedTopic == all.last

                Button(action: previousTopic) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(isFirst ? .tertiary : .secondary)
                .disabled(isFirst)

                Spacer()

                // Progress fraction pill instead of per-topic dots (22 topics makes dots impractical)
                Text("\(HandbookTopic.allCases.firstIndex(of: selectedTopic).map { $0 + 1 } ?? 1) / \(HandbookTopic.allCases.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                if isLast {
                    Button {
                        viewModel.markHandbookShown()
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Text("Done")
                                .font(.system(size: 12, weight: .semibold))
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(MSCPrimaryButtonStyle())
                } else {
                    Button(action: nextTopic) {
                        HStack(spacing: 4) {
                            Text("Next")
                                .font(.system(size: 12))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isLast ? .tertiary : .secondary)
                    .disabled(isLast)
                }
            }
            .padding(.horizontal, MSC.Spacing.xl)
            .padding(.vertical, MSC.Spacing.md)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Content Router

    @ViewBuilder
    private func content(for topic: HandbookTopic) -> some View {
        switch topic {
        case .overview:                 overviewContent
        case .networkingBasics:         networkingBasicsContent
        case .ramPerformance:           ramPerformanceContent
        case .standardVsModded:         standardVsModdedContent
        case .paper:                    paperContent
        case .vanilla:                  vanillaContent
        case .purpur:                   purpurContent
        case .jarsJava:                 jarsJavaContent
        case .eulaOnlineMode:           eulaOnlineModeContent
        case .pluginsGeyserFloodgate:   pluginsGeyserFloodgateContent
        case .fabric:                   fabricContent
        case .neoforge:                 neoforgeContent
        case .forge:                    forgeContent
        case .modsModBrowser:           modsModBrowserContent
        case .clientRequirementsModded: clientRequirementsModdedContent
        case .bedrock:                  bedrockContent
        case .docker:                   dockerContent
        case .portsForwardingDuckDNS:   portsForwardingDuckDNSContent
        case .playitSetup:              playitSetupContent
        case .tailscale:                tailscaleContent
        case .broadcast:                broadcastContent
        case .remoteAccess:             remoteAccessContent
        case .worldsBackups:            worldsBackupsContent
        case .worldConversion:          worldConversionContent
        case .serverTransfer:           serverTransferContent
        case .serverFiles:              serverFilesContent
        case .watchdog:                 watchdogContent
        case .playerManagement:         playerManagementContent
        case .firstServer:              firstServerContent
        case .firstModdedServer:        firstModdedServerContent
        case .bedrockSetup:             bedrockSetupContent
        }
    }
}

//
//  WelcomeGuideView.swift
//  MinecraftServerController
//
//  Long-form in-app reference guide covering hosting concepts, workflows,
//  and feature explanations for both Java and Bedrock servers.
//

import SwiftUI

// MARK: - Topic Model

enum WelcomeGuideTopic: String, CaseIterable, Identifiable {
    case overview
    case paper
    case jarsJava
    case bedrock
    case docker
    case ramPerformance
    case pluginsGeyserFloodgate
    case eulaOnlineMode
    case portsForwardingDuckDNS
    case broadcast
    case bedrockConnect
    case worldsBackups
    case remoteAccess
    case firstServer
    case bedrockSetup
    case serverFiles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:               return "Overview"
        case .paper:                  return "What is Paper?"
        case .bedrock:                return "What is Bedrock Dedicated Server?"
        case .docker:                 return "Docker & How Bedrock Runs"
        case .jarsJava:               return "JAR Files & Java"
        case .ramPerformance:         return "RAM & Performance"
        case .pluginsGeyserFloodgate: return "Plugins & Cross-Play"
        case .eulaOnlineMode:         return "EULA & Online Mode"
        case .portsForwardingDuckDNS: return "Ports & DuckDNS"
        case .broadcast:              return "Xbox Broadcast"
        case .bedrockConnect:         return "Bedrock Connect"
        case .worldsBackups:          return "Worlds & Backups"
        case .remoteAccess:           return "MSC Remote (iOS)"
        case .firstServer:            return "Your First Java Server"
        case .bedrockSetup:           return "Your First Bedrock Server"
        case .serverFiles:            return "Server Files Browser"
        }
    }

    var icon: String {
        switch self {
        case .overview:               return "house.fill"
        case .paper:                  return "server.rack"
        case .bedrock:                return "cube.fill"
        case .docker:                 return "shippingbox.fill"
        case .jarsJava:               return "shippingbox.fill"
        case .ramPerformance:         return "memorychip.fill"
        case .pluginsGeyserFloodgate: return "puzzlepiece.fill"
        case .eulaOnlineMode:         return "checkmark.seal.fill"
        case .portsForwardingDuckDNS: return "network"
        case .broadcast:              return "dot.radiowaves.left.and.right"
        case .bedrockConnect:         return "gamecontroller.fill"
        case .worldsBackups:          return "archivebox.fill"
        case .remoteAccess:           return "iphone"
        case .firstServer:            return "flag.checkered"
        case .bedrockSetup:           return "flag.checkered"
        case .serverFiles:            return "folder.fill"
        }
    }

    var category: TopicCategory {
        switch self {
        case .overview, .paper, .bedrock, .docker, .jarsJava, .ramPerformance:
            return .basics
        case .pluginsGeyserFloodgate, .eulaOnlineMode, .portsForwardingDuckDNS:
            return .setup
        case .broadcast, .bedrockConnect, .remoteAccess:
            return .advanced
        case .worldsBackups, .firstServer, .bedrockSetup, .serverFiles:
            return .management
        }
    }
}

enum TopicCategory: String, CaseIterable {
    case basics     = "Basics"
    case setup      = "Setup"
    case advanced   = "Advanced Features"
    case management = "Management"

    var color: Color {
        switch self {
        case .basics:     return .blue
        case .setup:      return .orange
        case .advanced:   return .purple
        case .management: return .green
        }
    }
}

// MARK: - Main View

struct WelcomeGuideView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTopic: WelcomeGuideTopic = .overview
    @State private var visitedTopics: Set<WelcomeGuideTopic> = [.overview]
    @State private var searchText: String = ""
    @State private var topicTransitionID: UUID = UUID()

    private var filteredTopics: [WelcomeGuideTopic] {
        if searchText.isEmpty { return WelcomeGuideTopic.allCases }
        return WelcomeGuideTopic.allCases.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var progressFraction: Double {
        Double(visitedTopics.count) / Double(WelcomeGuideTopic.allCases.count)
    }

    private func selectTopic(_ topic: WelcomeGuideTopic) {
        withAnimation(.easeInOut(duration: 0.18)) {
            selectedTopic = topic
            visitedTopics.insert(topic)
            topicTransitionID = UUID()
        }
    }

    private func nextTopic() {
        let all = WelcomeGuideTopic.allCases
        if let idx = all.firstIndex(of: selectedTopic), idx + 1 < all.count {
            selectTopic(all[idx + 1])
        }
    }

    private func previousTopic() {
        let all = WelcomeGuideTopic.allCases
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
        .frame(minWidth: 960, idealWidth: 1020, minHeight: 600, idealHeight: 700)
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
                Text("Minecraft Server Controller")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Your complete guide to hosting Minecraft servers \u{2014} Java or Bedrock \u{2014} on your Mac.")
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
                        viewModel.markWelcomeGuideShown()
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
            Text("\(visitedTopics.count) of \(WelcomeGuideTopic.allCases.count) topics read")
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
                        ForEach(TopicCategory.allCases, id: \.self) { category in
                            let topicsInCategory = WelcomeGuideTopic.allCases.filter { $0.category == category }
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

    private func sidebarSection(category: TopicCategory, topics: [WelcomeGuideTopic]) -> some View {
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

    private func sidebarRow(topic: WelcomeGuideTopic) -> some View {
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
                let all = WelcomeGuideTopic.allCases
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

                // Dot progress
                HStack(spacing: 4) {
                    ForEach(all) { topic in
                        Circle()
                            .fill(selectedTopic == topic ? Color.accentColor : (visitedTopics.contains(topic) ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.2)))
                            .frame(width: selectedTopic == topic ? 7 : 5, height: selectedTopic == topic ? 7 : 5)
                            .animation(.spring(response: 0.3), value: selectedTopic)
                    }
                }

                Spacer()

                if isLast {
                    Button {
                        viewModel.markWelcomeGuideShown()
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
    private func content(for topic: WelcomeGuideTopic) -> some View {
        switch topic {
        case .overview:                 overviewContent
        case .paper:                    paperContent
        case .bedrock:                  bedrockContent
        case .docker:                   dockerContent
        case .jarsJava:                 jarsJavaContent
        case .ramPerformance:           ramPerformanceContent
        case .pluginsGeyserFloodgate:   pluginsGeyserFloodgateContent
        case .eulaOnlineMode:           eulaOnlineModeContent
        case .portsForwardingDuckDNS:   portsForwardingDuckDNSContent
        case .broadcast:                broadcastContent
        case .bedrockConnect:           bedrockConnectContent
        case .worldsBackups:            worldsBackupsContent
        case .remoteAccess:             remoteAccessContent
        case .firstServer:              firstServerContent
        case .bedrockSetup:             bedrockSetupContent
        case .serverFiles:              serverFilesContent
        }
    }
}

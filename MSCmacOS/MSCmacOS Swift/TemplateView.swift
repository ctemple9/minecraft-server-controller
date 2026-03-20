//
//  TemplatesView.swift
//  MinecraftServerController
//
//  Unified templates UI for Paper, plugin, and cross-play JARs.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

// Entry point for presenting the Paper templates view
struct PaperTemplateView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Binding var isPresented: Bool

    var body: some View {
        TemplatesView(isPresented: $isPresented)
            .environmentObject(viewModel)
    }
}

// Entry point for presenting the plugin templates view
struct PluginTemplatesView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Binding var isPresented: Bool

    var body: some View {
        TemplatesView(isPresented: $isPresented)
            .environmentObject(viewModel)
    }
}

// MARK: - Unified Templates View

struct TemplatesView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Binding var isPresented: Bool

    private enum TemplatesTab: Hashable {
        case paper
        case plugins
        case broadcastAndConnect
    }

    @State private var selectedTab: TemplatesTab = .paper

    // Sheets / importers
    @State private var isShowingPaperImporter: Bool = false
    @State private var isShowingPluginImporter: Bool = false
    @State private var isShowingXboxBroadcastImporter: Bool = false
    @State private var isShowingBedrockConnectImporter: Bool = false

    // MARK: - Active status helpers

    private func isPaperTemplateActive(_ item: PaperTemplateItem) -> Bool {
        guard let server = viewModel.selectedServer,
              let cfgServer = viewModel.configServer(for: server) else { return false }
        let serverDir = URL(fileURLWithPath: cfgServer.serverDir, isDirectory: true)
        guard let sidecar = PaperVersionSidecarManager.read(fromServerDirectory: serverDir),
              let parsed = ComponentVersionParsing.parsePaperJarFilename(item.filename) else { return false }
        return sidecar.mcVersion == parsed.mcVersion && sidecar.build == parsed.build
    }

    private func isPluginTemplateActive(_ item: PluginTemplateItem) -> Bool {
        guard let server = viewModel.selectedServer,
              let cfgServer = viewModel.configServer(for: server) else { return false }
        let serverDir = URL(fileURLWithPath: cfgServer.serverDir, isDirectory: true)
        let pluginsDir = serverDir.appendingPathComponent("plugins")
        return FileManager.default.fileExists(
            atPath: pluginsDir.appendingPathComponent(item.filename).path
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // HEADER
            HStack(alignment: .center) {
                Text("JARs")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
                Spacer()
                Button("Close") {
                    isPresented = false
                }
                .buttonStyle(MSCSecondaryButtonStyle())
            }
            .padding(.horizontal, MSC.Spacing.lg)
            .padding(.top, MSC.Spacing.lg)
            .padding(.bottom, MSC.Spacing.md)

            Divider()
                .padding(.horizontal, MSC.Spacing.lg)
                .padding(.bottom, MSC.Spacing.md)

            // TAB PICKER
            Picker("", selection: $selectedTab) {
                Text("Paper JARs").tag(TemplatesTab.paper)
                Text("Plugin JARs").tag(TemplatesTab.plugins)
                Text("Cross-Play JARs").tag(TemplatesTab.broadcastAndConnect)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, MSC.Spacing.lg)
            .padding(.bottom, MSC.Spacing.md)

            // TAB CONTENT
            Group {
                switch selectedTab {
                case .paper:
                    paperTab
                case .plugins:
                    pluginsTab
                case .broadcastAndConnect:
                    broadcastAndConnectTab
                }
            }
        }
        .frame(minWidth: 820, minHeight: 460)
        .onAppear {
            viewModel.loadPaperTemplates()
            viewModel.loadPluginTemplates()
            viewModel.loadXboxBroadcastJars()
            viewModel.loadBedrockConnectJars()
        }
        .fileImporter(
            isPresented: $isShowingPaperImporter,
            allowedContentTypes: [UTType.data],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                let jarURLs = urls.filter { $0.pathExtension.lowercased() == "jar" }
                viewModel.addPaperTemplates(from: jarURLs)
            case .failure(let error):
                viewModel.logAppMessage("[Paper] File import failed: \(error.localizedDescription)")
            }
        }
        .fileImporter(
            isPresented: $isShowingPluginImporter,
            allowedContentTypes: [UTType.data],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                let jarURLs = urls.filter { $0.pathExtension.lowercased() == "jar" }
                viewModel.addPluginTemplates(from: jarURLs)
            case .failure(let error):
                viewModel.logAppMessage("[Plugin] File import failed: \(error.localizedDescription)")
            }
        }
        .fileImporter(
            isPresented: $isShowingXboxBroadcastImporter,
            allowedContentTypes: [UTType.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first, url.pathExtension.lowercased() == "jar" {
                    viewModel.addXboxBroadcastJarFromBrowse(url)
                }
            case .failure(let error):
                viewModel.logAppMessage("[Broadcast] File import failed: \(error.localizedDescription)")
            }
        }
        .fileImporter(
            isPresented: $isShowingBedrockConnectImporter,
            allowedContentTypes: [UTType.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first, url.pathExtension.lowercased() == "jar" {
                    viewModel.addBedrockConnectJarFromBrowse(url)
                }
            case .failure(let error):
                viewModel.logAppMessage("[BedrockConnect] File import failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Paper Tab

    private var paperTab: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: MSC.Spacing.lg) {

                JarSectionCard(
                    icon: "server.rack",
                    iconColor: .blue,
                    title: "Paper JAR",
                    description: "The server runtime for Minecraft Java Edition. Download builds here, then apply one to the active server."
                ) {
                    JarLibraryList(
                        items: viewModel.paperTemplateItems.reversed().map { .paper($0) },
                        isActive: { item in
                            if case .paper(let p) = item { return isPaperTemplateActive(p) }
                            return false
                        },
                        onApply: { item in
                            if case .paper(let p) = item {
                                viewModel.applyPaperTemplateToSelectedServer(template: p)
                            }
                        },
                        onDelete: { item in
                            if case .paper(let p) = item { viewModel.removePaperTemplate(p) }
                        },
                        applyDisabled: viewModel.selectedServer == nil
                    )

                    JarActionRow {
                        Button("Download Latest") {
                            Task { await viewModel.downloadLatestPaperTemplate() }
                        }
                        .help("Download the latest Paper build.")

                        Button("Browse\u{2026}") {
                            isShowingPaperImporter = true
                        }
                        .help("Choose an existing Paper JAR from your Mac.")

                        Button("Releases Page") {
                            if let url = URL(string: "https://papermc.io/downloads/paper") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .help("Open the Paper downloads page.")

                        Button("Open Folder") {
                            viewModel.openPaperTemplatesFolder()
                        }
                        .help("Open the Paper Templates folder in Finder.")
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, MSC.Spacing.lg)
            .padding(.bottom, MSC.Spacing.lg)
        }
    }

    // MARK: - Plugins Tab

    private var pluginsTab: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: MSC.Spacing.lg) {

                JarSectionCard(
                    icon: "puzzlepiece.fill",
                    iconColor: .purple,
                    title: "Geyser",
                    description: "Allows Bedrock Edition players (mobile, console, Windows) to join Java servers. Install into the server's plugins folder."
                ) {
                    let geyserItems = viewModel.pluginTemplateItems
                        .filter { $0.filename.lowercased().contains("geyser") }
                        .reversed() as [PluginTemplateItem]

                    JarLibraryList(
                        items: geyserItems.map { .plugin($0) },
                        isActive: { item in
                            if case .plugin(let p) = item { return isPluginTemplateActive(p) }
                            return false
                        },
                        onApply: { item in
                            if case .plugin(let p) = item {
                                viewModel.applyPluginTemplatesToSelectedServer(selectedTemplates: [p])
                            }
                        },
                        onDelete: { item in
                            if case .plugin(let p) = item { viewModel.removePluginTemplate(p) }
                        },
                        applyDisabled: viewModel.selectedServer == nil
                    )

                    JarActionRow {
                        Button("Download Latest") {
                            Task { await viewModel.downloadLatestGeyserTemplate() }
                        }
                        .help("Download the latest Geyser (Spigot) build.")

                        Button("Browse\u{2026}") { isShowingPluginImporter = true }
                            .help("Choose an existing Geyser JAR from your Mac.")

                        Button("Releases Page") {
                            if let url = URL(string: "https://geysermc.org/download") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .help("Open the Geyser downloads page.")

                        Button("Open Folder") { viewModel.openPluginTemplatesFolder() }
                            .help("Open the Plugin Templates folder in Finder.")
                    }
                }

                JarSectionCard(
                    icon: "person.badge.key.fill",
                    iconColor: .orange,
                    title: "Floodgate",
                    description: "Works alongside Geyser to allow Bedrock players to join without a Java account. Install into the server's plugins folder alongside Geyser."
                ) {
                    let floodgateItems = viewModel.pluginTemplateItems
                        .filter { $0.filename.lowercased().contains("floodgate") }
                        .reversed() as [PluginTemplateItem]

                    JarLibraryList(
                        items: floodgateItems.map { .plugin($0) },
                        isActive: { item in
                            if case .plugin(let p) = item { return isPluginTemplateActive(p) }
                            return false
                        },
                        onApply: { item in
                            if case .plugin(let p) = item {
                                viewModel.applyPluginTemplatesToSelectedServer(selectedTemplates: [p])
                            }
                        },
                        onDelete: { item in
                            if case .plugin(let p) = item { viewModel.removePluginTemplate(p) }
                        },
                        applyDisabled: viewModel.selectedServer == nil
                    )

                    JarActionRow {
                        Button("Download Latest") {
                            Task { await viewModel.downloadLatestFloodgateTemplate() }
                        }
                        .help("Download the latest Floodgate (Spigot) build.")

                        Button("Browse\u{2026}") { isShowingPluginImporter = true }
                            .help("Choose an existing Floodgate JAR from your Mac.")

                        Button("Releases Page") {
                            if let url = URL(string: "https://geysermc.org/download") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .help("Open the Floodgate downloads page.")

                        Button("Open Folder") { viewModel.openPluginTemplatesFolder() }
                            .help("Open the Plugin Templates folder in Finder.")
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, MSC.Spacing.lg)
            .padding(.bottom, MSC.Spacing.lg)
        }
    }

    // MARK: - Broadcast & Connect Tab

    private var broadcastAndConnectTab: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: MSC.Spacing.lg) {

                JarSectionCard(
                    icon: "antenna.radiowaves.left.and.right",
                    iconColor: .green,
                    title: "MCXboxBroadcast",
                    description: "Allows Xbox and Windows Bedrock players to discover this server in their Friends tab via a Microsoft account relay."
                ) {
                    JarLibraryList(
                        items: viewModel.xboxBroadcastJarItems.map { .library($0) },
                        isActive: { item in
                            if case .library(let l) = item {
                                return viewModel.configManager.config.xboxBroadcastJarPath == l.url.path
                            }
                            return false
                        },
                        onApply: { item in
                            if case .library(let l) = item {
                                viewModel.setActiveXboxBroadcastJar(l)
                            }
                        },
                        onDelete: { item in
                            if case .library(let l) = item {
                                viewModel.deleteXboxBroadcastJarItem(l)
                            }
                        },
                        applyDisabled: false
                    )

                    JarActionRow {
                        Button("Download Latest") {
                            viewModel.downloadOrUpdateXboxBroadcastJar()
                        }
                        .help("Download the latest MCXboxBroadcastStandalone.jar from GitHub.")

                        Button("Browse\u{2026}") { isShowingXboxBroadcastImporter = true }
                            .help("Choose an existing JAR from your Mac — it will be copied into the library folder.")

                        Button("Releases Page") {
                            if let url = URL(string: "https://github.com/rtm516/MCXboxBroadcast/releases") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .help("Open the MCXboxBroadcast releases page on GitHub.")

                        Button("Open Folder") { viewModel.openXboxBroadcastJarFolder() }
                            .help("Open the MCXboxBroadcast JAR library folder in Finder.")
                    }
                }

                JarSectionCard(
                    icon: "gamecontroller.fill",
                    iconColor: .cyan,
                    title: "Bedrock Connect",
                    description: "Lets PlayStation and Nintendo Switch players join via a DNS trick — intercepts Mojang's featured-server lookup and replaces it with your server list. Requires pointing your router or console DNS to this Mac's IP."
                ) {
                    JarLibraryList(
                        items: viewModel.bedrockConnectJarItems.map { .library($0) },
                        isActive: { item in
                            if case .library(let l) = item {
                                return viewModel.configManager.config.bedrockConnectJarPath == l.url.path
                            }
                            return false
                        },
                        onApply: { item in
                            if case .library(let l) = item {
                                viewModel.setActiveBedrockConnectJar(l)
                            }
                        },
                        onDelete: { item in
                            if case .library(let l) = item {
                                viewModel.deleteBedrockConnectJarItem(l)
                            }
                        },
                        applyDisabled: false
                    )

                    JarActionRow {
                        Button("Download Latest") {
                            viewModel.downloadOrUpdateBedrockConnectJar()
                        }
                        .help("Download the latest BedrockConnect.jar from GitHub.")

                        Button("Browse\u{2026}") { isShowingBedrockConnectImporter = true }
                            .help("Choose an existing JAR from your Mac — it will be copied into the library folder.")

                        Button("Releases Page") {
                            if let url = URL(string: "https://github.com/Pugmatt/BedrockConnect/releases") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .help("Open the BedrockConnect releases page on GitHub.")

                        Button("Open Folder") { viewModel.openBedrockConnectJarFolder() }
                            .help("Open the BedrockConnect JAR library folder in Finder.")
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, MSC.Spacing.lg)
            .padding(.bottom, MSC.Spacing.lg)
        }
    }
}

// MARK: - Jar Item Enum (unified type for all three library types)

private enum JarItem: Identifiable {
    case paper(PaperTemplateItem)
    case plugin(PluginTemplateItem)
    case library(JarLibraryItem)

    var id: String {
        switch self {
        case .paper(let p):   return "paper-\(p.id)"
        case .plugin(let p):  return "plugin-\(p.id)"
        case .library(let l): return "library-\(l.id)"
        }
    }

    var displayTitle: String {
        switch self {
        case .paper(let p):   return p.displayTitle
        case .plugin(let p):  return p.displayTitle
        case .library(let l): return l.displayTitle
        }
    }

    var filename: String {
        switch self {
        case .paper(let p):   return p.filename
        case .plugin(let p):  return p.filename
        case .library(let l): return l.filename
        }
    }
}

// MARK: - Section Card

private struct JarSectionCard<Content: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {

            // Header row
            HStack(spacing: MSC.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }

            // Description callout
            HStack(alignment: .top, spacing: MSC.Spacing.sm) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(iconColor.opacity(0.8))
                    .padding(.top, 1)
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(MSC.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                    .fill(iconColor.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                    .stroke(iconColor.opacity(0.18), lineWidth: 1)
            )

            content()
        }
        .padding(MSC.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .fill(MSC.Colors.tierContent)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }
}

// MARK: - Jar Library List

private struct JarLibraryList: View {
    let items: [JarItem]
    let isActive: (JarItem) -> Bool
    let onApply: (JarItem) -> Void
    let onDelete: (JarItem) -> Void
    let applyDisabled: Bool

    var body: some View {
        if items.isEmpty {
            HStack(spacing: MSC.Spacing.sm) {
                Image(systemName: "tray")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                Text("No versions downloaded yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, MSC.Spacing.xs)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    let active = isActive(item)

                    HStack(spacing: MSC.Spacing.sm) {
                        Image(systemName: active ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 13))
                            .foregroundStyle(active ? MSC.Colors.success : Color.secondary.opacity(0.4))
                            .frame(width: 16)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.displayTitle)
                                .font(.system(size: 12, weight: active ? .semibold : .regular))
                                .foregroundStyle(.primary)
                            Text(item.filename)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        if active {
                            Text("Active")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(MSC.Colors.success)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(MSC.Colors.success.opacity(0.12)))
                                .overlay(Capsule().stroke(MSC.Colors.success.opacity(0.25), lineWidth: 0.75))
                        } else {
                            Button("Apply") { onApply(item) }
                                .buttonStyle(MSCSecondaryButtonStyle())
                                .controlSize(.mini)
                                .disabled(applyDisabled)
                        }

                        Button {
                            onDelete(item)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundStyle(.red.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .controlSize(.mini)
                        .help("Remove this version from the library.")
                    }
                    .padding(.horizontal, MSC.Spacing.sm)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                            .fill(active
                                  ? MSC.Colors.success.opacity(0.06)
                                  : (idx.isMultiple(of: 2) ? Color.clear : Color.white.opacity(0.025)))
                    )
                }
            }
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                    .fill(Color.black.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous))
        }
    }
}

// MARK: - Jar Action Row

private struct JarActionRow<Buttons: View>: View {
    @ViewBuilder let buttons: () -> Buttons

    init(@ViewBuilder buttons: @escaping () -> Buttons) {
        self.buttons = buttons
    }

    var body: some View {
        HStack(spacing: MSC.Spacing.sm) {
            buttons()
                .buttonStyle(MSCSecondaryButtonStyle())
                .controlSize(.small)
            Spacer()
        }
    }
}

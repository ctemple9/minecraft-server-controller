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
        case serverJar
        case broadcastAndConnect
    }

    @State private var selectedTab: TemplatesTab = .serverJar

    // Sheets / importers
    @State private var isShowingPaperImporter: Bool = false
    @State private var isShowingXboxBroadcastImporter: Bool = false

    // Loader version apply confirmation
    @State private var pendingLoaderApply: LoaderVersionRecord? = nil

    // MARK: - Context helpers

    private var selectedConfig: ConfigServer? {
        guard let server = viewModel.selectedServer else { return nil }
        return viewModel.configServer(for: server)
    }

    /// Filename prefix for the selected server's flavor in the archive.
    private var archivePrefix: String? {
        switch selectedConfig?.javaFlavor {
        case .paper:       return "paper-"
        case .purpur:      return "purpur-"
        case .pufferfish:  return "pufferfish-paperclip-"
        case .vanilla:     return "minecraft_server-"
        case .fabric:      return "fabric-server-launch-"
        default:           return nil
        }
    }

    /// All archived server JARs that are relevant to the currently selected server.
    private var relevantArchiveItems: [JarItem] {
        guard let prefix = archivePrefix else { return [] }
        return viewModel.paperTemplateItems
            .reversed()
            .filter { $0.filename.lowercased().hasPrefix(prefix.lowercased()) }
            .map { .paper($0) }
    }

    private var serverJarSectionTitle: String {
        switch selectedConfig?.javaFlavor {
        case .paper:       return "Paper JAR"
        case .purpur:      return "Purpur JAR"
        case .pufferfish:  return "Pufferfish JAR"
        case .vanilla:     return "Vanilla Server JAR"
        case .fabric:      return "Fabric Launcher JAR"
        case .neoforge:    return "NeoForge Version Library"
        case .forge:       return "Forge Version Library"
        default:           return "Server JAR"
        }
    }

    private var serverJarSectionDescription: String {
        guard let flavor = selectedConfig?.javaFlavor else {
            return "Select a server to see its relevant archived JARs. Apply a saved version to skip re-downloading."
        }
        switch flavor {
        case .neoforge, .forge:
            return "Saved \(flavor.displayName) installation profiles. Apply a version to re-run the \(flavor.displayName) installer — mods and world data are not affected."
        case .quilt:
            return "Quilt server upgrades are managed from the Components tab. Use the create flow to provision a new version."
        default:
            return "Saved \(flavor.displayName) server JARs for this server. Apply a saved version to replace the current JAR without re-downloading from the internet."
        }
    }

    private func isLoaderVersionActive(_ record: LoaderVersionRecord) -> Bool {
        guard let cfg = selectedConfig else { return false }
        return cfg.minecraftVersion == record.mcVersion && cfg.loaderVersion == record.loaderVersion
    }

    private func isPaperTemplateActive(_ item: PaperTemplateItem) -> Bool {
        guard let cfgServer = selectedConfig else { return false }
        let serverDir = URL(fileURLWithPath: cfgServer.serverDir, isDirectory: true)
        guard let sidecar = PaperVersionSidecarManager.read(fromServerDirectory: serverDir),
              let parsed = ComponentVersionParsing.parsePaperJarFilename(item.filename) else { return false }
        return sidecar.mcVersion == parsed.mcVersion && sidecar.build == parsed.build
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // HEADER
            HStack(alignment: .center) {
                Text("Archives")
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
            // Cross-Play tab hidden — MCXboxBroadcast management moved out of Archives.
            // Restore by uncommenting .broadcastAndConnect row and its case below.
            Picker("", selection: $selectedTab) {
                Text("Server JAR").tag(TemplatesTab.serverJar)
                // Text("Cross-Play").tag(TemplatesTab.broadcastAndConnect)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, MSC.Spacing.lg)
            .padding(.bottom, MSC.Spacing.md)

            // TAB CONTENT
            Group {
                switch selectedTab {
                case .serverJar:
                    serverJarTab
                case .broadcastAndConnect:
                    // Hidden — restore by re-enabling the picker tab above and this case.
                    // broadcastAndConnectTab
                    serverJarTab
                }
            }
        }
        .frame(minWidth: 820, minHeight: 460)
        .confirmationDialog(
            "Re-install This Version?",
            isPresented: Binding<Bool>(
                get: { pendingLoaderApply != nil },
                set: { if !$0 { pendingLoaderApply = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let record = pendingLoaderApply, let cfg = selectedConfig {
                Button("Install \(record.flavor.displayName) \(record.loaderVersion)") {
                    viewModel.applyLoaderVersionRecord(record, for: cfg)
                    pendingLoaderApply = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingLoaderApply = nil }
        } message: {
            if let record = pendingLoaderApply {
                Text("Re-runs the \(record.flavor.displayName) installer for MC \(record.mcVersion). Mods and world data are not affected.")
            }
        }
        .onAppear {
            viewModel.loadPaperTemplates()
            viewModel.loadXboxBroadcastJars()
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
                viewModel.logAppMessage("[Archive] File import failed: \(error.localizedDescription)")
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
    }

    // MARK: - Server JAR Tab (context-aware by selected server flavor)

    private var serverJarTab: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: MSC.Spacing.lg) {

                JarSectionCard(
                    icon: "shippingbox.fill",
                    iconColor: .blue,
                    title: serverJarSectionTitle,
                    description: serverJarSectionDescription
                ) {
                    let flavor = selectedConfig?.javaFlavor
                    if flavor == .neoforge || flavor == .forge, let flav = flavor {
                        let records = viewModel.loaderVersionRecords(for: flav).map { JarItem.loaderVersion($0) }
                        JarLibraryList(
                            items: records,
                            isActive: { item in
                                if case .loaderVersion(let r) = item { return isLoaderVersionActive(r) }
                                return false
                            },
                            onApply: { item in
                                if case .loaderVersion(let r) = item { pendingLoaderApply = r }
                            },
                            onDelete: { item in
                                if case .loaderVersion(let r) = item { viewModel.removeLoaderVersionRecord(r) }
                            },
                            applyDisabled: viewModel.isDownloadingJar
                        )
                    } else if archivePrefix != nil {
                        JarLibraryList(
                            items: relevantArchiveItems,
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
                            Button("Browse\u{2026}") {
                                isShowingPaperImporter = true
                            }
                            .help("Add a server JAR from your Mac to the archive.")

                            Button("Open Folder") {
                                viewModel.openPaperTemplatesFolder()
                            }
                            .help("Open the archive folder in Finder.")
                        }
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
    case loaderVersion(LoaderVersionRecord)

    var id: String {
        switch self {
        case .paper(let p):         return "paper-\(p.id)"
        case .plugin(let p):        return "plugin-\(p.id)"
        case .library(let l):       return "library-\(l.id)"
        case .loaderVersion(let r): return "loader-\(r.id)"
        }
    }

    var displayTitle: String {
        switch self {
        case .paper(let p):         return p.displayTitle
        case .plugin(let p):        return p.displayTitle
        case .library(let l):       return l.displayTitle
        case .loaderVersion(let r): return r.displayTitle
        }
    }

    var filename: String {
        switch self {
        case .paper(let p):         return p.filename
        case .plugin(let p):        return p.filename
        case .library(let l):       return l.filename
        case .loaderVersion(let r): return r.dateLabel
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

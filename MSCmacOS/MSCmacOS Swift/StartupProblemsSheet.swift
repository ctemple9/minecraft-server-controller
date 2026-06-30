//
//  StartupProblemsSheet.swift
//  MinecraftServerController
//
//  Shown when a modded server fails to start and the crash analyzer attributed the
//  failure to specific mods. Each row names the offending mod, the unmet requirement,
//  and offers the fix: view it on Modrinth (pick a compatible version), disable it, or
//  delete it. A "Try starting again" footer re-launches once changes are made.
//

import SwiftUI

struct StartupProblemsSheet: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Binding var isPresented: Bool

    @State private var expanded: Set<String> = []
    @State private var detailHit: ModrinthSearchHit? = nil
    @State private var pendingDelete: StartupProblem? = nil

    private var problems: [StartupProblem] { viewModel.startupProblems }
    private var isSoftFail: Bool { viewModel.startupProblemsAreSoftFail }
    private var cfg: ConfigServer? {
        if let id = viewModel.startupProblemsServerId,
           let match = viewModel.configManager.config.servers.first(where: { $0.id == id }) {
            return match
        }
        return viewModel.selectedServerConfig
    }

    private func problems(_ kind: StartupProblemKind) -> [StartupProblem] {
        problems.filter { $0.kind == kind }
    }

    var body: some View {
        VStack(spacing: 0) {
            MSCSheetHeader(isSoftFail ? "Add-ons Failed to Load" : "Server Couldn't Start") { isPresented = false }
                .padding(.horizontal, MSC.Spacing.xl)
                .padding(.top, MSC.Spacing.xl)

            header
            Divider()

            if problems.isEmpty {
                resolvedState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
                        section("Missing dependencies", .missingDependency,
                                note: "These mods need something that isn't installed.")
                        section("Incompatible versions", .incompatibleVersion,
                                note: "These mods don't match this server's Minecraft version.")
                        section("Failed to load", .loadError, note: nil)
                        section("Duplicates", .duplicate, note: nil)
                        section("Other problems", .unknown, note: nil)
                    }
                    .padding(MSC.Spacing.xl)
                }
            }

            Divider()
            footer
        }
        .frame(width: 600, height: 640)
        .sheet(item: $detailHit) { hit in
            if let cfg {
                NavigationStack {
                    ModrinthProjectDetailView(hit: hit, serverConfig: cfg)
                        .environmentObject(viewModel)
                        .frame(width: 640, height: 680)
                }
            }
        }
        .confirmationDialog(
            pendingDelete.map { "Delete \($0.offenderName)?" } ?? "Delete mod?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let p = pendingDelete { performDelete(p) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("The mod JAR will be permanently removed from the mods folder.")
        }
    }

    // MARK: - Header / footer

    private var header: some View {
        HStack(spacing: MSC.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(MSC.Colors.warning)
            Text(isSoftFail
                 ? "The server started, but \(problems.count) add-on\(problems.count == 1 ? "" : "s") didn't load. Fix them below, then restart to enable them."
                 : "\(problems.count) \(problems.count == 1 ? "problem" : "problems") stopped this server from starting. Resolve them below, then try again.")
                .font(MSC.Typography.caption)
                .foregroundStyle(MSC.Colors.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, MSC.Spacing.xl)
        .padding(.vertical, MSC.Spacing.md)
    }

    private var resolvedState: some View {
        VStack(spacing: MSC.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 26)).foregroundStyle(MSC.Colors.success)
            Text("All listed problems addressed.")
                .font(MSC.Typography.caption).foregroundStyle(MSC.Colors.tertiary)
            Text("Start the server again to confirm it boots cleanly.")
                .font(.system(size: 10)).foregroundStyle(MSC.Colors.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            if isSoftFail && viewModel.isServerRunning {
                Text("Restart the server to apply changes.")
                    .font(.system(size: 10)).foregroundStyle(MSC.Colors.tertiary)
            }
            Spacer()
            Button("Close") { isPresented = false }
                .buttonStyle(MSCSecondaryButtonStyle())
            if !viewModel.isServerRunning {
                Button {
                    isPresented = false
                    viewModel.startServer()
                } label: {
                    Label(isSoftFail ? "Start Server" : "Try Starting Again", systemImage: "play.fill")
                }
                .buttonStyle(MSCPrimaryButtonStyle())
            }
        }
        .padding(.horizontal, MSC.Spacing.xl)
        .padding(.vertical, MSC.Spacing.lg)
    }

    // MARK: - Sections / rows

    @ViewBuilder
    private func section(_ title: String, _ kind: StartupProblemKind, note: String?) -> some View {
        let items = problems(kind)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                HStack(spacing: 6) {
                    Image(systemName: kind.symbol).font(.system(size: 11)).foregroundStyle(tint(kind))
                    Text("\(title) (\(items.count))")
                        .font(.system(size: 10, weight: .semibold)).tracking(0.5).textCase(.uppercase)
                        .foregroundStyle(MSC.Colors.tertiary)
                }
                if let note {
                    Text(note).font(.system(size: 10)).foregroundStyle(MSC.Colors.tertiary)
                }
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        if idx > 0 { Divider().opacity(0.4) }
                        row(item)
                    }
                }
                .background(RoundedRectangle(cornerRadius: MSC.Radius.md).fill(Color(NSColor.controlBackgroundColor)))
            }
        }
    }

    @ViewBuilder
    private func row(_ p: StartupProblem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: MSC.Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                        .fill(tint(p.kind).opacity(0.12)).frame(width: 28, height: 28)
                    Image(systemName: p.kind.symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint(p.kind))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.offenderName).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    if let req = p.requirement {
                        Text(req).font(.system(size: 10.5)).foregroundStyle(MSC.Colors.caption).lineLimit(2)
                    }
                    if p.installedFile == nil {
                        Text("Not matched to an installed file — view on Modrinth to resolve manually.")
                            .font(.system(size: 9.5)).foregroundStyle(MSC.Colors.tertiary)
                    }
                }
                Spacer()
                rowActions(p)
            }

            Button {
                if expanded.contains(p.id) { expanded.remove(p.id) } else { expanded.insert(p.id) }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: expanded.contains(p.id) ? "chevron.down" : "chevron.right").font(.system(size: 8))
                    Text("Log detail").font(.system(size: 9.5))
                }
                .foregroundStyle(MSC.Colors.tertiary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 36)

            if expanded.contains(p.id) {
                Text(p.rawExcerpt)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(MSC.Colors.caption)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: MSC.Radius.sm).fill(Color.black.opacity(0.25)))
                    .padding(.leading, 36)
            }
        }
        // Smaller leading inset so the icon lines up with the section/header warning
        // glyphs at the content margin (they're bare; this row's icon is in a 28pt box).
        .padding(.leading, MSC.Spacing.xs)
        .padding(.trailing, MSC.Spacing.md)
        .padding(.vertical, MSC.Spacing.sm)
    }

    @ViewBuilder
    private func rowActions(_ p: StartupProblem) -> some View {
        HStack(spacing: 4) {
            if viewModel.repairingProblemIds.contains(p.id) {
                ProgressView().controlSize(.mini)
            } else {
                // Primary fix, depends on the problem kind.
                if let cfg {
                    if p.kind == .incompatibleVersion, p.installedFile != nil {
                        Button("Update") { viewModel.repairIncompatibleAddon(p, for: cfg) }
                            .buttonStyle(MSCSecondaryButtonStyle()).controlSize(.mini)
                            .disabled(viewModel.isServerRunning)
                            .help("Update to a build compatible with this server's Minecraft version")
                    }
                    if p.kind == .missingDependency, let dep = p.missingDependency {
                        Button("Install") { viewModel.installMissingDependency(p, for: cfg) }
                            .buttonStyle(MSCSecondaryButtonStyle()).controlSize(.mini)
                            .disabled(viewModel.isServerRunning)
                            .help("Find \(dep) on Modrinth and install a compatible version")
                    }
                }

                Button("View") { openModrinth(p) }
                    .buttonStyle(MSCSecondaryButtonStyle()).controlSize(.mini)

                if p.installedJarStem != nil {
                    Button("Disable") { performDisable(p) }
                        .buttonStyle(MSCSecondaryButtonStyle()).controlSize(.mini)
                        .disabled(viewModel.isServerRunning)
                    Button { pendingDelete = p } label: {
                        Image(systemName: "trash").foregroundStyle(MSC.Colors.error.opacity(0.8))
                    }
                    .buttonStyle(MSCSecondaryButtonStyle()).controlSize(.mini)
                    .disabled(viewModel.isServerRunning)
                }
            }
        }
    }

    // MARK: - Actions

    private func tint(_ kind: StartupProblemKind) -> Color {
        switch kind {
        case .missingDependency:   return MSC.Colors.info
        case .incompatibleVersion: return MSC.Colors.warning
        default:                   return MSC.Colors.error
        }
    }

    private func resolve(_ p: StartupProblem) { viewModel.startupProblems.removeAll { $0.id == p.id } }

    private var isMod: Bool { cfg?.javaFlavor.addOnKind == .mod }

    private func performDelete(_ p: StartupProblem) {
        if let stem = p.installedJarStem {
            if isMod { viewModel.removeMod(jarStem: stem) } else { viewModel.removePlugin(jarStem: stem) }
        }
        resolve(p)
    }
    private func performDisable(_ p: StartupProblem) {
        if let stem = p.installedJarStem {
            if isMod { viewModel.toggleMod(jarStem: stem) } else { viewModel.togglePlugin(jarStem: stem) }
        }
        resolve(p)
    }

    /// Opens the Modrinth detail view for the offender. Prefers a persisted link
    /// (reliable project id), falling back to the mod-id as the project slug.
    private func openModrinth(_ p: StartupProblem) {
        let linked = cfg?.addonLinks?.values.first { $0.installedFileName == p.installedFile }
        let projectType = (cfg?.javaFlavor.addOnKind == .mod) ? "mod" : "plugin"
        if let linked {
            detailHit = ModrinthSearchHit(
                projectId: linked.projectId, slug: linked.slug, title: linked.title,
                description: "", author: "", downloads: 0, iconUrl: linked.iconURL,
                clientSide: "unknown", serverSide: "unknown", projectType: projectType)
        } else if let slug = p.offenderId ?? slugGuess(from: p.offenderName) {
            detailHit = ModrinthSearchHit(
                projectId: slug, slug: slug, title: p.offenderName,
                description: "", author: "", downloads: 0, iconUrl: nil,
                clientSide: "unknown", serverSide: "unknown", projectType: projectType)
        }
    }

    private func slugGuess(from name: String) -> String? {
        let s = name.lowercased().replacingOccurrences(of: " ", with: "-")
        return s.isEmpty ? nil : s
    }
}

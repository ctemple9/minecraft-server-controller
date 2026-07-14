//
//  AddonUpdateSheet.swift
//  MinecraftServerController
//
//  The "Update All" surface for plugins/mods. Installed add-ons are grouped into
//  priority buckets (update available → no compatible build → up to date → not on
//  Modrinth). Updatable rows are checkboxes, selected by default, so the user can
//  deselect anything before applying. Linked rows can open the existing Modrinth
//  detail sheet to read changelogs; unlinked rows can be manually linked.
//

import SwiftUI

struct AddonUpdateSheet: View {
    @EnvironmentObject var viewModel: AppViewModel
    let cfg: ConfigServer
    @Binding var isPresented: Bool

    @State private var selected: Set<String> = []
    @State private var detailHit: ModrinthSearchHit? = nil
    @State private var linkingItem: AddonUpdateItem? = nil
    @State private var showPackManagedAlert = false

    private var kindNoun: String { cfg.javaFlavor.addOnKind == .mod ? "Mods" : "Plugins" }
    private var projectType: String { cfg.javaFlavor.addOnKind == .mod ? "mod" : "plugin" }

    private var plan: [AddonUpdateItem] { viewModel.addonUpdatePlan }
    private func items(_ bucket: AddonUpdateBucket) -> [AddonUpdateItem] {
        plan.filter { $0.bucket == bucket }
    }
    private var isBusy: Bool { !viewModel.updatingAddonStems.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                MSCSheetHeader("Update \(kindNoun)") { isPresented = false }
                Button {
                    viewModel.resolveAddonUpdates(for: cfg, force: true)
                } label: {
                    if viewModel.isResolvingAddonUpdates {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(MSCSecondaryButtonStyle())
                .controlSize(.mini)
                .disabled(viewModel.isResolvingAddonUpdates)
                .help("Re-check Modrinth for updates")
            }
            .padding(.horizontal, MSC.Spacing.xl)
            .padding(.top, MSC.Spacing.xl)

            Divider().padding(.top, MSC.Spacing.sm)

            content

            Divider()
            footer
        }
        .frame(width: 580, height: 640)
        .onAppear {
            if plan.isEmpty { viewModel.resolveAddonUpdates(for: cfg) }
            else { defaultSelectUpdatable() }
        }
        .onChange(of: viewModel.addonUpdatePlan) { _, _ in defaultSelectUpdatable() }
        .sheet(item: $detailHit) { hit in
            NavigationStack {
                ModrinthProjectDetailView(hit: hit, serverConfig: cfg)
                    .environmentObject(viewModel)
                    .frame(width: 640, height: 680)
            }
        }
        .sheet(item: $linkingItem) { item in
            ModrinthBrowserView(serverConfig: cfg, onAddToStaging: { hit, _ in
                viewModel.manuallyLinkAddon(item, to: hit, for: cfg)
                linkingItem = nil
            })
            .environmentObject(viewModel)
        }
        .background(
            Color.clear
                .alert("Pack-managed server", isPresented: $showPackManagedAlert) {
                    Button("Update Anyway", role: .destructive) {
                        let toUpdate = items(.updateAvailable).filter { selected.contains($0.jarStem) }
                        viewModel.updateAddons(toUpdate, for: cfg)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    let label: String = {
                        var parts: [String] = []
                        if let n = cfg.packName { parts.append(n) }
                        if let v = cfg.packVersion { parts.append(v) }
                        return parts.isEmpty ? "a modpack" : parts.joined(separator: " ")
                    }()
                    Text("This server was installed from \(label). Updating individual mods can break the pack's tested version set.")
                }
        )
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isResolvingAddonUpdates && plan.isEmpty {
            VStack(spacing: MSC.Spacing.md) {
                ProgressView()
                Text("Checking Modrinth for updates…")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if plan.isEmpty {
            VStack(spacing: MSC.Spacing.sm) {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 26))
                    .foregroundStyle(MSC.Colors.tertiary)
                Text("No \(kindNoun.lowercased()) installed.")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
                    bucketSection(
                        "Update available", systemImage: "arrow.up.circle.fill",
                        tint: MSC.Colors.warning, items: items(.updateAvailable), selectable: true)
                    bucketSection(
                        "No compatible version", systemImage: "exclamationmark.triangle.fill",
                        tint: MSC.Colors.error, items: items(.noCompatibleVersion), selectable: false,
                        footnote: cfg.minecraftVersion.map { "Nothing published for Minecraft \($0) yet." })
                    bucketSection(
                        "Up to date", systemImage: "checkmark.circle.fill",
                        tint: MSC.Colors.success, items: items(.upToDate), selectable: false)
                    bucketSection(
                        "Not on Modrinth", systemImage: "questionmark.circle.fill",
                        tint: MSC.Colors.tertiary, items: items(.unlinked), selectable: false,
                        footnote: "These couldn't be matched automatically. Link one to enable updates.")
                }
                .padding(MSC.Spacing.xl)
            }
        }
    }

    @ViewBuilder
    private func bucketSection(
        _ title: String, systemImage: String, tint: Color,
        items: [AddonUpdateItem], selectable: Bool, footnote: String? = nil
    ) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                HStack(spacing: 6) {
                    Image(systemName: systemImage).font(.system(size: 11)).foregroundStyle(tint)
                    Text("\(title) (\(items.count))")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.5).textCase(.uppercase)
                        .foregroundStyle(MSC.Colors.tertiary)
                    if selectable, items.count > 1 {
                        Spacer()
                        Button(allSelected(items) ? "Deselect all" : "Select all") {
                            toggleAll(items)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentColor)
                    }
                }
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        if idx > 0 { Divider().opacity(0.4) }
                        row(item, selectable: selectable)
                    }
                }
                .background(RoundedRectangle(cornerRadius: MSC.Radius.md).fill(Color(NSColor.controlBackgroundColor)))
                if let footnote {
                    Text(footnote).font(.system(size: 10)).foregroundStyle(MSC.Colors.tertiary)
                }
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func row(_ item: AddonUpdateItem, selectable: Bool) -> some View {
        HStack(spacing: MSC.Spacing.sm) {
            if selectable {
                Image(systemName: selected.contains(item.jarStem) ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15))
                    .foregroundStyle(selected.contains(item.jarStem) ? Color.accentColor : MSC.Colors.tertiary)
                    .onTapGesture { toggle(item.jarStem) }
            } else {
                Spacer().frame(width: 15)
            }

            icon(item)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                if let desc = item.description, !desc.isEmpty {
                    Text(desc).font(.system(size: 10.5)).foregroundStyle(MSC.Colors.caption).lineLimit(1)
                } else if item.bucket == .unlinked {
                    Text(item.fileName).font(.system(size: 10.5)).foregroundStyle(MSC.Colors.tertiary).lineLimit(1)
                }
                versionLine(item)
            }

            Spacer()

            if viewModel.updatingAddonStems.contains(item.jarStem) {
                ProgressView().controlSize(.mini)
            } else if item.bucket == .unlinked {
                Button("Link…") { linkingItem = item }
                    .buttonStyle(MSCSecondaryButtonStyle()).controlSize(.mini)
            } else if let _ = item.projectId {
                Button("View") { openDetail(item) }
                    .buttonStyle(MSCSecondaryButtonStyle()).controlSize(.mini)
            }
        }
        .padding(.horizontal, MSC.Spacing.md)
        .padding(.vertical, MSC.Spacing.sm)
        .contentShape(Rectangle())
        .opacity(item.isEnabled ? 1.0 : 0.55)
    }

    @ViewBuilder
    private func versionLine(_ item: AddonUpdateItem) -> some View {
        HStack(spacing: 4) {
            if let cur = item.currentVersion {
                Text(cur).font(.system(size: 10, design: .monospaced)).foregroundStyle(MSC.Colors.tertiary)
            }
            if let avail = item.availableVersion {
                Image(systemName: "arrow.right").font(.system(size: 8)).foregroundStyle(MSC.Colors.tertiary)
                Text(avail).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(MSC.Colors.warning)
            }
            if !item.isEnabled {
                Text("· disabled").font(.system(size: 9)).foregroundStyle(MSC.Colors.tertiary)
            }
        }
    }

    @ViewBuilder
    private func icon(_ item: AddonUpdateItem) -> some View {
        let placeholder = RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15))
        if let s = item.iconURL, let url = URL(string: s) {
            AsyncImage(url: url) { phase in
                if let img = phase.image { img.resizable().scaledToFit() } else { placeholder }
            }
            .frame(width: 26, height: 26)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            ZStack {
                placeholder.frame(width: 26, height: 26)
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.system(size: 10)).foregroundStyle(MSC.Colors.tertiary)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: MSC.Spacing.md) {
            let count = selectedUpdatableCount
            Text(count == 0 ? "No updates selected" : "\(count) selected")
                .font(MSC.Typography.caption)
                .foregroundStyle(MSC.Colors.tertiary)
            Spacer()
            Button("Done") { isPresented = false }
                .buttonStyle(MSCSecondaryButtonStyle())
            Button {
                if cfg.packManaged {
                    showPackManagedAlert = true
                } else {
                    let toUpdate = items(.updateAvailable).filter { selected.contains($0.jarStem) }
                    viewModel.updateAddons(toUpdate, for: cfg)
                }
            } label: {
                if isBusy {
                    HStack(spacing: 4) { ProgressView().controlSize(.mini); Text("Updating…") }
                } else {
                    Text("Update Selected")
                }
            }
            .buttonStyle(MSCPrimaryButtonStyle())
            .disabled(isBusy || selectedUpdatableCount == 0 || viewModel.isServerRunning)
        }
        .padding(.horizontal, MSC.Spacing.xl)
        .padding(.vertical, MSC.Spacing.lg)
    }

    // MARK: - Selection helpers

    private var selectedUpdatableCount: Int {
        items(.updateAvailable).filter { selected.contains($0.jarStem) }.count
    }
    private func defaultSelectUpdatable() {
        selected = Set(items(.updateAvailable).map { $0.jarStem })
    }
    private func toggle(_ stem: String) {
        if selected.contains(stem) { selected.remove(stem) } else { selected.insert(stem) }
    }
    private func allSelected(_ items: [AddonUpdateItem]) -> Bool {
        items.allSatisfy { selected.contains($0.jarStem) }
    }
    private func toggleAll(_ items: [AddonUpdateItem]) {
        if allSelected(items) { items.forEach { selected.remove($0.jarStem) } }
        else { items.forEach { selected.insert($0.jarStem) } }
    }

    // MARK: - Detail

    private func openDetail(_ item: AddonUpdateItem) {
        detailHit = item.modrinthHit(projectType: projectType)
    }
}

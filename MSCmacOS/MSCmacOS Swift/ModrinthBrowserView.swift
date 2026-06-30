//
//  ModrinthBrowserView.swift
//  MinecraftServerController
//
//  M5: the Prism-style add-on browser. Searches Modrinth filtered to the server's
//  loader + Minecraft version, and installs the latest compatible version into the
//  server's add-on folder (plugins/ or mods/).
//

import SwiftUI

struct ModrinthBrowserView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    let serverConfig: ConfigServer
    /// When non-nil, the browser is in staging mode: "Add" calls this callback instead of writing to disk.
    var onAddToStaging: ((ModrinthSearchHit, ModrinthVersionInfo) -> Void)? = nil
    /// Override for the game version filter (used in staging mode when no server exists yet).
    var stagingGameVersion: String? = nil

    @State private var searchText = ""
    @State private var hits: [ModrinthSearchHit] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var installing: Set<String> = []
    @State private var installed: Set<String> = []
    @State private var toast: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var path: [ModrinthSearchHit] = []
    @State private var showClientOnly = false

    private var visibleHits: [ModrinthSearchHit] {
        showClientOnly ? hits : hits.filter { !$0.isClientOnly }
    }

    private var loaders: [String] { serverConfig.javaFlavor.modrinthLoaderFacets }
    private var gameVersion: String? { stagingGameVersion ?? serverConfig.minecraftVersion }
    private var addOnNoun: String { serverConfig.addOnKind?.displayName ?? "Add-ons" }
    private var isStaging: Bool { onAddToStaging != nil }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header
                Divider()
                Group {
                    if let errorText {
                        errorState(errorText)
                    } else if isLoading && hits.isEmpty {
                        ProgressView("Searching Modrinth…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if visibleHits.isEmpty {
                        emptyState
                    } else {
                        resultsList
                    }
                }
            }
            .navigationDestination(for: ModrinthSearchHit.self) { hit in
                ModrinthProjectDetailView(hit: hit, serverConfig: serverConfig, onAddToStaging: onAddToStaging)
                    .environmentObject(viewModel)
            }
        }
        .frame(minWidth: 580, idealWidth: 640, minHeight: 540, idealHeight: 620)
        .task { await runSearch() }
        .onChange(of: searchText) { _, _ in scheduleSearch() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Browse \(addOnNoun.lowercased())")
                        .font(.headline)
                    Text("Modrinth · \(serverConfig.javaFlavor.displayName)\(gameVersion.map { " · \($0)" } ?? "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search \(addOnNoun.lowercased())…", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                if isLoading { ProgressView().controlSize(.small) }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: MSC.Radius.md).fill(Color(NSColor.controlBackgroundColor)))

            HStack {
                Toggle("Show client-only", isOn: $showClientOnly)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let toast {
                    Text(toast).font(.caption).foregroundStyle(.green).lineLimit(1)
                }
            }
        }
        .padding(MSC.Spacing.md)
    }

    // MARK: - Results

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: MSC.Spacing.sm) {
                ForEach(visibleHits) { hit in
                    resultRow(hit)
                    Divider().opacity(0.4)
                }
            }
            .padding(MSC.Spacing.md)
        }
    }

    private func resultRow(_ hit: ModrinthSearchHit) -> some View {
        HStack(alignment: .top, spacing: MSC.Spacing.md) {
            Button {
                path.append(hit)
            } label: {
                HStack(alignment: .top, spacing: MSC.Spacing.md) {
                    icon(hit)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(hit.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            if hit.isClientOnly { tag("Client-only", color: .orange) }
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                        Text("by \(hit.author) · \(formatDownloads(hit.downloads)) downloads")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text(hit.description)
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            installButton(hit)
        }
        .padding(.vertical, 4)
        .opacity(hit.isClientOnly ? 0.75 : 1)
    }

    @ViewBuilder
    private func icon(_ hit: ModrinthSearchHit) -> some View {
        let placeholder = RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.15))
            .overlay(Image(systemName: "shippingbox").foregroundStyle(.secondary))
        if let urlStr = hit.iconUrl, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else { placeholder }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            placeholder.frame(width: 44, height: 44)
        }
    }

    @ViewBuilder
    private func installButton(_ hit: ModrinthSearchHit) -> some View {
        if installed.contains(hit.projectId) {
            Label("Added", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        } else if installing.contains(hit.projectId) {
            ProgressView().controlSize(.small)
        } else {
            Button {
                if isStaging {
                    stageAddOn(hit)
                } else {
                    install(hit)
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
            .controlSize(.small)
        }
    }

    // MARK: - Empty / error

    private var emptyState: some View {
        let allHidden = !hits.isEmpty && visibleHits.isEmpty
        return VStack(spacing: 8) {
            Image(systemName: allHidden ? "eye.slash" : "magnifyingglass")
                .font(.largeTitle).foregroundStyle(.secondary)
            Text(allHidden
                 ? "All results are client-only. Enable \"Show client-only\" to see them."
                 : searchText.isEmpty
                    ? "No \(addOnNoun.lowercased()) found for this server."
                    : "No results for \"\(searchText)\".")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark").font(.largeTitle).foregroundStyle(.secondary)
            Text("Couldn't reach Modrinth").font(.headline)
            Text(text).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Retry") { Task { await runSearch() } }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func tag(_ text: String, color: Color) -> some View {
        Text(text.uppercased())
            .font(.system(size: 8.5, weight: .semibold)).tracking(0.5)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }

    private func formatDownloads(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    // MARK: - Actions

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await runSearch()
        }
    }

    private func runSearch() async {
        isLoading = true
        errorText = nil
        do {
            // Always filter by the server's loader categories so results are limited to
            // add-ons that actually run on this server type (e.g. a Forge server won't see
            // Fabric/NeoForge-only mods). Cross-platform projects like Geyser still appear
            // for Paper because Modrinth tags them with the `paper`/`spigot` loader, and the
            // project_type:plugin-OR-mod facet (see ModrinthAPI.facets) lets them through
            // despite being typed as "mod".
            let result = try await ModrinthAPI.search(
                query: searchText,
                loaders: loaders,
                gameVersion: gameVersion,
                projectType: serverConfig.javaFlavor.modrinthProjectType,
                limit: 30)
            guard !Task.isCancelled else { return }
            // Down-rank client-only add-ons (they do nothing on a server).
            hits = result.hits.sorted { !$0.isClientOnly && $1.isClientOnly }
        } catch {
            errorText = error.localizedDescription
            hits = []
        }
        isLoading = false
    }

    private func install(_ hit: ModrinthSearchHit) {
        installing.insert(hit.projectId)
        Task {
            let result = await viewModel.installModrinthAddon(hit, into: serverConfig)
            await MainActor.run {
                installing.remove(hit.projectId)
                if result.ok {
                    installed.insert(hit.projectId)
                    toast = "\(result.message) — restart the server to apply."
                } else {
                    toast = result.message
                }
            }
        }
    }

    private func stageAddOn(_ hit: ModrinthSearchHit) {
        installing.insert(hit.projectId)
        Task {
            let versions = try? await ModrinthAPI.projectVersions(
                idOrSlug: hit.slug, loaders: loaders, gameVersion: gameVersion)
            await MainActor.run {
                installing.remove(hit.projectId)
                if let version = versions?.first {
                    onAddToStaging?(hit, version)
                    installed.insert(hit.projectId)
                } else {
                    toast = "No compatible version found for \(hit.title)."
                }
            }
        }
    }
}

// MARK: - Project detail page

struct ModrinthProjectDetailView: View {
    @EnvironmentObject var viewModel: AppViewModel
    let hit: ModrinthSearchHit
    let serverConfig: ConfigServer
    var onAddToStaging: ((ModrinthSearchHit, ModrinthVersionInfo) -> Void)? = nil

    @State private var project: ModrinthProject?
    @State private var versions: [ModrinthVersionInfo] = []
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var stableOnly = true
    @State private var installingVersionId: String?
    @State private var installedVersionIds: Set<String> = []
    @State private var expandedVersionIds: Set<String> = []
    @State private var toast: String?

    private var loaders: [String] { serverConfig.javaFlavor.modrinthLoaderFacets }
    private var serverMC: String? { serverConfig.minecraftVersion }

    /// Collapses platform-variant duplicates. Projects like Geyser publish one Modrinth
    /// version per loader (paper, fabric, neoforge, velocity, bungeecord) that all share the
    /// same build number. We keep a single entry per version number, preferring the variant
    /// whose loaders match this server's loader so the correct jar gets installed.
    private var collapsedVersions: [ModrinthVersionInfo] {
        let serverLoaders = Set(loaders)
        var best: [String: ModrinthVersionInfo] = [:]
        var order: [String] = []
        for v in versions {
            let key = v.versionNumber
            let matches = !serverLoaders.isEmpty && !serverLoaders.isDisjoint(with: Set(v.loaders))
            if let existing = best[key] {
                let existingMatches = !serverLoaders.isEmpty && !serverLoaders.isDisjoint(with: Set(existing.loaders))
                if matches && !existingMatches { best[key] = v }
            } else {
                best[key] = v
                order.append(key)
            }
        }
        return order.compactMap { best[$0] }
    }

    /// Server loaders plus first-party-compatible siblings (NeoForge runs Forge mods,
    /// Quilt runs Fabric mods). Used to filter the version list without hiding valid options.
    private var expandedLoaders: Set<String> {
        var set = Set(loaders)
        if serverConfig.javaFlavor == .neoforge { set.insert("forge") }
        if serverConfig.javaFlavor == .quilt    { set.insert("fabric") }
        return set
    }

    private var visibleVersions: [ModrinthVersionInfo] {
        let collapsed = collapsedVersions
        let stable = stableOnly ? collapsed.filter { $0.isStable } : collapsed

        // Hide versions that declare a loader set with zero overlap with this server.
        // Versions with no loaders tagged (rare) are always shown.
        // Safety: if filtering removes everything, fall back to the full list so we
        // never silently hide all options (guards against the Create-mod class of issue).
        if !expandedLoaders.isEmpty {
            let filtered = stable.filter { v in
                v.loaders.isEmpty || !Set(v.loaders).isDisjoint(with: expandedLoaders)
            }
            if !filtered.isEmpty { return filtered }
        }
        return stable
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
                headerSection
                modrinthLinkButton
                if isLoading {
                    ProgressView("Loading…").frame(maxWidth: .infinity).padding()
                } else if let errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                } else {
                    compatibilitySummary
                    if let project, !project.gallery.isEmpty { gallerySection(project) }
                    descriptionSection
                    versionsSection
                    if let project { linksSection(project) }
                }
            }
            .padding(MSC.Spacing.md)
        }
        .navigationTitle(hit.title)
        .task { await load() }
        .safeAreaInset(edge: .bottom) {
            if let toast {
                Text(toast).font(.caption).padding(8)
                    .frame(maxWidth: .infinity).background(.thinMaterial)
            }
        }
    }

    // MARK: Sections

    private var headerSection: some View {
        HStack(alignment: .top, spacing: MSC.Spacing.md) {
            icon
            VStack(alignment: .leading, spacing: 4) {
                Text(hit.title).font(.title3.weight(.semibold))
                Text("by \(hit.author)").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Label(formatNum(project?.downloads ?? hit.downloads), systemImage: "arrow.down.circle")
                    if let f = project?.followers { Label(formatNum(f), systemImage: "heart") }
                }
                .font(.caption2).foregroundStyle(.secondary)
                serverSideBadge
            }
            Spacer()
        }
    }

    /// Canonical web URL for this project. Modrinth's web routes are keyed by the
    /// project type ("mod", "plugin", "datapack", …), which matches `projectType`.
    private var modrinthURL: URL? {
        URL(string: "https://modrinth.com/\(hit.projectType)/\(hit.slug)")
    }

    @ViewBuilder
    private var modrinthLinkButton: some View {
        if let url = modrinthURL {
            Link(destination: url) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.square")
                    Text("View on Modrinth")
                }
            }
            .buttonStyle(MSCSecondaryButtonStyle())
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var compatibilitySummary: some View {
        if let mc = serverMC {
            let hasCompatible = versions.contains { isCompatible($0) }
            if hasCompatible {
                Label("A version is available for your server (\(serverConfig.javaFlavor.displayName) · \(mc)).",
                      systemImage: "checkmark.seal.fill")
                    .font(.caption).foregroundStyle(.green)
            } else if !versions.isEmpty {
                Label("No version yet for Minecraft \(mc). You can still install another version below, at your own risk.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func gallerySection(_ p: ModrinthProject) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Gallery").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(p.gallery) { img in
                        if let url = URL(string: img.url) {
                            AsyncImage(url: url) { phase in
                                (phase.image ?? Image(systemName: "photo")).resizable().scaledToFill()
                            }
                            .frame(width: 220, height: 124).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("About").font(.headline)
            Text(renderedBody)
                .font(.callout).foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var versionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Versions").font(.headline)
                Spacer()
                Toggle("Stable only", isOn: $stableOnly).toggleStyle(.checkbox).font(.caption)
            }
            if visibleVersions.isEmpty {
                if stableOnly && !versions.isEmpty {
                    HStack(spacing: 6) {
                        Text("Only pre-release builds are available.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Show them") { stableOnly = false }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                    }
                } else {
                    Text("No versions found for this loader.").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                ForEach(visibleVersions.prefix(40)) { v in
                    versionRow(v)
                    Divider().opacity(0.3)
                }
            }
        }
    }

    private func versionRow(_ v: ModrinthVersionInfo) -> some View {
        let compatible = isCompatible(v)
        let conflictCount = v.dependencies.filter { $0.dependencyType == "incompatible" }.count
        let isExpanded = expandedVersionIds.contains(v.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: MSC.Spacing.md) {
                Button {
                    if isExpanded { expandedVersionIds.remove(v.id) }
                    else { expandedVersionIds.insert(v.id) }
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .padding(.top, 3)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(v.versionNumber)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                channelBadge(v.versionType)
                                badge(compatible ? "Compatible" : "Other version", compatible ? .green : .orange)
                                if conflictCount > 0 {
                                    badge("⚠ \(conflictCount == 1 ? "1 conflict" : "\(conflictCount) conflicts")", .red)
                                }
                            }
                            Text("MC " + v.gameVersions.prefix(4).joined(separator: ", ")
                                 + (v.gameVersions.count > 4 ? "…" : ""))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                versionInstallButton(v, compatible: compatible)
            }
            if conflictCount > 0 {
                Text("This version declares incompatibilities with \(conflictCount == 1 ? "another mod" : "\(conflictCount) other mods"). Check before installing.")
                    .font(.caption2).foregroundStyle(.red.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 18)
            }
            if isExpanded {
                versionExpandedDetail(v)
                    .padding(.leading, 18)
            }
        }
        .padding(.vertical, 4)
        .opacity(compatible ? 1 : 0.85)
    }

    /// Full per-version detail shown when a build row is expanded: every supported
    /// Minecraft version (so the user can verify their version is really covered) and
    /// the platform loaders the build targets.
    @ViewBuilder
    private func versionExpandedDetail(_ v: ModrinthVersionInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Supported Minecraft versions")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                FlowVersionTags(versions: v.gameVersions, highlight: serverMC)
            }
            if !v.loaders.isEmpty {
                Text("Platforms: " + v.loaders.map { $0.capitalized }.joined(separator: ", "))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
    }

    @ViewBuilder
    private func versionInstallButton(_ v: ModrinthVersionInfo, compatible: Bool) -> some View {
        if installedVersionIds.contains(v.id) {
            Label("Added", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
        } else if installingVersionId == v.id {
            ProgressView().controlSize(.small)
        } else if onAddToStaging != nil {
            Button(compatible ? "Add" : "Add anyway") {
                onAddToStaging?(hit, v)
                installedVersionIds.insert(v.id)
            }
            .controlSize(.small)
        } else {
            Button(compatible ? "Install" : "Install anyway") { installVersion(v, compatible: compatible) }
                .controlSize(.small)
        }
    }

    private func linksSection(_ p: ModrinthProject) -> some View {
        let links: [(String, String?)] = [
            ("Source", p.sourceUrl), ("Issues", p.issuesUrl),
            ("Wiki", p.wikiUrl), ("Discord", p.discordUrl),
        ]
        return HStack(spacing: 14) {
            ForEach(links.filter { $0.1 != nil }, id: \.0) { item in
                if let s = item.1, let url = URL(string: s) { Link(item.0, destination: url) }
            }
        }
        .font(.caption)
    }

    // MARK: Pieces

    private var icon: some View {
        let placeholder = RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.15))
            .overlay(Image(systemName: "shippingbox").foregroundStyle(.secondary))
        return Group {
            if let s = hit.iconUrl, let url = URL(string: s) {
                AsyncImage(url: url) { phase in
                    if let img = phase.image { img.resizable().scaledToFit() } else { placeholder }
                }
            } else { placeholder }
        }
        .frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var serverSideBadge: some View {
        let ss = project?.serverSide ?? hit.serverSide
        switch ss {
        case "unsupported": badge("Client-only — does nothing on a server", .orange)
        case "required":    badge("Server-side required", .green)
        default:            badge("Server-side optional", .secondary)
        }
    }

    private func channelBadge(_ type: String) -> some View {
        let color: Color = type == "release" ? .green : (type == "beta" ? .orange : .red)
        return badge(type.capitalized, color)
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.16)))
            .foregroundStyle(color)
    }

    private var renderedBody: AttributedString {
        let raw = project?.body ?? hit.description
        guard !raw.isEmpty else { return AttributedString(hit.description) }
        let cleaned = sanitizedBodyMarkdown(raw)
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: cleaned, options: opts)) ?? AttributedString(cleaned)
    }

    /// Modrinth bodies are GitHub-Flavored Markdown with raw HTML mixed in (iframes,
    /// `<img>` badges, `<div align>`, `<a>` links, …). Apple's inline-only Markdown parser
    /// renders none of that — it leaks the tags and block syntax as literal text. This
    /// strips the parts we can't render and converts what we can into inline Markdown the
    /// parser understands, so the "About" section reads cleanly while staying fully native.
    private func sanitizedBodyMarkdown(_ raw: String) -> String {
        var s = raw

        func regexReplace(_ pattern: String, _ replacement: String) {
            s = s.replacingOccurrences(of: pattern, with: replacement,
                                       options: [.regularExpression, .caseInsensitive])
        }

        // 1. Drop block embeds entirely (tag + inner content): videos, scripts, tables.
        for tag in ["iframe", "script", "style", "video", "table"] {
            regexReplace("<\(tag)[\\s\\S]*?</\(tag)>", "")
        }

        // 2. <br> → newline.
        regexReplace("<br\\s*/?>", "\n")

        // 3. Drop images (HTML and Markdown) — there's no native inline image rendering.
        regexReplace("<img[^>]*>", "")
        regexReplace("!\\[[^\\]]*\\]\\([^)]*\\)", "")

        // 4. HTML anchors → inline Markdown links so they stay tappable.
        regexReplace("<a[^>]*href=[\"']([^\"']+)[\"'][^>]*>([\\s\\S]*?)</a>", "[$2]($1)")

        // 5. Remove now-empty links left behind by stripped badge images.
        regexReplace("\\[\\s*\\]\\([^)]*\\)", "")

        // 6. Strip any remaining HTML tags, keeping inner text.
        regexReplace("<[^>]+>", "")

        // 7. Decode the handful of HTML entities that actually show up.
        for (entity, char) in ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
                               "&#39;": "'", "&nbsp;": " ", "&mdash;": "—", "&ndash;": "–"] {
            s = s.replacingOccurrences(of: entity, with: char)
        }

        // 8. Per-line block cleanup: headers → bold, drop rules/blockquote markers.
        s = s.components(separatedBy: "\n").map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed == "***" || trimmed == "___" { return "" }
            if let r = trimmed.range(of: "^#{1,6}\\s+", options: .regularExpression) {
                let text = String(trimmed[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                return text.isEmpty ? "" : "**\(text)**"
            }
            return line.replacingOccurrences(of: "^\\s*>\\s?", with: "", options: .regularExpression)
        }.joined(separator: "\n")

        // 9. Collapse runs of blank lines and trim.
        regexReplace("\\n{3,}", "\n\n")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isCompatible(_ v: ModrinthVersionInfo) -> Bool {
        guard let mc = serverMC else { return false }
        return v.gameVersions.contains(mc)
    }

    private func formatNum(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    // MARK: Actions

    private func load() async {
        isLoading = true
        errorText = nil
        async let projTask = ModrinthAPI.project(idOrSlug: hit.slug)
        // Fetch all versions without a loader filter — projects like Geyser/Floodgate tag
        // their versions with platform-specific loaders (spigot, bungeecord, fabric) that
        // may not match our server's loader list exactly. The compatibility summary already
        // shows which versions work for the server, so filtering here just hides valid options.
        async let versTask = ModrinthAPI.projectVersions(idOrSlug: hit.slug, loaders: [], gameVersion: nil)
        project = try? await projTask
        versions = (try? await versTask) ?? []
        if project == nil && versions.isEmpty {
            errorText = "Couldn't load this project from Modrinth."
        }
        // Some projects (e.g. Geyser, Floodgate) publish every build through the beta
        // channel and never mark a version as "release". For those, "Stable only" would
        // hide everything, so turn it off automatically when no release versions exist.
        if !versions.isEmpty && !versions.contains(where: { $0.isStable }) {
            stableOnly = false
        }
        isLoading = false
    }

    private func installVersion(_ v: ModrinthVersionInfo, compatible: Bool) {
        installingVersionId = v.id
        Task {
            let result = await viewModel.installModrinthVersion(v, title: hit.title, into: serverConfig)
            await MainActor.run {
                installingVersionId = nil
                if result.ok {
                    installedVersionIds.insert(v.id)
                    toast = compatible
                        ? "\(result.message) — restart the server to apply."
                        : "\(result.message) — note: built for a different Minecraft version. Restart to apply."
                } else {
                    toast = result.message
                }
            }
        }
    }
}

// MARK: - Flow-wrapping version tags

/// Wraps a list of Minecraft version strings into chips that flow onto multiple lines.
/// The chip matching `highlight` (the server's MC version) is shown in green so the user
/// can immediately confirm whether a build actually supports their version.
private struct FlowVersionTags: View {
    let versions: [String]
    let highlight: String?

    var body: some View {
        FlowLayout(spacing: 4, lineSpacing: 4) {
            ForEach(versions, id: \.self) { v in
                let isMatch = (v == highlight)
                Text(v)
                    .font(.system(size: 9.5, weight: isMatch ? .bold : .regular, design: .monospaced))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill((isMatch ? Color.green : Color.secondary).opacity(0.16)))
                    .foregroundStyle(isMatch ? Color.green : Color.secondary)
            }
        }
    }
}

/// Minimal flow layout: lays children left-to-right, wrapping to the next line when the
/// current row runs out of width.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, lineHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x - bounds.minX + size.width > maxWidth && x > bounds.minX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

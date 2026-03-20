import SwiftUI

// MARK: - Inline level/tag inference
//
// The ConsoleLineDTO.level field from the server is unreliable — it is often
// nil, or set to a value that doesn't match what's visually in the text.
// The macOS ConsoleManager infers level and tag by scanning the raw text.
// We port that same logic here so iOS filtering matches macOS behaviour.

private func inferredLevel(from text: String) -> String {
    let upper = text.uppercased()
    if upper.contains(" ERROR") || upper.contains(" SEVERE") || upper.contains("EXCEPTION") || upper.contains("JAVA.LANG.") { return "ERROR" }
    if upper.contains(" WARN")  { return "WARN"  }
    if upper.contains(" INFO")  { return "INFO"  }
    return "OTHER"
}

/// Returns the plugin/component tag from a server line, or nil if none.
/// Mirrors ConsoleManager.inferTag + extractBracketTokens + isCoreServerTag.
private func inferredTag(from text: String) -> String? {
    // Extract all [token] groups
    var tokens: [String] = []
    var current = ""
    var inBracket = false
    for ch in text {
        if ch == "[" { inBracket = true; current = ""; continue }
        if ch == "]" { if inBracket { tokens.append(current) }; inBracket = false; current = ""; continue }
        if inBracket { current.append(ch) }
    }
    let trimmed = tokens.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

    // Drop timestamp tokens (contain ":" and digits) and level words
    let filtered = trimmed.filter { tok in
        let hasColon = tok.contains(":")
        let hasDigit = tok.rangeOfCharacter(from: .decimalDigits) != nil
        if hasColon && hasDigit { return false }
        let lower = tok.lowercased()
        return lower != "info" && lower != "warn" && lower != "error"
    }

    return filtered.first
}

private let coreServerTags: Set<String> = ["bootstrap", "minecraftserver", "paper", "server", "main"]

private func isPlugin(_ text: String) -> Bool {
    guard let tag = inferredTag(from: text) else { return false }
    return !coreServerTags.contains(tag.lowercased())
}

private func isAutoLine(_ text: String) -> Bool {
    if text.contains("[Auto →") || text.contains("[Auto ->") { return true }
    let lower = text.lowercased()
    if lower.contains("tps from last 1m, 5m, 15m") { return true }
    if lower.contains("there are") && lower.contains("players online") { return true }
    return false
}

// MARK: - ConsoleView

struct ConsoleView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var vm: DashboardViewModel

    @State private var tailN: Int = 200
    @State private var showLive: Bool = false

    // MARK: Filter state
    //
    // All filtering is a single computed property (displayLines) that reads
    // these @State values directly. SwiftUI re-evaluates it whenever state
    // changes — no Combine pipeline, no cached array, no .onChange needed.

    @State private var activeSourceChips: Set<String> = []   // "app" | "server"
    @State private var activeLevelChips: Set<String>  = []   // "INFO" | "WARN" | "ERROR"
    @State private var pluginsOnly: Bool  = false
    @State private var hideAuto:    Bool  = false
    @State private var searchText:  String = ""
    @State private var showSearch:  Bool   = false
    @FocusState private var searchFocused: Bool

    private var resolvedBaseURL: URL? { settings.resolvedBaseURL() }
    private var resolvedToken:   URL? { nil }   // unused — kept for symmetry
    private var isPaired: Bool {
        settings.resolvedBaseURL() != nil && settings.resolvedToken() != nil
    }

    private var sourceLines: [ConsoleLineDTO] {
        showLive ? vm.consoleStream : vm.consoleTail
    }

    private var isAnyFilterActive: Bool {
        !activeSourceChips.isEmpty || !activeLevelChips.isEmpty ||
        pluginsOnly || hideAuto ||
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // The "app" source chip is only worth showing if there are app-source lines
    private var hasAppLines:    Bool { sourceLines.contains { $0.source == "app"    } }
    private var hasServerLines: Bool { sourceLines.contains { $0.source == "server" } }
    private var hasAutoLines:   Bool { sourceLines.contains { isAutoLine($0.text)   } }
    private var hasPluginLines: Bool { sourceLines.contains { $0.source == "server" && isPlugin($0.text) } }

    /// Final visible line set — derived inline, never cached.
    private var displayLines: [ConsoleLineDTO] {
        var lines = sourceLines

        // Source filter
        if !activeSourceChips.isEmpty {
            lines = lines.filter { activeSourceChips.contains($0.source) }
        }

        // Level filter — inferred from text, not the DTO field
        if !activeLevelChips.isEmpty {
            lines = lines.filter { activeLevelChips.contains(inferredLevel(from: $0.text)) }
        }

        // Plugins filter — server lines whose tag is NOT a core server component
        if pluginsOnly {
            lines = lines.filter { $0.source == "server" && isPlugin($0.text) }
        }

        // Hide auto — suppress polling noise and known auto-response patterns
        if hideAuto {
            lines = lines.filter { !isAutoLine($0.text) }
        }

        // Text search
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !term.isEmpty {
            lines = lines.filter { $0.text.lowercased().contains(term) }
        }

        return lines
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                MSCRemoteStyle.bgBase.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: MSCRemoteStyle.spaceLG) {
                        streamControlCard
                        tailControlCard
                        consoleOutputCard
                        footerText
                    }
                    .padding(.horizontal, MSCRemoteStyle.spaceLG)
                    .padding(.top,    MSCRemoteStyle.spaceMD)
                    .padding(.bottom, MSCRemoteStyle.space2XL)
                }
                .refreshable { await fetchTail() }
            }
            .navigationTitle("Console")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(MSCRemoteStyle.bgBase, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onDisappear { vm.disconnectConsoleStream(); showLive = false }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                guard isPaired, showLive else { return }
                Task { vm.disconnectConsoleStream(); await connectStream() }
            }
            .onChange(of: showLive) { _, _ in resetFilters() }
        }
    }

    // MARK: - Stream Control Card

    private var streamControlCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            MSCSectionHeader(title: "Live Stream")
                .padding(.bottom, MSCRemoteStyle.spaceMD)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(vm.isStreamingConsole ? "Connected" : "Disconnected")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(vm.isStreamingConsole ? MSCRemoteStyle.success : MSCRemoteStyle.textSecondary)
                    Text("Continuous output when enabled")
                        .font(.system(size: 11))
                        .foregroundStyle(MSCRemoteStyle.textTertiary)
                }
                Spacer()
                Toggle("", isOn: $showLive)
                    .labelsHidden()
                    .tint(MSCRemoteStyle.accent)
                    .onChange(of: showLive) { _, newValue in
                        if newValue { Task { await connectStream() } }
                        else { vm.disconnectConsoleStream() }
                    }
                    .disabled(!isPaired)
            }
        }
        .mscCard()
    }

    // MARK: - Tail / Buffer Card

    private var tailControlCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            MSCSectionHeader(
                title: showLive ? "Buffer" : "Snapshot",
                trailing: showLive ? "Rolling \(tailN) lines" : nil
            )
            .padding(.bottom, MSCRemoteStyle.spaceMD)
            HStack(spacing: MSCRemoteStyle.spaceMD) {
                Stepper(value: $tailN, in: 20...500, step: 20) {
                    Text("Lines: \(tailN)")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(MSCRemoteStyle.textPrimary)
                }
                .tint(MSCRemoteStyle.accent)

                Button {
                    hapticLight()
                    if showLive { vm.trimConsoleStream(to: tailN) }
                    else { Task { await fetchTail() } }
                } label: {
                    Text(showLive ? "Trim" : "Fetch")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isPaired ? MSCRemoteStyle.bgBase : MSCRemoteStyle.textTertiary)
                        .padding(.horizontal, MSCRemoteStyle.spaceLG)
                        .frame(height: 36)
                        .background(isPaired ? MSCRemoteStyle.accent : MSCRemoteStyle.bgElevated)
                        .clipShape(RoundedRectangle(cornerRadius: MSCRemoteStyle.radiusSM, style: .continuous))
                }
                .disabled(!isPaired)
            }
        }
        .mscCard()
    }

    // MARK: - Console Output Card

    private var consoleOutputCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            let filtered = displayLines
            let total    = sourceLines.count

            // ── Header ─────────────────────────────────────────────────────
            HStack(alignment: .center) {
                Text(showLive ? "LIVE" : "TAIL")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(MSCRemoteStyle.textTertiary)
                    .kerning(1.2)
                Spacer()
                if total > 0 {
                    Text(isAnyFilterActive ? "\(filtered.count) of \(total)" : "\(total)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(isAnyFilterActive ? MSCRemoteStyle.accent : MSCRemoteStyle.textTertiary)
                }
                // Search toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showSearch.toggle()
                        if !showSearch { searchText = "" }
                    }
                } label: {
                    Image(systemName: showSearch ? "magnifyingglass.circle.fill" : "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundStyle(showSearch ? MSCRemoteStyle.accent : MSCRemoteStyle.textTertiary)
                }
                .buttonStyle(.plain)
                .padding(.leading, MSCRemoteStyle.spaceSM)
                // Copy visible
                Button { copyVisibleLines(filtered) } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13))
                        .foregroundStyle(filtered.isEmpty ? MSCRemoteStyle.textTertiary.opacity(0.3) : MSCRemoteStyle.textTertiary)
                }
                .buttonStyle(.plain)
                .disabled(filtered.isEmpty)
                .padding(.leading, MSCRemoteStyle.spaceSM)
                // Reset — only when a filter is active
                if isAnyFilterActive {
                    Button { withAnimation(.easeInOut(duration: 0.15)) { resetFilters() } } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(MSCRemoteStyle.warning)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, MSCRemoteStyle.spaceSM)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .padding(.horizontal, 2)
            .padding(.bottom, MSCRemoteStyle.spaceMD)

            // ── Search bar ─────────────────────────────────────────────────
            if showSearch {
                searchBar
                    .padding(.bottom, MSCRemoteStyle.spaceMD)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // ── Single chip row ────────────────────────────────────────────
            // All filter chips live on one horizontal scroll row, no labels.
            // Chips only appear when the data actually contains lines they
            // would act on, preventing phantom filters.
            if total > 0 {
                filterChipStrip
                    .padding(.bottom, MSCRemoteStyle.spaceMD)
            }

            // ── Terminal box ───────────────────────────────────────────────
            ZStack(alignment: .topLeading) {
                Color(hex: "#0A0C0E")
                    .clipShape(RoundedRectangle(cornerRadius: MSCRemoteStyle.radiusSM, style: .continuous))

                if filtered.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        if isAnyFilterActive && total > 0 {
                            Text("No lines match the active filters.")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(MSCRemoteStyle.textTertiary)
                            Text("Tap \u{00D7} above to reset.")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(MSCRemoteStyle.textTertiary.opacity(0.6))
                        } else {
                            Text(showLive ? "Waiting for live output…" : "No lines loaded yet.")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(MSCRemoteStyle.textTertiary)
                            Text(showLive ? "Turn on the toggle above." : "Tap Fetch to load a snapshot.")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(MSCRemoteStyle.textTertiary.opacity(0.6))
                        }
                    }
                    .padding(MSCRemoteStyle.spaceMD)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach(filtered) { line in
                                    consoleLine(line).id(line.id)
                                }
                            }
                            .padding(MSCRemoteStyle.spaceMD)
                        }
                        .onChange(of: vm.consoleStream.count) { _, _ in
                            guard showLive, let last = filtered.last else { return }
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            }
            .frame(maxHeight: 360)
            .overlay(
                RoundedRectangle(cornerRadius: MSCRemoteStyle.radiusSM, style: .continuous)
                    .strokeBorder(MSCRemoteStyle.borderSubtle, lineWidth: 1)
            )
        }
        .mscCard()
    }

    // MARK: - Filter chip strip

    private var filterChipStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MSCRemoteStyle.spaceSM) {

                // SOURCE chips — only show sources that actually have lines
                if hasAppLines {
                    chip("APP",
                         isActive: activeSourceChips.contains("app"),
                         accent: MSCRemoteStyle.accent) {
                        toggle(&activeSourceChips, value: "app")
                    }
                }
                if hasServerLines {
                    chip("SERVER",
                         isActive: activeSourceChips.contains("server"),
                         accent: MSCRemoteStyle.accent) {
                        toggle(&activeSourceChips, value: "server")
                    }
                }

                // Subtle divider between source and level groups
                if (hasAppLines || hasServerLines) {
                    Divider()
                        .frame(height: 16)
                        .background(MSCRemoteStyle.borderMid)
                        .padding(.horizontal, 2)
                }

                // LEVEL chips — always shown so user can see what's available
                chip("INFO",
                     isActive: activeLevelChips.contains("INFO"),
                     accent: MSCRemoteStyle.accent) {
                    toggle(&activeLevelChips, value: "INFO")
                }
                chip("WARN",
                     isActive: activeLevelChips.contains("WARN"),
                     accent: MSCRemoteStyle.warning) {
                    toggle(&activeLevelChips, value: "WARN")
                }
                chip("ERROR",
                     isActive: activeLevelChips.contains("ERROR"),
                     accent: MSCRemoteStyle.danger) {
                    toggle(&activeLevelChips, value: "ERROR")
                }

                Divider()
                    .frame(height: 16)
                    .background(MSCRemoteStyle.borderMid)
                    .padding(.horizontal, 2)

                // PLUGINS chip — only shown when plugin lines exist
                if hasPluginLines {
                    chip("PLUGINS",
                         isActive: pluginsOnly,
                         accent: MSCRemoteStyle.accent) {
                        withAnimation(.easeInOut(duration: 0.15)) { pluginsOnly.toggle() }
                    }
                }

                // HIDE AUTO chip — only shown when auto lines exist
                if hasAutoLines {
                    chip("HIDE AUTO",
                         isActive: hideAuto,
                         accent: MSCRemoteStyle.warning) {
                        withAnimation(.easeInOut(duration: 0.15)) { hideAuto.toggle() }
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }

    // MARK: - Chip component

    private func chip(
        _ label: String,
        isActive: Bool,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .kerning(0.5)
                .foregroundStyle(isActive ? MSCRemoteStyle.bgBase : MSCRemoteStyle.textSecondary)
                .padding(.horizontal, MSCRemoteStyle.spaceSM)
                .padding(.vertical, 5)
                .background(isActive ? accent : MSCRemoteStyle.bgElevated)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(isActive ? accent : MSCRemoteStyle.borderMid, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isActive)
    }

    private func toggle(_ set: inout Set<String>, value: String) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if set.contains(value) { set.remove(value) } else { set.insert(value) }
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: MSCRemoteStyle.spaceSM) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(searchFocused ? MSCRemoteStyle.accent : MSCRemoteStyle.textTertiary)
                .animation(.easeInOut(duration: 0.15), value: searchFocused)

            TextField("Search output…", text: $searchText)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(MSCRemoteStyle.textPrimary)
                .tint(MSCRemoteStyle.accent)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(MSCRemoteStyle.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, MSCRemoteStyle.spaceMD)
        .padding(.vertical, MSCRemoteStyle.spaceSM)
        .background(MSCRemoteStyle.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: MSCRemoteStyle.radiusSM, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MSCRemoteStyle.radiusSM, style: .continuous)
                .strokeBorder(
                    searchFocused ? MSCRemoteStyle.accent.opacity(0.45) : MSCRemoteStyle.borderMid,
                    lineWidth: 1
                )
                .animation(.easeInOut(duration: 0.15), value: searchFocused)
        )
    }

    // MARK: - Console line row

    @ViewBuilder
    private func consoleLine(_ line: ConsoleLineDTO) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(formatTimestamp(line.ts))  [\(line.source)]")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(MSCRemoteStyle.textTertiary)
                .lineLimit(1)
            Text(line.text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(lineColor(for: line))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Timestamp

    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let isoParserNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm:ss a"; f.amSymbol = "AM"; f.pmSymbol = "PM"; return f
    }()

    private func formatTimestamp(_ raw: String) -> String {
        if let d = Self.isoParser.date(from: raw)           { return Self.timeFormatter.string(from: d) }
        if let d = Self.isoParserNoFraction.date(from: raw) { return Self.timeFormatter.string(from: d) }
        return raw
    }

    // MARK: - Line color (by inferred level for consistency with filter)

    private func lineColor(for line: ConsoleLineDTO) -> Color {
        if line.source == "app" { return Color.white.opacity(0.45) }
        switch inferredLevel(from: line.text) {
        case "WARN":  return MSCRemoteStyle.warning
        case "ERROR": return MSCRemoteStyle.danger
        default:      return Color.white.opacity(0.75)
        }
    }

    // MARK: - Helpers

    private func resetFilters() {
        activeSourceChips.removeAll()
        activeLevelChips.removeAll()
        pluginsOnly  = false
        hideAuto     = false
        searchText   = ""
        showSearch   = false
    }

    private func copyVisibleLines(_ lines: [ConsoleLineDTO]) {
        UIPasteboard.general.string = lines.map { $0.text }.joined(separator: "\n")
        hapticSuccess()
    }

    private var footerText: some View {
        Text("TempleTech · MSC REMOTE")
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .foregroundStyle(MSCRemoteStyle.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private func fetchTail() async {
        guard let baseURL = settings.resolvedBaseURL(), let token = settings.resolvedToken() else { return }
        await vm.refreshAll(baseURL: baseURL, token: token, tailN: tailN)
    }

    private func connectStream() async {
        guard let baseURL = settings.resolvedBaseURL(), let token = settings.resolvedToken() else { return }
        await vm.connectConsoleStream(baseURL: baseURL, token: token)
    }
}


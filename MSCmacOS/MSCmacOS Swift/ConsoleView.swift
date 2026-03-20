
//
//  ConsoleView.swift
//  MinecraftServerController
//
//  Console UI — command input with three-layer UX:
//    1. Raw input  — type and send, always available
//    2. Autocomplete strip — smart token-aware suggestions above the command bar
//    3. Command Palette — full sheet with categories, search, favorites, guided builder
//

import SwiftUI
import AppKit

struct ConsoleView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var showFiltersPopover: Bool = false
    @State private var showCommandPalette: Bool = false

    /// Persisted toggle — user can disable autocomplete if they find it distracting.
    @AppStorage("msc_autocomplete_enabled") private var autoCompleteEnabled: Bool = true

    /// When true, only the log scroll area and command bar are shown.
    var isCollapsed: Bool = false

    // MARK: - Autocomplete Suggestions

    private var serverType: ServerType {
            viewModel.selectedServer
                .flatMap { viewModel.configServer(for: $0) }?.serverType ?? .java
        }

    private var autoCompleteSuggestions: [String] {
        guard autoCompleteEnabled else { return [] }
        let text = viewModel.commandText
        guard !text.isEmpty else { return [] }
        return MinecraftCommandRegistry.suggestions(
            for: text,
            serverType: serverType,
            onlinePlayers: viewModel.onlinePlayers
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            if !isCollapsed {
                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                    HStack(spacing: MSC.Spacing.sm) {
                        MSCOverline("Console")

                        // Search field
                        HStack(spacing: MSC.Spacing.xs) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.tertiary)

                            TextField("Search…", text: $viewModel.consoleSearchText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, MSC.Spacing.sm)
                        .padding(.vertical, MSC.Spacing.xs + 1)
                        .frame(maxWidth: .infinity)
                        .background {
                            RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                                .fill(MSC.Colors.tierTerminal)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        }

                        // Autocomplete toggle
                        Button {
                            autoCompleteEnabled.toggle()
                        } label: {
                            Image(systemName: autoCompleteEnabled ? "wand.and.rays" : "wand.and.rays.inverse")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(autoCompleteEnabled ? Color.accentColor.opacity(0.85) : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(autoCompleteEnabled ? "Autocomplete On — click to disable" : "Autocomplete Off — click to enable")

                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: MSC.Spacing.xs) {
                            ForEach(ConsoleTab.allCases) { tab in
                                if tab == .custom {
                                    Button {
                                        showFiltersPopover = true
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "slider.horizontal.3")
                                                .font(.system(size: 10, weight: .medium))
                                            Text(tab.displayName)
                                                .font(.system(size: 11, weight: .medium))
                                        }
                                        .foregroundStyle(Color.white.opacity(0.66))
                                        .padding(.horizontal, MSC.Spacing.sm)
                                        .padding(.vertical, MSC.Spacing.xs)
                                        .background {
                                            consoleChipBackground(isActive: false, accentColor: .accentColor)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .popover(isPresented: $showFiltersPopover, arrowEdge: .bottom) {
                                        filtersPopover
                                            .frame(width: 380)
                                            .padding(MSC.Spacing.md)
                                    }
                                } else {
                                    let isActive = viewModel.consoleTab == tab

                                    Button {
                                        withAnimation(MSC.Animation.tabSwitch) {
                                            viewModel.consoleTab = tab
                                        }
                                    } label: {
                                        Text(tab.displayName)
                                            .font(.system(size: 11, weight: isActive ? .semibold : .medium))
                                            .foregroundStyle(
                                                isActive
                                                    ? Color.white.opacity(0.96)
                                                    : Color.white.opacity(0.66)
                                            )
                                            .padding(.horizontal, MSC.Spacing.sm)
                                            .padding(.vertical, MSC.Spacing.xs)
                                            .background {
                                                consoleChipBackground(isActive: isActive, accentColor: .accentColor)
                                            }
                                    }
                                    .buttonStyle(ConsoleChipPressStyle())
                                }
                            }
                        }
                        .padding(.horizontal, MSC.Spacing.xxs)
                    }
                }
                .padding(.horizontal, MSC.Spacing.lg)
                .padding(.top, MSC.Spacing.sm)
                .padding(.bottom, MSC.Spacing.md)
                .background {
                    ZStack {
                        MSC.Colors.tierTerminal
                        LinearGradient(
                            colors: [Color.white.opacity(0.045), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }

                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 0.5)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(viewModel.filteredConsoleEntries.enumerated()), id: \.element.id) { idx, entry in
                            Text(entry.raw)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundStyle(logColor(for: entry))
                                .textSelection(.enabled)
                                .padding(.horizontal, MSC.Spacing.sm)
                                .padding(.vertical, 1)
                                .background(
                                    idx.isMultiple(of: 2)
                                        ? Color.clear
                                        : Color.white.opacity(0.018)
                                )
                                .id(idx)
                        }
                    }
                    .padding(.vertical, MSC.Spacing.xs)
                }
                .onChange(of: viewModel.filteredConsoleEntries.count) { _ in
                    if let lastIndex = viewModel.filteredConsoleEntries.indices.last {
                        proxy.scrollTo(lastIndex, anchor: .bottom)
                    }
                }
            }

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)

            // MARK: Autocomplete Strip

            if !autoCompleteSuggestions.isEmpty {
                autocompleteStrip
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // MARK: Command Bar

            HStack(spacing: MSC.Spacing.sm) {
                HStack(spacing: MSC.Spacing.xs) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)

                    TextField("Enter command...", text: Binding(
                        get: { viewModel.commandText },
                        set: { viewModel.commandText = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.white)
                }
                .padding(.horizontal, MSC.Spacing.sm)
                .padding(.vertical, MSC.Spacing.xs + 2)
                .frame(maxWidth: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                        .fill(MSC.Colors.tierTerminal)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                        .stroke(Color.white.opacity(0.09), lineWidth: 0.5)
                }

                // Command palette shortcut button in the command bar
                Button {
                    showCommandPalette = true
                } label: {
                    Image(systemName: "list.bullet.rectangle.portrait")
                        .font(.system(size: 13, weight: .regular))
                }
                .buttonStyle(MSCGhostIconButtonStyle(size: 28))
                .help("Command Palette")

                Button {
                    copyVisibleLines()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13, weight: .regular))
                }
                .buttonStyle(MSCGhostIconButtonStyle(size: 28))
                .help("Copy Visible")

                Button {
                    viewModel.clearConsole()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .regular))
                }
                .buttonStyle(MSCGhostIconButtonStyle(size: 28))
                .help("Clear Console")

                Button("Send") {
                    viewModel.sendCommand()
                }
                .buttonStyle(MSCPrimaryButtonStyle())
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.horizontal, MSC.Spacing.lg)
            .padding(.vertical, MSC.Spacing.sm)
            .background {
                ZStack {
                    MSC.Colors.tierChrome
                    LinearGradient(
                        colors: [Color.white.opacity(0.05), Color.clear],
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.75)
                    )
                }
            }
        }
        .background(MSC.Colors.tierTerminal)
        .onboardingAnchor(.consolePanel)
        .sheet(isPresented: $showCommandPalette) {
            CommandPaletteView()
                .environmentObject(viewModel)
        }
        .animation(.easeInOut(duration: 0.15), value: autoCompleteSuggestions.count)
    }

    // MARK: - Autocomplete Strip

    private var autocompleteStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MSC.Spacing.xs) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.accentColor.opacity(0.7))
                    .padding(.leading, MSC.Spacing.lg)

                ForEach(autoCompleteSuggestions, id: \.self) { suggestion in
                    Button {
                        viewModel.commandText = suggestion
                    } label: {
                        Text(suggestion)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .padding(.horizontal, MSC.Spacing.sm)
                            .padding(.vertical, MSC.Spacing.xs)
                            .background {
                                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                                    .stroke(Color.accentColor.opacity(0.18), lineWidth: 0.5)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.trailing, MSC.Spacing.lg)
            .padding(.vertical, MSC.Spacing.xs + 1)
        }
        .background {
            ZStack {
                MSC.Colors.tierTerminal
                Color.accentColor.opacity(0.03)
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.accentColor.opacity(0.12))
                .frame(height: 0.5)
        }
    }

    // MARK: - Filters Popover

    private var filtersPopover: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {
            HStack {
                Text("Filters")
                    .font(MSC.Typography.sectionHeader)
                Spacer()
                Button("Reset") {
                    viewModel.resetConsoleFilters()
                }
                .buttonStyle(MSCSecondaryButtonStyle())
            }

            GroupBox("Sources") {
                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                    filterToggle("Server", isOn: Binding(
                        get: { viewModel.consoleSelectedSources.contains(.server) },
                        set: { viewModel.setSource(.server, enabled: $0) }
                    ))
                    filterToggle("Controller", isOn: Binding(
                        get: { viewModel.consoleSelectedSources.contains(.controller) },
                        set: { viewModel.setSource(.controller, enabled: $0) }
                    ))
                }
                .padding(.top, 4)
            }

            GroupBox("Levels") {
                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                    filterToggle("Info", isOn: Binding(
                        get: { viewModel.consoleSelectedLevels.contains(.info) },
                        set: { viewModel.setLevel(.info, enabled: $0) }
                    ))
                    filterToggle("Warn", isOn: Binding(
                        get: { viewModel.consoleSelectedLevels.contains(.warn) },
                        set: { viewModel.setLevel(.warn, enabled: $0) }
                    ))
                    filterToggle("Error", isOn: Binding(
                        get: { viewModel.consoleSelectedLevels.contains(.error) },
                        set: { viewModel.setLevel(.error, enabled: $0) }
                    ))
                }
                .padding(.top, 4)
            }

            GroupBox("Tags") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                        ForEach(viewModel.consoleKnownTags, id: \.self) { tag in
                            filterToggle(tag, isOn: Binding(
                                get: { viewModel.consoleSelectedTags.contains(tag) },
                                set: { viewModel.setTag(tag, enabled: $0) }
                            ))
                        }
                    }
                    .padding(.top, 4)
                }
                .frame(height: 160)
            }

            Divider()

            filterToggle("Hide Auto", isOn: Binding(
                get: { viewModel.consoleHideAuto },
                set: { viewModel.consoleHideAuto = $0; viewModel.autoSelectConsoleTabForCurrentFilters() }
            ))

            filterToggle("Error Popups", isOn: Binding(
                get: { viewModel.errorPopupsEnabled },
                set: { viewModel.setErrorPopupsEnabled($0) }
            ))

            Text("Controls whether controller errors appear as popup alerts. Default is off.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func filterToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) { Text(title) }
            .toggleStyle(.checkbox)
    }

    // MARK: - Log text color

    private func logColor(for entry: ConsoleEntry) -> Color {
        if entry.source == .controller { return .secondary }
        switch entry.level {
        case .error:  return .red
        case .warn:   return .orange
        default:      return .primary
        }
    }

    // MARK: - Console chip background

    @ViewBuilder
    private func consoleChipBackground(isActive: Bool, accentColor: Color) -> some View {
        ZStack {
            if isActive {
                Capsule()
                    .fill(.regularMaterial)
            } else {
                Capsule()
                    .fill(Color.white.opacity(0.05))
            }

            Capsule()
                .fill(isActive ? accentColor.opacity(0.18) : Color.clear)

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isActive ? 0.14 : 0.08),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.72)
                    )
                )
        }
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(isActive ? 0.12 : 0.08), lineWidth: 0.5)
        }
        .shadow(color: isActive ? accentColor.opacity(0.14) : .clear, radius: 8, x: 0, y: 4)
    }

    // MARK: - Clipboard

    private func copyVisibleLines() {
        let text = viewModel.filteredConsoleEntries.map { $0.raw }.joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}

private struct ConsoleChipPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(MSC.Animation.buttonPress, value: configuration.isPressed)
    }
}

#Preview {
    ConsoleView()
        .frame(height: 220)
        .environmentObject(AppViewModel())
}

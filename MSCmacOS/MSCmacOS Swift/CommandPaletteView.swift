//
//  CommandPaletteView.swift
//  MinecraftServerController
//
//  Full-screen command palette. Three modes depending on user type:
//    - Browse by category + search (discovery)
//    - Favorites for repeat-use commands
//    - Guided builder for commands that require arguments
//
//  When the user selects a command, it populates viewModel.commandText
//  and dismisses the sheet so the user can review before sending.
//

import SwiftUI

// MARK: - Palette State

private enum PaletteMode {
    case browsing
    case building(MinecraftCommandDef)
}

// MARK: - CommandPaletteView

struct CommandPaletteView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    /// Comma-separated command names the user has favorited.
    @AppStorage("msc_command_favorites") private var favoritesData: String = ""

    @State private var searchText: String = ""
    @State private var mode: PaletteMode = .browsing
    @State private var selectedCategory: CommandCategory? = nil

    private var serverType: ServerType {
            viewModel.selectedServer
                .flatMap { viewModel.configServer(for: $0) }?.serverType ?? .java
        }

    private var favoriteNames: Set<String> {
        Set(favoritesData.split(separator: ",").map { String($0) })
    }

    private var allCommands: [MinecraftCommandDef] {
        MinecraftCommandRegistry.commands(for: serverType)
    }

    private var filteredCommands: [MinecraftCommandDef] {
        let base: [MinecraftCommandDef]
        if let cat = selectedCategory {
            base = allCommands.filter { $0.category == cat }
        } else {
            base = allCommands
        }
        if searchText.isEmpty { return base }
        let lower = searchText.lowercased()
        return base.filter {
            $0.name.lowercased().contains(lower) ||
            $0.description.lowercased().contains(lower)
        }
    }

    private var favoriteCommands: [MinecraftCommandDef] {
        allCommands.filter { favoriteNames.contains($0.name) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if case .building(let def) = mode {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { mode = .browsing }
                    } label: {
                        HStack(spacing: MSC.Spacing.xs) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .medium))
                            Text("Back")
                                .font(.system(size: 13))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text(def.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)

                } else {
                    Text("Command Palette")
                        .font(.system(size: 15, weight: .semibold))
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, MSC.Spacing.lg)
            .padding(.vertical, MSC.Spacing.md)
            .background(MSC.Colors.tierChrome)

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 0.5)

            if case .building(let def) = mode {
                // Guided Builder
                GuidedCommandBuilderView(
                    definition: def,
                    onlinePlayers: viewModel.onlinePlayers,
                    isFavorite: favoriteNames.contains(def.name),
                    onToggleFavorite: { toggleFavorite(def.name) },
                    onConfirm: { command in
                        viewModel.commandText = command
                        dismiss()
                    }
                )
            } else {
                // Browse + Search
                VStack(spacing: 0) {
                    // Search bar
                    HStack(spacing: MSC.Spacing.sm) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        TextField("Search commands...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, MSC.Spacing.md)
                    .padding(.vertical, MSC.Spacing.sm)
                    .background(MSC.Colors.tierContent.opacity(0.6))
                    .padding(.horizontal, MSC.Spacing.lg)
                    .padding(.vertical, MSC.Spacing.sm)
                    .background(MSC.Colors.tierChrome)

                    // Category filter strip
                    if searchText.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: MSC.Spacing.xs) {
                                CategoryChip(
                                    label: "All",
                                    icon: "square.grid.2x2",
                                    color: .secondary,
                                    isSelected: selectedCategory == nil
                                ) {
                                    selectedCategory = nil
                                }
                                ForEach(CommandCategory.allCases) { cat in
                                    CategoryChip(
                                        label: cat.rawValue,
                                        icon: cat.icon,
                                        color: cat.color,
                                        isSelected: selectedCategory == cat
                                    ) {
                                        selectedCategory = cat
                                    }
                                }
                            }
                            .padding(.horizontal, MSC.Spacing.lg)
                            .padding(.vertical, MSC.Spacing.xs)
                        }
                        .background(MSC.Colors.tierChrome)

                        Rectangle()
                            .fill(Color.white.opacity(0.07))
                            .frame(height: 0.5)
                    }

                    // Command list
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {

                            // Favorites section
                            if searchText.isEmpty && !favoriteCommands.isEmpty && selectedCategory == nil {
                                PaletteSectionHeader(label: "Favorites")
                                ForEach(favoriteCommands) { def in
                                    CommandRow(
                                        definition: def,
                                        isFavorite: true,
                                        onToggleFavorite: { toggleFavorite(def.name) },
                                        onTap: { handleCommandTap(def) }
                                    )
                                }
                                Rectangle()
                                    .fill(Color.white.opacity(0.05))
                                    .frame(height: 1)
                                    .padding(.vertical, MSC.Spacing.xs)
                            }

                            // Commands by category (or filtered flat list)
                            if searchText.isEmpty && selectedCategory == nil {
                                ForEach(CommandCategory.allCases) { category in
                                    let cmds = filteredCommands.filter { $0.category == category }
                                    if !cmds.isEmpty {
                                        PaletteSectionHeader(label: category.rawValue, icon: category.icon, color: category.color)
                                        ForEach(cmds) { def in
                                            CommandRow(
                                                definition: def,
                                                isFavorite: favoriteNames.contains(def.name),
                                                onToggleFavorite: { toggleFavorite(def.name) },
                                                onTap: { handleCommandTap(def) }
                                            )
                                        }
                                    }
                                }
                            } else {
                                if filteredCommands.isEmpty {
                                    Text("No commands match \"\(searchText)\"")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.top, 40)
                                } else {
                                    ForEach(filteredCommands) { def in
                                        CommandRow(
                                            definition: def,
                                            isFavorite: favoriteNames.contains(def.name),
                                            onToggleFavorite: { toggleFavorite(def.name) },
                                            onTap: { handleCommandTap(def) }
                                        )
                                    }
                                }
                            }
                        }
                        .padding(.bottom, MSC.Spacing.lg)
                    }
                }
            }
        }
        .background(MSC.Colors.tierAtmosphere)
        .frame(minWidth: 480, minHeight: 560)
    }

    // MARK: - Helpers

    private func handleCommandTap(_ def: MinecraftCommandDef) {
        if def.hasRequiredArgs {
            withAnimation(.easeInOut(duration: 0.18)) {
                mode = .building(def)
            }
        } else {
            viewModel.commandText = "/\(def.name)"
            dismiss()
        }
    }

    private func toggleFavorite(_ name: String) {
        var names = Set(favoritesData.split(separator: ",").map { String($0) })
        if names.contains(name) {
            names.remove(name)
        } else {
            names.insert(name)
        }
        favoritesData = names.joined(separator: ",")
    }
}

// MARK: - Guided Builder

private struct GuidedCommandBuilderView: View {
    let definition: MinecraftCommandDef
    let onlinePlayers: [OnlinePlayer]
    let isFavorite: Bool
    let onToggleFavorite: () -> Void
    let onConfirm: (String) -> Void

    @State private var argValues: [String]

    init(
        definition: MinecraftCommandDef,
        onlinePlayers: [OnlinePlayer],
        isFavorite: Bool,
        onToggleFavorite: @escaping () -> Void,
        onConfirm: @escaping (String) -> Void
    ) {
        self.definition = definition
        self.onlinePlayers = onlinePlayers
        self.isFavorite = isFavorite
        self.onToggleFavorite = onToggleFavorite
        self.onConfirm = onConfirm
        _argValues = State(initialValue: Array(repeating: "", count: definition.argumentSlots.count))
    }

    private var builtCommand: String {
        let filledArgs = argValues
            .enumerated()
            .compactMap { (i, v) -> String? in
                let trimmed = v.trimmingCharacters(in: .whitespaces)
                return trimmed.isEmpty ? nil : trimmed
            }
        let argString = filledArgs.joined(separator: " ")
        return argString.isEmpty ? "/\(definition.name)" : "/\(definition.name) \(argString)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MSC.Spacing.lg) {

                // Description + favorite
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: MSC.Spacing.xxs) {
                        Text(definition.description)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Text(definition.syntaxHint)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button(action: onToggleFavorite) {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .font(.system(size: 14))
                            .foregroundStyle(isFavorite ? Color.yellow : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(isFavorite ? "Remove from favorites" : "Add to favorites")
                }
                .padding(MSC.Spacing.md)
                .background(MSC.Colors.tierContent.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous))

                // Argument fields
                VStack(alignment: .leading, spacing: MSC.Spacing.md) {
                    ForEach(Array(definition.argumentSlots.enumerated()), id: \.offset) { idx, slot in
                        ArgFieldView(
                            slot: slot,
                            slotIndex: idx,
                            value: $argValues[idx],
                            onlinePlayers: onlinePlayers,
                            totalSlots: definition.argumentSlots.count
                        )
                    }
                }

                // Command preview
                VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                    Text("Preview")
                        .font(MSC.Typography.overline)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text(builtCommand)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString(builtCommand, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Copy command")
                    }
                    .padding(MSC.Spacing.sm)
                    .background(MSC.Colors.tierTerminal)
                    .clipShape(RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    }
                }

                // Confirm
                Button {
                    onConfirm(builtCommand)
                } label: {
                    HStack {
                        Spacer()
                        Text("Use Command")
                        Image(systemName: "arrow.right")
                        Spacer()
                    }
                }
                .buttonStyle(MSCPrimaryButtonStyle())
                .padding(.top, MSC.Spacing.xs)
            }
            .padding(MSC.Spacing.lg)
        }
    }
}

// MARK: - Argument Field

private struct ArgFieldView: View {
    let slot: CommandArgSlot
    let slotIndex: Int
    @Binding var value: String
    let onlinePlayers: [OnlinePlayer]
    let totalSlots: Int

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
            HStack(spacing: MSC.Spacing.xs) {
                Text("Argument \(slotIndex + 1) of \(totalSlots)")
                    .font(.system(size: 9, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(.tertiary)
                Text(slot.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            argInput
        }
    }

    @ViewBuilder
    private var argInput: some View {
        if slot.isPlayerName && !onlinePlayers.isEmpty {
            playerPicker
        } else if let options = slot.keywordOptions {
            keywordPicker(options: options)
        } else {
            textInput
        }
    }

    private var playerPicker: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
            // Quick pick from online players
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MSC.Spacing.xs) {
                    ForEach(onlinePlayers) { player in
                        let selected = value == player.name
                        Button {
                            value = player.name
                        } label: {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(selected ? Color.green : Color.secondary.opacity(0.3))
                                    .frame(width: 6, height: 6)
                                Text(player.name)
                                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                            }
                            .padding(.horizontal, MSC.Spacing.sm)
                            .padding(.vertical, MSC.Spacing.xs)
                            .background(
                                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                                    .fill(selected
                                          ? Color.green.opacity(0.15)
                                          : MSC.Colors.tierContent.opacity(0.6))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                                    .stroke(selected ? Color.green.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Also allow typing
            plainTextField(placeholder: slot.label)
        }
    }

    private func keywordPicker(options: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MSC.Spacing.xs) {
                ForEach(options, id: \.self) { option in
                    let selected = value == option
                    Button {
                        value = option
                    } label: {
                        Text(option)
                            .font(.system(size: 12, weight: selected ? .semibold : .regular))
                            .padding(.horizontal, MSC.Spacing.sm)
                            .padding(.vertical, MSC.Spacing.xs + 1)
                            .background(
                                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                                    .fill(selected
                                          ? Color.accentColor.opacity(0.18)
                                          : MSC.Colors.tierContent.opacity(0.6))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                                    .stroke(selected ? Color.accentColor.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 0.5)
                            )
                            .foregroundStyle(selected ? Color.primary : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var textInput: some View {
        plainTextField(placeholder: slot.label)
    }

    private func plainTextField(placeholder: String) -> some View {
        TextField(placeholder, text: $value)
            .textFieldStyle(.plain)
            .font(.system(size: 13, design: slot.isCoordinates ? .monospaced : .default))
            .padding(.horizontal, MSC.Spacing.sm)
            .padding(.vertical, MSC.Spacing.xs + 2)
            .background(MSC.Colors.tierContent.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            }
    }
}

// MARK: - Command Row

private struct CommandRow: View {
    let definition: MinecraftCommandDef
    let isFavorite: Bool
    let onToggleFavorite: () -> Void
    let onTap: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: MSC.Spacing.sm) {
            // Category color dot
            Circle()
                .fill(definition.category.color)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: MSC.Spacing.xs) {
                    Text("/\(definition.name)")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary)

                    if definition.hasRequiredArgs {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(definition.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Favorite button (shown on hover or if already favorited)
            if isFavorite || isHovered {
                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 12))
                        .foregroundStyle(isFavorite ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(isFavorite ? "Remove from favorites" : "Add to favorites")
            }

            if !definition.hasRequiredArgs {
                Image(systemName: "return")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .opacity(isHovered ? 1 : 0)
            }
        }
        .padding(.horizontal, MSC.Spacing.lg)
        .padding(.vertical, MSC.Spacing.sm)
        .background(isHovered ? Color.white.opacity(0.045) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { onTap() }
    }
}

// MARK: - Palette Section Header

private struct PaletteSectionHeader: View {
    let label: String
    var icon: String? = nil
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: MSC.Spacing.xs) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(icon != nil ? color : Color.secondary)
        }
        .padding(.horizontal, MSC.Spacing.lg)
        .padding(.top, MSC.Spacing.md)
        .padding(.bottom, MSC.Spacing.xs)
    }
}

// MARK: - Category Chip

private struct CategoryChip: View {
    let label: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(label)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? color : Color.secondary)
            .padding(.horizontal, MSC.Spacing.sm)
            .padding(.vertical, MSC.Spacing.xs)
            .background(
                Capsule()
                    .fill(isSelected ? color.opacity(0.12) : Color.white.opacity(0.05))
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? color.opacity(0.3) : Color.white.opacity(0.07), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

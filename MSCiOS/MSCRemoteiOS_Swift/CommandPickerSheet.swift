import SwiftUI

struct CommandPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsStore

    @Binding var commandText: String

    @State private var searchText: String = ""

    private let groups: [CommandGroup] = CommandCatalog.defaultGroups

    private var orderedAllCommands: [CommandTemplate] {
        groups.flatMap { $0.commands }
    }

    private var commandByString: [String: CommandTemplate] {
        Dictionary(uniqueKeysWithValues: orderedAllCommands.map { ($0.command, $0) })
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var searchResults: [CommandTemplate] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }

        return orderedAllCommands.filter { item in
            item.title.lowercased().contains(q) ||
            item.command.lowercased().contains(q) ||
            item.description.lowercased().contains(q)
        }
    }

    private var recentTemplates: [CommandTemplate] {
        settings.recentCommands.compactMap { commandByString[$0] }
    }

    private var favoriteTemplates: [CommandTemplate] {
        // Preserve catalog order
        orderedAllCommands.filter { settings.isFavorite(command: $0.command) }
    }

    var body: some View {
        NavigationStack {
            List {
                if isSearching {
                    Section("Results") {
                        if searchResults.isEmpty {
                            Text("No matches.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(searchResults) { item in
                                commandRow(item)
                            }
                        }
                    }
                } else {
                    if !recentTemplates.isEmpty {
                        Section("Recents") {
                            ForEach(recentTemplates) { item in
                                commandRow(item)
                            }
                        }
                    }

                    if !favoriteTemplates.isEmpty {
                        Section("Favorites") {
                            ForEach(favoriteTemplates) { item in
                                commandRow(item)
                            }
                        }
                    }

                    ForEach(groups) { group in
                        Section(group.title) {
                            ForEach(group.commands) { item in
                                commandRow(item)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Commands")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func commandRow(_ item: CommandTemplate) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                select(item)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)

                    Text(item.command)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)

                    if !item.description.isEmpty {
                        Text(item.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                settings.toggleFavorite(command: item.command)
            } label: {
                Image(systemName: settings.isFavorite(command: item.command) ? "star.fill" : "star")
                    .imageScale(.medium)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(settings.isFavorite(command: item.command) ? "Unfavorite command" : "Favorite command")
        }
    }

    private func select(_ item: CommandTemplate) {
        commandText = item.command
        settings.recordRecent(command: item.command)
        dismiss()
    }
}

struct CommandGroup: Identifiable {
    let title: String
    let commands: [CommandTemplate]

    var id: String { title }
}

struct CommandTemplate: Identifiable {
    let title: String
    let command: String
    let description: String

    var id: String { command }
}

enum CommandCatalog {
    static let defaultGroups: [CommandGroup] = [
        CommandGroup(
            title: "Essentials",
            commands: [
                CommandTemplate(
                    title: "List players",
                    command: "/list",
                    description: "Shows online players."
                ),
                CommandTemplate(
                    title: "Server TPS (Paper)",
                    command: "/tps",
                    description: "Shows server tick performance."
                ),
                CommandTemplate(
                    title: "Say (broadcast message)",
                    command: "/say Hello everyone!",
                    description: "Broadcast a message to all players."
                ),
                CommandTemplate(
                    title: "Save all",
                    command: "/save-all",
                    description: "Forces a world save."
                )
            ]
        ),

        CommandGroup(
            title: "Time & Weather",
            commands: [
                CommandTemplate(
                    title: "Set day",
                    command: "/time set day",
                    description: "Sets the time to daytime."
                ),
                CommandTemplate(
                    title: "Set night",
                    command: "/time set night",
                    description: "Sets the time to nighttime."
                ),
                CommandTemplate(
                    title: "Clear weather",
                    command: "/weather clear",
                    description: "Stops rain/thunder."
                ),
                CommandTemplate(
                    title: "Start rain",
                    command: "/weather rain",
                    description: "Makes it rain."
                ),
                CommandTemplate(
                    title: "Start thunder",
                    command: "/weather thunder",
                    description: "Starts a thunderstorm."
                )
            ]
        ),

        CommandGroup(
            title: "Gamemode & Difficulty",
            commands: [
                CommandTemplate(
                    title: "Gamemode survival",
                    command: "/gamemode survival <player>",
                    description: "Set a player's gamemode."
                ),
                CommandTemplate(
                    title: "Gamemode creative",
                    command: "/gamemode creative <player>",
                    description: "Set a player's gamemode."
                ),
                CommandTemplate(
                    title: "Gamemode spectator",
                    command: "/gamemode spectator <player>",
                    description: "Set a player's gamemode."
                ),
                CommandTemplate(
                    title: "Difficulty peaceful",
                    command: "/difficulty peaceful",
                    description: "Change world difficulty."
                ),
                CommandTemplate(
                    title: "Difficulty easy",
                    command: "/difficulty easy",
                    description: "Change world difficulty."
                ),
                CommandTemplate(
                    title: "Difficulty normal",
                    command: "/difficulty normal",
                    description: "Change world difficulty."
                ),
                CommandTemplate(
                    title: "Difficulty hard",
                    command: "/difficulty hard",
                    description: "Change world difficulty."
                )
            ]
        ),

        CommandGroup(
            title: "Sleep / Rules",
            commands: [
                CommandTemplate(
                    title: "Keep inventory ON",
                    command: "/gamerule keepInventory true",
                    description: "Players keep items on death."
                ),
                CommandTemplate(
                    title: "Keep inventory OFF",
                    command: "/gamerule keepInventory false",
                    description: "Default behavior."
                ),
                CommandTemplate(
                    title: "Daylight cycle OFF",
                    command: "/gamerule doDaylightCycle false",
                    description: "Freezes time."
                ),
                CommandTemplate(
                    title: "Daylight cycle ON",
                    command: "/gamerule doDaylightCycle true",
                    description: "Normal time progression."
                ),
                CommandTemplate(
                    title: "Weather cycle OFF",
                    command: "/gamerule doWeatherCycle false",
                    description: "Locks current weather."
                ),
                CommandTemplate(
                    title: "Weather cycle ON",
                    command: "/gamerule doWeatherCycle true",
                    description: "Normal weather changes."
                ),
                CommandTemplate(
                    title: "One-player sleep (0%)",
                    command: "/gamerule playersSleepingPercentage 0",
                    description: "Make skipping night easier."
                ),
                CommandTemplate(
                    title: "Default sleep (100%)",
                    command: "/gamerule playersSleepingPercentage 100",
                    description: "Require all players to sleep."
                )
            ]
        ),

        CommandGroup(
            title: "Teleport & Utility",
            commands: [
                CommandTemplate(
                    title: "Teleport player to player",
                    command: "/tp <player> <targetPlayer>",
                    description: "Move one player to another."
                ),
                CommandTemplate(
                    title: "Teleport player to coords",
                    command: "/tp <player> <x> <y> <z>",
                    description: "Move a player to coordinates."
                ),
                CommandTemplate(
                    title: "Give item",
                    command: "/give <player> minecraft:diamond 64",
                    description: "Gives an item stack."
                ),
                CommandTemplate(
                    title: "Clear inventory",
                    command: "/clear <player>",
                    description: "Clears a player's inventory."
                )
            ]
        ),

        CommandGroup(
            title: "Admin",
            commands: [
                CommandTemplate(
                    title: "Whitelist ON",
                    command: "/whitelist on",
                    description: "Enable whitelist."
                ),
                CommandTemplate(
                    title: "Whitelist OFF",
                    command: "/whitelist off",
                    description: "Disable whitelist."
                ),
                CommandTemplate(
                    title: "Whitelist add",
                    command: "/whitelist add <player>",
                    description: "Allow a player to join."
                ),
                CommandTemplate(
                    title: "Whitelist remove",
                    command: "/whitelist remove <player>",
                    description: "Remove a player from whitelist."
                ),
                CommandTemplate(
                    title: "OP player",
                    command: "/op <player>",
                    description: "Grant operator permissions."
                ),
                CommandTemplate(
                    title: "DEOP player",
                    command: "/deop <player>",
                    description: "Remove operator permissions."
                ),
                CommandTemplate(
                    title: "Kick player",
                    command: "/kick <player> <reason>",
                    description: "Kick a player with a reason."
                ),
                CommandTemplate(
                    title: "Ban player",
                    command: "/ban <player> <reason>",
                    description: "Ban a player with a reason."
                ),
                CommandTemplate(
                    title: "Pardon player",
                    command: "/pardon <player>",
                    description: "Unban a player."
                ),
                CommandTemplate(
                    title: "Stop server (danger)",
                    command: "/stop",
                    description: "Stops the Minecraft server process."
                ),
                CommandTemplate(
                    title: "Reload (danger)",
                    command: "/reload",
                    description: "Not recommended on Paper unless you know why."
                )
            ]
        )
    ]
}


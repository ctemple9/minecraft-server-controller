//
//  PlayerProfilesCard.swift
//  MinecraftServerController
//
//  The "Player Data" card shown at the bottom of the Java Edition Players tab.
//  Displays a grid of player profile cards with search, sort, and detail sheet access.
//

import SwiftUI

struct PlayerProfilesCard: View {
    @EnvironmentObject var viewModel: AppViewModel

    @State private var searchText: String = ""
    @State private var sortOrder: ProfileSortOrder = .lastSeen
    @State private var selectedProfile: PlayerProfile? = nil

    enum ProfileSortOrder: String, CaseIterable, Identifiable {
        case lastSeen = "Last Seen"
        case nameAZ   = "Name A–Z"
        var id: String { rawValue }
    }

    private var filteredProfiles: [PlayerProfile] {
        let trim = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var result = viewModel.playerProfiles

        // Filter
        if !trim.isEmpty {
            result = result.filter {
                ($0.username?.lowercased().contains(trim) ?? false)
                || $0.uuid.uuidString.lowercased().contains(trim)
            }
        }

        // Sort
        switch sortOrder {
        case .lastSeen:
            result.sort { $0.lastModified > $1.lastModified }
        case .nameAZ:
            result.sort { $0.displayName.lowercased() < $1.displayName.lowercased() }
        }

        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {

            // ── Card header ────────────────────────────────────────────────
            HStack {
                Label("Player Data", systemImage: "person.crop.rectangle.stack")
                    .font(MSC.Typography.cardTitle)
                    .foregroundStyle(.secondary)

                Spacer()

                if viewModel.isLoadingProfiles {
                    ProgressView()
                        .scaleEffect(0.6)
                        .padding(.trailing, MSC.Spacing.xs)
                } else {
                    Text("\(viewModel.playerProfiles.count) profiles")
                        .font(MSC.Typography.caption)
                        .foregroundStyle(MSC.Colors.caption)
                }

                // Sort picker
                Picker("Sort", selection: $sortOrder) {
                    ForEach(ProfileSortOrder.allCases) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)

                // Refresh
                Button {
                    viewModel.loadPlayerProfilesForSelectedServer()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .font(MSC.Typography.caption)
                .help("Reload player profiles from disk")
            }

            Divider()

            // ── Search field ───────────────────────────────────────────────
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(MSC.Colors.tertiary)
                TextField("Filter by name or UUID", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(MSC.Typography.caption)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(MSC.Colors.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, MSC.Spacing.sm)
            .padding(.vertical, MSC.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.sm)
                    .fill(MSC.Colors.subtleBackground)
            )

            // ── Grid or empty states ───────────────────────────────────────
            if viewModel.isLoadingProfiles && viewModel.playerProfiles.isEmpty {
                loadingView
            } else if viewModel.playerProfiles.isEmpty {
                emptyState
            } else if filteredProfiles.isEmpty {
                Text("No profiles match \"\(searchText)\".")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.caption)
                    .padding(MSC.Spacing.md)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 90, maximum: 110), spacing: MSC.Spacing.sm)],
                    spacing: MSC.Spacing.sm
                ) {
                    ForEach(filteredProfiles) { profile in
                        PlayerProfileCardView(
                            profile: profile,
                            selectedProfile: $selectedProfile
                        )
                    }
                }
            }

            // ── Hint text ──────────────────────────────────────────────────
            if !viewModel.playerProfiles.isEmpty {
                Text("Tap a card to view stats, inventory, and data management options.")
                    .font(.system(size: 10))
                    .foregroundStyle(MSC.Colors.tertiary)
            }
        }
        .padding(MSC.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .fill(MSC.Colors.tierContent)
        )
        .sheet(item: $selectedProfile) { profile in
            PlayerProfileDetailSheet(profile: profile)
                .environmentObject(viewModel)
        }
    }

    // MARK: - Sub-views

    private var loadingView: some View {
        HStack(spacing: MSC.Spacing.sm) {
            ProgressView().scaleEffect(0.7)
            Text("Scanning player data…")
                .font(MSC.Typography.caption)
                .foregroundStyle(MSC.Colors.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(MSC.Spacing.lg)
    }

    private var emptyState: some View {
        VStack(spacing: MSC.Spacing.sm) {
            Image(systemName: "person.crop.rectangle.stack.fill")
                .font(.system(size: 28))
                .foregroundStyle(MSC.Colors.tertiary)
            Text("No player data found")
                .font(MSC.Typography.captionBold)
                .foregroundStyle(MSC.Colors.caption)
            Text("Player profiles appear here after someone has joined the server at least once.")
                .font(MSC.Typography.caption)
                .foregroundStyle(MSC.Colors.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(MSC.Spacing.xl)
    }
}

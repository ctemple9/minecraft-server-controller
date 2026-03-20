//
//  PlayerSessionTimelineView.swift
//  MinecraftServerController
//
//
//  Sheet presented from the header button "Session Log".
//  Shows join/leave events grouped by day, with duration where available,
//  filter-by-player-name, and a clear-log action.

import SwiftUI

struct PlayerSessionTimelineView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Binding var isPresented: Bool

    @State private var filterText: String = ""
    @State private var showClearConfirm: Bool = false

    // MARK: - Filtered data

    private var filteredDays: [(day: Date, events: [SessionEvent])] {
        let trim = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trim.isEmpty else { return viewModel.sessionEventsByDay }

        return viewModel.sessionEventsByDay.compactMap { section in
            let filtered = section.events.filter {
                $0.playerName.lowercased().contains(trim)
            }
            return filtered.isEmpty ? nil : (day: section.day, events: filtered)
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ──────────────────────────────────────────────────
            HStack {
                Text("Session Log")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("Clear Log") {
                    showClearConfirm = true
                }
                .foregroundStyle(MSC.Colors.error)
                .font(MSC.Typography.caption)
                .disabled(viewModel.sessionEvents.isEmpty)
                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, MSC.Spacing.lg)
            .padding(.vertical, MSC.Spacing.md)

            Divider()

            // ── Filter bar ──────────────────────────────────────────────
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(MSC.Colors.tertiary)
                TextField("Filter by player name", text: $filterText)
                    .textFieldStyle(.plain)
                if !filterText.isEmpty {
                    Button {
                        filterText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(MSC.Colors.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, MSC.Spacing.lg)
            .padding(.vertical, MSC.Spacing.sm)
            .background(MSC.Colors.cardBackground)

            Divider()

            // ── Content ─────────────────────────────────────────────────
            if viewModel.sessionEvents.isEmpty {
                emptyState
            } else if filteredDays.isEmpty {
                noMatchState
            } else {
                timelineList
            }
        }
        .frame(minWidth: 460, minHeight: 460)
        .confirmationDialog(
            "Clear session log for this server?",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear Log", role: .destructive) {
                viewModel.clearSessionLog()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all recorded join and leave events. This cannot be undone.")
        }
    }

    // MARK: - Sub-views

    private var emptyState: some View {
        VStack(spacing: MSC.Spacing.sm) {
            Image(systemName: "clock.badge.xmark")
                .font(.system(size: 36))
                .foregroundStyle(MSC.Colors.tertiary)
            Text("No session events recorded yet.")
                .font(MSC.Typography.caption)
                .foregroundStyle(MSC.Colors.caption)
            Text("Player join and leave events will appear here once the server has run.")
                .font(MSC.Typography.caption)
                .foregroundStyle(MSC.Colors.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var noMatchState: some View {
        VStack(spacing: MSC.Spacing.sm) {
            Image(systemName: "person.fill.questionmark")
                .font(.system(size: 32))
                .foregroundStyle(MSC.Colors.tertiary)
            Text("No events match \"\(filterText)\".")
                .font(MSC.Typography.caption)
                .foregroundStyle(MSC.Colors.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var timelineList: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: MSC.Spacing.md, pinnedViews: [.sectionHeaders]) {
                ForEach(filteredDays, id: \.day) { section in
                    Section {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(section.events) { event in
                                SessionEventRow(
                                    event: event,
                                    duration: viewModel.sessionDuration(after: event)
                                )
                            }
                        }
                        .padding(.horizontal, MSC.Spacing.lg)
                    } header: {
                        DayHeaderView(day: section.day)
                    }
                }
            }
            .padding(.bottom, MSC.Spacing.lg)
        }
    }
}

// MARK: - Day header

private struct DayHeaderView: View {
    let day: Date

    var body: some View {
        HStack {
            Text(day, style: .date)
                .font(MSC.Typography.captionBold)
                .foregroundStyle(MSC.Colors.tertiary)
            Spacer()
        }
        .padding(.horizontal, MSC.Spacing.lg)
        .padding(.vertical, MSC.Spacing.xs)
        .background(.regularMaterial)
    }
}

// MARK: - Event row

private struct SessionEventRow: View {
    let event: SessionEvent
    let duration: String?    // non-nil for join events where leave was found

    private var isJoin: Bool { event.eventType == .joined }

    var body: some View {
        HStack(spacing: MSC.Spacing.sm) {

            // Icon
            Image(systemName: isJoin ? "arrow.right.circle.fill" : "arrow.left.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(isJoin ? MSC.Colors.success : MSC.Colors.caption)
                .frame(width: 20)

            // Player name
            Text(event.playerName)
                .font(MSC.Typography.caption)
                .foregroundStyle(MSC.Colors.body)
                .lineLimit(1)

            // Event label
            Text(isJoin ? "joined" : "left")
                .font(MSC.Typography.caption)
                .foregroundStyle(isJoin ? MSC.Colors.success : MSC.Colors.caption)

            Spacer()

            // Duration badge (join events only, when leave was found)
            if let duration, isJoin {
                Text(duration)
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(MSC.Colors.cardBorder.opacity(0.4))
                    )
            }

            // Timestamp
            Text(event.timestamp, style: .time)
                .font(MSC.Typography.caption)
                .foregroundStyle(MSC.Colors.tertiary)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }
}

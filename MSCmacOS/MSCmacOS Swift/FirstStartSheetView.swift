//
//  FirstStartSheetView.swift
//  MinecraftServerController
//
//  Post-start guidance sheet that explains what just happened and points
//  the user to the next safe setup or server-management steps.
//

import SwiftUI
import AppKit

struct FirstStartSheetView: View {
    @EnvironmentObject var viewModel: AppViewModel

    @Binding var isShowingManageServers: Bool

    var body: some View {
        let parsed = parseFirstStartMessage(viewModel.firstStartAlertMessage)

        VStack(spacing: 0) {

            // ── Coloured hero header ──────────────────────────────────────
            firstStartHeader

            Divider()

            // ── Scrollable body ───────────────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: MSC.Spacing.lg) {

                    // "What happened" card
                    FSCard(
                        icon: "sparkles",
                        color: .green,
                        title: "What happened"
                    ) {
                        Text(parsed.body)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }

                    // "Next steps" card — only when there are steps
                    if !parsed.nextSteps.isEmpty {
                        FSCard(
                            icon: "list.number",
                            color: .blue,
                            title: "Next steps"
                        ) {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(Array(parsed.nextSteps.enumerated()), id: \.offset) { idx, step in
                                    FSStep(number: idx + 1, text: step)
                                }
                            }
                            .textSelection(.enabled)
                        }
                    }

                    // Footer callout (Xbox Broadcast note, etc.)
                    if let footer = parsed.footer, !footer.isEmpty,
                       footer != parsed.body {
                        FSCallout(
                            icon: "info.circle.fill",
                            color: .secondary,
                            text: footer
                        )
                    }

                }
                .padding(MSC.Spacing.xl)
            }

            // ── Action footer ─────────────────────────────────────────────
            Divider()
            HStack(spacing: MSC.Spacing.sm) {
                Button("Open Server Settings\u{2026}") {
                    viewModel.manageServersShouldAutoEditSelectedOnSettingsTab = true
                    isShowingManageServers = true
                    viewModel.showFirstStartAlert = false
                }
                .buttonStyle(MSCSecondaryButtonStyle())

                Spacer()

                Button("OK") {
                    viewModel.showFirstStartAlert = false
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(MSCPrimaryButtonStyle())
            }
            .padding(.horizontal, MSC.Spacing.xl)
            .padding(.vertical, MSC.Spacing.md)
        }
        .frame(minWidth: 560, idealWidth: 580, minHeight: 380)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Hero Header

    private var firstStartHeader: some View {
        HStack(spacing: MSC.Spacing.md) {
            // App icon
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.firstStartAlertTitle.isEmpty
                     ? "Server Initialised"
                     : viewModel.firstStartAlertTitle)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.primary)

                if let headline = parseFirstStartMessage(viewModel.firstStartAlertMessage).headline,
                   !headline.isEmpty {
                    Text(headline)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Success badge
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
                Text("Ready")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.green.opacity(0.1)))
            .overlay(Capsule().stroke(Color.green.opacity(0.25), lineWidth: 1))
        }
        .padding(.horizontal, MSC.Spacing.xl)
        .padding(.vertical, MSC.Spacing.lg)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Parser

    private func parseFirstStartMessage(_ raw: String) -> (headline: String?, body: String, nextSteps: [String], footer: String?) {
        let blocks = raw.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var headline: String? = nil
        var body: String = raw
        var nextSteps: [String] = []
        var footer: String? = nil

        if blocks.count >= 1 { headline = blocks[0] }
        if blocks.count >= 2 { body = blocks[1] } else { body = raw }

        let lines = raw.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        nextSteps = lines.compactMap { line in
            if line.hasPrefix("\u{2022}") {
                return line.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return nil
        }

        if let last = blocks.last, last.contains("Xbox") || last.contains("Broadcast") {
            footer = last
        } else if blocks.count >= 3 {
            footer = blocks.last
        }

        return (headline: headline, body: body, nextSteps: nextSteps, footer: footer)
    }
}

// MARK: - Card Container

/// Section card with icon badge + title header — mirrors QSStep outer shell.
private struct FSCard<Content: View>: View {
    let icon: String
    let color: Color
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
            // Card header
            HStack(spacing: MSC.Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                        .fill(color.opacity(0.13))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(color)
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            Rectangle()
                .fill(Color.secondary.opacity(0.1))
                .frame(height: 1)

            content
        }
        .padding(MSC.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.lg, style: .continuous)
                .fill(MSC.Colors.cardBackground.opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MSC.Radius.lg, style: .continuous)
                .stroke(MSC.Colors.cardBorder, lineWidth: 1)
        )
    }
}

// MARK: - Step Row

/// A numbered step row — mirrors ChecklistStep from WelcomeGuideView.
private struct FSStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 22, height: 22)
                Text("\(number)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.top, 1)

            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Callout

/// Tinted callout — mirrors GuideCallout / QSCallout.
private struct FSCallout: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(color)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(MSC.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
}


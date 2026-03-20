//
//  ServerNotesSectionView.swift
//  MinecraftServerController
//
//  to match the rest of the overview card hierarchy.
//

import SwiftUI

struct ServerNotesSectionView: View {
    @EnvironmentObject var viewModel: AppViewModel

    @Binding var serverNotesText: String

    var body: some View {
        serverNotesSection
    }

    // MARK: - Server Notes Section

    private var serverNotesSection: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {

            // Header row
            HStack(spacing: MSC.Spacing.sm) {
                HStack(spacing: MSC.Spacing.xs) {
                    Image(systemName: "note.text")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(MSC.Colors.tertiary)
                    MSCOverline("Notes")
                }
                Text("· for this server")
                    .font(.caption2)
                    .foregroundStyle(MSC.Colors.tertiary)
                Spacer()
                if !serverNotesText.isEmpty {
                    Button("Save") {
                        viewModel.saveSelectedServerNotes(serverNotesText)
                    }
                    .controlSize(.mini)
                    .buttonStyle(.borderedProminent)
                }
            }

            // Scrollable text editor area
            ScrollView(.vertical, showsIndicators: true) {
                TextEditor(text: $serverNotesText)
                    .font(MSC.Typography.mono)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .frame(minHeight: 80, maxHeight: .infinity)
                    .onChange(of: serverNotesText) { _ in
                        // Auto-save after a short pause so the user doesn't
                        // have to think about it, but we don't hammer disk
                        // on every keystroke.
                        NSObject.cancelPreviousPerformRequests(
                            withTarget: NotesAutoSaveProxy.shared,
                            selector: #selector(NotesAutoSaveProxy.fire),
                            object: nil
                        )
                        NotesAutoSaveProxy.shared.action = {
                            viewModel.saveSelectedServerNotes(serverNotesText)
                        }
                        NotesAutoSaveProxy.shared.perform(
                            #selector(NotesAutoSaveProxy.fire),
                            with: nil,
                            afterDelay: 1.5
                        )
                    }
            }
            .frame(height: 100)
            .padding(MSC.Spacing.sm)
            .background(
                            RoundedRectangle(cornerRadius: MSC.Radius.sm)
                                .fill(MSC.Colors.tierTerminal)
                        )
            .overlay(
                RoundedRectangle(cornerRadius: MSC.Radius.sm)
                    .stroke(MSC.Colors.contentBorder, lineWidth: 1)
            )

            Text("Auto-saved as you type. Visible only in this app.")
                .font(.caption2)
                .foregroundStyle(MSC.Colors.tertiary)
        }
        .padding(MSC.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.lg, style: .continuous)
                .fill(MSC.Colors.tierContent)
        )
        .overlay(
                    RoundedRectangle(cornerRadius: MSC.Radius.lg, style: .continuous)
                        .stroke(MSC.Colors.contentBorder, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.22), radius: 6, x: 0, y: 3)
                .disabled(viewModel.selectedServer == nil)
    }
}

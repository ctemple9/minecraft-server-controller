//
//  CreateWorldSlotSheet.swift
//  MinecraftServerController
//
//  Shared sheet for creating a new named world slot on an existing server.
//  Used by DetailsWorldsTabView and ServerEditorWorldTab.
//
//  API:
//    CreateWorldSlotSheet(isPresented: $flag) { name, seed in
//        viewModel.createNewWorldSlot(name: name, seed: seed)
//    }
//

import SwiftUI

struct CreateWorldSlotSheet: View {
    @Binding var isPresented: Bool
    var onCreate: (String, String?) -> Void

    @State private var name: String = ""
    @State private var seed: String = ""
    @FocusState private var nameFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedSeed: String {
        seed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ──────────────────────────────────────────────
            HStack(alignment: .top, spacing: MSC.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                        .fill(Color.green.opacity(0.15))
                    Image(systemName: "globe.europe.africa.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.green)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Create New World")
                        .font(MSC.Typography.pageTitle)
                    Text("Adds a new persistent world slot to this server. You can switch between world slots whenever the server is stopped.")
                        .font(MSC.Typography.caption)
                        .foregroundStyle(MSC.Colors.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, MSC.Spacing.xl)

            Divider()
                .padding(.bottom, MSC.Spacing.lg)

            // ── World Name ──────────────────────────────────────────
            VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                Text("World Name")
                    .font(MSC.Typography.sectionHeader)
                TextField("e.g. Survival World", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
                Text("This is the display name for the world slot. It is separate from the server name.")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.caption)
            }
            .padding(.bottom, MSC.Spacing.lg)

            // ── Seed ────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                Text("Seed")
                    .font(MSC.Typography.sectionHeader)
                TextField("Optional — leave blank for a random world", text: $seed)
                    .textFieldStyle(.roundedBorder)
                Text("The seed is only used the first time this world slot generates terrain. It has no effect on worlds that have already been generated.")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.caption)
            }
            .padding(.bottom, MSC.Spacing.lg)

            // ── Difficulty / Gamemode note ──────────────────────────
            HStack(alignment: .top, spacing: MSC.Spacing.sm) {
                Image(systemName: "info.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(MSC.Colors.info)
                    .padding(.top, 1)
                Text("Difficulty and game mode are server-wide settings. They apply to all worlds and can be changed in the Settings tab.")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(MSC.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                    .fill(MSC.Colors.info.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                    .stroke(MSC.Colors.info.opacity(0.18), lineWidth: 1)
            )
            .padding(.bottom, MSC.Spacing.xl)

            // ── Actions ─────────────────────────────────────────────
            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(MSCSecondaryButtonStyle())

                Button("Create World") {
                    let resolvedSeed = trimmedSeed.isEmpty ? nil : trimmedSeed
                    onCreate(trimmedName, resolvedSeed)
                    isPresented = false
                }
                .buttonStyle(MSCPrimaryButtonStyle())
                .disabled(trimmedName.isEmpty)
            }
        }
        .padding(MSC.Spacing.xxl)
        .frame(width: 460)
        .onAppear {
            nameFocused = true
        }
    }
}

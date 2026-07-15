// CurseForgeManualDownloadSheet.swift
// MinecraftServerController

import SwiftUI
import AppKit

/// Wraps a list of distribution-blocked CurseForge mods so it can be used
/// as a sheet item (`Identifiable`). Each call to `importCurseForgeModpack`
/// that produces blocked files sets `AppViewModel.pendingManualDownloads`.
struct PendingCFManualDownloads: Identifiable {
    let id = UUID()
    let items: [CurseForgeModpack.ManualDownload]
}

/// Sheet shown after a CurseForge modpack import when one or more mods
/// couldn't be auto-downloaded (author disabled API distribution).
/// Shows a per-mod "Open" link and an "Open All" shortcut.
struct CurseForgeManualDownloadSheet: View {

    let pending: PendingCFManualDownloads
    @Binding var isPresented: PendingCFManualDownloads?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MSCSheetHeader(
                "\(pending.items.count) mod\(pending.items.count == 1 ? "" : "s") need a manual download",
                subtitle: "These mods can't be auto-downloaded (authors disabled API distribution)."
            ) { isPresented = nil }
            .padding(.horizontal, MSC.Spacing.xl)
            .padding(.top, MSC.Spacing.xl)

            ScrollView {
                VStack(alignment: .leading, spacing: MSC.Spacing.lg) {

                    SECallout(
                        icon: "arrow.down.circle",
                        color: .orange,
                        text: "Download each mod from its CurseForge page and drop the .jar file into your server's mods/ folder. The server is otherwise ready to start."
                    )

                    SESection(icon: "shippingbox.fill", title: "Mods to download", color: .blue) {
                        VStack(spacing: 0) {
                            ForEach(Array(pending.items.enumerated()), id: \.offset) { idx, mod in
                                modRow(mod)
                                if idx < pending.items.count - 1 {
                                    Divider().padding(.leading, MSC.Spacing.md)
                                }
                            }
                        }
                    }
                }
                .padding(MSC.Spacing.xl)
            }

            Divider()

            HStack(spacing: MSC.Spacing.sm) {
                Button {
                    openAll()
                } label: {
                    Label("Open All in CurseForge", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(MSCSecondaryButtonStyle())

                Spacer()

                Button {
                    isPresented = nil
                } label: {
                    Text("Done")
                }
                .buttonStyle(MSCPrimaryButtonStyle())
            }
            .padding(MSC.Spacing.xl)
        }
        .background(MSC.Colors.tierAtmosphere)
        .frame(minWidth: 520, idealWidth: 580, minHeight: 380, idealHeight: 480)
    }

    // MARK: - Row

    private func modRow(_ mod: CurseForgeModpack.ManualDownload) -> some View {
        HStack(spacing: MSC.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(mod.modName)
                    .font(.system(size: 13, weight: .medium))
                Text(mod.fileName)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                openURL(mod.projectPageURL)
            } label: {
                Label("Open", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(MSCSecondaryButtonStyle())
            .controlSize(.small)
        }
        .padding(.vertical, MSC.Spacing.sm)
        .padding(.horizontal, MSC.Spacing.md)
    }

    // MARK: - Actions

    private func openAll() {
        for mod in pending.items {
            openURL(mod.projectPageURL)
        }
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}

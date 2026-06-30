//
//  ClientExportSheet.swift
//  MinecraftServerController
//
//  Shows which mods/plugins clients need to install. Two export formats:
//    • Modded servers (Fabric / NeoForge / Forge): ZIP of selected JAR files —
//      players drag the contents into their .minecraft/mods folder.
//    • Paper / Purpur: Modrinth link list to clipboard — players download the
//      client build themselves (the server plugin JAR ≠ the client mod JAR).
//

import SwiftUI

struct ClientExportSheet: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Binding var isPresented: Bool

    let cfg: ConfigServer

    @State private var items: [ClientExportItem] = []
    @State private var isLoading = true
    @State private var copyConfirmation = false

    private var isPaperLike: Bool {
        cfg.javaFlavor.addOnKind == .plugin
    }

    private var selectedCount: Int { items.filter(\.isSelected).count }

    private func items(_ status: ClientSideStatus) -> [ClientExportItem] {
        items.filter { $0.clientStatus == status }
    }

    var body: some View {
        VStack(spacing: 0) {
            MSCSheetHeader("Export for Clients") { isPresented = false }
                .padding(.horizontal, MSC.Spacing.xl)
                .padding(.top, MSC.Spacing.xl)

            subheader

            Divider()

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
                        if isPaperLike {
                            paperSections
                        } else {
                            moddedSections
                        }
                    }
                    .padding(MSC.Spacing.xl)
                }
            }

            Divider()
            footer
        }
        .frame(width: 560, height: 580)
        .task {
            let built = viewModel.buildClientExportItems(for: cfg)
            await MainActor.run {
                items = built
                isLoading = false
            }
        }
    }

    // MARK: - Subheader

    private var subheader: some View {
        HStack(spacing: MSC.Spacing.sm) {
            Image(systemName: isPaperLike ? "info.circle.fill" : "shippingbox.fill")
                .foregroundStyle(isPaperLike ? MSC.Colors.info : MSC.Colors.accent)
            Text(isPaperLike
                 ? "Clients can connect to Paper servers without installing any plugins. The items below have optional or required client components."
                 : "Select the mods your clients need to install. Required and unknown mods are checked by default; server-only mods are unchecked.")
                .font(MSC.Typography.caption)
                .foregroundStyle(MSC.Colors.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, MSC.Spacing.xl)
        .padding(.vertical, MSC.Spacing.md)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: MSC.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 26)).foregroundStyle(MSC.Colors.success)
            Text(isPaperLike
                 ? "No client-side plugin components found."
                 : "No mods found in the mods folder.")
                .font(MSC.Typography.caption).foregroundStyle(MSC.Colors.tertiary)
            Text(isPaperLike
                 ? "Your players can connect without installing anything."
                 : "Add mods to the server first.")
                .font(.system(size: 10)).foregroundStyle(MSC.Colors.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Modded sections (Fabric / NeoForge / Forge)

    @ViewBuilder
    private var moddedSections: some View {
        let required   = items(.required)
        let optional   = items(.optional)
        let unknown    = items(.unknown)
        let serverOnly = items(.serverOnly)

        if !required.isEmpty || !unknown.isEmpty {
            section(
                title: "Required on client",
                note: "Clients must have these installed to connect or see content.",
                items: required + unknown
            )
        }
        if !optional.isEmpty {
            section(
                title: "Optional — enhances experience",
                note: "Clients can connect without these, but installing them adds extra features.",
                items: optional
            )
        }
        if !serverOnly.isEmpty {
            section(
                title: "Server-only",
                note: "Performance and server-management mods clients don't need.",
                items: serverOnly
            )
        }
    }

    // MARK: - Paper sections

    @ViewBuilder
    private var paperSections: some View {
        let required = items(.required)
        let optional = items(.optional)

        if !required.isEmpty {
            section(
                title: "Required — clients must install",
                note: "Clients cannot use this feature without installing these.",
                items: required
            )
        }
        if !optional.isEmpty {
            section(
                title: "Enhances experience",
                note: "Clients can connect without these, but won't have these features.",
                items: optional
            )
        }
    }

    // MARK: - Section builder

    @ViewBuilder
    private func section(title: String, note: String, items sectionItems: [ClientExportItem]) -> some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
            Text(title)
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(MSC.Colors.tertiary)
            Text(note)
                .font(.system(size: 10))
                .foregroundStyle(MSC.Colors.tertiary)

            VStack(spacing: 0) {
                ForEach(Array(sectionItems.enumerated()), id: \.element.id) { idx, item in
                    if idx > 0 { Divider().opacity(0.4) }
                    row(item)
                }
            }
            .background(RoundedRectangle(cornerRadius: MSC.Radius.md).fill(Color(NSColor.controlBackgroundColor)))
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func row(_ item: ClientExportItem) -> some View {
        let binding = Binding<Bool>(
            get: { items.first(where: { $0.id == item.id })?.isSelected ?? false },
            set: { val in
                if let idx = items.firstIndex(where: { $0.id == item.id }) {
                    items[idx].isSelected = val
                }
            }
        )
        HStack(spacing: MSC.Spacing.sm) {
            Toggle("", isOn: binding)
                .labelsHidden()
                .toggleStyle(.checkbox)

            // Icon box
            Group {
                if let urlStr = item.iconURL, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { iconPlaceholder }
                        .frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: MSC.Radius.sm))
                } else {
                    iconPlaceholder.frame(width: 28, height: 28)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    statusChip(item.clientStatus)
                    Text("·").foregroundStyle(MSC.Colors.tertiary).font(.system(size: 10))
                    Text(item.statusSource)
                        .font(.system(size: 10))
                        .foregroundStyle(MSC.Colors.tertiary)
                }
            }

            Spacer()

            // For Paper, show Modrinth link button
            if isPaperLike, let url = item.modrinthURL {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12))
                        .foregroundStyle(MSC.Colors.tertiary)
                }
                .buttonStyle(.plain)
                .help("View on Modrinth to download the client version")
            }
        }
        .padding(.horizontal, MSC.Spacing.md)
        .padding(.vertical, MSC.Spacing.sm)
    }

    private var iconPlaceholder: some View {
        RoundedRectangle(cornerRadius: MSC.Radius.sm)
            .fill(MSC.Colors.accent.opacity(0.1))
            .overlay(Image(systemName: "puzzlepiece.fill").font(.system(size: 10)).foregroundStyle(MSC.Colors.accent.opacity(0.4)))
    }

    // MARK: - Status chip

    @ViewBuilder
    private func statusChip(_ status: ClientSideStatus) -> some View {
        let (color, label): (Color, String) = switch status {
        case .required:   (MSC.Colors.error,   "Required")
        case .optional:   (MSC.Colors.info,    "Optional")
        case .serverOnly: (MSC.Colors.tertiary, "Server-only")
        case .unknown:    (MSC.Colors.warning,  "Unknown")
        }
        Text(label)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.1)))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text(isPaperLike
                 ? "\(selectedCount) item\(selectedCount == 1 ? "" : "s") selected"
                 : "\(selectedCount) mod\(selectedCount == 1 ? "" : "s") selected")
                .font(.system(size: 10))
                .foregroundStyle(MSC.Colors.tertiary)
            Spacer()
            Button("Close") { isPresented = false }
                .buttonStyle(MSCSecondaryButtonStyle())
            if isPaperLike {
                Button {
                    viewModel.copyClientLinksToClipboard(items: items)
                    copyConfirmation = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copyConfirmation = false }
                } label: {
                    Label(copyConfirmation ? "Copied!" : "Copy Modrinth Links", systemImage: copyConfirmation ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(MSCPrimaryButtonStyle())
                .disabled(selectedCount == 0)
            } else {
                Button {
                    viewModel.exportClientModsAsZip(items: items, for: cfg)
                    isPresented = false
                } label: {
                    Label("Export ZIP", systemImage: "archivebox")
                }
                .buttonStyle(MSCPrimaryButtonStyle())
                .disabled(selectedCount == 0)
            }
        }
        .padding(.horizontal, MSC.Spacing.xl)
        .padding(.vertical, MSC.Spacing.lg)
    }
}

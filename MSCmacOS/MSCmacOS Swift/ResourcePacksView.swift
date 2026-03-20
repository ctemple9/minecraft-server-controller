// ResourcePacksView.swift
// MinecraftServerController
//
//
// Sheet displayed from DetailsHeaderSectionView via the "Resource Packs…" button.
//
// Features:
//   - List of installed packs with name, size, type, and requirement label (Java)
//   - Add button (NSOpenPanel file picker)
//   - Drag-and-drop support (drop .zip / .mcpack onto the list area)
//   - Remove button per row
//   - Java only: "Set as Active" / "Clear Active" toggle in server.properties
//   - Empty state guidance

import SwiftUI
import UniformTypeIdentifiers

struct ResourcePacksView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Binding var isPresented: Bool

    @State private var isDragTargeted: Bool = false
    @State private var pendingRemovePack: InstalledResourcePack? = nil
    @State private var showRemoveConfirm: Bool = false

    // Computed helpers
    private var cfg: ConfigServer? {
        guard let s = viewModel.selectedServer else { return nil }
        return viewModel.configServer(for: s)
    }

    private var isJava: Bool { cfg?.isJava ?? true }

    private var packs: [InstalledResourcePack] { viewModel.installedResourcePacks }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ─────────────────────────────────────────────────────
            MSCSheetHeader(
                "Resource Packs",
                subtitle: cfg.map { "\($0.displayName) · \($0.serverType.displayName)" }
            ) {
                isPresented = false
            }
            .padding(.horizontal, MSC.Spacing.xxl)
            .padding(.top, MSC.Spacing.xxl)

            Divider()
                .padding(.top, MSC.Spacing.sm)

            // ── Content ────────────────────────────────────────────────────
            if viewModel.isLoadingResourcePacks {
                loadingState
            } else if packs.isEmpty {
                emptyState
            } else {
                packList
            }
        }
        .frame(minWidth: 600, minHeight: 420)
        .onAppear {
            viewModel.loadResourcePacksForSelectedServer()
        }
        .confirmationDialog(
            "Remove \"\(pendingRemovePack?.name ?? "")\"?",
            isPresented: $showRemoveConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove Pack", role: .destructive) {
                if let pack = pendingRemovePack {
                    viewModel.removeResourcePack(pack)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The file will be permanently deleted from the server folder.")
        }
    }

    // MARK: - Loading state

    private var loadingState: some View {
        VStack(spacing: MSC.Spacing.md) {
            ProgressView()
            Text("Loading packs…")
                .font(MSC.Typography.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(MSC.Spacing.xxl)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: MSC.Spacing.lg) {
            Image(systemName: "shippingbox")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("No resource packs installed")
                .font(MSC.Typography.sectionHeader)

            if isJava {
                Text("Add a .zip resource pack using the button below, or drag and drop a file here. The pack will be placed in the server\u{2019}s resource-packs/ folder.")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            } else {
                Text("Add a .mcpack file using the button below, or drag and drop a file here. The pack will be placed in the server\u{2019}s resource_packs/ folder.")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            addButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(MSC.Spacing.xxl)
        .background(dropTarget)
    }

    // MARK: - Pack list

    private var packList: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Column header
            HStack {
                Text("Pack Name")
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isJava {
                    Text("Status")
                        .frame(width: 90, alignment: .center)
                } else {
                    Text("Type")
                        .frame(width: 120, alignment: .center)
                }
                Text("Size")
                    .frame(width: 72, alignment: .trailing)
                Spacer().frame(width: 70)
            }
            .font(MSC.Typography.captionBold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, MSC.Spacing.xxl)
            .padding(.vertical, MSC.Spacing.sm)

            Divider()

            List(packs) { pack in
                packRow(pack)
                    .listRowInsets(EdgeInsets(
                        top: MSC.Spacing.sm,
                        leading: MSC.Spacing.xxl,
                        bottom: MSC.Spacing.sm,
                        trailing: MSC.Spacing.xxl
                    ))
            }
            .listStyle(.plain)

            Divider()

            // Footer toolbar
            HStack {
                addButton

                if isJava {
                    Button("Clear Active Pack") {
                        viewModel.setJavaActivePack(nil)
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                    .disabled(packs.allSatisfy { !$0.isRequired })
                }

                Spacer()

                Text(packCountLabel)
                    .font(MSC.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, MSC.Spacing.xxl)
            .padding(.vertical, MSC.Spacing.md)
        }
        .background(dropTarget)
    }

    // MARK: - Pack row

    @ViewBuilder
    private func packRow(_ pack: InstalledResourcePack) -> some View {
        HStack(spacing: MSC.Spacing.md) {

            // Icon
            Image(systemName: packIcon(for: pack))
                .font(.system(size: 16))
                .foregroundStyle(packColor(for: pack))
                .frame(width: 24)

            // Name + filename
            VStack(alignment: .leading, spacing: 2) {
                Text(pack.name)
                    .font(MSC.Typography.cardTitle)
                    .lineLimit(1)
                Text(pack.fileName)
                    .font(MSC.Typography.monoSmall)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Status / type column
            if isJava, let req = pack.requirementLabel {
                Text(req)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(pack.isRequired ? MSC.Colors.success : .secondary)
                    .padding(.horizontal, MSC.Spacing.sm)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(
                            (pack.isRequired ? MSC.Colors.success : Color.secondary)
                                .opacity(0.10)
                        )
                    )
                    .frame(width: 90, alignment: .center)
            } else if !isJava {
                Text(pack.typeLabel)
                    .font(MSC.Typography.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 120, alignment: .center)
            }

            // Size
            Text(pack.fileSizeDisplay)
                .font(MSC.Typography.monoSmall)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)

            // Actions
            HStack(spacing: MSC.Spacing.xs) {
                if isJava && !pack.isRequired {
                    Button("Set Active") {
                        viewModel.setJavaActivePack(pack)
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                }

                Button {
                    pendingRemovePack = pack
                    showRemoveConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(MSCSecondaryButtonStyle())
                .foregroundStyle(MSC.Colors.error)
            }
            .frame(width: 70, alignment: .trailing)
        }
    }

    // MARK: - Add button

    private var addButton: some View {
        Button {
            viewModel.presentResourcePackPicker()
        } label: {
            Label("Add Pack\u{2026}", systemImage: "plus")
        }
        .buttonStyle(MSCPrimaryButtonStyle())
    }

    // MARK: - Drag and drop target overlay

    private var dropTarget: some View {
        RoundedRectangle(cornerRadius: MSC.Radius.md)
            .stroke(
                isDragTargeted ? MSC.Colors.accent : Color.clear,
                style: StrokeStyle(lineWidth: 2, dash: [6])
            )
            .padding(MSC.Spacing.md)
            .animation(.easeInOut(duration: 0.15), value: isDragTargeted)
            .background(
                isDragTargeted
                    ? MSC.Colors.accent.opacity(0.06)
                    : Color.clear
            )
            .allowsHitTesting(false)
    }

    // MARK: - Drop delegate

    // Implemented as a view modifier on the whole view.
    // SwiftUI's .onDrop lets us respond to file drops.
    var body_withDrop: some View {
        body
            .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
                handleDrop(providers: providers)
            }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let cfg = cfg else { return false }
        var handled = false

        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

                let ext = url.pathExtension.lowercased()
                let allowed = cfg.isJava
                    ? ResourcePackManager.javaAllowedTypes
                    : ResourcePackManager.bedrockAllowedTypes

                guard allowed.contains(ext) else {
                    DispatchQueue.main.async {
                        self.viewModel.showError(
                            title: "Unsupported File",
                            message: cfg.isJava
                                ? "Java resource packs must be .zip files."
                                : "Bedrock resource packs must be .mcpack or .zip files."
                        )
                    }
                    return
                }

                DispatchQueue.main.async {
                    self.viewModel.installResourcePack(from: url, for: cfg)
                }
            }
            handled = true
        }

        return handled
    }

    // MARK: - Display helpers

    private var packCountLabel: String {
        let n = packs.count
        return n == 1 ? "1 pack installed" : "\(n) packs installed"
    }

    private func packIcon(for pack: InstalledResourcePack) -> String {
        switch pack.packType {
        case .javaZip:        return "archivebox.fill"
        case .bedrockMcpack:  return "cube.fill"
        case .bedrockFolder:  return "folder.fill"
        }
    }

    private func packColor(for pack: InstalledResourcePack) -> Color {
        switch pack.packType {
        case .javaZip:        return .blue
        case .bedrockMcpack:  return MSC.Colors.success
        case .bedrockFolder:  return MSC.Colors.warning
        }
    }
}

// MARK: - Drop-enabled wrapper

/// Wraps ResourcePacksView and applies the drag-and-drop modifier at the VStack level.
struct ResourcePacksViewWithDrop: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Binding var isPresented: Bool

    @State private var isDragTargeted: Bool = false

    var body: some View {
        ResourcePacksView(isPresented: $isPresented)
            .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
                handleDrop(providers: providers)
            }
            .overlay(
                RoundedRectangle(cornerRadius: MSC.Radius.md)
                    .stroke(
                        isDragTargeted ? MSC.Colors.accent : Color.clear,
                        style: StrokeStyle(lineWidth: 2, dash: [6])
                    )
                    .padding(MSC.Spacing.sm)
                    .allowsHitTesting(false)
                    .animation(.easeInOut(duration: 0.15), value: isDragTargeted)
            )
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let server = viewModel.selectedServer,
              let cfg = viewModel.configServer(for: server) else { return false }
        var handled = false

        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

                let ext = url.pathExtension.lowercased()
                let allowed = cfg.isJava
                    ? ResourcePackManager.javaAllowedTypes
                    : ResourcePackManager.bedrockAllowedTypes

                guard allowed.contains(ext) else {
                    DispatchQueue.main.async {
                        self.viewModel.showError(
                            title: "Unsupported File",
                            message: cfg.isJava
                                ? "Java resource packs must be .zip files."
                                : "Bedrock resource packs must be .mcpack or .zip files."
                        )
                    }
                    return
                }

                DispatchQueue.main.async {
                    self.viewModel.installResourcePack(from: url, for: cfg)
                }
            }
            handled = true
        }

        return handled
    }
}

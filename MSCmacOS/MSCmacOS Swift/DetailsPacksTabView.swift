//
//  DetailsPacksTabView.swift
//  MinecraftServerController
//
//  Packs tab — resource pack / texture pack manager, inline (no sheet).
//  All logic delegated to ViewModel; UI pulled from ResourcePacksView.
//

import SwiftUI
import UniformTypeIdentifiers

struct DetailsPacksTabView: View {
    @EnvironmentObject var viewModel: AppViewModel

    @State private var isDragTargeted: Bool = false
    @State private var pendingRemovePack: InstalledResourcePack? = nil
    @State private var showRemoveConfirm: Bool = false

    private var cfg: ConfigServer? {
        guard let s = viewModel.selectedServer else { return nil }
        return viewModel.configServer(for: s)
    }

    private var isJava: Bool { cfg?.isJava ?? true }
    private var packs: [InstalledResourcePack] { viewModel.installedResourcePacks }

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {

            // Header row
            HStack {
                Label("Resource Packs", systemImage: "shippingbox")
                    .font(MSC.Typography.cardTitle)
                    .foregroundStyle(.secondary)

                Spacer()

                if viewModel.isLoadingResourcePacks {
                    ProgressView().scaleEffect(0.7)
                }

                addButton

                if isJava {
                    Button("Clear Active Pack") {
                        viewModel.setJavaActivePack(nil)
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                    .disabled(packs.allSatisfy { !$0.isRequired })
                }
            }

            Divider()

            // Content
            if viewModel.isLoadingResourcePacks {
                VStack(spacing: MSC.Spacing.md) {
                    ProgressView()
                    Text("Loading packs\u{2026}")
                        .font(MSC.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(MSC.Spacing.xxl)

            } else if packs.isEmpty {
                emptyState

            } else {
                packList
            }
        }
        .padding(MSC.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .fill(MSC.Colors.tierContent)
        )
        .overlay(
            // Only show a border when drag-targeted — gives drop affordance without a permanent box
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .stroke(MSC.Colors.accent.opacity(isDragTargeted ? 0.6 : 0), lineWidth: isDragTargeted ? 2 : 0)
        )
        .onAppear { viewModel.loadResourcePacksForSelectedServer() }
        .onChange(of: viewModel.selectedServer) { _ in
            viewModel.loadResourcePacksForSelectedServer()
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
            handleDrop(providers: providers)
        }
        .confirmationDialog(
            "Remove \"\(pendingRemovePack?.name ?? "")\"?",
            isPresented: $showRemoveConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove Pack", role: .destructive) {
                if let pack = pendingRemovePack { viewModel.removeResourcePack(pack) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The file will be permanently deleted from the server folder.")
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: MSC.Spacing.lg) {
            Image(systemName: "shippingbox")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("No resource packs installed")
                .font(MSC.Typography.sectionHeader)

            Text(isJava
                 ? "Add a .zip resource pack using the button above, or drag and drop a file here."
                 : "Add a .mcpack file using the button above, or drag and drop a file here."
            )
            .font(MSC.Typography.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity)
        .padding(MSC.Spacing.xxl)
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
                Spacer().frame(width: 80)
            }
            .font(MSC.Typography.captionBold)
            .foregroundStyle(.secondary)
            .padding(.vertical, MSC.Spacing.xs)

            Divider()

            ForEach(packs) { pack in
                packRow(pack)
                Divider()
            }

            // Footer
            HStack {
                Spacer()
                Text(packs.count == 1 ? "1 pack installed" : "\(packs.count) packs installed")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, MSC.Spacing.sm)
        }
    }

    // MARK: - Pack row

    @ViewBuilder
    private func packRow(_ pack: InstalledResourcePack) -> some View {
        HStack(spacing: MSC.Spacing.md) {
            Image(systemName: packIcon(for: pack))
                .font(.system(size: 16))
                .foregroundStyle(packColor(for: pack))
                .frame(width: 24)

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

            if isJava, let req = pack.requirementLabel {
                Text(req)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(pack.isRequired ? MSC.Colors.success : .secondary)
                    .padding(.horizontal, MSC.Spacing.sm)
                    .padding(.vertical, 2)
                    .background(Capsule().fill((pack.isRequired ? MSC.Colors.success : Color.secondary).opacity(0.10)))
                    .frame(width: 90, alignment: .center)
            } else if !isJava {
                Text(pack.typeLabel)
                    .font(MSC.Typography.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 120, alignment: .center)
            }

            Text(pack.fileSizeDisplay)
                .font(MSC.Typography.monoSmall)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)

            HStack(spacing: MSC.Spacing.xs) {
                if isJava && !pack.isRequired {
                    Button("Set Active") { viewModel.setJavaActivePack(pack) }
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
            .frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, MSC.Spacing.sm)
    }

    // MARK: - Add button

    private var addButton: some View {
        Button {
            viewModel.presentResourcePackPicker()
        } label: {
            Label("Add Pack\u{2026}", systemImage: "plus")
        }
        .buttonStyle(MSCSecondaryButtonStyle())
    }

    // MARK: - Drag and drop

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

    private func packIcon(for pack: InstalledResourcePack) -> String {
        switch pack.packType {
        case .javaZip:       return "archivebox.fill"
        case .bedrockMcpack: return "cube.fill"
        case .bedrockFolder: return "folder.fill"
        }
    }

    private func packColor(for pack: InstalledResourcePack) -> Color {
        switch pack.packType {
        case .javaZip:       return .blue
        case .bedrockMcpack: return MSC.Colors.success
        case .bedrockFolder: return MSC.Colors.warning
        }
    }
}

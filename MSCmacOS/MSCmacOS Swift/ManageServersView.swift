//
//  ManageServersView.swift
//  MinecraftServerController
//
//  Redesigned to match the Welcome Guide visual language:
//  server rows replaced with pscCard() tiles, status chips for JAR/cross-play,
//  clearer header/footer, context menus preserved.
//  All functionality, state, and sheet connections are identical to the original.
//
//  Bedrock servers show "Docker" + "Native cross-play" instead of JAR/Geyser status.
//

import SwiftUI

struct ManageServersView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Binding var isPresented: Bool

    @State private var isShowingEditor = false
    @State private var editorMode: ServerEditorMode = .new
    @State private var editorData = ServerEditorData.empty()

    @State private var serverToDelete: ConfigServer?
    @State private var isShowingDeleteAlert = false

    @State private var isShowingCreateServer = false

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            MSCSheetHeader("Manage Servers", subtitle: "\(viewModel.configServers.count) server\(viewModel.configServers.count == 1 ? "" : "s") configured") {
                if OnboardingManager.shared.isActive,
                   OnboardingManager.shared.currentStep == .dismissManage {
                    if OnboardingManager.shared.tourServerType == .bedrock {
                        OnboardingManager.shared.jumpTo(.startButton)
                    } else if viewModel.eulaAccepted == false {
                        OnboardingManager.shared.jumpTo(.acceptEula)
                    } else {
                        OnboardingManager.shared.jumpTo(.startButton)
                    }
                }
                isPresented = false
            }
                        .onboardingAnchor(.manageServersDoneButton)
                        .padding(.horizontal, MSC.Spacing.xl)
                        .padding(.top, MSC.Spacing.xl)

            // Server List
            ScrollView {
                if viewModel.configServers.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: MSC.Spacing.sm) {
                        ForEach(viewModel.configServers, id: \.id) { server in
                            serverCard(server)
                        }
                    }
                    .padding(.horizontal, MSC.Spacing.xl)
                    .padding(.vertical, MSC.Spacing.lg)
                }
            }

            // Footer
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: MSC.Spacing.sm) {
                    Button {
                        editorMode = .new
                        editorData = ServerEditorData.empty()
                        isShowingEditor = true
                    } label: {
                        Label("Add Server", systemImage: "plus")
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                    .help("Point to an existing server folder you already have on disk.")

                    Spacer()

                    Button {
                        isShowingCreateServer = true
                        if OnboardingManager.shared.currentStep == .createServer {
                            // Tour advances to serverName once CreateServerView opens
                        }
                    } label: {
                        Label("Create New Server\u{2026}", systemImage: "hammer")
                    }
                    .buttonStyle(MSCPrimaryButtonStyle())
                    .help("Run the guided wizard to set up a new Paper server from scratch.")
                    .onboardingAnchor(.createServerButton)
                }
                .padding(.horizontal, MSC.Spacing.xl)
                .padding(.vertical, MSC.Spacing.lg)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 640, minHeight: 440)
        .overlay {
                    OnboardingOverlayView(ownedSteps: [.createServer, .dismissManage])
                }
                // Sheets & Alerts

        .sheet(isPresented: $isShowingEditor) {
            ServerEditorView(
                mode: editorMode,
                data: $editorData,
                onSave: { data in
                    let cfg = data.toConfigServer()
                    viewModel.upsertServer(cfg)

                    if let model = viewModel.servers.first(where: { $0.id == cfg.id }) {
                        viewModel.selectedServer = model
                    }

                    if editorMode == .new {
                        isShowingEditor = false
                    } else {
                        editorMode = .edit
                    }
                },
                onCancel: {
                    isShowingEditor = false
                }
            )
            .environmentObject(viewModel)
        }

        .sheet(isPresented: $isShowingCreateServer) {
            CreateServerView(isPresented: $isShowingCreateServer)
                .environmentObject(viewModel)
        }

        .alert(
            "Delete Server?",
            isPresented: $isShowingDeleteAlert,
            presenting: serverToDelete
        ) { server in
            Button("Delete from Disk", role: .destructive) {
                do {
                    try viewModel.deleteServerFromDisk(withId: server.id)
                } catch {
                    viewModel.logAppMessage("[Server] Failed to delete server folder for \"\(server.displayName)\": \(error.localizedDescription)")
                }
            }
            Button("Remove Only") {
                viewModel.deleteServer(withId: server.id)
            }
            Button("Cancel", role: .cancel) { }
        } message: { server in
            Text("Choose whether to remove \"\(server.displayName)\" only from the controller or also delete its server folder from disk.")
        }

        .onAppear {
            // If the onboarding tour is on the manageServers step, advance it
            // now that the sheet has opened.
            if OnboardingManager.shared.isActive &&
               OnboardingManager.shared.currentStep == .manageServers {
                OnboardingManager.shared.jumpTo(.createServer)
            }

            guard viewModel.manageServersShouldAutoEditSelectedOnSettingsTab else { return }
            viewModel.manageServersShouldAutoEditSelectedOnSettingsTab = false
            guard let uiServer = viewModel.selectedServer else { return }
            guard let cfg = viewModel.configServers.first(where: { $0.id == uiServer.id }) else { return }
            openEditor(for: cfg)
        }
    }

    // MARK: - Server Card

    @ViewBuilder
    private func serverCard(_ server: ConfigServer) -> some View {
        let isActive = viewModel.selectedServer?.id == server.id

        HStack(alignment: .center, spacing: MSC.Spacing.md) {

            // Left accent bar when active
            if isActive {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: 3, height: 36)
            }

            // Server icon
            ZStack {
                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                    .frame(width: 36, height: 36)
                Image(systemName: "server.rack")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
            }

            // Info block
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: MSC.Spacing.xs) {
                    Text(server.displayName.isEmpty ? "(no name)" : server.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    // Server type badge — always visible
                    Text(server.isBedrock ? "BEDROCK" : "JAVA")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(server.isBedrock ? Color.orange : Color.green)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill((server.isBedrock ? Color.orange : Color.green).opacity(0.12)))

                    if isActive {
                        Text("ACTIVE")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                    }
                }

                Text(server.serverDir)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)

                // Status chips — contextual per server type
                statusChips(for: server)
            }

            Spacer()

        // Edit button
            Button("Edit Server") {
                openEditor(for: server)
            }
            .buttonStyle(MSCSecondaryButtonStyle())
            .fixedSize()
        }
        .padding(MSC.Spacing.md)
        .pscCard()
        .contentShape(RoundedRectangle(cornerRadius: MSC.Radius.lg, style: .continuous))
        .onTapGesture {
            viewModel.setActiveServer(withId: server.id)
        }
        .contextMenu {
            Button("Set as Active") {
                viewModel.setActiveServer(withId: server.id)
            }
            Divider()
            Button("Edit\u{2026}") {
                openEditor(for: server)
            }
            Divider()
            Button("Remove from Controller", role: .destructive) {
                serverToDelete = server
                isShowingDeleteAlert = true
            }
        }
    }

    // MARK: - Status Chips

    /// Chips are contextual: Bedrock shows runtime type and cross-play model;
    /// Java shows JAR name and Geyser/Floodgate status.
    @ViewBuilder
    private func statusChips(for server: ConfigServer) -> some View {
        HStack(spacing: MSC.Spacing.sm) {
            if server.isBedrock {
                MSChip(
                    icon: "shippingbox.fill",
                    label: "Docker",
                    color: .blue
                )
                MSChip(
                    icon: "checkmark.circle.fill",
                    label: "Native cross-play",
                    color: .green
                )
            } else {
                MSChip(
                    icon: "shippingbox.fill",
                    label: viewModel.paperJarDisplayName(for: server),
                    color: .blue
                )
                MSChip(
                    icon: crossPlayIcon(for: server),
                    label: viewModel.crossPlayStatus(for: server).label,
                    color: crossPlayColor(for: server)
                )
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: MSC.Spacing.lg) {
            Image(systemName: "server.rack")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary.opacity(0.4))

            VStack(spacing: MSC.Spacing.xs) {
                Text("No servers yet")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Create a new server or add an existing folder.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Helpers

    private func openEditor(for server: ConfigServer) {
        viewModel.setActiveServer(withId: server.id)
        editorMode = .edit
        editorData = ServerEditorData(from: server)
        isShowingEditor = true
    }

    private func crossPlayIcon(for server: ConfigServer) -> String {
        switch viewModel.crossPlayStatus(for: server) {
        case .both:          return "puzzlepiece.fill"
        case .geyserOnly,
             .floodgateOnly: return "puzzlepiece"
        case .none:          return "xmark.circle"
        }
    }

    private func crossPlayColor(for server: ConfigServer) -> Color {
        switch viewModel.crossPlayStatus(for: server) {
        case .both:          return .green
        case .geyserOnly,
             .floodgateOnly: return .orange
        case .none:          return .secondary
        }
    }

    @ViewBuilder
    private func closeableFallback(label: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: MSC.Spacing.md) {
            Text(label).foregroundStyle(.secondary)
            Button("Close", action: action)
        }
        .padding()
        .frame(minWidth: 300, minHeight: 120)
    }
}

// MARK: - Chip Component (private to this file)

/// A small icon+label status chip, styled like the WelcomeGuide InAppBox arrows.
private struct MSChip: View {
    let icon: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(color.opacity(0.08))
        )
        .overlay(Capsule().stroke(color.opacity(0.2), lineWidth: 0.5))
    }
}

import SwiftUI

struct WorldsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var vm: DashboardViewModel

    @State private var isLoading: Bool = false
    @State private var isBackingUp: Bool = false
    @State private var isActivating: Bool = false
    @State private var isRestoring: Bool = false

    @State private var slotToActivate: WorldSlotDTO? = nil
    @State private var backupToRestore: BackupItemDTO? = nil
    @State private var toastMessage: String? = nil

    private var resolvedBaseURL: URL? { settings.resolvedBaseURL() }
    private var resolvedToken: String? { settings.resolvedToken() }
    private var isPaired: Bool { resolvedBaseURL != nil && resolvedToken != nil }
    private var isAdmin: Bool { vm.connectedRole == "admin" }

    var body: some View {
        NavigationStack {
            ZStack {
                MSCRemoteStyle.bgBase.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: MSCRemoteStyle.spaceLG) {
                        worldSlotsCard
                        backupsCard
                    }
                    .padding(.horizontal, MSCRemoteStyle.spaceLG)
                    .padding(.top, MSCRemoteStyle.spaceMD)
                    .padding(.bottom, MSCRemoteStyle.spaceLG)
                    .frame(maxWidth: MSCRemoteStyle.contentMaxWidth)
                    .frame(maxWidth: .infinity)
                }
                .refreshable { await refresh() }

                if let toast = toastMessage {
                    VStack {
                        Spacer()
                        Text(toast)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, MSCRemoteStyle.spaceLG)
                            .padding(.vertical, MSCRemoteStyle.spaceMD)
                            .background(MSCRemoteStyle.bgElevated)
                            .clipShape(Capsule())
                            .padding(.bottom, MSCRemoteStyle.spaceLG)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: toast)
                }
            }
            .navigationTitle("Worlds")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(MSCRemoteStyle.bgBase, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task(id: isPaired) {
                guard isPaired else { return }
                await refresh()
            }
            // Activate world confirmation
            .alert("Switch World", isPresented: Binding(
                get: { slotToActivate != nil },
                set: { if !$0 { slotToActivate = nil } }
            )) {
                Button("Cancel", role: .cancel) { slotToActivate = nil }
                Button("Switch") {
                    guard let slot = slotToActivate else { return }
                    slotToActivate = nil
                    Task { await performActivate(slot: slot) }
                }
            } message: {
                if let slot = slotToActivate {
                    Text("Switch to \"\(slot.name)\"?\n\nThe current world will be saved to its slot first. The server must be stopped.")
                }
            }
            // Restore backup confirmation
            .alert("Restore Backup", isPresented: Binding(
                get: { backupToRestore != nil },
                set: { if !$0 { backupToRestore = nil } }
            )) {
                Button("Cancel", role: .cancel) { backupToRestore = nil }
                Button("Restore", role: .destructive) {
                    guard let backup = backupToRestore else { return }
                    backupToRestore = nil
                    Task { await performRestore(backup: backup) }
                }
            } message: {
                if let backup = backupToRestore {
                    Text("Restore \"\(backup.displayName)\"?\n\nA safety backup of the current world will be taken first.")
                }
            }
        }
    }

    // MARK: - World Slots Card

    private var worldSlotsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            MSCSectionHeader(title: "World Slots")
                .padding(.bottom, MSCRemoteStyle.spaceMD)

            if let error = vm.errorMessage, vm.worldsResponse == nil {
                Text("Error: \(error)")
                    .font(.system(size: 12))
                    .foregroundStyle(MSCRemoteStyle.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, MSCRemoteStyle.spaceSM)
            }

            if let response = vm.worldsResponse {
                if response.serverRunning && !response.slots.isEmpty {
                    serverRunningBanner
                        .padding(.bottom, MSCRemoteStyle.spaceMD)
                }

                if response.slots.isEmpty {
                    emptyState(icon: "square.2.layers.3d", message: "No world slots found for the active server.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(response.slots.enumerated()), id: \.element.id) { index, slot in
                            slotRow(slot, serverRunning: response.serverRunning)
                            if index < response.slots.count - 1 {
                                Divider().background(MSCRemoteStyle.borderSubtle)
                            }
                        }
                    }
                }
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, MSCRemoteStyle.spaceLG)
            } else {
                emptyState(icon: "globe", message: "No data — pull to refresh.")
            }
        }
        .mscCard()
    }

    private func slotRow(_ slot: WorldSlotDTO, serverRunning: Bool) -> some View {
        HStack(spacing: MSCRemoteStyle.spaceMD) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: MSCRemoteStyle.spaceSM) {
                    Text(slot.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MSCRemoteStyle.textPrimary)
                    if slot.isActive {
                        Text("Active")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(MSCRemoteStyle.success)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(MSCRemoteStyle.success.opacity(0.12)))
                    }
                }
                HStack(spacing: 6) {
                    if let seed = slot.worldSeed, !seed.isEmpty {
                        Text("Seed: \(seed)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(MSCRemoteStyle.textTertiary)
                        Text("·")
                            .foregroundStyle(MSCRemoteStyle.textTertiary)
                            .font(.system(size: 11))
                    }
                    if let bytes = slot.zipSizeBytes {
                        Text(formatBytes(bytes))
                            .font(.system(size: 11))
                            .foregroundStyle(MSCRemoteStyle.textTertiary)
                        Text("·")
                            .foregroundStyle(MSCRemoteStyle.textTertiary)
                            .font(.system(size: 11))
                    }
                    Text(shortDate(slot.createdAt))
                        .font(.system(size: 11))
                        .foregroundStyle(MSCRemoteStyle.textTertiary)
                }
            }
            Spacer()
            if isAdmin && !slot.isActive {
                Button {
                    slotToActivate = slot
                } label: {
                    Text("Set Active")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(serverRunning ? MSCRemoteStyle.textTertiary : MSCRemoteStyle.accent)
                        .padding(.horizontal, MSCRemoteStyle.spaceMD)
                        .padding(.vertical, MSCRemoteStyle.spaceSM)
                        .background(
                            RoundedRectangle(cornerRadius: MSCRemoteStyle.radiusSM, style: .continuous)
                                .fill(serverRunning ? MSCRemoteStyle.bgElevated : MSCRemoteStyle.accentDim)
                        )
                }
                .disabled(serverRunning || isActivating)
            }
        }
        .padding(.vertical, MSCRemoteStyle.spaceSM + 2)
    }

    private var serverRunningBanner: some View {
        HStack(spacing: MSCRemoteStyle.spaceSM) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(MSCRemoteStyle.warning)
            Text("Stop the server before switching worlds.")
                .font(.system(size: 12))
                .foregroundStyle(MSCRemoteStyle.warning)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Backups Card

    private var backupsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            MSCSectionHeader(title: "Backups")
                .padding(.bottom, MSCRemoteStyle.spaceMD)

            if isAdmin {
                MSCActionButton(
                    title: isBackingUp ? "Backing Up…" : "Back Up Now",
                    icon: "arrow.down.doc.fill",
                    style: .primary,
                    isEnabled: isPaired && !isBackingUp
                ) {
                    Task { await performBackupNow() }
                }
                .padding(.bottom, MSCRemoteStyle.spaceMD)
            }

            if let response = vm.backupsResponse {
                if response.backups.isEmpty {
                    emptyState(icon: "archivebox", message: "No backups yet for the active server.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(response.backups.enumerated()), id: \.element.id) { index, backup in
                            backupRow(backup)
                            if index < response.backups.count - 1 {
                                Divider().background(MSCRemoteStyle.borderSubtle)
                            }
                        }
                    }
                }
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, MSCRemoteStyle.spaceLG)
            } else {
                emptyState(icon: "archivebox", message: "No data — pull to refresh.")
            }
        }
        .mscCard()
    }

    private func backupRow(_ backup: BackupItemDTO) -> some View {
        HStack(spacing: MSCRemoteStyle.spaceMD) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(backup.displayName)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(MSCRemoteStyle.textPrimary)
                    Text(backup.isAutomatic ? "Auto" : "Manual")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(backup.isAutomatic ? .blue : MSCRemoteStyle.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(backup.isAutomatic ? Color.blue.opacity(0.12) : MSCRemoteStyle.bgElevated)
                        )
                }
                HStack(spacing: 6) {
                    if let size = backup.fileSize {
                        Text(formatBytes(size))
                            .font(.system(size: 11))
                            .foregroundStyle(MSCRemoteStyle.textTertiary)
                    }
                    if let slotName = backup.slotName {
                        Text("·")
                            .foregroundStyle(MSCRemoteStyle.textTertiary)
                            .font(.system(size: 11))
                        Text(slotName)
                            .font(.system(size: 11))
                            .foregroundStyle(MSCRemoteStyle.textTertiary)
                    }
                }
            }
            Spacer()
            if isAdmin {
                Button {
                    backupToRestore = backup
                } label: {
                    Text("Restore")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isRestoring ? MSCRemoteStyle.textTertiary : MSCRemoteStyle.accent)
                        .padding(.horizontal, MSCRemoteStyle.spaceMD)
                        .padding(.vertical, MSCRemoteStyle.spaceSM)
                        .background(
                            RoundedRectangle(cornerRadius: MSCRemoteStyle.radiusSM, style: .continuous)
                                .fill(isRestoring ? MSCRemoteStyle.bgElevated : MSCRemoteStyle.accentDim)
                        )
                }
                .disabled(isRestoring)
            }
        }
        .padding(.vertical, MSCRemoteStyle.spaceSM + 2)
    }

    // MARK: - Shared helpers

    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: MSCRemoteStyle.spaceMD) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(MSCRemoteStyle.textTertiary)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(MSCRemoteStyle.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MSCRemoteStyle.spaceLG)
    }

    // MARK: - Actions

    private func refresh() async {
        guard let baseURL = resolvedBaseURL, let token = resolvedToken else { return }
        isLoading = true
        async let w: () = vm.fetchWorlds(baseURL: baseURL, token: token)
        async let b: () = vm.fetchBackups(baseURL: baseURL, token: token)
        _ = await (w, b)
        isLoading = false
    }

    private func performActivate(slot: WorldSlotDTO) async {
        guard let baseURL = resolvedBaseURL, let token = resolvedToken else { return }
        isActivating = true
        let ok = await vm.activateWorldSlot(baseURL: baseURL, token: token, slotId: slot.id)
        isActivating = false
        if ok {
            showToast("Switching to \"\(slot.name)\"…")
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await refresh()
        }
    }

    private func performBackupNow() async {
        guard let baseURL = resolvedBaseURL, let token = resolvedToken else { return }
        isBackingUp = true
        let ok = await vm.createBackupNow(baseURL: baseURL, token: token)
        isBackingUp = false
        if ok {
            showToast("Backup started")
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await refresh()
        }
    }

    private func performRestore(backup: BackupItemDTO) async {
        guard let baseURL = resolvedBaseURL, let token = resolvedToken else { return }
        isRestoring = true
        let ok = await vm.restoreBackup(baseURL: baseURL, token: token, backupId: backup.id)
        isRestoring = false
        if ok {
            showToast("Restoring \"\(backup.displayName)\"…")
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await refresh()
        }
    }

    private func showToast(_ message: String) {
        withAnimation { toastMessage = message }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation { toastMessage = nil }
        }
    }

    // MARK: - Formatting

    private func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / (1024 * 1024)
        if mb >= 1000 { return String(format: "%.1f GB", mb / 1024) }
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        return String(format: "%.0f KB", Double(bytes) / 1024)
    }

    private func shortDate(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = parser.date(from: iso) {
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .none
            return f.string(from: date)
        }
        return iso
    }
}

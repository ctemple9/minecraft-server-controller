import SwiftUI

struct HealthView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var vm: DashboardViewModel

    @State private var updatingComponent: String? = nil
    @State private var updateToast: String? = nil
    @State private var isRefreshing: Bool = false
    @State private var isBroadcastActioning: Bool = false
    @State private var isTogglingAutoStart: Bool = false

    private var resolvedBaseURL: URL? { settings.resolvedBaseURL() }
    private var resolvedToken: String? { settings.resolvedToken() }
    private var isPaired: Bool { resolvedBaseURL != nil && resolvedToken != nil }

    var body: some View {
        NavigationStack {
            ZStack {
                MSCRemoteStyle.bgBase.ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: MSCRemoteStyle.spaceLG) {
                            componentsCard
                            broadcastCard
                        }
                        .padding(.horizontal, MSCRemoteStyle.spaceLG)
                        .padding(.top, MSCRemoteStyle.spaceMD)
                        .padding(.bottom, MSCRemoteStyle.spaceLG)
                    }
                    .refreshable { await refresh() }
                    footerText.padding(.vertical, MSCRemoteStyle.spaceMD)
                }
            }
            .navigationTitle("Health")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(MSCRemoteStyle.bgBase, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task(id: isPaired) {
                guard isPaired else { return }
                // Initial fetch on appear
                await refresh()
                // Keep polling while this tab is visible
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    guard !Task.isCancelled else { break }
                    await refresh()
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { Task { await refresh() } } label: {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                            .animation(isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                    }
                    .disabled(isRefreshing)
                }
            }
        }
    }

    // MARK: - Components Card

    private var componentsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            MSCSectionHeader(title: "Server Components")
                .padding(.bottom, MSCRemoteStyle.spaceMD)

            if let status = vm.componentsStatus {
                if status.components.isEmpty {
                    Text("No components found for the active server.")
                        .font(.system(size: 13))
                        .foregroundStyle(MSCRemoteStyle.textTertiary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(status.components.enumerated()), id: \.element.id) { index, component in
                            componentRow(component)
                            if index < status.components.count - 1 {
                                Divider().background(MSCRemoteStyle.borderSubtle)
                            }
                        }
                    }

                    if status.restartRequiredToApply {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.orange)
                            Text("Restart the server to apply any updates.")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.orange)
                        }
                        .padding(.top, MSCRemoteStyle.spaceMD)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Loading component status…")
                        .font(.system(size: 13))
                        .foregroundStyle(MSCRemoteStyle.textTertiary)
                }
            }

            if let toast = updateToast {
                Text(toast)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(MSCRemoteStyle.success)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, MSCRemoteStyle.spaceSM)
                    .transition(.opacity)
            }
        }
        .mscCard()
        .animation(.easeInOut(duration: 0.2), value: updateToast)
    }

    @ViewBuilder
    private func componentRow(_ component: ComponentStatusDTO) -> some View {
        HStack(spacing: MSCRemoteStyle.spaceMD) {
            // Status dot
            Circle()
                .fill(rowDotColor(component))
                .frame(width: 8, height: 8)
                .shadow(color: rowDotColor(component).opacity(0.5), radius: 3)

            // Name + version info
            VStack(alignment: .leading, spacing: 2) {
                Text(component.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MSCRemoteStyle.textPrimary)

                if let installedBuild = component.installedBuild {
                    let versionStr = component.installedVersion.map { "\($0) · " } ?? ""
                    Text("\(versionStr)build \(installedBuild)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(MSCRemoteStyle.textTertiary)
                } else {
                    Text("Not found")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(MSCRemoteStyle.textTertiary)
                }

                if let latest = component.latestBuild, let installed = component.installedBuild, installed < latest {
                    let latestVer = component.latestVersion.map { "\($0) · " } ?? ""
                    Text("Latest: \(latestVer)build \(latest)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.orange.opacity(0.85))
                }
            }

            Spacer()

            // Status badge or update button
            if component.installedBuild == nil {
                Text("Not installed")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MSCRemoteStyle.textTertiary)
            } else if component.isUpToDate {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                    Text("Up to date")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(MSCRemoteStyle.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(MSCRemoteStyle.accent.opacity(0.12)))
                .overlay(Capsule().stroke(MSCRemoteStyle.accent.opacity(0.3), lineWidth: 0.75))
            } else if vm.connectedRole != "guest" {
                Button {
                    Task { await updateComponent(component) }
                } label: {
                    if updatingComponent == component.name {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 60, height: 24)
                    } else {
                        Text("Update")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.orange))
                    }
                }
                .buttonStyle(.plain)
                .disabled(updatingComponent != nil || !isPaired)
            }
        }
        .padding(.vertical, MSCRemoteStyle.spaceSM)
    }

    private func rowDotColor(_ component: ComponentStatusDTO) -> Color {
        guard component.installedBuild != nil else { return MSCRemoteStyle.textTertiary }
        return component.isUpToDate ? MSCRemoteStyle.accent : Color.orange
    }

    // MARK: - Broadcast Card

    private var broadcastCard: some View {
        let running = vm.broadcastStatus.map { $0.xboxBroadcastRunning || $0.bedrockBroadcastRunning } ?? false
        let statusColor: Color = vm.broadcastStatus == nil ? MSCRemoteStyle.textTertiary : (running ? MSCRemoteStyle.success : MSCRemoteStyle.danger)
        let statusLabel = vm.broadcastStatus == nil ? "Unknown" : (running ? "Running" : "Stopped")

        return VStack(alignment: .leading, spacing: 0) {
            MSCSectionHeader(title: "Xbox Broadcast")
                .padding(.bottom, MSCRemoteStyle.spaceMD)

            // Status row
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Broadcast Status")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MSCRemoteStyle.textPrimary)
                    Text(statusLabel)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(statusColor)
                }
                Spacer()
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: statusColor.opacity(0.6), radius: 4)
            }
            .padding(.bottom, MSCRemoteStyle.spaceMD)

            Divider().background(MSCRemoteStyle.borderSubtle).padding(.bottom, MSCRemoteStyle.spaceMD)

            // Auto-start toggle
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-start with server")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MSCRemoteStyle.textPrimary)
                    Text("Start broadcast when the server starts")
                        .font(.system(size: 11))
                        .foregroundStyle(MSCRemoteStyle.textTertiary)
                }
                Spacer()
                if isTogglingAutoStart {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Toggle("", isOn: Binding(
                        get: { vm.broadcastAutoStart ?? false },
                        set: { newValue in
                            Task { await setAutoStart(newValue) }
                        }
                    ))
                    .labelsHidden()
                    .tint(MSCRemoteStyle.accent)
                    .disabled(!isPaired || isTogglingAutoStart)
                }
            }
            .padding(.bottom, MSCRemoteStyle.spaceMD)

            // Start / Stop button
            Button {
                Task { await toggleBroadcast(wasRunning: running) }
            } label: {
                HStack(spacing: 6) {
                    if isBroadcastActioning {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: running ? "stop.fill" : "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Text(running ? "Stop Broadcast" : "Start Broadcast")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .foregroundStyle(running ? .white : MSCRemoteStyle.bgBase)
                .background(running ? MSCRemoteStyle.danger : MSCRemoteStyle.accent)
                .clipShape(RoundedRectangle(cornerRadius: MSCRemoteStyle.radiusSM, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!isPaired || isBroadcastActioning)
            .padding(.bottom, MSCRemoteStyle.spaceSM)

            // Re-authenticate button (restarts broadcast to trigger a new device code)
            Button {
                Task { await reAuthenticate() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.badge.key")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Re-authenticate with Microsoft")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .foregroundStyle(MSCRemoteStyle.textSecondary)
                .background(MSCRemoteStyle.bgElevated)
                .clipShape(RoundedRectangle(cornerRadius: MSCRemoteStyle.radiusSM, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: MSCRemoteStyle.radiusSM, style: .continuous)
                        .strokeBorder(MSCRemoteStyle.borderMid, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(!isPaired || isBroadcastActioning)
        }
        .mscCard()
    }

    // MARK: - Actions

    private func refresh() async {
        guard let baseURL = resolvedBaseURL, let token = resolvedToken else { return }
        isRefreshing = true
        await vm.fetchComponentsAndBroadcast(baseURL: baseURL, token: token)
        isRefreshing = false
    }

    private func updateComponent(_ component: ComponentStatusDTO) async {
        guard let baseURL = resolvedBaseURL, let token = resolvedToken else { return }
        updatingComponent = component.name
        vm.updateCredentials(baseURL: baseURL, token: token)
        do {
            let client = try vm.requireClient()
            let result = try await client.updateComponent(component.name.lowercased())
            showUpdateToast(result.success ? result.message : "Failed: \(result.message)")
            if result.success {
                await vm.fetchComponentsAndBroadcast(baseURL: baseURL, token: token)
            }
        } catch {
            showUpdateToast("Error: \(error.localizedDescription)")
        }
        updatingComponent = nil
    }

    private func toggleBroadcast(wasRunning: Bool) async {
        guard let baseURL = resolvedBaseURL, let token = resolvedToken else { return }
        isBroadcastActioning = true
        vm.updateCredentials(baseURL: baseURL, token: token)
        if wasRunning {
            _ = try? await vm.requireClient().stopBroadcast()
        } else {
            _ = try? await vm.requireClient().startBroadcast()
        }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        await vm.fetchComponentsAndBroadcast(baseURL: baseURL, token: token)
        isBroadcastActioning = false
    }

    private func setAutoStart(_ enabled: Bool) async {
        guard let baseURL = resolvedBaseURL, let token = resolvedToken else { return }
        isTogglingAutoStart = true
        vm.updateCredentials(baseURL: baseURL, token: token)
        _ = try? await vm.requireClient().setBroadcastAutoStart(enabled: enabled)
        vm.broadcastAutoStart = enabled  // optimistic update
        isTogglingAutoStart = false
    }

    private func reAuthenticate() async {
        guard let baseURL = resolvedBaseURL, let token = resolvedToken else { return }
        isBroadcastActioning = true
        vm.updateCredentials(baseURL: baseURL, token: token)
        _ = try? await vm.requireClient().stopBroadcast()
        try? await Task.sleep(nanoseconds: 500_000_000)
        _ = try? await vm.requireClient().startBroadcast()
        isBroadcastActioning = false
        // The polling loop will pick up the new auth prompt within a few seconds
    }

    private func showUpdateToast(_ text: String) {
        withAnimation { updateToast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation { updateToast = nil }
        }
    }

    private var footerText: some View {
        Text("TempleTech · MSC REMOTE")
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .foregroundStyle(MSCRemoteStyle.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

import SwiftUI
import Combine

struct DashboardView: View {
    var navigateToHealth: (() -> Void)? = nil

    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var vm: DashboardViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selectedServerId: String = ""
    @State private var showDangerConfirm: Bool = false
    @State private var dangerCommandToConfirm: String = ""
    @State private var showSetActiveConfirm: Bool = false
    @State private var pendingActiveServerId: String = ""
    @State private var suppressServerSelectionPrompt: Bool = false
    @State private var performancePollTask: Task<Void, Never>? = nil
    @State private var connectivityPollTask: Task<Void, Never>? = nil
    @State private var showQuickGuide: Bool = false
    @State private var showManageServers: Bool = false

    @State private var showRAMLine: Bool = false
    @State private var now: Date = Date()
    @State private var serverStartedAt: Date? = nil
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var isIPad: Bool { horizontalSizeClass == .regular }
    private var metricColumnCount: Int { isIPad ? 3 : 2 }
    private var horizontalPadding: CGFloat { isIPad ? MSCRemoteStyle.iPadContentPadding : MSCRemoteStyle.spaceLG }

    private var resolvedBaseURL: URL? { settings.resolvedBaseURL() }
    private var resolvedToken: String? { settings.resolvedToken() }
    private var isPaired: Bool { resolvedBaseURL != nil && resolvedToken != nil }
    private var isRunning: Bool { vm.status?.running == true }

    private var perfAgeLabel: String? {
        guard let ts = vm.performanceLatest?.timestamp else { return nil }
        let secs = Int(now.timeIntervalSince(ts))
        if secs < 5  { return "just now" }
        if secs < 100 { return "\(secs)s ago" }
        return ">99s ago"
    }

    private var activeServerNameText: String {
        guard isPaired else { return "—" }
        if let activeId = vm.status?.activeServerId,
           let name = vm.servers.first(where: { $0.id == activeId })?.name { return name }
        if !selectedServerId.isEmpty,
           let name = vm.servers.first(where: { $0.id == selectedServerId })?.name { return name }
        return vm.servers.isEmpty ? "Loading…" : "Unknown"
    }

    private var activeServerType: ServerType {
        let resolveId = vm.status?.activeServerId ?? selectedServerId
        if let fromServers = vm.servers.first(where: { $0.id == resolveId })?.resolvedServerType {
            return fromServers
        }
        return vm.status?.resolvedServerType ?? .java
    }

    private var pendingActiveServerDisplayName: String {
        guard !pendingActiveServerId.isEmpty else { return "Unknown" }
        return vm.servers.first(where: { $0.id == pendingActiveServerId })?.name ?? "Unknown"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MSCRemoteStyle.bgBase.ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        scrollContent
                            .padding(.horizontal, horizontalPadding)
                            .padding(.top, MSCRemoteStyle.spaceMD)
                            .padding(.bottom, MSCRemoteStyle.spaceLG)
                            .frame(maxWidth: isIPad ? MSCRemoteStyle.contentMaxWidth : .infinity)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                    .refreshable { await refreshAll() }
                    footerText.padding(.vertical, MSCRemoteStyle.spaceMD)
                }
            }
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(MSCRemoteStyle.bgBase, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showQuickGuide = true } label: {
                        AppIconMark(size: 26)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Quick Guide")
                }
            }
            .sheet(isPresented: $showQuickGuide) { QuickGuideView() }
            .alert("Confirm Command", isPresented: $showDangerConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Send", role: .destructive) {
                    Task { await sendCommandString(dangerCommandToConfirm) }
                }
            } message: {
                Text("This command can disrupt the server or players:\n\n\(dangerCommandToConfirm)\n\nAre you sure?")
            }
            .alert("Set Active Server", isPresented: $showSetActiveConfirm) {
                Button("Cancel", role: .cancel) { revertSelectionToActive() }
                Button("Set Active") { Task { await confirmSetActiveServer() } }
            } message: {
                Text("Set \"\(pendingActiveServerDisplayName)\" as the active server?")
            }
            .task { await initialRefreshIfPossible() }
            .task(id: isPaired) {
                performancePollTask?.cancel()
                connectivityPollTask?.cancel()
                guard isPaired else { return }
                startPerformancePolling()
                startConnectivityPolling()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                guard isPaired else { return }
                Task { await refreshAll() }
            }
            .onDisappear {
                performancePollTask?.cancel()
                performancePollTask = nil
                connectivityPollTask?.cancel()
                connectivityPollTask = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                guard isPaired else { return }
                Task { await refreshAll() }
            }
            .onReceive(ticker) { date in
                now = date
            }
            .onChange(of: vm.servers) { _, _ in syncSelectionFromStatusOrFirst() }
            .onChange(of: vm.status?.activeServerId) { _, _ in syncSelectionFromStatusOrFirst() }
            .onChange(of: selectedServerId) { _, newValue in handleServerSelectionChanged(to: newValue) }
            .onChange(of: vm.status?.running) { _, running in
                if running == true, serverStartedAt == nil {
                    serverStartedAt = Date()
                } else if running == false {
                    serverStartedAt = nil
                }
            }
            .background(manageServersSheetAnchor)
        }
    }

    private var manageServersSheetAnchor: some View {
        Color.clear
            .sheet(isPresented: $showManageServers) {
                ManageServersSheet()
                    .environmentObject(settings)
                    .environmentObject(vm)
            }
    }

    @ViewBuilder
    private var scrollContent: some View {
        VStack(spacing: MSCRemoteStyle.spaceLG) {
            if isIPad {
                HStack(alignment: .top, spacing: MSCRemoteStyle.spaceLG) {
                    DashboardStatusCard(
                        isRunning: isRunning,
                        isPaired: isPaired,
                        activeServerNameText: activeServerNameText,
                        serverStartedAt: serverStartedAt,
                        now: now,
                        refreshAction: { Task { await refreshAll() } },
                        connectivity: vm.connectivityResponse
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    DashboardServerCard(
                        servers: vm.servers,
                        activeServerId: vm.status?.activeServerId ?? selectedServerId,
                        activeServerNameText: activeServerNameText,
                        activeServerType: activeServerType,
                        isPaired: isPaired,
                        isRunning: isRunning,
                        selectedServerId: $selectedServerId,
                        manageAction: { showManageServers = true },
                        startAction: { Task { await startServer() } },
                        stopAction: { Task { await stopServer() } }
                    )
                    .frame(maxWidth: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                DashboardStatusCard(
                    isRunning: isRunning,
                    isPaired: isPaired,
                    activeServerNameText: activeServerNameText,
                    serverStartedAt: serverStartedAt,
                    now: now,
                    refreshAction: { Task { await refreshAll() } },
                    connectivity: vm.connectivityResponse
                )
                DashboardServerCard(
                    servers: vm.servers,
                    activeServerId: vm.status?.activeServerId ?? selectedServerId,
                    activeServerNameText: activeServerNameText,
                    activeServerType: activeServerType,
                    isPaired: isPaired,
                    isRunning: isRunning,
                    selectedServerId: $selectedServerId,
                    manageAction: { showManageServers = true },
                    startAction: { Task { await startServer() } },
                    stopAction: { Task { await stopServer() } }
                )
            }

            if isPaired { serverSettingsLinkCard }
            if isPaired && vm.connectedRole == "admin" { usersLinkCard }

            DashboardPlayersCard(players: vm.players?.players ?? [], isRunning: isRunning)

            DashboardPerformanceCard(
                activeServerType: activeServerType,
                performanceLatest: vm.performanceLatest,
                performanceHistory: vm.performanceHistory,
                performanceErrorMessage: vm.performanceErrorMessage,
                errorMessage: vm.errorMessage,
                isRunning: isRunning,
                now: now,
                metricColumnCount: metricColumnCount,
                perfAgeLabel: perfAgeLabel
            )

            DashboardChartsCard(
                performanceHistory: vm.performanceHistory,
                showRAMLine: $showRAMLine,
                isIPad: isIPad
            )

            ComponentsStatusStripView(
                componentsStatus: vm.componentsStatus,
                broadcastStatus: vm.broadcastStatus,
                onTap: { navigateToHealth?() }
            )

            if settings.showJoinCard { JoinCardView() }
            if let err = vm.errorMessage, !err.isEmpty { errorBanner(err) }
        }
    }

    private var serverSettingsLinkCard: some View {
        NavigationLink {
            ServerSettingsView()
                .environmentObject(settings)
                .environmentObject(vm)
        } label: {
            HStack(spacing: MSCRemoteStyle.spaceMD) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18))
                    .foregroundStyle(MSCRemoteStyle.accent)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Server Settings")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(MSCRemoteStyle.textPrimary)
                    Text("Edit difficulty, players, MOTD, ports & more")
                        .font(.system(size: 12))
                        .foregroundStyle(MSCRemoteStyle.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MSCRemoteStyle.textTertiary)
                    .accessibilityHidden(true)
            }
            .mscCard()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var usersLinkCard: some View {
        NavigationLink {
            UsersView()
                .environmentObject(settings)
                .environmentObject(vm)
        } label: {
            HStack(spacing: MSCRemoteStyle.spaceMD) {
                Image(systemName: "person.2.badge.key.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(MSCRemoteStyle.accent)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Users & Access")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(MSCRemoteStyle.textPrimary)
                    Text("Manage shared access tokens and permissions")
                        .font(.system(size: 12))
                        .foregroundStyle(MSCRemoteStyle.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MSCRemoteStyle.textTertiary)
                    .accessibilityHidden(true)
            }
            .mscCard()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: MSCRemoteStyle.spaceMD) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(MSCRemoteStyle.danger)
                .accessibilityHidden(true)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(MSCRemoteStyle.danger)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .mscCard(padding: MSCRemoteStyle.spaceMD)
        .overlay(
            RoundedRectangle(cornerRadius: MSCRemoteStyle.radiusMD, style: .continuous)
                .strokeBorder(MSCRemoteStyle.danger.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }

    private var footerText: some View {
        Text("TempleTech · MSC REMOTE")
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .foregroundStyle(MSCRemoteStyle.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private func initialRefreshIfPossible() async {
        guard isPaired else { return }
        await refreshAll()
        syncSelectionFromStatusOrFirst()
    }
    private func refreshAll() async {
        guard let baseURL = resolvedBaseURL, let token = resolvedToken else {
            vm.errorMessage = "Set Base URL + Token in Settings first."
            return
        }
        await vm.refreshAll(baseURL: baseURL, token: token, tailN: 200)
        syncSelectionFromStatusOrFirst()
    }
    private func refreshUntilRunningState(expectedRunning: Bool) async {
        for _ in 0..<6 {
            await refreshAll()
            if vm.status?.running == expectedRunning { return }
            try? await Task.sleep(nanoseconds: 700_000_000)
        }
    }
    private func startPerformancePolling() {
        guard let baseURL = resolvedBaseURL, let token = resolvedToken else { return }
        performancePollTask = Task {
            while !Task.isCancelled {
                await vm.fetchPerformanceSnapshot(baseURL: baseURL, token: token)
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }
    /// Connectivity runs a live external reachability probe (~10s on the Mac), so it polls on a
    /// slower cadence than performance and stays out of the main refresh path.
    private func startConnectivityPolling() {
        guard let baseURL = resolvedBaseURL, let token = resolvedToken else { return }
        connectivityPollTask = Task {
            while !Task.isCancelled {
                await vm.fetchConnectivity(baseURL: baseURL, token: token)
                try? await Task.sleep(nanoseconds: 20_000_000_000)
            }
        }
    }
    private func setSelectionSilently(_ serverId: String) {
        suppressServerSelectionPrompt = true
        selectedServerId = serverId
        DispatchQueue.main.async { suppressServerSelectionPrompt = false }
    }
    private func syncSelectionFromStatusOrFirst() {
        if let active = vm.status?.activeServerId, vm.servers.contains(where: { $0.id == active }) {
            setSelectionSilently(active); return
        }
        if selectedServerId.isEmpty, let first = vm.servers.first { setSelectionSilently(first.id) }
    }
    private func handleServerSelectionChanged(to newServerId: String) {
        guard !suppressServerSelectionPrompt, isPaired, !newServerId.isEmpty else { return }
        guard vm.connectedRole != "guest" else { revertSelectionToActive(); return }
        let activeId = vm.status?.activeServerId ?? ""
        guard newServerId != activeId else { return }
        pendingActiveServerId = newServerId
        showSetActiveConfirm = true
    }
    private func revertSelectionToActive() {
        let activeId = vm.status?.activeServerId ?? ""
        guard !activeId.isEmpty else { return }
        setSelectionSilently(activeId)
    }
    private func confirmSetActiveServer() async {
        let serverId = pendingActiveServerId
        guard !serverId.isEmpty, let baseURL = resolvedBaseURL, let token = resolvedToken else {
            revertSelectionToActive(); return
        }
        let ok = await vm.setActiveServer(baseURL: baseURL, token: token, serverId: serverId)
        if ok { await refreshAll() } else { revertSelectionToActive() }
    }
    private func startServer() async {
        guard let baseURL = resolvedBaseURL, let token = resolvedToken else { return }
        let ok = await vm.start(baseURL: baseURL, token: token)
        if ok { hapticSuccess(); await refreshUntilRunningState(expectedRunning: true) } else { hapticError() }
    }
    private func stopServer() async {
        guard let baseURL = resolvedBaseURL, let token = resolvedToken else { return }
        let ok = await vm.stop(baseURL: baseURL, token: token)
        if ok { hapticSuccess(); await refreshUntilRunningState(expectedRunning: false) } else { hapticError() }
    }
    private func sendCommandString(_ cmd: String) async {
        guard let baseURL = resolvedBaseURL, let token = resolvedToken else { return }
        let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let ok = await vm.sendCommand(baseURL: baseURL, token: token, command: trimmed)
        if ok { hapticSuccess(); await refreshAll() } else { hapticError() }
    }
}

private struct ManageServersSheet: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var vm: DashboardViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var serverToRename: ServerDTO? = nil
    @State private var renameText: String = ""
    @State private var serverToDelete: ServerDTO? = nil
    @State private var mutatingServerId: String? = nil
    @State private var toastMessage: String? = nil
    @State private var showTemplates: Bool = false
    @State private var showImport: Bool = false

    private var resolvedBaseURL: URL? { settings.resolvedBaseURL() }
    private var resolvedToken: String? { settings.resolvedToken() }
    private var isAdmin: Bool { vm.connectedRole == "admin" }
    private var activeServerId: String { vm.status?.activeServerId ?? "" }

    var body: some View {
        NavigationStack {
            ZStack {
                MSCRemoteStyle.bgBase.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: MSCRemoteStyle.spaceLG) {
                        serversCard
                        lifecycleCard
                    }
                    .padding(.horizontal, MSCRemoteStyle.spaceLG)
                    .padding(.top, MSCRemoteStyle.spaceMD)
                    .padding(.bottom, MSCRemoteStyle.spaceLG)
                    .frame(maxWidth: MSCRemoteStyle.contentMaxWidth)
                    .frame(maxWidth: .infinity)
                }
                .refreshable { await refreshServers() }

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
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: toastMessage)
                }
            }
            .navigationTitle("Manage Servers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(MSCRemoteStyle.bgBase, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(MSCRemoteStyle.accent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await refreshServers() } } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(MSCRemoteStyle.accent)
                    }
                    .disabled(resolvedBaseURL == nil || resolvedToken == nil)
                    .accessibilityLabel("Refresh servers")
                }
            }
            .task { await refreshServers() }
            .background(renameAlertAnchor)
            .background(deleteAlertAnchor)
            .background(templatesSheetAnchor)
            .background(importSheetAnchor)
        }
    }

    private var serversCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            MSCSectionHeader(title: "SERVERS", trailing: "\(vm.servers.count)")
                .padding(.bottom, MSCRemoteStyle.spaceMD)

            if vm.servers.isEmpty {
                Text("No servers found.")
                    .font(.system(size: 13))
                    .foregroundStyle(MSCRemoteStyle.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, MSCRemoteStyle.spaceLG)
            } else {
                ForEach(vm.servers) { server in
                    serverRow(server)
                    if server.id != vm.servers.last?.id {
                        Divider().background(MSCRemoteStyle.borderSubtle)
                    }
                }
            }
        }
        .mscCard()
    }

    private var lifecycleCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            MSCSectionHeader(title: "LIFECYCLE")
                .padding(.bottom, MSCRemoteStyle.spaceMD)

            openSheetRow(icon: "shippingbox", title: "Templates",
                         detail: "Export reusable JARs and create servers from templates.") {
                hapticLight()
                showTemplates = true
            }

            Divider().background(MSCRemoteStyle.borderSubtle)

            openSheetRow(icon: "square.and.arrow.down.on.square", title: "Import / Transfer",
                         detail: "Import a server folder, zip archive, or transfer package.") {
                hapticLight()
                showImport = true
            }
        }
        .mscCard()
    }

    private func openSheetRow(icon: String, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: MSCRemoteStyle.spaceMD) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(MSCRemoteStyle.accent)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MSCRemoteStyle.textPrimary)
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(MSCRemoteStyle.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MSCRemoteStyle.textTertiary)
            }
            .padding(.vertical, MSCRemoteStyle.spaceSM)
        }
        .buttonStyle(.plain)
    }

    private func serverRow(_ server: ServerDTO) -> some View {
        let isActive = server.id == activeServerId
        let isBusy = mutatingServerId == server.id

        return HStack(spacing: MSCRemoteStyle.spaceMD) {
            Image(systemName: server.resolvedServerType.iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isActive ? MSCRemoteStyle.accent : MSCRemoteStyle.textTertiary)
                .frame(width: 28)

            Button {
                guard isAdmin, !isBusy else { return }
                hapticLight()
                renameText = server.name
                serverToRename = server
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: MSCRemoteStyle.spaceSM) {
                        Text(server.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(MSCRemoteStyle.textPrimary)
                            .lineLimit(1)
                        if isActive {
                            Text("ACTIVE")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(MSCRemoteStyle.accent)
                                .padding(.horizontal, MSCRemoteStyle.spaceSM)
                                .padding(.vertical, 3)
                                .background(MSCRemoteStyle.accentDim)
                                .clipShape(Capsule())
                        }
                    }
                    Text(server.resolvedServerType.displayName)
                        .font(.system(size: 12))
                        .foregroundStyle(MSCRemoteStyle.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isAdmin || isBusy)

            if isBusy {
                ProgressView().scaleEffect(0.8)
            } else if isAdmin {
                HStack(spacing: MSCRemoteStyle.spaceSM) {
                    Button {
                        hapticLight()
                        renameText = server.name
                        serverToRename = server
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(MSCRemoteStyle.accent)
                            .frame(width: 32, height: 32)
                            .background(MSCRemoteStyle.bgElevated)
                            .clipShape(RoundedRectangle(cornerRadius: MSCRemoteStyle.radiusSM, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Rename \(server.name)")

                    Button {
                        hapticLight()
                        serverToDelete = server
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(MSCRemoteStyle.danger)
                            .frame(width: 32, height: 32)
                            .background(MSCRemoteStyle.bgElevated)
                            .clipShape(RoundedRectangle(cornerRadius: MSCRemoteStyle.radiusSM, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete \(server.name)")
                }
            }
        }
        .padding(.vertical, MSCRemoteStyle.spaceSM)
    }

    private var renameAlertAnchor: some View {
        Color.clear
            .alert("Rename Server", isPresented: Binding(
                get: { serverToRename != nil },
                set: { if !$0 { serverToRename = nil } }
            )) {
                TextField("Server name", text: $renameText)
                Button("Cancel", role: .cancel) { serverToRename = nil }
                Button("Rename") {
                    guard let server = serverToRename else { return }
                    let newName = renameText
                    serverToRename = nil
                    Task { await performRename(server: server, name: newName) }
                }
            } message: {
                Text("Enter a new name for this server.")
            }
    }

    private var deleteAlertAnchor: some View {
        Color.clear
            .alert("Delete Server", isPresented: Binding(
                get: { serverToDelete != nil },
                set: { if !$0 { serverToDelete = nil } }
            )) {
                Button("Cancel", role: .cancel) { serverToDelete = nil }
                Button("Delete", role: .destructive) {
                    guard let server = serverToDelete else { return }
                    serverToDelete = nil
                    Task { await performDelete(server: server) }
                }
            } message: {
                if let server = serverToDelete {
                    Text("Delete \(server.name)? This will remove it from the server list.")
                }
            }
    }

    private var templatesSheetAnchor: some View {
        Color.clear
            .sheet(isPresented: $showTemplates) {
                ServerTemplatesSheet()
                    .environmentObject(settings)
                    .environmentObject(vm)
            }
    }

    private var importSheetAnchor: some View {
        Color.clear
            .sheet(isPresented: $showImport) {
                ServerImportSheet()
                    .environmentObject(settings)
                    .environmentObject(vm)
            }
    }

    private func refreshServers() async {
        guard let baseURL = resolvedBaseURL, let token = resolvedToken else { return }
        async let r: () = vm.refreshAll(baseURL: baseURL, token: token, tailN: 200)
        async let t: () = vm.fetchTemplates(baseURL: baseURL, token: token)
        _ = await (r, t)
    }

    private func performRename(server: ServerDTO, name: String) async {
        guard let baseURL = resolvedBaseURL, let token = resolvedToken else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            hapticError()
            showToast("Enter a server name.")
            return
        }
        mutatingServerId = server.id
        let error = await vm.renameServer(baseURL: baseURL, token: token, serverId: server.id, name: trimmed)
        mutatingServerId = nil
        if let error {
            hapticError()
            showToast(error)
        } else {
            hapticSuccess()
            showToast("Renamed to \"\(trimmed)\".")
        }
    }

    private func performDelete(server: ServerDTO) async {
        guard let baseURL = resolvedBaseURL, let token = resolvedToken else { return }
        mutatingServerId = server.id
        let error = await vm.deleteServer(baseURL: baseURL, token: token, serverId: server.id)
        mutatingServerId = nil
        if let error {
            hapticError()
            showToast(error)
        } else {
            hapticSuccess()
            showToast("Removed \"\(server.name)\".")
            await refreshServers()
        }
    }

    private func showToast(_ message: String) {
        withAnimation { toastMessage = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { toastMessage = nil }
        }
    }
}

private struct ServerTemplatesSheet: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var vm: DashboardViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTemplateId: String? = nil
    @State private var newServerName: String = ""
    @State private var javaPort: String = "25565"
    @State private var enableCrossPlay: Bool = false
    @State private var crossPlayPort: String = "19132"
    @State private var enablePlayit: Bool = false
    @State private var acceptEula: Bool = false
    @State private var difficulty: String = "normal"
    @State private var gamemode: String = "survival"
    @State private var worldName: String = ""
    @State private var worldSeed: String = ""
    @State private var includePlugins: Bool = true
    @State private var isWorking: Bool = false
    @State private var toastMessage: String? = nil

    private var resolvedBaseURL: URL? { settings.resolvedBaseURL() }
    private var resolvedToken: String? { settings.resolvedToken() }
    private var isAdmin: Bool { vm.connectedRole == "admin" }
    private var paperTemplates: [TemplateItemDTO] { vm.templatesResponse?.paperTemplates ?? [] }
    private var pluginTemplates: [TemplateItemDTO] { vm.templatesResponse?.pluginTemplates ?? [] }
    private var selectedTemplate: TemplateItemDTO? { paperTemplates.first { $0.id == selectedTemplateId } }

    var body: some View {
        NavigationStack {
            ZStack {
                MSCRemoteStyle.bgBase.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: MSCRemoteStyle.spaceLG) {
                        exportCard
                        libraryCard
                        createCard
                    }
                    .padding(.horizontal, MSCRemoteStyle.spaceLG)
                    .padding(.top, MSCRemoteStyle.spaceMD)
                    .padding(.bottom, MSCRemoteStyle.spaceLG)
                    .frame(maxWidth: MSCRemoteStyle.contentMaxWidth)
                    .frame(maxWidth: .infinity)
                }
                .refreshable { await refresh() }
                toastOverlay
            }
            .navigationTitle("Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(MSCRemoteStyle.bgBase, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(MSCRemoteStyle.accent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await refresh() } } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(MSCRemoteStyle.accent)
                    }
                }
            }
            .task { await refresh() }
        }
    }

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            MSCSectionHeader(title: "EXPORT ACTIVE SERVER")
                .padding(.bottom, MSCRemoteStyle.spaceMD)
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(vm.templatesResponse?.serverName ?? "Active server")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MSCRemoteStyle.textPrimary)
                    Text("Save its server JAR and plugin JARs into the Mac template library.")
                        .font(.system(size: 12))
                        .foregroundStyle(MSCRemoteStyle.textSecondary)
                }
                Spacer()
                Toggle("", isOn: $includePlugins)
                    .labelsHidden()
                    .tint(MSCRemoteStyle.accent)
                    .disabled(!isAdmin || isWorking)
                    .accessibilityLabel("Include plugin JARs")
            }
            .padding(.bottom, MSCRemoteStyle.spaceMD)

            actionButton(title: isWorking ? "Working…" : "Export Templates",
                         icon: "square.and.arrow.up",
                         enabled: isAdmin && !isWorking) {
                Task { await performExport() }
            }
        }
        .mscCard()
    }

    private var libraryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            MSCSectionHeader(title: "SERVER JAR TEMPLATES", trailing: "\(paperTemplates.count)")
                .padding(.bottom, MSCRemoteStyle.spaceMD)
            if paperTemplates.isEmpty {
                emptyText("No server JAR templates found.")
            } else {
                ForEach(paperTemplates) { item in
                    templateRow(item)
                    if item.id != paperTemplates.last?.id { Divider().background(MSCRemoteStyle.borderSubtle) }
                }
            }
            if !pluginTemplates.isEmpty {
                Divider().background(MSCRemoteStyle.borderSubtle).padding(.vertical, MSCRemoteStyle.spaceMD)
                MSCSectionHeader(title: "PLUGIN TEMPLATES", trailing: "\(pluginTemplates.count)")
                    .padding(.bottom, MSCRemoteStyle.spaceSM)
                ForEach(pluginTemplates.prefix(6)) { item in
                    HStack {
                        Text(item.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(MSCRemoteStyle.textSecondary)
                            .lineLimit(1)
                        Spacer()
                        Text(item.filename)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(MSCRemoteStyle.textTertiary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, MSCRemoteStyle.spaceXS)
                }
            }
        }
        .mscCard()
    }

    private var createCard: some View {
        VStack(alignment: .leading, spacing: MSCRemoteStyle.spaceMD) {
            MSCSectionHeader(title: "CREATE FROM TEMPLATE")
            labeledField("Server Name", text: $newServerName, placeholder: "New Paper Server")
            labeledField("Java Port", text: $javaPort, placeholder: "25565", keyboard: .numberPad)
            labeledField("World Name", text: $worldName, placeholder: "Optional")
            labeledField("World Seed", text: $worldSeed, placeholder: "Optional")

            Picker("", selection: $difficulty) {
                Text("Peaceful").tag("peaceful")
                Text("Easy").tag("easy")
                Text("Normal").tag("normal")
                Text("Hard").tag("hard")
            }
            .pickerStyle(.segmented)
            .tint(MSCRemoteStyle.accent)

            Picker("", selection: $gamemode) {
                Text("Survival").tag("survival")
                Text("Creative").tag("creative")
                Text("Adventure").tag("adventure")
            }
            .pickerStyle(.segmented)
            .tint(MSCRemoteStyle.accent)

            toggleRow(title: "Bedrock Cross-play", detail: "Copy Geyser and Floodgate plugin templates into the new server.", isOn: $enableCrossPlay)
            if enableCrossPlay {
                labeledField("Bedrock Port", text: $crossPlayPort, placeholder: "19132", keyboard: .numberPad)
            }
            toggleRow(title: "Enable playit", detail: "Start with playit enabled in the new server config.", isOn: $enablePlayit)
            toggleRow(title: "Accept EULA", detail: "Write eula=true after creation.", isOn: $acceptEula)

            actionButton(title: isWorking ? "Creating…" : "Create Server",
                         icon: "plus",
                         enabled: isAdmin && !isWorking && selectedTemplate != nil) {
                Task { await performCreate() }
            }
        }
        .mscCard()
    }

    private func templateRow(_ item: TemplateItemDTO) -> some View {
        let selected = item.id == selectedTemplateId
        return Button {
            hapticLight()
            selectedTemplateId = item.id
        } label: {
            HStack(spacing: MSCRemoteStyle.spaceMD) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected ? MSCRemoteStyle.accent : MSCRemoteStyle.textTertiary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MSCRemoteStyle.textPrimary)
                        .lineLimit(1)
                    Text(item.filename)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(MSCRemoteStyle.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.vertical, MSCRemoteStyle.spaceSM)
        }
        .buttonStyle(.plain)
    }

    private func performExport() async {
        guard let baseURL = resolvedBaseURL, let token = resolvedToken else { return }
        hapticLight()
        isWorking = true
        let error = await vm.exportServerTemplate(baseURL: baseURL, token: token, serverId: vm.status?.activeServerId, includePlugins: includePlugins)
        isWorking = false
        if let error {
            hapticError()
            showToast(error)
        } else {
            hapticSuccess()
            showToast("Templates exported.")
        }
    }

    private func performCreate() async {
        guard let baseURL = resolvedBaseURL, let token = resolvedToken, let selectedTemplate else { return }
        let name = newServerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { hapticError(); showToast("Enter a server name."); return }
        hapticLight()
        isWorking = true
        let error = await vm.createServerFromTemplate(
            baseURL: baseURL,
            token: token,
            name: name,
            templateId: selectedTemplate.id,
            port: Int(javaPort) ?? 25565,
            enableCrossPlay: enableCrossPlay,
            crossPlayBedrockPort: Int(crossPlayPort) ?? 19132,
            enablePlayit: enablePlayit,
            difficulty: difficulty,
            gamemode: gamemode,
            worldName: worldName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            worldSeed: worldSeed.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            acceptEula: acceptEula
        )
        isWorking = false
        if let error {
            hapticError()
            showToast(error)
        } else {
            hapticSuccess()
            showToast("Server created.")
        }
    }

    private func refresh() async {
        guard let baseURL = resolvedBaseURL, let token = resolvedToken else { return }
        await vm.fetchTemplates(baseURL: baseURL, token: token)
        if selectedTemplateId == nil { selectedTemplateId = paperTemplates.first?.id }
    }

    private var toastOverlay: some View {
        Group {
            if let toastMessage {
                VStack {
                    Spacer()
                    Text(toastMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MSCRemoteStyle.textPrimary)
                        .padding(.horizontal, MSCRemoteStyle.spaceLG)
                        .padding(.vertical, MSCRemoteStyle.spaceMD)
                        .background(MSCRemoteStyle.bgElevated)
                        .clipShape(Capsule())
                        .padding(.bottom, MSCRemoteStyle.spaceLG)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func showToast(_ message: String) {
        withAnimation { toastMessage = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { toastMessage = nil }
        }
    }
}

private struct ServerImportSheet: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var vm: DashboardViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var sourcePath: String = ""
    @State private var importKind: String = "folder"
    @State private var displayName: String = ""
    @State private var portText: String = ""
    @State private var maxPlayersText: String = ""
    @State private var activeWorldName: String = ""
    @State private var acceptEula: Bool = false
    @State private var enablePlayit: Bool = false
    @State private var replaceAll: Bool = false
    @State private var backupPath: String = ""
    @State private var isWorking: Bool = false
    @State private var toastMessage: String? = nil

    private var resolvedBaseURL: URL? { settings.resolvedBaseURL() }
    private var resolvedToken: String? { settings.resolvedToken() }
    private var isAdmin: Bool { vm.connectedRole == "admin" }
    private var scan: ServerImportScanResponseDTO? { vm.serverImportScanResponse }

    var body: some View {
        NavigationStack {
            ZStack {
                MSCRemoteStyle.bgBase.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: MSCRemoteStyle.spaceLG) {
                        sourceCard
                        if importKind == "transfer" { transferCard }
                        else if let scan { scanCard(scan) }
                    }
                    .padding(.horizontal, MSCRemoteStyle.spaceLG)
                    .padding(.top, MSCRemoteStyle.spaceMD)
                    .padding(.bottom, MSCRemoteStyle.spaceLG)
                    .frame(maxWidth: MSCRemoteStyle.contentMaxWidth)
                    .frame(maxWidth: .infinity)
                }
                toastOverlay
            }
            .navigationTitle("Import / Transfer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(MSCRemoteStyle.bgBase, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(MSCRemoteStyle.accent)
                }
            }
        }
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: MSCRemoteStyle.spaceMD) {
            MSCSectionHeader(title: "SOURCE ON MAC")
            labeledField("Path", text: $sourcePath, placeholder: "/Users/me/Downloads/server.zip")
            Picker("", selection: $importKind) {
                Text("Folder").tag("folder")
                Text("Zip").tag("zip")
                Text("Transfer").tag("transfer")
            }
            .pickerStyle(.segmented)
            .tint(MSCRemoteStyle.accent)
            if importKind != "transfer" {
                actionButton(title: isWorking ? "Scanning…" : "Scan Server",
                             icon: "doc.text.magnifyingglass",
                             enabled: isAdmin && !isWorking && !sourcePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    Task { await performScan() }
                }
            }
        }
        .mscCard()
    }

    private func scanCard(_ scan: ServerImportScanResponseDTO) -> some View {
        VStack(alignment: .leading, spacing: MSCRemoteStyle.spaceMD) {
            MSCSectionHeader(title: "IMPORT SERVER")
            HStack {
                MSCStatusDot(isActive: true)
                Text(scan.serverType?.displayName ?? "Server")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MSCRemoteStyle.textPrimary)
                Spacer()
                Text(scan.eulaAccepted == true ? "EULA accepted" : "EULA needed")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(scan.eulaAccepted == true ? MSCRemoteStyle.success : MSCRemoteStyle.warning)
            }
            labeledField("Display Name", text: $displayName, placeholder: "Imported Server")
            labeledField("Port", text: $portText, placeholder: "25565", keyboard: .numberPad)
            labeledField("Max Players", text: $maxPlayersText, placeholder: "20", keyboard: .numberPad)
            labeledField("Active World", text: $activeWorldName, placeholder: scan.defaultWorldName ?? "world")
            toggleRow(title: "Accept EULA", detail: "Write eula=true during import.", isOn: $acceptEula)
            toggleRow(title: "Enable playit", detail: "Turn on playit for this imported server.", isOn: $enablePlayit)
            if let worlds = scan.worlds, !worlds.isEmpty {
                Divider().background(MSCRemoteStyle.borderSubtle)
                ForEach(worlds.prefix(4)) { world in
                    HStack {
                        Text(world.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(MSCRemoteStyle.textSecondary)
                        Spacer()
                        Text(world.dimensionsLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(MSCRemoteStyle.textTertiary)
                    }
                }
            }
            actionButton(title: isWorking ? "Importing…" : "Import Server",
                         icon: "square.and.arrow.down",
                         enabled: isAdmin && !isWorking) {
                Task { await performExistingImport() }
            }
        }
        .mscCard()
    }

    private var transferCard: some View {
        VStack(alignment: .leading, spacing: MSCRemoteStyle.spaceMD) {
            MSCSectionHeader(title: "TRANSFER PACKAGE")
            toggleRow(title: "Replace all servers", detail: "Requires a backup path before import.", isOn: $replaceAll)
            if replaceAll {
                labeledField("Backup Path", text: $backupPath, placeholder: "/Users/me/Desktop/MSC-backup.msctransfer")
            }
            actionButton(title: isWorking ? "Importing…" : "Import Transfer",
                         icon: "archivebox",
                         enabled: isAdmin && !isWorking && !sourcePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                Task { await performTransferImport() }
            }
        }
        .mscCard()
    }

    private func performScan() async {
        guard let baseURL = resolvedBaseURL, let token = resolvedToken else { return }
        hapticLight()
        isWorking = true
        let error = await vm.scanServerImport(baseURL: baseURL, token: token, sourcePath: sourcePath, importKind: importKind)
        isWorking = false
        if let error {
            hapticError()
            showToast(error)
        } else if let scan = vm.serverImportScanResponse {
            hapticSuccess()
            displayName = displayName.isEmpty ? URL(fileURLWithPath: sourcePath).deletingPathExtension().lastPathComponent : displayName
            portText = String(scan.port ?? (scan.serverType == .bedrock ? 19132 : 25565))
            maxPlayersText = String(scan.maxPlayers ?? 20)
            activeWorldName = scan.defaultWorldName ?? ""
            acceptEula = scan.eulaAccepted ?? false
            showToast("Scan complete.")
        }
    }

    private func performExistingImport() async {
        guard let baseURL = resolvedBaseURL, let token = resolvedToken, let scan else { return }
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { hapticError(); showToast("Enter a display name."); return }
        hapticLight()
        isWorking = true
        let error = await vm.importExistingServer(
            baseURL: baseURL,
            token: token,
            sourcePath: sourcePath,
            importKind: importKind,
            displayName: name,
            serverType: scan.serverType ?? .java,
            activeWorldName: activeWorldName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            port: Int(portText),
            maxPlayers: Int(maxPlayersText),
            acceptEula: acceptEula,
            enablePlayit: enablePlayit
        )
        isWorking = false
        if let error {
            hapticError()
            showToast(error)
        } else {
            hapticSuccess()
            showToast("Server imported.")
        }
    }

    private func performTransferImport() async {
        guard let baseURL = resolvedBaseURL, let token = resolvedToken else { return }
        hapticLight()
        isWorking = true
        let error = await vm.importTransferPackage(
            baseURL: baseURL,
            token: token,
            sourcePath: sourcePath,
            replaceAll: replaceAll,
            backupPath: replaceAll ? backupPath.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty : nil
        )
        isWorking = false
        if let error {
            hapticError()
            showToast(error)
        } else {
            hapticSuccess()
            showToast("Transfer imported.")
        }
    }

    private var toastOverlay: some View {
        Group {
            if let toastMessage {
                VStack {
                    Spacer()
                    Text(toastMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MSCRemoteStyle.textPrimary)
                        .padding(.horizontal, MSCRemoteStyle.spaceLG)
                        .padding(.vertical, MSCRemoteStyle.spaceMD)
                        .background(MSCRemoteStyle.bgElevated)
                        .clipShape(Capsule())
                        .padding(.bottom, MSCRemoteStyle.spaceLG)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func showToast(_ message: String) {
        withAnimation { toastMessage = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { toastMessage = nil }
        }
    }
}

private func labeledField(_ label: String, text: Binding<String>, placeholder: String, keyboard: UIKeyboardType = .default) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(MSCRemoteStyle.textTertiary)
        TextField(placeholder, text: text)
            .font(.system(size: 13))
            .foregroundStyle(MSCRemoteStyle.textPrimary)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(keyboard)
            .padding(.horizontal, MSCRemoteStyle.spaceMD)
            .padding(.vertical, 10)
            .background(MSCRemoteStyle.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: MSCRemoteStyle.radiusSM, style: .continuous))
            .accessibilityLabel(label)
    }
}

private func toggleRow(title: String, detail: String, isOn: Binding<Bool>) -> some View {
    HStack {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MSCRemoteStyle.textPrimary)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(MSCRemoteStyle.textTertiary)
        }
        Spacer()
        Toggle("", isOn: isOn)
            .labelsHidden()
            .tint(MSCRemoteStyle.accent)
            .accessibilityLabel(title)
            .accessibilityHint(detail)
    }
}

private func actionButton(title: String, icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(.system(size: 14, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .foregroundStyle(enabled ? MSCRemoteStyle.bgBase : MSCRemoteStyle.textTertiary)
        .background(enabled ? MSCRemoteStyle.accent : MSCRemoteStyle.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: MSCRemoteStyle.radiusSM, style: .continuous))
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
}

private func emptyText(_ message: String) -> some View {
    Text(message)
        .font(.system(size: 13))
        .foregroundStyle(MSCRemoteStyle.textTertiary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, MSCRemoteStyle.spaceLG)
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

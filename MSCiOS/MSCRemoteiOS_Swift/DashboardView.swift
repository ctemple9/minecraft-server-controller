import SwiftUI
import Combine

struct DashboardView: View {
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
    @State private var showQuickGuide: Bool = false

    @State private var showRAMLine: Bool = false
    @State private var now: Date = Date()
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

                ScrollView(showsIndicators: false) {
                    VStack(spacing: MSCRemoteStyle.spaceLG) {
                        if isIPad {
                            LazyVGrid(
                                columns: [GridItem(.flexible()), GridItem(.flexible())],
                                spacing: MSCRemoteStyle.spaceLG
                            ) {
                                DashboardStatusCard(
                                    isRunning: isRunning,
                                    isPaired: isPaired,
                                    activeServerNameText: activeServerNameText,
                                    refreshAction: { Task { await refreshAll() } }
                                )

                                DashboardServerCard(
                                    servers: vm.servers,
                                    activeServerId: vm.status?.activeServerId ?? selectedServerId,
                                    activeServerNameText: activeServerNameText,
                                    activeServerType: activeServerType,
                                    isPaired: isPaired,
                                    isRunning: isRunning,
                                    selectedServerId: $selectedServerId,
                                    startAction: { Task { await startServer() } },
                                    stopAction: { Task { await stopServer() } }
                                )
                            }
                        } else {
                            DashboardStatusCard(
                                isRunning: isRunning,
                                isPaired: isPaired,
                                activeServerNameText: activeServerNameText,
                                refreshAction: { Task { await refreshAll() } }
                            )

                            DashboardServerCard(
                                servers: vm.servers,
                                activeServerId: vm.status?.activeServerId ?? selectedServerId,
                                activeServerNameText: activeServerNameText,
                                activeServerType: activeServerType,
                                isPaired: isPaired,
                                isRunning: isRunning,
                                selectedServerId: $selectedServerId,
                                startAction: { Task { await startServer() } },
                                stopAction: { Task { await stopServer() } }
                            )
                        }

                        DashboardPlayersCard(
                            players: vm.players?.players ?? [],
                            isRunning: isRunning
                        )

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

                        if settings.showJoinCard {
                            JoinCardView()
                        }
                        if let err = vm.errorMessage, !err.isEmpty {
                            errorBanner(err)
                        }
                        footerText
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, MSCRemoteStyle.spaceMD)
                    .padding(.bottom, MSCRemoteStyle.space2XL)
                    .frame(maxWidth: isIPad ? MSCRemoteStyle.contentMaxWidth : .infinity)
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
                .refreshable { await refreshAll() }
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
                guard isPaired else { return }
                startPerformancePolling()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                guard isPaired else { return }
                Task { await refreshAll() }
            }
            .onDisappear {
                performancePollTask?.cancel()
                performancePollTask = nil
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
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: MSCRemoteStyle.spaceMD) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(MSCRemoteStyle.danger)
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
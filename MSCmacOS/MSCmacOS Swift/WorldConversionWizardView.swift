// WorldConversionWizardView.swift
// MinecraftServerController
//
// Multi-step sheet for converting a world between Java and Bedrock using Chunker CLI.
// Layout mirrors ServerHandbookView: left sidebar navigation + right scrollable content.

import SwiftUI

// MARK: - Wizard steps

private enum WizardStep: Int, CaseIterable {
    case preflight = 1
    case selectVersion
    case selectTargetServer
    case selectPlacement
    case summary
    case converting
    case done

    var title: String {
        switch self {
        case .preflight:          return "Check"
        case .selectVersion:      return "Target Version"
        case .selectTargetServer: return "Target Server"
        case .selectPlacement:    return "Placement"
        case .summary:            return "Summary"
        case .converting:         return "Converting"
        case .done:               return "Done"
        }
    }

    var icon: String {
        switch self {
        case .preflight:          return "checkmark.shield"
        case .selectVersion:      return "cube.transparent"
        case .selectTargetServer: return "server.rack"
        case .selectPlacement:    return "tray.and.arrow.down"
        case .summary:            return "list.bullet.clipboard"
        case .converting:         return "arrow.triangle.2.circlepath"
        case .done:               return "checkmark.circle"
        }
    }
}

// MARK: - Sidebar step state

private enum StepState { case upcoming, current, completed, failed }

// MARK: - Placement mode

private enum PlacementMode: Equatable {
    case newSlot
    case replaceExisting
}

// MARK: - WorldConversionWizardView

struct WorldConversionWizardView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Binding var isPresented: Bool

    let sourceSlot: WorldSlot
    let sourceServer: ConfigServer

    // MARK: Step state

    @State private var step: WizardStep = .preflight
    @State private var hasFailed = false
    @State private var failureMessage = ""

    // Preflight
    @State private var preflightItems: [(text: String, isError: Bool)] = []
    @State private var isDownloadingChunker = false
    @State private var downloadLog: [String] = []
    @State private var isLoadingFormats = false

    // Version
    @State private var availableFormats: [String] = []
    @State private var selectedFormat: String = ""
    @State private var detectedSourceLabel: String? = nil

    // Target server
    @State private var selectedTargetServer: ConfigServer? = nil

    // Placement
    @State private var placementMode: PlacementMode = .newSlot
    @State private var newSlotName: String = ""
    @State private var replaceTargetSlots: [WorldSlot] = []
    @State private var selectedReplaceSlot: WorldSlot? = nil

    // Converting
    @State private var progressLines: [String] = []

    // MARK: Computed

    private var targetEditionLabel: String { sourceServer.isBedrock ? "Java" : "Bedrock" }

    private var compatibleTargetServers: [ConfigServer] {
        viewModel.configServers.filter { s in
            s.id != sourceServer.id &&
            (sourceServer.isBedrock ? s.isJava : s.isBedrock)
        }
    }

    private var targetFormats: [String] {
        let prefix = sourceServer.isBedrock ? "JAVA_" : "BEDROCK_"
        return availableFormats.filter { $0.hasPrefix(prefix) }.reversed()
    }

    private var preflightHasErrors: Bool {
        preflightItems.contains { $0.isError }
    }

    private var chunkerNeedsDownload: Bool {
        !ChunkerManager.shared.isInstalled || isDownloadingChunker
    }

    // MARK: Body

    var body: some View {
        HStack(spacing: 0) {

            // ── Left sidebar ───────────────────────────────────────────────
            sidebar

            Divider()

            // ── Right content + footer ─────────────────────────────────────
            VStack(spacing: 0) {
                ScrollView {
                    stepContent
                        .padding(MSC.Spacing.xxl)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                Divider()
                navFooter
            }
        }
        .frame(minWidth: 760, idealWidth: 800, minHeight: 520, idealHeight: 600)
        .onAppear { runPreflight() }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Convert World")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                Text("\(sourceServer.isBedrock ? "Bedrock" : "Java") → \(targetEditionLabel)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, MSC.Spacing.lg)
            .padding(.top, MSC.Spacing.lg)
            .padding(.bottom, MSC.Spacing.md)

            Divider()

            // Step rows
            VStack(spacing: 2) {
                ForEach(WizardStep.allCases, id: \.rawValue) { s in
                    sidebarStepRow(s)
                }
            }
            .padding(.vertical, MSC.Spacing.sm)

            Spacer()

            // Source info footer
            VStack(alignment: .leading, spacing: 4) {
                Divider()
                VStack(alignment: .leading, spacing: 3) {
                    Text("SOURCE")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(1)
                    Text(sourceServer.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\"\(sourceSlot.name)\"")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, MSC.Spacing.lg)
                .padding(.vertical, MSC.Spacing.md)
            }
        }
        .frame(width: 190)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func sidebarStepRow(_ s: WizardStep) -> some View {
        let state = stepState(s)
        let isCurrent = s == step && !hasFailed
        let isCompleted = state == .completed
        let isFailed = hasFailed && s == step

        return HStack(spacing: 10) {
            // Step badge
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(badgeBackground(state: isFailed ? .failed : state))
                    .frame(width: 24, height: 24)
                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                } else if isFailed {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: s.icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isCurrent ? .white : .secondary)
                }
            }

            Text(s.title)
                .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent || isCompleted ? .primary : .secondary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, MSC.Spacing.md)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                .fill(isCurrent ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .padding(.horizontal, MSC.Spacing.xs)
    }

    private func stepState(_ s: WizardStep) -> StepState {
        if s.rawValue < step.rawValue { return .completed }
        if s == step { return hasFailed ? .failed : .current }
        return .upcoming
    }

    private func badgeBackground(state: StepState) -> Color {
        switch state {
        case .upcoming:   return Color.secondary.opacity(0.15)
        case .current:    return Color.accentColor
        case .completed:  return MSC.Colors.success
        case .failed:     return MSC.Colors.error
        }
    }

    // MARK: - Step content

    @ViewBuilder
    private var stepContent: some View {
        if hasFailed {
            failedContent(message: failureMessage)
        } else {
            switch step {
            case .preflight:          preflightContent
            case .selectVersion:      versionContent
            case .selectTargetServer: targetServerContent
            case .selectPlacement:    placementContent
            case .summary:            summaryContent
            case .converting:         convertingContent
            case .done:               doneContent
            }
        }
    }

    // MARK: Preflight

    private var preflightContent: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
            stepHeader(icon: "checkmark.shield", title: "Checking Requirements",
                       subtitle: "Making sure everything is in place before converting.", color: .blue)

            // Check list
            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                if preflightItems.isEmpty {
                    HStack(spacing: MSC.Spacing.sm) {
                        ProgressView().scaleEffect(0.7)
                        Text("Running checks…").font(MSC.Typography.caption).foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(preflightItems, id: \.text) { item in
                        HStack(alignment: .top, spacing: MSC.Spacing.sm) {
                            Image(systemName: item.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(item.isError ? MSC.Colors.error : MSC.Colors.success)
                                .font(.system(size: 14))
                            Text(item.text)
                                .font(.system(size: 12))
                                .foregroundStyle(.primary.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(MSC.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                    .fill(MSC.Colors.tierContent)
            )

            // Chunker download section
            if chunkerNeedsDownload {
                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.blue)
                        Text("Chunker CLI Required")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.blue)
                    }
                    Text("Chunker is a free, open-source Minecraft world converter by HiveGames. It will be downloaded from GitHub (~30 MB) and stored in Application Support.")
                        .font(.system(size: 12))
                        .foregroundStyle(.primary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)

                    if isDownloadingChunker {
                        HStack(spacing: MSC.Spacing.sm) {
                            ProgressView().scaleEffect(0.7)
                            Text(downloadLog.last ?? "Downloading…")
                                .font(MSC.Typography.caption).foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else {
                        Button("Download Chunker CLI") { downloadChunker() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(MSC.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                        .fill(Color.blue.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                        .stroke(Color.blue.opacity(0.18), lineWidth: 1)
                )
            }

            if isLoadingFormats {
                HStack(spacing: MSC.Spacing.sm) {
                    ProgressView().scaleEffect(0.7)
                    Text("Loading supported versions…").font(MSC.Typography.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Version

    private var versionContent: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
            stepHeader(icon: "cube.transparent", title: "Target Version",
                       subtitle: "Choose which \(targetEditionLabel) version to convert the world into.", color: .purple)

            if let sourceLabel = detectedSourceLabel {
                GuideCallout(style: .note,
                    text: "Chunker auto-detects the source format from the world data — you only need to select the target. Detected source: \(sourceLabel).")
            }

            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                Text("TARGET \(targetEditionLabel.uppercased()) VERSION")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary).tracking(1)

                if targetFormats.isEmpty {
                    Text("No \(targetEditionLabel) versions found in the installed Chunker jar. Try re-downloading Chunker.")
                        .font(MSC.Typography.caption).foregroundStyle(MSC.Colors.warning)
                } else {
                    Picker("", selection: $selectedFormat) {
                        ForEach(targetFormats, id: \.self) { fmt in
                            Text(ChunkerManager.shared.displayName(forFormat: fmt)).tag(fmt)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 260)
                }
            }
            .padding(MSC.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).fill(MSC.Colors.tierContent))

            GuideCallout(style: .tip,
                text: "Pick the version that matches your target server. Newer versions include more blocks and biomes but require that version's Chunker support.")
        }
    }

    // MARK: Target server

    private var targetServerContent: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
            stepHeader(icon: "server.rack", title: "Target \(targetEditionLabel) Server",
                       subtitle: "The converted world will be placed on this server.", color: .orange)

            if compatibleTargetServers.isEmpty {
                VStack(spacing: MSC.Spacing.md) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 32)).foregroundStyle(.secondary)
                    Text("No \(targetEditionLabel) Servers Found")
                        .font(MSC.Typography.sectionHeader)
                    Text("Create a \(targetEditionLabel) server first, then return to this conversion.")
                        .font(MSC.Typography.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Create \(targetEditionLabel) Server") {
                        isPresented = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            viewModel.isShowingCreateServer = true
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding(MSC.Spacing.xl)
                .background(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).fill(MSC.Colors.tierContent))
            } else {
                VStack(spacing: MSC.Spacing.sm) {
                    ForEach(compatibleTargetServers, id: \.id) { server in
                        serverPickerRow(server)
                    }
                }
            }
        }
    }

    private func serverPickerRow(_ server: ConfigServer) -> some View {
        let isSelected = selectedTargetServer?.id == server.id
        let isRunning = viewModel.isRunning(server)
        let activeSlotName = WorldSlotManager.activeSlot(forServerDir: server.serverDir)?.name

        return Button {
            guard !isRunning else { return }
            selectedTargetServer = server
        } label: {
            HStack(spacing: MSC.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.accentColor.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: server.isBedrock ? "square.fill" : "cup.and.saucer.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(server.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    HStack(spacing: MSC.Spacing.sm) {
                        if let name = activeSlotName {
                            Text("Active slot: \"\(name)\"")
                                .font(MSC.Typography.caption).foregroundStyle(.secondary)
                        }
                        if isRunning {
                            Label("Running — stop first", systemImage: "exclamationmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(MSC.Colors.warning)
                        }
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(MSC.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : MSC.Colors.tierContent)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .opacity(isRunning ? 0.55 : 1)
    }

    // MARK: Placement

    private var placementContent: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
            stepHeader(icon: "tray.and.arrow.down", title: "Slot Placement",
                       subtitle: "Where should the converted world go on the target server?", color: .green)

            // New slot
            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                HStack(spacing: 10) {
                    Image(systemName: placementMode == .newSlot ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 16)).foregroundStyle(placementMode == .newSlot ? Color.accentColor : .secondary)
                    Text("Create a new world slot")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("Recommended")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(MSC.Colors.success)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(MSC.Colors.success.opacity(0.12)))
                }
                .contentShape(Rectangle()).onTapGesture { placementMode = .newSlot }

                if placementMode == .newSlot {
                    TextField("Slot name", text: $newSlotName)
                        .textFieldStyle(.roundedBorder)
                        .padding(.leading, 26)
                }
            }
            .padding(MSC.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                    .fill(MSC.Colors.tierContent)
                    .overlay(
                        RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                            .stroke(placementMode == .newSlot ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1.5)
                    )
            )

            // Replace existing
            if !replaceTargetSlots.isEmpty {
                VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                    HStack(spacing: 10) {
                        Image(systemName: placementMode == .replaceExisting ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 16)).foregroundStyle(placementMode == .replaceExisting ? Color.accentColor : .secondary)
                        Text("Replace an existing slot")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text("Overwrites slot data")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(MSC.Colors.warning)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(MSC.Colors.warning.opacity(0.12)))
                    }
                    .contentShape(Rectangle()).onTapGesture { placementMode = .replaceExisting }

                    if placementMode == .replaceExisting {
                        VStack(spacing: 2) {
                            ForEach(replaceTargetSlots, id: \.id) { slot in
                                let isActive = WorldSlotManager.resolvedActiveSlotID(
                                    forServerDir: selectedTargetServer?.serverDir ?? "") == slot.id
                                let isChosen = selectedReplaceSlot?.id == slot.id
                                HStack(spacing: MSC.Spacing.sm) {
                                    Text(slot.name)
                                        .font(.system(size: 12, weight: isChosen ? .semibold : .regular))
                                    if isActive {
                                        Text("Active")
                                            .font(.system(size: 9, weight: .bold)).foregroundStyle(MSC.Colors.success)
                                            .padding(.horizontal, 5).padding(.vertical, 2)
                                            .background(Capsule().fill(MSC.Colors.success.opacity(0.12)))
                                    }
                                    Spacer()
                                    if isChosen {
                                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .padding(.horizontal, MSC.Spacing.md).padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                                        .fill(isChosen ? Color.accentColor.opacity(0.1) : Color.clear)
                                )
                                .contentShape(Rectangle()).onTapGesture { selectedReplaceSlot = slot }
                            }
                        }
                        .padding(.leading, 26)
                    }
                }
                .padding(MSC.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                        .fill(MSC.Colors.tierContent)
                        .overlay(
                            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                                .stroke(placementMode == .replaceExisting ? MSC.Colors.warning.opacity(0.4) : Color.clear, lineWidth: 1.5)
                        )
                )
            }
        }
    }

    // MARK: Summary

    private var summaryContent: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
            stepHeader(icon: "list.bullet.clipboard", title: "Ready to Convert",
                       subtitle: "Review the plan below, then click Convert World.", color: .blue)

            let formatLabel = ChunkerManager.shared.displayName(forFormat: selectedFormat)

            VStack(alignment: .leading, spacing: 0) {
                summaryRow(label: "From", value: "\(sourceServer.displayName)  →  \"\(sourceSlot.name)\"")
                Divider().padding(.leading, MSC.Spacing.xxl + MSC.Spacing.xl)
                summaryRow(label: "To", value: selectedTargetServer.map { $0.displayName } ?? "—")
                Divider().padding(.leading, MSC.Spacing.xxl + MSC.Spacing.xl)
                summaryRow(label: "Target version", value: formatLabel)
                Divider().padding(.leading, MSC.Spacing.xxl + MSC.Spacing.xl)
                switch placementMode {
                case .newSlot:
                    summaryRow(label: "New slot", value: "\"\(newSlotName)\"")
                case .replaceExisting:
                    summaryRow(label: "Replacing", value: "\"\(selectedReplaceSlot?.name ?? "—")\"",
                               valueColor: MSC.Colors.warning)
                }
            }
            .background(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous).fill(MSC.Colors.tierContent))

            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                GuideCallout(style: .tip,
                    text: "A backup of \"\(selectedTargetServer?.displayName ?? "the target server")\"'s current active world will be taken automatically before conversion completes.")
                GuideCallout(style: .note,
                    text: "The original world on \"\(sourceServer.displayName)\" will not be changed.")
                GuideCallout(style: .warning,
                    text: "Conversion may take several minutes for large worlds. Do not close the app or stop either server while it runs.")
            }
        }
    }

    private func summaryRow(label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack(alignment: .top, spacing: MSC.Spacing.md) {
            Text(label)
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .medium)).foregroundStyle(valueColor)
            Spacer()
        }
        .padding(.horizontal, MSC.Spacing.md)
        .padding(.vertical, 10)
    }

    // MARK: Converting

    private var convertingContent: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
            stepHeader(icon: "arrow.triangle.2.circlepath", title: "Converting…",
                       subtitle: "Chunker is running. This may take several minutes.", color: .orange)

            GuideCallout(style: .warning,
                text: "Do not close this window or stop either server while conversion is in progress.")

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(progressLines.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(MSC.Typography.mono)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .id(idx)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(MSC.Spacing.md)
                }
                .frame(minHeight: 200)
                .background(
                    RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                        .fill(MSC.Colors.tierContent)
                )
                .onChange(of: progressLines.count) {
                    withAnimation { proxy.scrollTo(progressLines.count - 1, anchor: .bottom) }
                }
            }
        }
    }

    // MARK: Done

    private var doneContent: some View {
        VStack(spacing: MSC.Spacing.xl) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56)).foregroundStyle(MSC.Colors.success)
            VStack(spacing: MSC.Spacing.sm) {
                Text("Conversion Complete")
                    .font(.system(size: 20, weight: .bold))
                if let target = selectedTargetServer {
                    Text("The converted world has been activated on \"\(target.displayName)\".\nThe original world on \"\(sourceServer.displayName)\" is unchanged.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Failed

    private func failedContent(message: String) -> some View {
        VStack(spacing: MSC.Spacing.xl) {
            Spacer()
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 56)).foregroundStyle(MSC.Colors.error)
            VStack(spacing: MSC.Spacing.sm) {
                Text("Conversion Failed")
                    .font(.system(size: 20, weight: .bold))
                Text(message)
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 440)
            }
            GuideCallout(style: .note, text: "The source world and target server were not modified.")
                .frame(maxWidth: 440)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Shared header component

    private func stepHeader(icon: String, title: String, subtitle: String, color: Color) -> some View {
        GuideTopicHeader(icon: icon, title: title, subtitle: subtitle, color: color)
    }

    // MARK: - Nav footer

    private var navFooter: some View {
        HStack {
            if canGoBack {
                Button {
                    goBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                        Text("Back").font(.system(size: 12))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Spacer()

            switch step {
            case .converting:
                EmptyView()

            case .done:
                Button("Done") { isPresented = false }
                    .buttonStyle(.borderedProminent)

            default:
                if hasFailed {
                    Button("Close") { isPresented = false }
                        .buttonStyle(MSCSecondaryButtonStyle())
                    Button("Try Again") {
                        hasFailed = false
                        failureMessage = ""
                        step = .preflight
                        runPreflight()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Cancel") { isPresented = false }
                        .buttonStyle(MSCSecondaryButtonStyle())

                    Button(step == .summary ? "Convert World" : "Next →") {
                        advance()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAdvance)
                }
            }
        }
        .padding(.horizontal, MSC.Spacing.xl)
        .padding(.vertical, MSC.Spacing.md)
    }

    // MARK: - Navigation

    private var canGoBack: Bool {
        guard !hasFailed, step != .converting, step != .done else { return false }
        return step.rawValue > WizardStep.preflight.rawValue
    }

    private func goBack() {
        guard let prev = WizardStep(rawValue: step.rawValue - 1) else { return }
        step = prev
    }

    private var canAdvance: Bool {
        switch step {
        case .preflight:
            return ChunkerManager.shared.isInstalled && !availableFormats.isEmpty
                && !preflightHasErrors && !isLoadingFormats
        case .selectVersion:
            return !selectedFormat.isEmpty
        case .selectTargetServer:
            return selectedTargetServer != nil && !viewModel.isRunning(selectedTargetServer!)
        case .selectPlacement:
            switch placementMode {
            case .newSlot:
                return !newSlotName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .replaceExisting:
                return selectedReplaceSlot != nil
            }
        case .summary:
            return true
        default:
            return false
        }
    }

    private func advance() {
        switch step {
        case .preflight:
            step = .selectVersion

        case .selectVersion:
            step = .selectTargetServer

        case .selectTargetServer:
            if let target = selectedTargetServer {
                replaceTargetSlots = WorldSlotManager.loadSlots(forServerDir: target.serverDir)
                selectedReplaceSlot = replaceTargetSlots.first
                if newSlotName.isEmpty { newSlotName = defaultNewSlotName }
                step = .selectPlacement
            }

        case .selectPlacement:
            step = .summary

        case .summary:
            startConversion()

        default:
            break
        }
    }

    private var defaultNewSlotName: String {
        sourceServer.isBedrock
            ? "\(sourceSlot.name) (from Bedrock)"
            : "\(sourceSlot.name) (from Java)"
    }

    // MARK: - Preflight

    private func runPreflight() {
        preflightItems = []
        downloadLog = []
        availableFormats = []

        Task { @MainActor in
            // Source server stopped?
            if viewModel.isRunning(sourceServer) {
                preflightItems.append((
                    "\"\(sourceServer.displayName)\" is currently running. Stop it before converting.",
                    true
                ))
                return
            }
            preflightItems.append(("\"\(sourceServer.displayName)\" is stopped — safe to convert.", false))

            // Java available?
            let javaPath = viewModel.configManager.config.javaPath
            guard ChunkerManager.shared.resolveJavaPath(appConfigJavaPath: javaPath) != nil else {
                preflightItems.append((
                    "Java was not found. Install Adoptium Temurin and set the path in MSC Preferences.",
                    true
                ))
                return
            }
            preflightItems.append(("Java runtime found.", false))

            // Chunker installed?
            if !ChunkerManager.shared.isInstalled {
                preflightItems.append((
                    "Chunker CLI is not installed. Click \"Download Chunker CLI\" below.",
                    true
                ))
                return
            }
            let version = ChunkerManager.shared.installedVersion ?? "unknown"
            preflightItems.append(("Chunker CLI installed (v\(version)).", false))

            // Compatible target servers?
            if compatibleTargetServers.isEmpty {
                preflightItems.append((
                    "No \(targetEditionLabel) servers found. Create one, then return here.",
                    true
                ))
                return
            }
            preflightItems.append((
                "\(compatibleTargetServers.count) \(targetEditionLabel) server(s) available.",
                false
            ))

            await loadFormats()
        }
    }

    private func downloadChunker() {
        isDownloadingChunker = true
        downloadLog = []
        Task { @MainActor in
            do {
                try await ChunkerManager.shared.downloadLatestJar { line in
                    Task { @MainActor in downloadLog.append(line) }
                }
                isDownloadingChunker = false
                await loadFormats()
            } catch {
                preflightItems.append(("Download failed: \(error.localizedDescription)", true))
                isDownloadingChunker = false
            }
        }
    }

    private func loadFormats() async {
        isLoadingFormats = true
        let javaPath = viewModel.configManager.config.javaPath
        let formats = await ChunkerManager.shared.supportedFormats(javaPath: javaPath)
        availableFormats = formats

        if let inferred = ChunkerManager.shared.inferSourceFormatString(from: sourceServer) {
            detectedSourceLabel = ChunkerManager.shared.displayName(forFormat: inferred)
        }

        let prefix = sourceServer.isBedrock ? "JAVA_" : "BEDROCK_"
        // Formats are sorted oldest→newest; default to the newest (last in list)
        if selectedFormat.isEmpty, let newest = formats.filter({ $0.hasPrefix(prefix) }).last {
            selectedFormat = newest
        }

        if formats.isEmpty {
            preflightItems.append((
                "Could not load supported versions from Chunker. Try re-downloading the jar.", true
            ))
        } else {
            preflightItems.removeAll { $0.text.contains("version") && $0.text.contains("loaded") }
            preflightItems.append(("\(formats.count) supported format(s) loaded.", false))
        }
        isLoadingFormats = false
    }

    // MARK: - Conversion

    private func startConversion() {
        guard let target = selectedTargetServer else { return }

        if viewModel.isRunning(target) {
            hasFailed = true
            failureMessage = "The target server \"\(target.displayName)\" is currently running. Stop it before converting."
            return
        }

        let placement: ConversionSlotPlacement
        switch placementMode {
        case .newSlot:
            placement = .newSlot(name: newSlotName.trimmingCharacters(in: .whitespacesAndNewlines))
        case .replaceExisting:
            guard let slot = selectedReplaceSlot else { return }
            placement = .replaceExisting(slot: slot)
        }

        progressLines = []
        step = .converting

        Task { @MainActor in
            do {
                try await viewModel.performWorldConversion(
                    sourceSlot: sourceSlot,
                    sourceServer: sourceServer,
                    targetServer: target,
                    targetFormat: selectedFormat,
                    placement: placement,
                    progressHandler: { line in
                        Task { @MainActor in progressLines.append(line) }
                    }
                )
                step = .done
            } catch {
                hasFailed = true
                failureMessage = error.localizedDescription
            }
        }
    }
}

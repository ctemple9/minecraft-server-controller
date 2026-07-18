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
    /// The server's mods/ directory — folder-watcher moves matched jars here.
    let modsDir: URL
}

/// Sheet shown after a CurseForge modpack import when one or more mods
/// couldn't be auto-downloaded (author disabled API distribution).
///
/// Opens each mod's direct per-file CurseForge download page (right loader/version
/// pre-selected), then watches a folder (default ~/Downloads) and auto-moves each
/// matched jar into the server's mods/ directory as it appears.
struct CurseForgeManualDownloadSheet: View {

    let pending: PendingCFManualDownloads
    @Binding var isPresented: PendingCFManualDownloads?

    @State private var foundIndices:    Set<Int> = []
    @State private var inFlightIndices: Set<Int> = []
    @State private var watchFolder: URL = FileManager.default
        .urls(for: .downloadsDirectory, in: .userDomainMask)
        .first ?? FileManager.default.homeDirectoryForCurrentUser
    @State private var isWatching: Bool  = false
    @State private var knownFiles: Set<String> = []

    private var foundCount: Int  { foundIndices.count }
    private var totalCount: Int  { pending.items.count }
    private var allFound: Bool   { foundCount >= totalCount }
    private var pendingCount: Int { totalCount - foundCount }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MSCSheetHeader(
                "\(pendingCount > 0 ? "\(pendingCount)" : "All") mod\(totalCount == 1 ? "" : "s") \(allFound ? "moved to mods/" : "need a manual download")",
                subtitle: allFound
                    ? "Your server's mods/ folder is complete — you're ready to start."
                    : "These mods can't be auto-downloaded (authors disabled API distribution)."
            ) { isPresented = nil }
            .padding(.horizontal, MSC.Spacing.xl)
            .padding(.top, MSC.Spacing.xl)

            ScrollView {
                VStack(alignment: .leading, spacing: MSC.Spacing.lg) {

                    if !allFound {
                        SECallout(
                            icon: "arrow.down.circle",
                            color: .orange,
                            text: "Click \"Open All\" — each mod's download page opens with the correct loader/version pre-selected, and the browser starts downloading automatically. Then start the folder watcher below to move them into your server automatically."
                        )
                    }

                    SESection(
                        icon: "shippingbox.fill",
                        title: allFound
                            ? "All \(totalCount) mods installed"
                            : "Mods to download (\(foundCount)/\(totalCount))",
                        color: allFound ? .green : .blue
                    ) {
                        VStack(spacing: 0) {
                            ForEach(Array(pending.items.enumerated()), id: \.offset) { idx, mod in
                                modRow(mod, idx: idx)
                                if idx < pending.items.count - 1 {
                                    Divider().padding(.leading, MSC.Spacing.md)
                                }
                            }
                        }
                    }

                    watchFolderSection
                }
                .padding(MSC.Spacing.xl)
            }

            Divider()

            HStack(spacing: MSC.Spacing.sm) {
                if !allFound {
                    Button {
                        openAll()
                    } label: {
                        Label("Open All in CurseForge", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(MSCSecondaryButtonStyle())
                }

                Spacer()

                Button { isPresented = nil } label: { Text("Done") }
                    .buttonStyle(MSCPrimaryButtonStyle())
            }
            .padding(MSC.Spacing.xl)
        }
        .background(MSC.Colors.tierAtmosphere)
        .frame(minWidth: 520, idealWidth: 600, minHeight: 420, idealHeight: 560)
        .task(id: isWatching) {
            guard isWatching else { return }
            while !Task.isCancelled && isWatching && !allFound {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, isWatching else { break }
                scanWatchFolder()
                if allFound { isWatching = false }
            }
        }
    }

    // MARK: - Mod row

    private func modRow(_ mod: CurseForgeModpack.ManualDownload, idx: Int) -> some View {
        let isFound     = foundIndices.contains(idx)
        let isInFlight  = inFlightIndices.contains(idx)
        return HStack(spacing: MSC.Spacing.md) {
            Group {
                if isFound {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                } else if isInFlight {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "clock")
                        .foregroundStyle(Color.secondary)
                }
            }
            .font(.system(size: 16))
            .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(mod.modName)
                    .font(.system(size: 13, weight: .medium))
                    .strikethrough(isFound)
                    .foregroundStyle(isFound ? .secondary : .primary)
                Text(mod.fileName)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !isFound && !isInFlight {
                Button {
                    openURL(mod.projectPageURL)
                } label: {
                    Label("Open", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(MSCSecondaryButtonStyle())
                .controlSize(.small)
            }
        }
        .padding(.vertical, MSC.Spacing.sm)
        .padding(.horizontal, MSC.Spacing.md)
        .background(isFound ? Color.green.opacity(0.06) : Color.clear)
        .animation(.easeInOut(duration: 0.2), value: isFound)
    }

    // MARK: - Watch folder section

    private var watchFolderSection: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
            Text("WATCH FOLDER")
                .font(MSC.Typography.sectionHeader)

            // Folder path row
            HStack(spacing: MSC.Spacing.sm) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(watchFolder.path)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Change…") { chooseWatchFolder() }
                    .buttonStyle(MSCSecondaryButtonStyle())
                    .controlSize(.small)
                    .disabled(isWatching)
            }
            .padding(MSC.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
            )

            // Status + start/stop
            HStack(spacing: MSC.Spacing.sm) {
                if allFound {
                    Label("All mods moved to mods/ — ready to start the server.", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.green)
                } else if isWatching {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Watching… (\(foundCount)/\(totalCount) found)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Stop") { isWatching = false }
                        .buttonStyle(MSCSecondaryButtonStyle())
                        .controlSize(.small)
                } else {
                    Text("MSC will watch this folder and move each downloaded .jar to your server's mods/ automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Start Watching") { startWatching() }
                        .buttonStyle(MSCSecondaryButtonStyle())
                }
            }
        }
    }

    // MARK: - Watcher logic

    private func startWatching() {
        // Snapshot all current files so we only act on ones that appear after watch starts.
        knownFiles = Set(
            (try? FileManager.default.contentsOfDirectory(atPath: watchFolder.path)) ?? []
        )
        isWatching = true
    }

    private func scanWatchFolder() {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: watchFolder.path)
        else { return }

        // Any fully-downloaded file that wasn't there when we started.
        // Exclude in-progress Chrome/Firefox partial downloads.
        let newFiles = contents.filter { name in
            let lower = name.lowercased()
            return !lower.hasSuffix(".crdownload")
                && !lower.hasSuffix(".part")
                && !lower.hasSuffix(".download")
                && !knownFiles.contains(name)
        }
        guard !newFiles.isEmpty else { return }

        for (idx, mod) in pending.items.enumerated() {
            guard !foundIndices.contains(idx), !inFlightIndices.contains(idx) else { continue }

            // Primary: exact filename match (covers .jar, .zip, or any other extension CF uses).
            if let match = newFiles.first(where: { $0 == mod.fileName }) {
                scheduleMove(fileName: match, for: idx)
                continue
            }

            // Secondary: macOS duplicate suffix — "modname-1.0 (1).jar" or "modname-1.0 (1).zip".
            let stem = (mod.fileName as NSString).deletingPathExtension
            let ext  = (mod.fileName as NSString).pathExtension.lowercased()
            if let match = newFiles.first(where: {
                let noExt   = ($0 as NSString).deletingPathExtension
                let fileExt = ($0 as NSString).pathExtension.lowercased()
                return fileExt == ext
                    && noExt.hasPrefix(stem + " (")
                    && noExt.hasSuffix(")")
            }) {
                scheduleMove(fileName: match, for: idx)
            }
        }

        // Fallback: if exactly one mod remains unmatched and exactly one new file appeared, claim it.
        let unmatchedMods = pending.items.indices.filter {
            !foundIndices.contains($0) && !inFlightIndices.contains($0)
        }
        let claimedNames: Set<String> = Set(
            pending.items.indices.compactMap { idx in
                inFlightIndices.contains(idx) ? pending.items[idx].fileName : nil
            }
        )
        let unclaimed = newFiles.filter { !claimedNames.contains($0) }
        if unmatchedMods.count == 1, unclaimed.count == 1 {
            scheduleMove(fileName: unclaimed[0], for: unmatchedMods[0])
        }
    }

    private func scheduleMove(fileName: String, for idx: Int) {
        inFlightIndices.insert(idx)
        let src     = watchFolder.appendingPathComponent(fileName)
        let dest    = pending.modsDir.appendingPathComponent(pending.items[idx].fileName)
        let modsDir = pending.modsDir
        Task.detached {
            let fm = FileManager.default
            do {
                try? fm.createDirectory(at: modsDir, withIntermediateDirectories: true)
                if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                try fm.moveItem(at: src, to: dest)
            } catch {
                // Cross-volume or other error: copy then delete source.
                try? fm.copyItem(at: src, to: dest)
                try? fm.removeItem(at: src)
            }
            await MainActor.run {
                foundIndices.insert(idx)
                inFlightIndices.remove(idx)
            }
        }
    }

    // MARK: - Actions

    private func openAll() {
        var delay = 0.0
        for (i, mod) in pending.items.enumerated() where !foundIndices.contains(i) {
            let urlStr = mod.directDownloadURL
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let url = URL(string: urlStr) else { return }
                NSWorkspace.shared.open(url)
            }
            delay += 0.3
        }
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    private func chooseWatchFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles          = false
        panel.canChooseDirectories    = true
        panel.allowsMultipleSelection = false
        panel.title   = "Choose Watch Folder"
        panel.message = "Select the folder where mods will be downloaded (usually ~/Downloads)."
        if panel.runModal() == .OK, let url = panel.url {
            watchFolder = url
        }
    }
}

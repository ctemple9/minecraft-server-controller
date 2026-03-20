//
//  ServerFilesTabView.swift
//  MinecraftServerController
//
//  In-app file browser for the server directory.
//  Works for both Java and Bedrock servers — both have a real local serverDir
//  on the host filesystem. Bedrock's directory is bind-mounted into Docker at /data
//  when the server runs, so all persistent files are visible here.
//

import SwiftUI
import AppKit

// MARK: - File Item Model

private struct ServerFileItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64?
    let modifiedDate: Date?

    var fileExtension: String { url.pathExtension.lowercased() }

    var systemIcon: String {
        if isDirectory { return "folder.fill" }
        switch fileExtension {
        case "json":                          return "doc.text"
        case "yml", "yaml":                   return "doc.plaintext"
        case "properties":                    return "slider.horizontal.3"
        case "jar":                           return "archivebox"
        case "zip":                           return "doc.zipper"
        case "log":                           return "doc.text.magnifyingglass"
        case "txt":                           return "doc.text"
        case "png", "jpg", "jpeg", "gif":     return "photo"
        case "sh":                            return "terminal"
        default:                              return "doc"
        }
    }

    var iconColor: Color {
        if isDirectory { return Color(red: 0.42, green: 0.62, blue: 0.94) }
        switch fileExtension {
        case "json":                          return Color(red: 0.95, green: 0.77, blue: 0.36)
        case "yml", "yaml":                   return Color(red: 0.56, green: 0.88, blue: 0.64)
        case "properties":                    return Color(red: 0.72, green: 0.56, blue: 0.94)
        case "jar":                           return Color(red: 0.95, green: 0.56, blue: 0.36)
        case "zip":                           return Color(red: 0.75, green: 0.75, blue: 0.78)
        case "log":                           return Color(red: 0.60, green: 0.60, blue: 0.65)
        default:                              return Color(red: 0.60, green: 0.60, blue: 0.65)
        }
    }
}

// MARK: - Main View

struct ServerFilesTabView: View {
    @EnvironmentObject var viewModel: AppViewModel

    @State private var navigationStack: [URL] = []
    @State private var items: [ServerFileItem] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var hoveredItemID: UUID? = nil
    @State private var textPreview: TextPreviewItem? = nil

    private var cfgServer: ConfigServer? {
        guard let s = viewModel.selectedServer else { return nil }
        return viewModel.configServer(for: s)
    }

    private var isBedrock: Bool { cfgServer?.isBedrock ?? false }

    private var rootURL: URL? {
        guard let server = viewModel.selectedServer else { return nil }
        return URL(fileURLWithPath: server.directory, isDirectory: true)
    }

    private var currentURL: URL? {
        navigationStack.last ?? rootURL
    }

    private var breadcrumbs: [BreadcrumbItem] {
        guard let root = rootURL else { return [] }
        var crumbs: [BreadcrumbItem] = [BreadcrumbItem(label: "Server Root", url: root)]
        for url in navigationStack {
            if url != root {
                crumbs.append(BreadcrumbItem(label: url.lastPathComponent, url: url))
            }
        }
        return crumbs
    }

    // MARK: - Body

    var body: some View {
        if rootURL == nil {
            noServerPlaceholder
        } else {
            filesContent
        }
    }

    // MARK: - Files Content

    private var filesContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isBedrock {
                bedrockInfoBanner
            }
            breadcrumbBar
            Divider().opacity(0.3)
            fileListArea
        }
        .onAppear { loadDirectory(rootURL) }
        .onChange(of: viewModel.selectedServer) { _, _ in
            navigationStack = []
            loadDirectory(rootURL)
        }
        .sheet(item: $textPreview) { preview in
            TextPreviewSheet(item: preview)
        }
    }

    // MARK: - Bedrock Info Banner

    private var bedrockInfoBanner: some View {
        HStack(spacing: MSC.Spacing.sm) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(MSC.Colors.info)
            Text("Bedrock server files are stored locally and bind-mounted into Docker at /data when the server runs.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, MSC.Spacing.md)
        .padding(.vertical, MSC.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MSC.Colors.info.opacity(0.08))
    }

    // MARK: - Breadcrumb Bar

    private var breadcrumbBar: some View {
        HStack(spacing: MSC.Spacing.xs) {
            if navigationStack.count > 0 {
                Button {
                    navigateBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Go back")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MSC.Spacing.xxs) {
                    ForEach(Array(breadcrumbs.enumerated()), id: \.element.url) { index, crumb in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(MSC.Colors.tertiary)
                        }
                        let isLast = index == breadcrumbs.count - 1
                        Button {
                            if !isLast { navigateTo(crumb.url, fromBreadcrumb: true) }
                        } label: {
                            Text(crumb.label)
                                .font(.system(size: 12, weight: isLast ? .semibold : .regular))
                                .foregroundStyle(isLast ? Color.primary : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(isLast)
                    }
                }
            }

            Spacer()

            Button {
                if let url = currentURL {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            } label: {
                Label("Show in Finder", systemImage: "arrow.up.forward.square")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open current folder in Finder")
        }
        .padding(.horizontal, MSC.Spacing.md)
        .padding(.vertical, MSC.Spacing.sm)
        .background(MSC.Colors.tierChrome.opacity(0.5))
    }

    // MARK: - File List Area

    private var fileListArea: some View {
        Group {
            if isLoading {
                loadingState
            } else if let error = errorMessage {
                errorState(error)
            } else if items.isEmpty {
                emptyState
            } else {
                fileList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fileList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 1) {
                let dirs  = items.filter { $0.isDirectory }
                let files = items.filter { !$0.isDirectory }

                if !dirs.isEmpty {
                    MSCOverline("Folders")
                        .padding(.horizontal, MSC.Spacing.md)
                        .padding(.top, MSC.Spacing.md)
                        .padding(.bottom, MSC.Spacing.xs)
                    ForEach(dirs) { item in fileRow(item) }
                }

                if !files.isEmpty {
                    MSCOverline("Files")
                        .padding(.horizontal, MSC.Spacing.md)
                        .padding(.top, MSC.Spacing.md)
                        .padding(.bottom, MSC.Spacing.xs)
                    ForEach(files) { item in fileRow(item) }
                }
            }
            .padding(.bottom, MSC.Spacing.lg)
        }
    }

    // MARK: - File Row

    private func fileRow(_ item: ServerFileItem) -> some View {
        let isHovered = hoveredItemID == item.id

        return HStack(spacing: MSC.Spacing.sm) {
            Image(systemName: item.systemIcon)
                .font(.system(size: 14))
                .foregroundStyle(item.iconColor)
                .frame(width: 20, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: MSC.Spacing.sm) {
                    if let date = item.modifiedDate {
                        Text(date.formatted(.relative(presentation: .named)))
                            .font(.system(size: 10))
                            .foregroundStyle(MSC.Colors.tertiary)
                    }
                    if let size = item.size, !item.isDirectory {
                        Text(formatBytes(size))
                            .font(.system(size: 10))
                            .foregroundStyle(MSC.Colors.tertiary)
                    }
                }
            }

            Spacer()

            if isHovered {
                HStack(spacing: MSC.Spacing.xs) {
                    if canPreview(item) {
                        Button {
                            openPreview(item)
                        } label: {
                            Image(systemName: "eye")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Preview file")
                    }

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                    } label: {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Reveal in Finder")
                }
                .transition(.opacity)
            }

            if item.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MSC.Colors.tertiary)
            }
        }
        .padding(.horizontal, MSC.Spacing.md)
        .padding(.vertical, MSC.Spacing.sm + 1)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                .fill(isHovered ? MSC.Colors.tierContent : Color.clear)
        )
        .padding(.horizontal, MSC.Spacing.sm)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                hoveredItemID = hovering ? item.id : nil
            }
        }
        .onTapGesture {
            if item.isDirectory {
                navigateTo(item.url, fromBreadcrumb: false)
            } else if canPreview(item) {
                openPreview(item)
            } else {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
        }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }

    // MARK: - State Views

    private var loadingState: some View {
        VStack(spacing: MSC.Spacing.md) {
            ProgressView().scaleEffect(0.8)
            Text("Loading…")
                .font(MSC.Typography.metaCaption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: MSC.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24))
                .foregroundStyle(MSC.Colors.warning)
            Text(message)
                .font(MSC.Typography.metaCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(MSC.Spacing.xl)
    }

    private var emptyState: some View {
        VStack(spacing: MSC.Spacing.sm) {
            Image(systemName: "folder")
                .font(.system(size: 28))
                .foregroundStyle(MSC.Colors.tertiary)
            Text("This folder is empty")
                .font(MSC.Typography.metaCaption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noServerPlaceholder: some View {
        VStack(spacing: MSC.Spacing.sm) {
            Image(systemName: "server.rack")
                .font(.system(size: 28))
                .foregroundStyle(MSC.Colors.tertiary)
            Text("No server selected")
                .font(MSC.Typography.metaCaption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Navigation

    private func navigateTo(_ url: URL, fromBreadcrumb: Bool) {
        if fromBreadcrumb {
            guard let root = rootURL else { return }
            if url == root {
                navigationStack = []
            } else if let idx = navigationStack.firstIndex(of: url) {
                navigationStack = Array(navigationStack.prefix(through: idx))
            }
        } else {
            navigationStack.append(url)
        }
        loadDirectory(url)
    }

    private func navigateBack() {
        if navigationStack.count <= 1 {
            navigationStack = []
            loadDirectory(rootURL)
        } else {
            navigationStack.removeLast()
            loadDirectory(navigationStack.last ?? rootURL)
        }
    }

    // MARK: - FileManager

    private func loadDirectory(_ url: URL?) {
        guard let url = url else { return }
        isLoading = true
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            do {
                let contents = try fm.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [
                        .isDirectoryKey, .fileSizeKey, .contentModificationDateKey
                    ],
                    options: [.skipsHiddenFiles]
                )

                let mapped: [ServerFileItem] = contents.compactMap { childURL in
                    let rv = try? childURL.resourceValues(
                        forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
                    )
                    return ServerFileItem(
                        url: childURL,
                        name: childURL.lastPathComponent,
                        isDirectory: rv?.isDirectory ?? false,
                        size: rv?.fileSize.map { Int64($0) },
                        modifiedDate: rv?.contentModificationDate
                    )
                }
                .sorted {
                    if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }

                DispatchQueue.main.async {
                    self.items = mapped
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Could not read folder: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }

    // MARK: - Preview

    private func canPreview(_ item: ServerFileItem) -> Bool {
        let previewable = ["txt", "log", "yml", "yaml", "json", "properties", "sh", "cfg", "conf"]
        return previewable.contains(item.fileExtension)
    }

    private func openPreview(_ item: ServerFileItem) {
        DispatchQueue.global(qos: .userInitiated).async {
            let content = (try? String(contentsOf: item.url, encoding: .utf8))
                ?? (try? String(contentsOf: item.url, encoding: .isoLatin1))
                ?? "<Could not decode file contents>"
            DispatchQueue.main.async {
                self.textPreview = TextPreviewItem(url: item.url, name: item.name, content: content)
            }
        }
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024
        let mb = kb / 1024
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        if kb >= 1 { return String(format: "%.0f KB", kb) }
        return "\(bytes) B"
    }
}

// MARK: - Supporting Models

private struct BreadcrumbItem: Hashable {
    let label: String
    let url: URL
}

struct TextPreviewItem: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let content: String
}

// MARK: - Text Preview / Editor Sheet

struct TextPreviewSheet: View {
    let item: TextPreviewItem
    @Environment(\.dismiss) private var dismiss

    // Edit state
    @State private var isEditing: Bool = false
    @State private var editableContent: String = ""
    @State private var showEditWarning: Bool = false
    @State private var saveError: String? = nil
    @State private var isSaving: Bool = false
    @State private var saveSuccessFlash: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            Divider().opacity(0.4)
            if isEditing { editWarningBanner }
            contentArea
            if let error = saveError { saveErrorBanner(error) }
        }
        .frame(minWidth: 560, minHeight: 420)
        .background(MSC.Colors.tierAtmosphere)
        .onAppear {
            editableContent = item.content
        }
        .alert("Edit Server File?", isPresented: $showEditWarning) {
            Button("Edit File", role: .destructive) {
                isEditing = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You are about to edit \"\(item.name)\" directly on disk.\n\nIncorrect changes can break your server or cause data loss. Make sure the server is stopped before editing critical config files.\n\nThis cannot be undone from within MSC.")
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: MSC.Spacing.sm) {
            Image(systemName: isEditing ? "pencil.line" : "doc.text")
                .foregroundStyle(isEditing ? MSC.Colors.warning : .secondary)

            Text(item.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            if isEditing {
                Text("EDITING")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(MSC.Colors.warning)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(MSC.Colors.warning.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }

            Spacer()

            if isEditing {
                // Edit mode: Save + Discard
                Button("Discard Changes") {
                    editableContent = item.content
                    saveError = nil
                    isEditing = false
                }
                .buttonStyle(MSCSecondaryButtonStyle())

                Button {
                    saveFile()
                } label: {
                    if isSaving {
                        HStack(spacing: 5) {
                            ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
                            Text("Saving…")
                        }
                    } else if saveSuccessFlash {
                        Label("Saved", systemImage: "checkmark")
                    } else {
                        Text("Save")
                    }
                }
                .buttonStyle(MSCPrimaryButtonStyle())
                .disabled(isSaving)
            } else {
                // Read-only mode: Show in Finder + Edit + Done
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                } label: {
                    Label("Show in Finder", systemImage: "arrow.up.forward.square")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button("Edit File") {
                    showEditWarning = true
                }
                .buttonStyle(MSCSecondaryButtonStyle())

                Button("Done") { dismiss() }
                    .buttonStyle(MSCPrimaryButtonStyle())
            }
        }
        .padding(MSC.Spacing.md)
        .background(MSC.Colors.tierChrome)
    }

    // MARK: - Edit Warning Banner

    private var editWarningBanner: some View {
        HStack(spacing: MSC.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(MSC.Colors.warning)
            Text("You are editing this file directly on disk. Changes take effect immediately when saved.")
                .font(.system(size: 11))
                .foregroundStyle(MSC.Colors.warning.opacity(0.85))
        }
        .padding(.horizontal, MSC.Spacing.md)
        .padding(.vertical, MSC.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MSC.Colors.warning.opacity(0.10))
    }

    // MARK: - Content Area

    private var contentArea: some View {
        Group {
            if isEditing {
                TextEditor(text: $editableContent)
                    .font(MSC.Typography.mono)
                    .foregroundStyle(.primary)
                    .scrollContentBackground(.hidden)
                    .background(MSC.Colors.tierTerminal)
                    .padding(MSC.Spacing.md)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(MSC.Colors.tierTerminal)
            } else {
                ScrollView([.vertical, .horizontal], showsIndicators: true) {
                    Text(item.content)
                        .font(MSC.Typography.mono)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(MSC.Spacing.md)
                }
                .background(MSC.Colors.tierTerminal)
            }
        }
    }

    // MARK: - Save Error Banner

    private func saveErrorBanner(_ message: String) -> some View {
        HStack(spacing: MSC.Spacing.sm) {
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 11))
                .foregroundStyle(MSC.Colors.error)
            Text("Save failed: \(message)")
                .font(.system(size: 11))
                .foregroundStyle(MSC.Colors.error.opacity(0.9))
            Spacer()
            Button {
                saveError = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, MSC.Spacing.md)
        .padding(.vertical, MSC.Spacing.sm)
        .background(MSC.Colors.error.opacity(0.10))
    }

    // MARK: - Save

    private func saveFile() {
        isSaving = true
        saveError = nil

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try editableContent.write(to: item.url, atomically: true, encoding: .utf8)
                DispatchQueue.main.async {
                    self.isSaving = false
                    self.saveSuccessFlash = true
                    // Reset the success flash after 2s, then exit edit mode
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self.saveSuccessFlash = false
                        self.isEditing = false
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isSaving = false
                    self.saveError = error.localizedDescription
                }
            }
        }
    }
}

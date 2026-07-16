// HeadlessScriptSheet.swift
// MinecraftServerController

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct HeadlessScriptSheet: View {

    @EnvironmentObject var viewModel: AppViewModel

    let config: ConfigServer
    @Binding var isPresented: Bool

    // Java options
    @State private var minRamGB: Int
    @State private var maxRamGB: Int
    @State private var wrapMode: HeadlessWrapMode = .none
    @State private var includeXboxBroadcast: Bool
    private var hasXboxBroadcastJar: Bool {
        appConfig.xboxBroadcastJarPath.map { !$0.isEmpty } ?? false
    }

    // Bedrock options
    @State private var dockerRestart: HeadlessDockerRestart = .never

    // UI state
    @State private var copyConfirmed = false

    init(config: ConfigServer, isPresented: Binding<Bool>) {
        self.config = config
        self._isPresented = isPresented
        _minRamGB = State(initialValue: max(1, config.minRamGB))
        _maxRamGB = State(initialValue: max(1, config.maxRamGB))
        // includeXboxBroadcast is seeded in onAppear once we have viewModel
        _includeXboxBroadcast = State(initialValue: config.xboxBroadcastEnabled)
    }

    private var appConfig: AppConfig { viewModel.configManager.config }

    private var script: String {
        switch config.serverType {
        case .java:
            return HeadlessScriptGenerator.javaScript(
                config: config,
                appConfig: appConfig,
                minRamGB: minRamGB,
                maxRamGB: maxRamGB,
                wrapMode: wrapMode,
                includeXboxBroadcast: includeXboxBroadcast
            )
        case .bedrock:
            // Bedrock servers run inside MSC's built-in Virtualization.framework VM —
            // they cannot be started from a shell script.
            // (Docker script kept below for reference; not surfaced — hide-don't-delete policy.)
            return """
            # Bedrock servers run inside MSC's built-in VM.
            # Keep MSC running — the crash watchdog handles restarts automatically.
            #
            # There is no standalone shell-script equivalent; the VM is managed entirely
            # by the app via Apple Virtualization.framework.
            """
            // return HeadlessScriptGenerator.bedrockScript(config: config, dockerRestart: dockerRestart)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MSCSheetHeader(
                "Start Script",
                subtitle: config.displayName
            ) { isPresented = false }
            .padding(.horizontal, MSC.Spacing.xl)
            .padding(.top, MSC.Spacing.xl)

            ScrollView {
                VStack(alignment: .leading, spacing: MSC.Spacing.lg) {

                    SECallout(
                        icon: "terminal.fill",
                        color: .purple,
                        text: "Run this script in Terminal to start your server without the app. You can save it as a .command file — double-clicking it will open Terminal and run it automatically."
                    )

                    // Options
                    if config.serverType == .java {
                        javaOptions
                    } else {
                        bedrockOptions
                    }

                    // Script display
                    scriptDisplay

                    // Action bar
                    actionBar
                }
                .padding(MSC.Spacing.xl)
            }
        }
        .background(MSC.Colors.tierAtmosphere)
        .frame(minWidth: 600, idealWidth: 680, minHeight: 500, idealHeight: 620)
    }

    // MARK: - Java options

    private var javaOptions: some View {
        SESection(icon: "gearshape.fill", title: "Options", color: .blue) {
            VStack(alignment: .leading, spacing: MSC.Spacing.md) {

                HStack(spacing: MSC.Spacing.xl) {
                    ramStepper(label: "Min RAM (GB)", value: $minRamGB)
                    ramStepper(label: "Max RAM (GB)", value: $maxRamGB)
                    Spacer(minLength: 0)
                }

                Divider()

                HStack {
                    Text("Wrap with")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $wrapMode) {
                        ForEach(HeadlessWrapMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 340)
                    Spacer(minLength: 0)
                }

                wrapModeHint

                if hasXboxBroadcastJar {
                    Divider()
                    Toggle(isOn: $includeXboxBroadcast) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Include Xbox Broadcast helper")
                                .font(.system(size: 12))
                            Text("Lets Xbox/Bedrock friends join via LAN discovery")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    @ViewBuilder
    private var wrapModeHint: some View {
        switch wrapMode {
        case .none:
            EmptyView()
        case .autoRestart:
            Text("Automatically restarts the server if it crashes. Press Ctrl+C once to stop the restart loop.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        case .screen:
            Text("The server runs in a persistent terminal session — closing this window won't stop it. Drop back in any time with: screen -r minecraft")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Bedrock options

    private var bedrockOptions: some View {
        // Bedrock servers run inside the built-in VM — no shell script needed.
        // (Docker restart picker kept below for reference; not surfaced — hide-don't-delete policy.)
        SECallout(
            icon: "memorychip",
            color: .orange,
            text: "Bedrock servers run inside MSC's built-in VM. Keep MSC running — the crash watchdog handles restarts automatically."
        )
        // Docker restart picker (hidden — Docker backend retired):
        // SESection(icon: "gearshape.fill", title: "Options", color: .blue) {
        //     HStack {
        //         Text("Restart policy").font(.system(size: 12)).foregroundStyle(.secondary)
        //         Picker("", selection: $dockerRestart) {
        //             ForEach(HeadlessDockerRestart.allCases) { mode in Text(mode.rawValue).tag(mode) }
        //         }
        //         .pickerStyle(.segmented).frame(maxWidth: 280)
        //         Spacer(minLength: 0)
        //     }
        // }
    }

    // MARK: - Script display

    private var scriptDisplay: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
            Text("Script")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            ScrollView([.vertical, .horizontal]) {
                Text(script)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(MSC.Spacing.md)
            }
            .frame(minHeight: 200, maxHeight: 280)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: MSC.Spacing.sm) {
            Button {
                copyScript()
            } label: {
                Label(copyConfirmed ? "Copied!" : "Copy", systemImage: copyConfirmed ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(MSCSecondaryButtonStyle())

            Button {
                saveAsCommand()
            } label: {
                Label("Save as .command…", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(MSCSecondaryButtonStyle())

            Button {
                openInTerminal()
            } label: {
                Label("Open in Terminal", systemImage: "terminal")
            }
            .buttonStyle(MSCPrimaryButtonStyle())

            Spacer(minLength: 0)
        }
    }

    // MARK: - RAM stepper helper

    private func ramStepper(label: String, value: Binding<Int>) -> some View {
        HStack(spacing: MSC.Spacing.sm) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Stepper("\(value.wrappedValue) GB", value: value, in: 1...64)
                .labelsHidden()
            Text("\(value.wrappedValue) GB")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 48, alignment: .leading)
        }
    }

    // MARK: - Actions

    private func copyScript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(script, forType: .string)
        withAnimation { copyConfirmed = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { copyConfirmed = false }
        }
    }

    private func saveAsCommand() {
        let panel = NSSavePanel()
        panel.title = "Save Start Script"
        panel.nameFieldStringValue = "\(sanitizeFilename(config.displayName))-start.command"
        panel.allowedContentTypes = [.init(filenameExtension: "command") ?? .plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        writeScript(to: url)
    }

    private func openInTerminal() {
        let tmpDir = FileManager.default.temporaryDirectory
        let filename = "\(sanitizeFilename(config.displayName))-start.command"
        let url = tmpDir.appendingPathComponent(filename)
        if writeScript(to: url) {
            NSWorkspace.shared.open(url)
        }
    }

    @discardableResult
    private func writeScript(to url: URL) -> Bool {
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            // Mark executable so Terminal runs it directly
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: url.path
            )
            return true
        } catch {
            return false
        }
    }

    private func sanitizeFilename(_ name: String) -> String {
        name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }
}
